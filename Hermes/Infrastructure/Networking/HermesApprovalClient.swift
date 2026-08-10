import Foundation

/// Status of a submitted run, used to resolve a turn whose event stream was lost.
nonisolated struct RunStatus: Decodable, Sendable, Equatable {
    var status: String
    var lastEvent: String?

    enum CodingKeys: String, CodingKey {
        case status
        case lastEvent = "last_event"
    }

    var isTerminal: Bool {
        ["completed", "failed", "cancelled", "error"].contains(status.lowercased())
    }

    var succeeded: Bool { status.lowercased() == "completed" }
}

/// Answers a pending approval and reports run status.
///
/// The approval response is bound to the run, not to a request identifier: the
/// server resolves the oldest pending approval in that run's queue.
protocol RunServicing: Sendable {
    func respond(
        runID: String,
        choice: String,
        profile: ServerProfile,
        password: String
    ) async throws -> ApprovalOutcome

    func status(runID: String, profile: ServerProfile, password: String) async throws -> RunStatus

    /// Ask the server to stop the run. This is not the same as disconnecting: it
    /// interrupts work that would otherwise keep going.
    func stop(runID: String, profile: ServerProfile, password: String) async throws
}

nonisolated enum ApprovalOutcome: Sendable, Equatable {
    case resolved
    /// Something else already answered it, here or on another client.
    case alreadyResolved
}

nonisolated struct HermesRunClient: RunServicing {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    func respond(
        runID: String,
        choice: String,
        profile: ServerProfile,
        password: String
    ) async throws -> ApprovalOutcome {
        let body = try JSONEncoder().encode(["choice": choice])
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .post("v1/runs/\(runID)/approval", body: body)

        switch response.statusCode {
        case 200..<300:
            return .resolved
        case 409:
            return .alreadyResolved
        default:
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
    }

    func status(runID: String, profile: ServerProfile, password: String) async throws -> RunStatus {
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .get("v1/runs/\(runID)")
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        return try JSONDecoder().decode(RunStatus.self, from: response.data)
    }

    func stop(runID: String, profile: ServerProfile, password: String) async throws {
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .post("v1/runs/\(runID)/stop", body: Data("{}".utf8))
        // A run that already finished cannot be stopped, which is not an error.
        guard (200..<300).contains(response.statusCode) || response.statusCode == 409 else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
    }
}
