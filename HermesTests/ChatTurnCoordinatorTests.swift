import Foundation
import Testing
@testable import Hermes

/// Emits a scripted turn, optionally failing partway through.
private struct ScriptedChatClient: ChatStreaming {
    var events: [AgentEvent] = []
    var failure: Error?

    func stream(
        _ request: ChatTurnRequest,
        profile: ServerProfile,
        password: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let events = events
        let failure = failure
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish(throwing: failure)
        }
    }
}

/// Serves a session list that can differ before and after a turn.
private actor ScriptedReconciler: TranscriptReconciling {
    private var pages: [[SessionSummary]]
    private(set) var callCount = 0

    init(pages: [[SessionSummary]]) {
        self.pages = pages
    }

    func session(id: String, profile: ServerProfile, password: String) async throws -> SessionSummary {
        throw HermesConnectionError.unavailable(404)
    }

    func sessions(limit: Int, profile: ServerProfile, password: String) async throws -> [SessionSummary] {
        defer { callCount += 1 }
        return pages[min(callCount, pages.count - 1)]
    }

    func messages(
        sessionID: String,
        limit: Int,
        profile: ServerProfile,
        password: String
    ) async throws -> [SessionMessage] {
        []
    }
}

private func summary(id: String, messageCount: Int, preview: String? = nil) -> SessionSummary {
    SessionSummary(
        id: id,
        source: "api_server",
        model: "hermes-agent",
        title: nil,
        messageCount: messageCount,
        toolCallCount: 0,
        preview: preview,
        lastActive: nil
    )
}

@Suite("Chat turn coordinator")
struct ChatTurnCoordinatorTests {
    private func profile() throws -> ServerProfile {
        try ServerProfile.validated(name: "Hermes", urlText: "https://hermes.example.ts.net:8443", username: "")
    }

    private func collect(_ coordinator: ChatTurnCoordinator, profile: ServerProfile) async -> [TurnUpdate] {
        var updates: [TurnUpdate] = []
        let request = ChatTurnRequest(messages: [ChatMessage(role: .user, content: "hi")])
        for await update in await coordinator.start(request, profile: profile, password: "sk-test") {
            updates.append(update)
        }
        return updates
    }

    private func states(_ updates: [TurnUpdate]) -> [TurnState] {
        updates.compactMap { if case let .state(state) = $0 { return state } else { return nil } }
    }

    @Test("A clean turn moves from sending through streaming to completed")
    func completesCleanly() async throws {
        let coordinator = ChatTurnCoordinator(chatClient: ScriptedChatClient(events: [
            .turnAccepted(id: "resp_1"),
            .textDelta("OK"),
            .done
        ]))

        let updates = await collect(coordinator, profile: try profile())

        #expect(states(updates) == [.sending, .streaming, .completed])
        #expect(updates.contains(.accepted(responseID: "resp_1")))
        #expect(updates.contains(.delta("OK")))
    }

    @Test("A rejected request is safe to retry because no work started")
    func rejectionIsRetryable() async throws {
        let coordinator = ChatTurnCoordinator(chatClient: ScriptedChatClient(
            failure: HermesConnectionError.unauthorized
        ))

        let states = states(await collect(coordinator, profile: try profile()))

        #expect(states.last?.allowsRetry == true)
        #expect(states.contains(.reconciling) == false)
    }

    @Test("An unaccepted drop with no reconciler reports an unknown outcome, never a retry")
    func ambiguousDropWithoutReconcilerIsUnknown() async throws {
        let coordinator = ChatTurnCoordinator(chatClient: ScriptedChatClient(
            failure: HermesConnectionError.offline
        ))

        let states = states(await collect(coordinator, profile: try profile()))

        #expect(states.contains(.reconciling))
        #expect(states.last == .outcomeUnknown)
        #expect(states.last?.allowsRetry == false)
    }

    @Test("Reconciliation proving the turn landed reports completion, not a resend")
    func reconcilesLandedTurn() async throws {
        let reconciler = ScriptedReconciler(pages: [
            [summary(id: "s1", messageCount: 2)],
            [summary(id: "s1", messageCount: 4)]
        ])
        let coordinator = ChatTurnCoordinator(
            chatClient: ScriptedChatClient(events: [.turnAccepted(id: "r")], failure: HermesConnectionError.offline),
            reconciler: reconciler
        )

        let states = states(await collect(coordinator, profile: try profile()))

        #expect(states.contains(.reconciling))
        #expect(states.last == .completed)
    }

    @Test("Reconciliation proving the turn never landed makes it retryable")
    func reconcilesMissingTurn() async throws {
        let reconciler = ScriptedReconciler(pages: [
            [summary(id: "s1", messageCount: 2)],
            [summary(id: "s1", messageCount: 2)]
        ])
        let coordinator = ChatTurnCoordinator(
            chatClient: ScriptedChatClient(failure: HermesConnectionError.offline),
            reconciler: reconciler
        )

        let states = states(await collect(coordinator, profile: try profile()))

        #expect(states.last?.allowsRetry == true)
    }

    @Test("A new session carrying the prompt counts as landed")
    func recognisesNewSessionByPreview() async throws {
        let reconciler = ScriptedReconciler(pages: [
            [],
            [summary(id: "s2", messageCount: 2, preview: "hi")]
        ])
        let coordinator = ChatTurnCoordinator(
            chatClient: ScriptedChatClient(failure: HermesConnectionError.timedOut),
            reconciler: reconciler
        )

        let states = states(await collect(coordinator, profile: try profile()))

        #expect(states.last == .completed)
    }

    @Test("Cancellation is reported as stopping, not as a failure")
    func cancellationIsNotFailure() async throws {
        let coordinator = ChatTurnCoordinator(chatClient: ScriptedChatClient(
            events: [.textDelta("partial")],
            failure: HermesConnectionError.cancelled
        ))

        let states = states(await collect(coordinator, profile: try profile()))

        #expect(states.last == .stopping)
        #expect(states.contains(.reconciling) == false)
    }
}

@Suite("Turn state")
struct TurnStateTests {
    @Test("Only a proven failure permits a resend")
    func retryIsNarrow() {
        #expect(TurnState.failed("x").allowsRetry)
        #expect(TurnState.outcomeUnknown.allowsRetry == false)
        #expect(TurnState.reconciling.allowsRetry == false)
        #expect(TurnState.completed.allowsRetry == false)
    }

    @Test("Active states keep the composer disabled")
    func activeStates() {
        #expect(TurnState.sending.isActive)
        #expect(TurnState.streaming.isActive)
        #expect(TurnState.reconciling.isActive)
        #expect(TurnState.completed.isActive == false)
        #expect(TurnState.outcomeUnknown.isActive == false)
    }
}
