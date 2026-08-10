import Foundation

/// Incremental report from a running turn.
nonisolated enum TurnUpdate: Sendable, Equatable {
    case state(TurnState)
    case delta(String)
    /// A server-side tool is running, for display only.
    case toolActivity(name: String, preview: String?)
    /// The server's transcript for the finished turn.
    case transcript([SessionMessage])
    /// The agent is blocked awaiting permission.
    case approval(ApprovalRequest)
    /// A pending approval was resolved.
    case approvalResolved
    /// The server acknowledged the turn; carries a continuation ID when the
    /// protocol provides one.
    case accepted(responseID: String?)
}

/// Owns exactly one foreground stream per conversation and decides what a failure
/// means.
///
/// The central rule from the architecture spec: a turn is only safe to retry when
/// it definitely never started. Anything that fails in the ambiguous window is
/// reconciled against the server's own transcript, and is never replayed
/// automatically, because the agent may already be doing expensive or destructive
/// work.
actor ChatTurnCoordinator {
    private let chatClient: any ChatStreaming
    private let reconciler: (any SessionServicing)?

    private var active: Task<Void, Never>?
    /// Stale events from a superseded turn are discarded by comparing generations.
    private var generation = UUID()

    init(chatClient: any ChatStreaming, reconciler: (any SessionServicing)? = nil) {
        self.chatClient = chatClient
        self.reconciler = reconciler
    }

    /// Cancel the local stream. This disconnects the client; it does not stop
    /// remote work.
    func cancelActive() {
        generation = UUID()
        active?.cancel()
        active = nil
    }

    func start(
        _ request: ChatTurnRequest,
        profile: ServerProfile,
        password: String
    ) -> AsyncStream<TurnUpdate> {
        cancelActive()
        let generation = generation

        return AsyncStream { continuation in
            let task = Task {
                await run(
                    request,
                    profile: profile,
                    password: password,
                    generation: generation,
                    continuation: continuation
                )
                continuation.finish()
            }
            active = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ request: ChatTurnRequest,
        profile: ServerProfile,
        password: String,
        generation: UUID,
        continuation: AsyncStream<TurnUpdate>.Continuation
    ) async {
        guard generation == self.generation else { return }
        continuation.yield(.state(.sending))

        // Captured before any network I/O so an ambiguous failure can be compared
        // against the server's transcript afterwards.
        let baseline = await snapshot(profile: profile, password: password)
        var accepted = false

        do {
            for try await event in chatClient.stream(request, profile: profile, password: password) {
                guard generation == self.generation else { return }
                switch event {
                case let .turnAccepted(id):
                    accepted = true
                    continuation.yield(.accepted(responseID: id))
                    continuation.yield(.state(.streaming))
                case .messageStarted:
                    if !accepted {
                        accepted = true
                        continuation.yield(.accepted(responseID: nil))
                        continuation.yield(.state(.streaming))
                    }
                case let .textDelta(text):
                    if !accepted {
                        accepted = true
                        continuation.yield(.accepted(responseID: nil))
                        continuation.yield(.state(.streaming))
                    }
                    continuation.yield(.delta(text))
                case let .toolActivity(name, preview):
                    continuation.yield(.toolActivity(name: name, preview: preview))
                case let .transcript(messages):
                    continuation.yield(.transcript(messages))
                case let .approvalRequested(request):
                    accepted = true
                    continuation.yield(.approval(request))
                case .approvalResolved:
                    continuation.yield(.approvalResolved)
                case let .turnFailed(message):
                    continuation.yield(.state(.failed(message)))
                    return
                case .finished:
                    break
                case .done:
                    continuation.yield(.state(.completed))
                    return
                }
            }
            guard generation == self.generation else { return }
            continuation.yield(.state(.completed))
        } catch {
            guard generation == self.generation else { return }
            await handle(
                error,
                accepted: accepted,
                prompt: request.messages.last?.content,
                baseline: baseline,
                profile: profile,
                password: password,
                continuation: continuation
            )
        }
    }

    private func handle(
        _ error: Error,
        accepted: Bool,
        prompt: String?,
        baseline: [SessionSummary]?,
        profile: ServerProfile,
        password: String,
        continuation: AsyncStream<TurnUpdate>.Continuation
    ) async {
        if case HermesConnectionError.cancelled = error {
            continuation.yield(.state(.stopping))
            return
        }

        if !accepted, isSafeToRetry(error) {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            continuation.yield(.state(.failed(message)))
            return
        }

        continuation.yield(.state(.reconciling))
        continuation.yield(.state(await reconcile(
            prompt: prompt,
            baseline: baseline,
            profile: profile,
            password: password
        )))
    }

    /// True only for failures that prove the server never began the turn.
    private func isSafeToRetry(_ error: Error) -> Bool {
        guard let error = error as? HermesConnectionError else { return false }
        switch error {
        case .invalidConfiguration, .unauthorized, .forbidden, .redirectedOutsideServer, .tlsFailure:
            return true
        case .unavailable:
            // The server answered and refused, so no work was started.
            return true
        default:
            return false
        }
    }

    private func snapshot(profile: ServerProfile, password: String) async -> [SessionSummary]? {
        guard let reconciler else { return nil }
        return try? await reconciler.sessions(limit: 10, profile: profile, password: password)
    }

    /// Compare the server's sessions against the pre-send snapshot to decide
    /// whether the turn landed. Without a reconciler the honest answer is that the
    /// outcome is unknown.
    private func reconcile(
        prompt: String?,
        baseline: [SessionSummary]?,
        profile: ServerProfile,
        password: String
    ) async -> TurnState {
        guard let reconciler, let baseline else { return .outcomeUnknown }
        guard let current = try? await reconciler.sessions(limit: 10, profile: profile, password: password) else {
            return .outcomeUnknown
        }

        let before = Dictionary(baseline.map { ($0.id, $0.messageCount) }, uniquingKeysWith: { first, _ in first })
        let landed = current.contains { session in
            if let previous = before[session.id] {
                return session.messageCount > previous
            }
            // A session that did not exist before, carrying this prompt, is ours.
            return session.preview.map { preview in
                prompt.map { $0.hasPrefix(preview) || preview.hasPrefix($0) } ?? false
            } ?? false
        }

        return landed ? .completed : .failed("The turn did not reach Hermes. You can send it again.")
    }
}
