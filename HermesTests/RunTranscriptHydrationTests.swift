import Foundation
import Testing
@testable import Hermes

/// Serves a session transcript, so a run turn can be hydrated after it completes.
private actor TranscriptReconciler: SessionServicing {
    private let stored: [SessionMessage]
    private(set) var messageFetches = 0

    init(stored: [SessionMessage]) {
        self.stored = stored
    }

    func createSession(profile: ServerProfile, password: String) async throws -> SessionSummary {
        throw HermesConnectionError.unavailable(404)
    }

    func session(id: String, profile: ServerProfile, password: String) async throws -> SessionSummary {
        throw HermesConnectionError.unavailable(404)
    }

    func sessions(limit: Int, profile: ServerProfile, password: String) async throws -> [SessionSummary] {
        []
    }

    func messages(
        sessionID: String,
        limit: Int,
        profile: ServerProfile,
        password: String
    ) async throws -> [SessionMessage] {
        messageFetches += 1
        return stored
    }

    func rename(id: String, title: String, profile: ServerProfile, password: String) async throws -> SessionSummary {
        throw HermesConnectionError.unavailable(404)
    }

    func delete(id: String, profile: ServerProfile, password: String) async throws {}

    func fork(id: String, profile: ServerProfile, password: String) async throws -> SessionSummary {
        throw HermesConnectionError.unavailable(404)
    }
}

private struct CompletingChatClient: ChatStreaming {
    var events: [AgentEvent]

    func stream(
        _ request: ChatTurnRequest,
        profile: ServerProfile,
        password: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let events = events
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

@Suite("Run turn transcript hydration")
struct RunTranscriptHydrationTests {
    private func profile() throws -> ServerProfile {
        try ServerProfile.validated(name: "Hermes", urlText: "https://hermes.example.ts.net:8443", username: "")
    }

    private func message(id: Int, role: String, content: String) -> SessionMessage {
        SessionMessage(
            id: id,
            role: role,
            content: content,
            toolName: nil,
            toolCalls: nil,
            timestamp: nil
        )
    }

    private func collect(
        _ coordinator: ChatTurnCoordinator,
        wireProtocol: ChatWireProtocol
    ) async throws -> [TurnUpdate] {
        var updates: [TurnUpdate] = []
        let request = ChatTurnRequest(
            messages: [ChatMessage(role: .user, content: "run something")],
            wireProtocol: wireProtocol
        )
        for await update in await coordinator.start(request, profile: try profile(), password: "sk-test") {
            updates.append(update)
        }
        return updates
    }

    @Test("A completed run fetches the session transcript, which the stream never sends")
    func hydratesAfterRun() async throws {
        let reconciler = TranscriptReconciler(stored: [
            message(id: 1, role: "user", content: "run something"),
            message(id: 2, role: "tool", content: "{\"output\":\"done\"}"),
            message(id: 3, role: "assistant", content: "Finished")
        ])
        let coordinator = ChatTurnCoordinator(
            chatClient: CompletingChatClient(events: [.turnAccepted(id: "run_1"), .textDelta("Fin"), .done]),
            reconciler: reconciler
        )

        let updates = try await collect(coordinator, wireProtocol: .run(sessionID: "api-1"))

        let hydrated = updates.compactMap { update -> [SessionMessage]? in
            if case let .fullTranscript(messages) = update { return messages } else { return nil }
        }
        #expect(hydrated.count == 1)
        #expect(hydrated.first?.count == 3)
        #expect(await reconciler.messageFetches == 1)
    }

    @Test("A session-chat turn does not refetch, because its stream carries the transcript")
    func doesNotHydrateSessionChat() async throws {
        let reconciler = TranscriptReconciler(stored: [message(id: 1, role: "assistant", content: "hi")])
        let coordinator = ChatTurnCoordinator(
            chatClient: CompletingChatClient(events: [.textDelta("hi"), .done]),
            reconciler: reconciler
        )

        let updates = try await collect(coordinator, wireProtocol: .sessionChat(sessionID: "api-1"))

        #expect(updates.contains { if case .fullTranscript = $0 { return true } else { return false } } == false)
        #expect(await reconciler.messageFetches == 0)
    }

    @Test("Hydration failure still completes the turn rather than losing it")
    func toleratesHydrationFailure() async throws {
        let coordinator = ChatTurnCoordinator(
            chatClient: CompletingChatClient(events: [.turnAccepted(id: "run_1"), .textDelta("Fin"), .done]),
            reconciler: TranscriptReconciler(stored: [])
        )

        let updates = try await collect(coordinator, wireProtocol: .run(sessionID: "api-1"))

        let states = updates.compactMap { update -> TurnState? in
            if case let .state(state) = update { return state } else { return nil }
        }
        #expect(states.last == .completed)
    }
}
