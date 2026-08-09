import Foundation

/// Decodes OpenAI-compatible Chat Completions streaming events into ``AgentEvent``s.
///
/// Each `SSEEvent.data` payload is either the sentinel `"[DONE]"` or a
/// `chat.completion.chunk` JSON object. Inline assistant text is treated purely as
/// display content; it is never interpreted as trusted structured tool metadata.
///
/// The decoder is deliberately tolerant: payloads that cannot be decoded into the
/// expected shape yield no events instead of failing the stream, so a single
/// malformed or unknown chunk cannot abort an in-progress turn.
nonisolated struct ChatCompletionsEventDecoder {
    /// Map one Server-Sent Event into zero or more normalized agent events.
    func decode(_ event: SSEEvent) -> [AgentEvent] {
        let payload = event.data.trimmingCharacters(in: .whitespacesAndNewlines)

        if payload == "[DONE]" {
            return [.done]
        }

        guard
            let data = payload.data(using: .utf8),
            let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
            let choice = chunk.choices.first
        else {
            return []
        }

        var events: [AgentEvent] = []

        if let roleName = choice.delta.role, let role = ChatRole(rawValue: roleName) {
            events.append(.messageStarted(role: role))
        }

        if let content = choice.delta.content, !content.isEmpty {
            events.append(.textDelta(content))
        }

        if let reason = choice.finishReason {
            events.append(.finished(reason: reason))
        }

        return events
    }
}

/// Minimal wire model for a Chat Completions streaming chunk. Unknown fields are ignored.
private nonisolated struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var role: String?
            var content: String?
        }

        var delta: Delta
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    var choices: [Choice]
}
