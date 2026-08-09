import Foundation

/// Decodes OpenAI Responses streaming events into ``AgentEvent``s.
///
/// The Responses protocol has no `[DONE]` sentinel; `response.completed` is the
/// terminator. Unknown event types yield no events so a newer server cannot abort
/// an in-progress turn.
///
/// Tool items arrive already executed server-side and are replayed for display.
/// They are never treated as calls for this client to perform.
nonisolated struct ResponsesEventDecoder {
    func decode(_ event: SSEEvent) -> [AgentEvent] {
        guard let data = event.data.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ResponseStreamEvent.self, from: data) else {
            return []
        }

        switch payload.type ?? event.type {
        case "response.created":
            guard let id = payload.response?.id else { return [] }
            return [.turnAccepted(id: id)]

        case "response.output_item.added":
            guard payload.item?.type == "message" else { return [] }
            let role = payload.item?.role.flatMap(ChatRole.init(rawValue:)) ?? .assistant
            return [.messageStarted(role: role)]

        case "response.output_text.delta":
            guard let delta = payload.delta, !delta.isEmpty else { return [] }
            return [.textDelta(delta)]

        case "response.completed":
            return [.finished(reason: payload.response?.status ?? "completed"), .done]

        case "response.failed", "response.incomplete":
            return [.finished(reason: payload.response?.status ?? "failed"), .done]

        default:
            return []
        }
    }
}

/// Minimal wire model. Unknown fields are ignored by design.
private nonisolated struct ResponseStreamEvent: Decodable {
    struct Response: Decodable {
        var id: String?
        var status: String?
    }

    struct Item: Decodable {
        var type: String?
        var role: String?
    }

    var type: String?
    var delta: String?
    var response: Response?
    var item: Item?
}
