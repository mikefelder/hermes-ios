import Foundation

/// Decodes the session-scoped chat stream from
/// `POST /api/sessions/{id}/chat/stream`.
///
/// This surface names its events, and unlike Chat Completions and Responses it
/// reports tool activity directly. Tool output is display-only; it is never
/// interpreted as an instruction or an approval.
nonisolated struct SessionChatEventDecoder {
    func decode(_ event: SSEEvent) -> [AgentEvent] {
        let payload = decodePayload(event.data)

        switch event.type {
        case "run.started":
            guard let runID = payload?.runID ?? payload?.sessionID else { return [] }
            return [.turnAccepted(id: runID)]

        case "message.started":
            return [.messageStarted(role: .assistant)]

        case "assistant.delta":
            guard let delta = payload?.delta, !delta.isEmpty else { return [] }
            return [.textDelta(delta)]

        case "tool.started":
            // `tool.progress` is deliberately ignored: its tool name is always the
            // `_thinking` channel and its delta duplicates assistant text.
            guard let name = payload?.toolName, !name.hasPrefix("_") else { return [] }
            return [.toolActivity(name: name, preview: payload?.preview)]

        case "run.completed":
            // The server sends the turn's true transcript here, including tool
            // results that no incremental event carries.
            guard let messages = payload?.messages, !messages.isEmpty else {
                return [.finished(reason: "completed")]
            }
            return [.transcript(messages), .finished(reason: "completed")]

        case "done":
            return [.done]

        default:
            return []
        }
    }

    private func decodePayload(_ data: String) -> SessionChatEvent? {
        guard let raw = data.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SessionChatEvent.self, from: raw)
    }
}

private nonisolated struct SessionChatEvent: Decodable {
    var delta: String?
    var toolName: String?
    var preview: String?
    var sessionID: String?
    var runID: String?
    var messages: [SessionMessage]?

    enum CodingKeys: String, CodingKey {
        case delta
        case toolName = "tool_name"
        case preview
        case sessionID = "session_id"
        case runID = "run_id"
        case messages
    }
}
