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

    var displayText: String? {
        guard let content else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : content
    }

    /// Tool work carried by this message. Names beginning with `_` are internal
    /// pseudo-tools that restate the assistant's own text.
    var activityEntries: [ToolActivity] {
        var entries: [ToolActivity] = []

        for call in toolCalls ?? [] {
            let name = call.function?.name ?? "tool"
            guard !name.hasPrefix("_") else { continue }
            entries.append(ToolActivity(name: name, detail: call.function?.arguments))
        }

        if role == "tool", entries.isEmpty, let content, !content.isEmpty {
            let name = toolName ?? "result"
            guard !name.hasPrefix("_") else { return entries }
            entries.append(ToolActivity(name: name, detail: content))
        }

        return entries
    }
}

extension Array where Element == SessionMessage {
    /// Flatten stored messages into a display transcript.
    ///
    /// System prompts are configuration rather than conversation, and tool work is
    /// attached to the reply it produced instead of being shown as its own turn.
    func asTranscript() -> [ChatMessage] {
        var transcript: [ChatMessage] = []
        var pending: [ToolActivity] = []

        // Work with no reply after it still has to be reachable.
        func flushPending(at date: Date) {
            guard !pending.isEmpty else { return }
            transcript.append(ChatMessage(role: .assistant, content: "", createdAt: date, activity: pending))
            pending = []
        }

        for message in self {
            switch ChatRole(rawValue: message.role) {
            case .system, nil:
                continue
            case .tool:
                pending.append(contentsOf: message.activityEntries)
            case .assistant:
                pending.append(contentsOf: message.activityEntries)
                if let text = message.displayText {
                    transcript.append(ChatMessage(
                        role: .assistant,
                        content: text,
                        createdAt: message.createdAt,
                        activity: pending
                    ))
                    pending = []
                }
            case .user:
                flushPending(at: message.createdAt)
                if let text = message.displayText {
                    transcript.append(ChatMessage(
                        role: .user,
                        content: text,
                        createdAt: message.createdAt
                    ))
                }
            }
        }

        flushPending(at: last?.createdAt ?? .now)
        return transcript
    }
}
