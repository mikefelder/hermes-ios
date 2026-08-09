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
    private(set) var isStreaming = false
    var draft = ""
    var errorMessage: String?

    private let appModel: AppModel
    private var turn: Task<Void, Never>?
    private var generation = 0

    init(appModel: AppModel) {
        self.appModel = appModel
    }

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
        messages.append(ChatMessage(role: .user, content: prompt))
        start()
    }

    /// Stop the active turn, keeping whatever text already arrived.
    func stop() {
        guard isStreaming else { return }
        generation &+= 1
        turn?.cancel()
        turn = nil
        commitStreamedText()
        isStreaming = false
    }

    func clear() {
        stop()
        messages.removeAll()
        streamingText = ""
        errorMessage = nil
    }

    private func start() {
        generation &+= 1
        let generation = generation
        isStreaming = true
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

                let stream = appModel.environment.chatClient.stream(
                    messages: messages,
                    model: appModel.capabilities.models.first,
                    profile: profile,
                    password: password
                )

                for try await event in stream {
                    guard generation == self.generation else { return }
                    apply(event)
                }
                guard generation == self.generation else { return }
                finish()
            } catch {
                guard generation == self.generation else { return }
                fail(error)
            }
        }
    }

    private func apply(_ event: AgentEvent) {
        switch event {
        case .messageStarted:
            break
        case let .textDelta(text):
            streamingText += text
        case .finished:
            break
        case .done:
            finish()
        }
    }

    private func finish() {
        commitStreamedText()
        isStreaming = false
        turn = nil
    }

    private func fail(_ error: Error) {
        commitStreamedText()
        isStreaming = false
        turn = nil
        if case HermesConnectionError.cancelled = error { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        appModel.environment.logger.error("Chat turn failed", code: "chat_turn")
    }

    private func commitStreamedText() {
        let text = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        streamingText = ""
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(role: .assistant, content: text))
    }
}
