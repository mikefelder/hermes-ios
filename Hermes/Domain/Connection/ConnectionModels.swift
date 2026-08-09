import Foundation

enum ServerProfileValidationError: LocalizedError, Equatable {
    case emptyURL
    case invalidURL
    case insecureScheme
    case missingHost
    case embeddedCredentials
    case queryOrFragment
    case usernameContainsColon

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            "Enter your Hermes server URL."
        case .invalidURL:
            "Enter a valid server URL."
        case .insecureScheme:
            "Hermes requires an HTTPS server URL."
        case .missingHost:
            "The server URL must include a host name."
        case .embeddedCredentials:
            "Enter the username and password in their separate fields."
        case .queryOrFragment:
            "The server URL cannot include a query or fragment."
        case .usernameContainsColon:
            "The username cannot contain a colon when using Basic Authentication."
        }
    }
}

nonisolated struct ServerProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var baseURL: URL
    var username: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Hermes",
        baseURL: URL,
        username: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func validated(
        id: UUID = UUID(),
        name: String,
        urlText: String,
        username: String,
        createdAt: Date = .now,
        now: Date = .now
    ) throws -> ServerProfile {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { throw ServerProfileValidationError.emptyURL }

        let candidate = trimmedURL.contains("://") ? trimmedURL : "https://\(trimmedURL)"
        guard var components = URLComponents(string: candidate) else {
            throw ServerProfileValidationError.invalidURL
        }
        guard components.scheme?.lowercased() == "https" else {
            throw ServerProfileValidationError.insecureScheme
        }
        guard let host = components.host, !host.isEmpty else {
            throw ServerProfileValidationError.missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw ServerProfileValidationError.embeddedCredentials
        }
        guard components.query == nil, components.fragment == nil else {
            throw ServerProfileValidationError.queryOrFragment
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.contains(":") else {
            throw ServerProfileValidationError.usernameContainsColon
        }

        components.scheme = "https"
        components.host = host.lowercased()
        if components.path == "/" {
            components.path = ""
        } else {
            while components.path.count > 1 && components.path.hasSuffix("/") {
                components.path.removeLast()
            }
        }
        guard let normalizedURL = components.url else {
            throw ServerProfileValidationError.invalidURL
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ServerProfile(
            id: id,
            name: trimmedName.isEmpty ? "Hermes" : trimmedName,
            baseURL: normalizedURL,
            username: trimmedUsername,
            createdAt: createdAt,
            updatedAt: now
        )
    }
}

struct ServerCapabilities: Codable, Equatable, Sendable {
    var supportsChatCompletions: Bool
    var supportsResponses: Bool
    var supportsMobileAdapter: Bool
    var observedVersion: String?
    var models: [String]
    var checkedAt: Date

    static let unknown = ServerCapabilities(
        supportsChatCompletions: false,
        supportsResponses: false,
        supportsMobileAdapter: false,
        observedVersion: nil,
        models: [],
        checkedAt: .distantPast
    )
}

enum ConnectionStage: String, Codable, CaseIterable, Sendable {
    case configuration
    case secureConnection
    case authentication
    case health
    case models
    case capabilities

    var title: String {
        switch self {
        case .configuration: "Configuration"
        case .secureConnection: "Secure connection"
        case .authentication: "Authentication"
        case .health: "Hermes health"
        case .models: "Agent model"
        case .capabilities: "Capabilities"
        }
    }
}

enum ConnectionCheckState: Equatable, Sendable {
    case running
    case passed(String?)
    case failed(String)
}

struct ConnectionCheck: Identifiable, Equatable, Sendable {
    var id: ConnectionStage { stage }
    let stage: ConnectionStage
    let state: ConnectionCheckState
}

struct ConnectionTestResult: Equatable, Sendable {
    let capabilities: ServerCapabilities
    let checks: [ConnectionCheck]
}

enum HermesConnectionError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case offline
    case timedOut
    case tlsFailure
    case unauthorized
    case forbidden
    case unavailable(Int?)
    case invalidResponse
    case redirectedOutsideServer
    case cancelled
    case other(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message): message
        case .offline: "The server is unreachable. Check your network and Tailscale connection."
        case .timedOut: "The connection timed out. The Azure service may be starting."
        case .tlsFailure: "The secure connection could not be verified. Check the server certificate."
        case .unauthorized: "The username or password was not accepted."
        case .forbidden: "The server accepted your identity but denied access."
        case let .unavailable(status):
            status.map { "Hermes is unavailable (HTTP \($0)). Try again shortly." }
                ?? "Hermes is unavailable. Try again shortly."
        case .invalidResponse: "Hermes returned an unexpected response."
        case .redirectedOutsideServer: "The server redirected to a different host or an insecure (HTTP) address, so credentials were not sent. Check the server URL and point it directly at your Hermes address."
        case .cancelled: "The connection test was cancelled."
        case let .other(message): message
        }
    }
}
