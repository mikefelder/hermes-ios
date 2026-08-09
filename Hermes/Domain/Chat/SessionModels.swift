import Foundation

/// A stored message from `GET /api/sessions/{id}/messages`.
nonisolated struct SessionMessage: Decodable, Sendable, Equatable, Identifiable {
    struct ToolCall: Decodable, Sendable, Equatable {
        struct Function: Decodable, Sendable, Equatable {
            var name: String?
            var arguments: String?
        }

        var id: String?
        var function: Function?
    }

    let id: Int
    var role: String
    var content: String?
    var toolName: String?
    var toolCalls: [ToolCall]?
    var timestamp: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case toolName = "tool_name"
        case toolCalls = "tool_calls"
        case timestamp
    }
}

nonisolated struct SessionMessagePage: Decodable, Sendable {
    var sessionID: String?
    var data: [SessionMessage]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case data
    }
}

extension SessionMessage {
    var createdAt: Date {
        timestamp.map(Date.init(timeIntervalSince1970:)) ?? .now
    }

    /// Render a stored message for the transcript.
    ///
    /// Tool activity is presented as fenced code so it reuses the Markdown code
    /// renderer, and so arguments and output are always shown as inert text.
    func asChatMessages() -> [ChatMessage] {
        var rendered: [ChatMessage] = []

        if let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rendered.append(ChatMessage(
                role: ChatRole(rawValue: role) ?? .assistant,
                content: content,
                createdAt: createdAt
            ))
        }

        for call in toolCalls ?? [] {
            let name = call.function?.name ?? "tool"
            let arguments = call.function?.arguments ?? ""
            rendered.append(ChatMessage(
                role: .tool,
                content: "**\(name)**\n\n```json\n\(arguments)\n```",
                createdAt: createdAt
            ))
        }

        if role == "tool", let content, !content.isEmpty, rendered.isEmpty {
            rendered.append(ChatMessage(
                role: .tool,
                content: "**\(toolName ?? "result")**\n\n```json\n\(content)\n```",
                createdAt: createdAt
            ))
        }

        return rendered
    }
}

extension Array where Element == SessionMessage {
    /// Flatten stored messages into a display transcript, dropping the empty
    /// assistant turns that only carry tool calls.
    func asTranscript() -> [ChatMessage] {
        flatMap { $0.asChatMessages() }
    }
}
