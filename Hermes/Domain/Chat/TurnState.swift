import Foundation

/// Lifecycle of a single user turn.
///
/// The distinction that matters is ``reconciling``: a turn whose outcome is
/// genuinely unknown because the transport failed after the request may have
/// reached the server but before the server acknowledged it. Such a turn is never
/// retried automatically, because the work may already be running.
nonisolated enum TurnState: Equatable, Sendable {
    case idle
    /// Request is being sent; nothing has been acknowledged yet.
    case sending
    /// The server acknowledged the turn and output is arriving.
    case streaming
    /// The local stream was cancelled by the user.
    case stopping
    case completed
    /// Failed before the server could have accepted it, so retry is safe.
    case failed(String)
    /// Failed in the ambiguous window. The turn may or may not be running.
    case reconciling
    /// Reconciliation finished without proving what happened.
    case outcomeUnknown

    var isActive: Bool {
        switch self {
        case .sending, .streaming, .stopping, .reconciling: true
        default: false
        }
    }

    /// Whether resending the same prompt is known to be safe.
    var allowsRetry: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// A server session as described by `GET /api/sessions`.
nonisolated struct SessionSummary: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    var source: String?
    var model: String?
    var title: String?
    var messageCount: Int
    var toolCallCount: Int?
    var preview: String?
    var lastActive: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case model
        case title
        case messageCount = "message_count"
        case toolCallCount = "tool_call_count"
        case preview
        case lastActive = "last_active"
    }
}

nonisolated struct SessionListPage: Decodable, Sendable {
    var data: [SessionSummary]
    var hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}

nonisolated struct SessionEnvelope: Decodable, Sendable {
    var session: SessionSummary
}

/// Reads and creates the agent's sessions, and answers whether an ambiguous turn
/// actually reached the server.
protocol SessionServicing: Sendable {
    func createSession(profile: ServerProfile, password: String) async throws -> SessionSummary
    func session(id: String, profile: ServerProfile, password: String) async throws -> SessionSummary
    func sessions(limit: Int, profile: ServerProfile, password: String) async throws -> [SessionSummary]
    func messages(sessionID: String, limit: Int, profile: ServerProfile, password: String) async throws -> [SessionMessage]
}
