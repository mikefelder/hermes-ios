import Foundation

/// Reads session resources from the API server so an ambiguous turn can be
/// resolved against the server's own transcript rather than guessed at.
nonisolated struct HermesSessionsClient: SessionServicing {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    func createSession(profile: ServerProfile, password: String) async throws -> SessionSummary {
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .post("api/sessions", body: Data("{}".utf8))
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        return try JSONDecoder().decode(SessionEnvelope.self, from: response.data).session
    }

    func session(id: String, profile: ServerProfile, password: String) async throws -> SessionSummary {
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .get("api/sessions/\(id)")
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        return try JSONDecoder().decode(SessionSummary.self, from: response.data)
    }

    func sessions(limit: Int, profile: ServerProfile, password: String) async throws -> [SessionSummary] {
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .get("api/sessions", query: [URLQueryItem(name: "limit", value: String(min(limit, 200)))])
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        return try JSONDecoder().decode(SessionListPage.self, from: response.data).data
    }

    func messages(
        sessionID: String,
        limit: Int,
        profile: ServerProfile,
        password: String
    ) async throws -> [SessionMessage] {
        // Without an explicit order the server returns the most recent page.
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .get("api/sessions/\(sessionID)/messages", query: [
                URLQueryItem(name: "limit", value: String(min(limit, 500))),
                URLQueryItem(name: "order", value: "oldest")
            ])
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        return try JSONDecoder().decode(SessionMessagePage.self, from: response.data).data
    }
}
