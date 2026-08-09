import Foundation

/// The outcome of interpreting a Hermes `/health` response body.
nonisolated enum HealthReport: Equatable, Sendable {
    /// The server is considered healthy; an optional version string may be present.
    case healthy(version: String?)
    /// The body explicitly reported a non-healthy status token.
    case unhealthy(status: String)
}

/// Interprets a `/health` response body tolerantly.
///
/// A successful (`2xx`) status has already proven reachability and authentication, so
/// the body itself is treated as extensible: it may be JSON, plain text such as `ok`,
/// or empty. The check only fails when the body is a JSON object whose `status` field
/// explicitly reports a known non-healthy value. Any other shape is treated as healthy,
/// and a version string is extracted when present.
nonisolated enum HealthInterpreter {
    /// Status tokens that indicate the service is not healthy.
    static let unhealthyTokens: Set<String> = [
        "error", "down", "unavailable", "offline",
        "fail", "failed", "failing", "unhealthy", "critical"
    ]

    static func interpret(_ data: Data) -> HealthReport {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Non-JSON, non-object, or empty body: the 2xx status already proved health.
            return .healthy(version: nil)
        }

        if let status = (object["status"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           unhealthyTokens.contains(status) {
            return .unhealthy(status: status)
        }

        let version = (object["version"] ?? object["hermes_version"]) as? String
        return .healthy(version: version)
    }
}
