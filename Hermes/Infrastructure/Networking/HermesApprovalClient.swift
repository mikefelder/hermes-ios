import Foundation

/// Answers a pending approval.
///
/// The response is bound to the run, not to a request identifier: the server
/// resolves the oldest pending approval in that run's queue.
protocol ApprovalResponding: Sendable {
    func respond(
        runID: String,
        choice: String,
        profile: ServerProfile,
        password: String
    ) async throws -> ApprovalOutcome
}

nonisolated enum ApprovalOutcome: Sendable, Equatable {
    case resolved
    /// Something else already answered it, here or on another client.
    case alreadyResolved
}

nonisolated struct HermesApprovalClient: ApprovalResponding {
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
}
