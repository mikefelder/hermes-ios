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
        // Forked sessions are children, which the server omits unless asked for.
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .get("api/sessions", query: [
                URLQueryItem(name: "limit", value: String(min(limit, 200))),
                URLQueryItem(name: "include_children", value: "true")
            ])
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        return try JSONDecoder().decode(SessionListPage.self, from: response.data)
            .data
            .filter { !$0.isInternal }
    }

    func messages(
        sessionID: String,
        limit: Int,
        profile: ServerProfile,
        password: String
    ) async throws -> [SessionMessage] {
        // Ask for the newest page so a session longer than `limit` hydrates to its
        // tail, then restore reading order for display.
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .get("api/sessions/\(sessionID)/messages", query: [
                URLQueryItem(name: "limit", value: String(min(limit, 500))),
                URLQueryItem(name: "order", value: "latest")
            ])
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        let page = try JSONDecoder().decode(SessionMessagePage.self, from: response.data)
        return page.data.sorted { $0.id < $1.id }
    }

    func rename(id: String, title: String, profile: ServerProfile, password: String) async throws -> SessionSummary {
        let body = try JSONEncoder().encode(["title": title])
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .patch("api/sessions/\(id)", body: body)
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        return try Self.decodeSession(from: response.data)
    }

    func delete(id: String, profile: ServerProfile, password: String) async throws {
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .delete("api/sessions/\(id)")
        // A session that is already gone is the outcome the caller wanted.
        guard (200..<300).contains(response.statusCode) || response.statusCode == 404 else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
    }

    func fork(id: String, profile: ServerProfile, password: String) async throws -> SessionSummary {
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .post("api/sessions/\(id)/fork", body: Data("{}".utf8))
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        return try Self.decodeSession(from: response.data)
    }

    /// Session mutations return either a bare session or one wrapped in `session`.
    static func decodeSession(from data: Data) throws -> SessionSummary {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(SessionEnvelope.self, from: data) {
            return envelope.session
        }
        return try decoder.decode(SessionSummary.self, from: data)
    }
}
