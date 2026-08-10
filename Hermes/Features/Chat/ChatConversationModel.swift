import Foundation
import Observation

/// Drives one conversation: composes turns, consumes the agent event stream, and
/// keeps the transcript consistent when a turn is cancelled or fails.
///
/// A generation counter guards against late events from a superseded turn, so a
/// cancelled stream can never append text to a newer one.
@MainActor
@Observable
final class ChatConversationModel {
    private(set) var messages: [ChatMessage] = []
    /// Text accumulated for the in-flight assistant turn, rendered as a live bubble.
    private(set) var streamingText = ""
    var draft = "" {
        didSet {
            guard oldValue != draft else { return }
            scheduleDraftSave()
        }
    }
    var errorMessage: String?

    private let appModel: AppModel
    private let coordinator: ChatTurnCoordinator
    private var turn: Task<Void, Never>?
    private var generation = 0

    /// Deltas are batched before touching observable state; re-rendering and
    /// re-parsing Markdown per token is what makes long streams stutter.
    private var pendingDelta = ""
    private var flush: Task<Void, Never>?
    private let flushInterval = Duration.milliseconds(50)

    /// Last response the server acknowledged, used to continue the chain instead
    /// of resending the transcript.
    private(set) var previousResponseID: String?
    private(set) var turnState: TurnState = .idle
    /// Retained so a turn that provably never started can be resent on request.
    private var lastPrompt: String?
    /// Server session this conversation is bound to. When set, the transcript is
    /// shared with every other Hermes client.
    private(set) var sessionID: String?
    private(set) var activeToolName: String?
    private(set) var isLoadingTranscript = false
    /// Turn recorded before network I/O, cleared once the outcome is known.
    private var pendingTurn: PendingTurn?
    private var draftSave: Task<Void, Never>?
    /// The server's version of the finished turn, applied in place of accumulated
    /// deltas so tool results appear without a second request.
    private var serverTranscript: [SessionMessage]?
    /// A complete session transcript, which supersedes the whole conversation.
    private var replacementTranscript: [SessionMessage]?
    /// Retained locally because a dropped run stream cannot replay this payload.
    private(set) var pendingApproval: ApprovalRequest?
    private var isRespondingToApproval = false
    private var approvalExpiry: Task<Void, Never>?

    /// The server fails an unanswered approval closed after this long and sends no
    /// event when it does, so the client runs its own clock.
    private static let approvalWindow: TimeInterval = 300

    /// When the pending approval stops being answerable.
    var approvalDeadline: Date? {
        pendingApproval.map { $0.receivedAt.addingTimeInterval(Self.approvalWindow) }
    }

    init(appModel: AppModel) {
        self.appModel = appModel
        self.coordinator = ChatTurnCoordinator(
            chatClient: appModel.environment.chatClient,
            reconciler: appModel.environment.sessionsClient,
            runService: appModel.environment.approvals
        )
    }

    var isStreaming: Bool { turnState.isActive }

    /// A turn is only resendable when it is known never to have reached Hermes.
    var canRetry: Bool { turnState.allowsRetry && lastPrompt != nil }

    /// True while the outcome of the last turn is genuinely undetermined.
    var isOutcomeUnknown: Bool { turnState == .outcomeUnknown }

    var canSend: Bool {
        !isStreaming
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && appModel.activeProfile != nil
    }

    var isEmpty: Bool {
        messages.isEmpty && streamingText.isEmpty
    }

    /// Open a server session and replace the transcript with its stored history.
    func open(sessionID: String) async {
        guard let reconciler = appModel.environment.sessionsClient,
              let profile = appModel.activeProfile else { return }
        stop()
        isLoadingTranscript = true
        defer { isLoadingTranscript = false }
        self.sessionID = sessionID
        previousResponseID = nil
        errorMessage = nil
        do {
            let password = try await appModel.passwordForActiveProfile() ?? ""
            let stored = try await reconciler.messages(
                sessionID: sessionID,
                limit: 200,
                profile: profile,
                password: password
            )
            messages = stored.asTranscript()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func send() {
        guard canSend else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        errorMessage = nil
        lastPrompt = prompt
        messages.append(ChatMessage(role: .user, content: prompt))
        start()
    }

    /// Resend a turn that reconciliation proved never started.
    func retry() {
        guard canRetry, let prompt = lastPrompt else { return }
        errorMessage = nil
        if messages.last?.content != prompt || messages.last?.role != .user {
            messages.append(ChatMessage(role: .user, content: prompt))
        }
        start()
    }

    /// Disconnect the local stream, keeping whatever text already arrived. This
    /// does not stop work already running on the server.
    func stop() {
        guard isStreaming else { return }
        generation &+= 1
        turn?.cancel()
        turn = nil
        Task { await coordinator.cancelActive() }
        commitStreamedText()
        turnState = .completed
    }

    func clear() {
        stop()
        messages.removeAll()
        streamingText = ""
        errorMessage = nil
        previousResponseID = nil
        lastPrompt = nil
        sessionID = nil
        turnState = .idle
    }

    private func start() {
        generation &+= 1
        let generation = generation
        turnState = .sending
        streamingText = ""

        turn = Task { [weak self] in
            guard let self else { return }
            do {
                guard let profile = appModel.activeProfile else {
                    throw HermesConnectionError.invalidConfiguration("Configure a Hermes server first.")
                }
                guard let password = try await appModel.passwordForActiveProfile(), !password.isEmpty else {
                    throw CredentialStoreError.invalidPassword
                }

                let capabilities = appModel.capabilities
                await bindSessionIfNeeded(capabilities: capabilities, profile: profile, password: password)
                if let prompt = lastPrompt { recordPendingTurn(prompt: prompt) }

                let request = ChatTurnRequest(
                    messages: messages,
                    model: capabilities.models.first,
                    wireProtocol: wireProtocol(for: capabilities),
                    previousResponseID: capabilities.supportsResponses ? previousResponseID : nil
                )

                for await update in await coordinator.start(request, profile: profile, password: password) {
                    guard generation == self.generation else { return }
                    apply(update)
                }
            } catch {
                guard generation == self.generation else { return }
                fail(error)
            }
        }
    }

    /// Create the server session up front so a new conversation is visible to the
    /// web dashboard and the terminal UI from its first message.
    private func bindSessionIfNeeded(
        capabilities: ServerCapabilities,
        profile: ServerProfile,
        password: String
    ) async {
        guard sessionID == nil,
              capabilities.supportsSessions,
              let client = appModel.environment.sessionsClient else { return }
        do {
            sessionID = try await client.createSession(profile: profile, password: password).id
        } catch {
            // A stateless protocol still works; the turn just will not be session-bound.
            appModel.environment.logger.error("Session creation failed", code: "session_create")
        }
    }

    /// Prefer a session-bound turn so the transcript stays shared with the web UI
    /// and TUI; fall back to stateless protocols when sessions are unavailable.
    private func wireProtocol(for capabilities: ServerCapabilities) -> ChatWireProtocol {
        // Runs are the only protocol that can deliver an approval prompt. Without
        // one a dangerous command is silently refused and the agent just says so.
        if capabilities.supportsRunApproval, appModel.environment.approvals != nil {
            return .run(sessionID: sessionID)
        }
        if let sessionID, capabilities.supportsSessions {
            return .sessionChat(sessionID: sessionID)
        }
        return capabilities.supportsResponses ? .responses : .chatCompletions
    }

    /// Answer a pending approval. Guarded because a notification or another client
    /// may have resolved it already.
    func respondToApproval(choice: String) async {
        guard !isRespondingToApproval,
              let request = pendingApproval,
              let responder = appModel.environment.approvals,
              let profile = appModel.activeProfile else { return }
        isRespondingToApproval = true
        defer { isRespondingToApproval = false }
        do {
            let password = try await appModel.passwordForActiveProfile() ?? ""
            _ = try await responder.respond(
                runID: request.runID,
                choice: choice,
                profile: profile,
                password: password
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        clearApproval()
    }

    /// The server treats silence as denial after its timeout, so stop offering a
    /// choice that can no longer be honoured.
    private func startApprovalExpiry(for request: ApprovalRequest) {
        approvalExpiry?.cancel()
        let remaining = request.receivedAt.addingTimeInterval(Self.approvalWindow).timeIntervalSinceNow
        guard remaining > 0 else { return expireApproval() }
        approvalExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard let self, !Task.isCancelled, pendingApproval?.runID == request.runID else { return }
            expireApproval()
        }
    }

    private func expireApproval() {
        clearApproval()
        errorMessage = """
            The approval expired without an answer, so Hermes treated it as denied. \
            Ask again if you still want that action.
            """
    }

    private func clearApproval() {
        approvalExpiry?.cancel()
        approvalExpiry = nil
        pendingApproval = nil
    }

    // MARK: - Pending work

    /// Restore an unsent draft and resolve any turn left in flight by a previous
    /// launch. A turn interrupted by termination is reconciling, never failed.
    func restorePendingWork() async {
        let work = await appModel.environment.pendingWork.load()
        if draft.isEmpty {
            draft = work.draft
            draftSave?.cancel()
            draftSave = nil
        }
        if let sessionID = work.draftSessionID, self.sessionID == nil {
            self.sessionID = sessionID
        }
        guard let interrupted = work.uncertainTurns.first else { return }
        turnState = .reconciling
        turnState = await resolve(interrupted)
        if case .failed = turnState { lastPrompt = interrupted.prompt }
        await persistPendingWork(turns: [])
    }

    /// Ask the server whether an interrupted turn actually landed.
    private func resolve(_ turn: PendingTurn) async -> TurnState {
        guard let sessionID = turn.sessionID,
              let reconciler = appModel.environment.sessionsClient,
              let profile = appModel.activeProfile,
              let password = try? await appModel.passwordForActiveProfile(),
              let stored = try? await reconciler.messages(
                  sessionID: sessionID,
                  limit: 50,
                  profile: profile,
                  password: password
              )
        else {
            errorMessage = """
                A message was interrupted before Hermes confirmed it. \
                The agent may have run it, so it was not sent again.
                """
            return .outcomeUnknown
        }

        if stored.contains(where: { $0.role == "user" && $0.content == turn.prompt }) {
            messages = stored.asTranscript()
            return .completed
        }
        errorMessage = "A message was interrupted before it reached Hermes. You can send it again."
        return .failed("The turn did not reach Hermes.")
    }

    private func recordPendingTurn(prompt: String) {
        let turn = PendingTurn(sessionID: sessionID, prompt: prompt)
        pendingTurn = turn
        Task { await persistPendingWork(turns: [turn]) }
    }

    private func clearPendingTurn() {
        guard pendingTurn != nil else { return }
        pendingTurn = nil
        Task { await persistPendingWork(turns: []) }
    }

    private func scheduleDraftSave() {
        draftSave?.cancel()
        draftSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            await persistPendingWork(turns: pendingTurn.map { [$0] } ?? [])
        }
    }

    private func persistPendingWork(turns: [PendingTurn]) async {
        await appModel.environment.pendingWork.save(PendingWork(
            draft: draft,
            draftSessionID: sessionID,
            uncertainTurns: turns
        ))
    }

    private func apply(_ update: TurnUpdate) {
        switch update {
        case let .accepted(responseID):
            if let responseID { previousResponseID = responseID }
        case let .delta(text):
            activeToolName = nil
            enqueue(text)
        case let .toolActivity(name, preview):
            activeToolName = preview.map { "\(name): \($0)" } ?? name
        case let .transcript(messages):
            serverTranscript = messages
        case let .fullTranscript(messages):
            replacementTranscript = messages
        case let .approval(request):
            pendingApproval = request
            activeToolName = nil
            startApprovalExpiry(for: request)
        case .approvalResolved:
            clearApproval()
        case let .state(state):
            apply(state)
        }
    }

    private func apply(_ state: TurnState) {
        turnState = state
        switch state {
        case .completed, .stopping:
            clearPendingTurn()
            finish()
        case let .failed(message):
            clearPendingTurn()
            commitStreamedText()
            errorMessage = message
            turn = nil
        case .outcomeUnknown:
            clearPendingTurn()
            commitStreamedText()
            errorMessage = """
                The connection dropped and Hermes did not confirm the outcome. \
                The agent may still be working, so this was not sent again. \
                Check your sessions before retrying.
                """
            turn = nil
        default:
            break
        }
    }

    private func enqueue(_ text: String) {
        pendingDelta += text
        guard flush == nil else { return }
        let generation = generation
        flush = Task { [weak self] in
            try? await Task.sleep(for: self?.flushInterval ?? .milliseconds(50))
            guard let self, generation == self.generation else { return }
            flush = nil
            drainPendingDelta()
        }
    }

    private func drainPendingDelta() {
        guard !pendingDelta.isEmpty else { return }
        streamingText += pendingDelta
        pendingDelta = ""
    }

    private func finish() {
        commitStreamedText()
        activeToolName = nil
        turn = nil
    }

    private func fail(_ error: Error) {
        commitStreamedText()
        turn = nil
        if case HermesConnectionError.cancelled = error {
            turnState = .completed
            return
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        turnState = .failed(message)
        errorMessage = message
        appModel.environment.logger.error("Chat turn failed", code: "chat_turn")
    }

    private func commitStreamedText() {
        flush?.cancel()
        flush = nil
        drainPendingDelta()

        // A full transcript already contains this turn, so replacing avoids the
        // duplication that appending would cause.
        if let transcript = replacementTranscript {
            replacementTranscript = nil
            serverTranscript = nil
            let rendered = transcript.asTranscript()
            if !rendered.isEmpty {
                streamingText = ""
                messages = rendered
                return
            }
        }

        // The server's transcript supersedes accumulated deltas: it also carries
        // this turn's tool calls and their results.
        if let transcript = serverTranscript {
            serverTranscript = nil
            let rendered = transcript.asTranscript()
            if !rendered.isEmpty {
                streamingText = ""
                messages.append(contentsOf: rendered)
                return
            }
        }

        let text = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        streamingText = ""
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(role: .assistant, content: text))
    }
}
