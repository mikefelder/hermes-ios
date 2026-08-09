import Foundation

/// A chat participant role, aligned with the OpenAI-compatible Hermes chat API.
nonisolated enum ChatRole: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

/// A single persisted chat message in a conversation transcript.
///
/// This is a domain value type. Transport DTOs are decoded separately and mapped
/// into these models so views never depend on wire formats.
nonisolated struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var role: ChatRole
    var content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

/// A transport-independent streaming event produced while a turn is generated.
///
/// Concrete transports (Chat Completions SSE today, Responses/JSON-RPC later)
/// decode into this stable enum. Views and coordinators only consume `AgentEvent`.
nonisolated enum AgentEvent: Sendable, Equatable {
    /// The server acknowledged the turn and issued an identifier for it. Receiving
    /// this is what makes a send "accepted", so a later drop is recoverable rather
    /// than ambiguous.
    case turnAccepted(id: String)
    /// The assistant message has started; carries the advertised role.
    case messageStarted(role: ChatRole)
    /// An incremental text fragment for the active assistant message.
    case textDelta(String)
    /// A server-side tool is running. Display only; the client never executes tools.
    case toolActivity(name: String, preview: String?)
    /// The server's authoritative transcript for the finished turn, including tool
    /// results that the incremental events do not carry.
    case transcript([SessionMessage])
    /// The model reported a terminal finish reason for the turn (e.g. `stop`, `length`).
    case finished(reason: String?)
    /// The stream signalled completion via its terminator.
    case done
}
