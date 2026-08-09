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
    var draft = ""
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

    init(appModel: AppModel) {
        self.appModel = appModel
        self.coordinator = ChatTurnCoordinator(
            chatClient: appModel.environment.chatClient,
            reconciler: appModel.environment.sessionsClient
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
                let request = ChatTurnRequest(
                    messages: messages,
                    model: capabilities.models.first,
                    wireProtocol: capabilities.supportsResponses ? .responses : .chatCompletions,
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

    private func apply(_ update: TurnUpdate) {
        switch update {
        case let .accepted(responseID):
            if let responseID { previousResponseID = responseID }
        case let .delta(text):
            enqueue(text)
        case let .state(state):
            apply(state)
        }
    }

    private func apply(_ state: TurnState) {
        turnState = state
        switch state {
        case .completed, .stopping:
            finish()
        case let .failed(message):
            commitStreamedText()
            errorMessage = message
            turn = nil
        case .outcomeUnknown:
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
        let text = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        streamingText = ""
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(role: .assistant, content: text))
    }
}
