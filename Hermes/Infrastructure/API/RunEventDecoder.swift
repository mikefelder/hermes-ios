import Foundation

/// A server-side request for permission to run a dangerous action.
///
/// Correlation is positional: the server keeps one FIFO queue per run and the
/// response carries no request identifier, so at most one approval is treated as
/// outstanding at a time. The payload is retained locally because a dropped
/// stream cannot be replayed and run status carries only an event name.
nonisolated struct ApprovalRequest: Codable, Sendable, Equatable, Identifiable {
    let runID: String
    var command: String
    var reason: String?
    var choices: [String]
    var receivedAt: Date

    var id: String { runID }

    /// The server computes the offered choices; do not derive them locally.
    var allowsSession: Bool { choices.contains("session") }
    var allowsAlways: Bool { choices.contains("always") }

    init(
        runID: String,
        command: String,
        reason: String?,
        choices: [String],
        receivedAt: Date = .now
    ) {
        self.runID = runID
        self.command = command
        self.reason = reason
        self.choices = choices.isEmpty ? ["once", "deny"] : choices
        self.receivedAt = receivedAt
    }
}

/// Decodes the run event stream from `GET /v1/runs/{run_id}/events`.
///
/// This stream is framed differently from the session chat stream: frames are
/// unnamed and the type lives in an `event` key inside the JSON. It is a separate
/// decoder rather than a union because the two also disagree on field names.
nonisolated struct RunEventDecoder {
    func decode(_ event: SSEEvent) -> [AgentEvent] {
        guard let data = event.data.data(using: .utf8),
              let payload = try? JSONDecoder().decode(RunEvent.self, from: data),
              let type = payload.event else {
            return []
        }

        switch type {
        case "message.delta":
            guard let delta = payload.delta, !delta.isEmpty else { return [] }
            return [.textDelta(delta)]

        case "tool.started":
            guard let name = payload.tool, !name.hasPrefix("_") else { return [] }
            return [.toolActivity(name: name, preview: payload.preview)]

        case "approval.request":
            guard let runID = payload.runID else { return [] }
            return [.approvalRequested(ApprovalRequest(
                runID: runID,
                command: payload.command ?? "",
                reason: payload.description,
                choices: payload.choices ?? []
            ))]

        case "approval.responded":
            return [.approvalResolved]

        case "run.completed":
            return [.finished(reason: "completed"), .done]

        case "run.failed":
            return [.turnFailed(payload.error ?? "The run failed."), .done]

        case "run.cancelled":
            return [.finished(reason: "cancelled"), .done]

        default:
            return []
        }
    }
}

/// Minimal wire model. The run stream names tools `tool`, not `tool_name`.
private nonisolated struct RunEvent: Decodable {
    var event: String?
    var runID: String?
    var delta: String?
    var tool: String?
    var preview: String?
    var command: String?
    var description: String?
    var choices: [String]?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case event
        case runID = "run_id"
        case delta
        case tool
        case preview
        case command
        case description
        case choices
        case error
    }
}
