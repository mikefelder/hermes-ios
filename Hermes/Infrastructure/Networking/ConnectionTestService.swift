import Foundation

enum ConnectionTestEvent: Sendable {
    case check(ConnectionCheck)
    case completed(ServerCapabilities)
}

protocol ConnectionTesting: Sendable {
    func test(profile: ServerProfile, password: String) -> AsyncThrowingStream<ConnectionTestEvent, Error>
}

struct ConnectionTestService: ConnectionTesting, Sendable {
    func test(profile: ServerProfile, password: String) -> AsyncThrowingStream<ConnectionTestEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(profile: profile, password: password, continuation: continuation)
                } catch is CancellationError {
                    continuation.finish(throwing: HermesConnectionError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        profile: ServerProfile,
        password: String,
        continuation: AsyncThrowingStream<ConnectionTestEvent, Error>.Continuation
    ) async throws {
        guard !password.isEmpty else {
            let error = CredentialStoreError.invalidPassword
            continuation.yield(.check(.init(stage: .configuration, state: .failed(error.localizedDescription))))
            throw error
        }

        continuation.yield(.check(.init(stage: .configuration, state: .passed("HTTPS settings are valid"))))
        continuation.yield(.check(.init(stage: .secureConnection, state: .running)))

        let client = HermesHTTPClient(profile: profile, password: password)
        let health: HermesHTTPResponse
        do {
            health = try await client.get("health")
            continuation.yield(.check(.init(stage: .secureConnection, state: .passed("TLS verified"))))
        } catch {
            continuation.yield(.check(.init(stage: .secureConnection, state: .failed(error.localizedDescription))))
            throw error
        }

        continuation.yield(.check(.init(stage: .authentication, state: .running)))
        do {
            try requireSuccess(health.statusCode)
            continuation.yield(.check(.init(stage: .authentication, state: .passed(authMode(for: profile)))))
        } catch {
            let message = describeFailure(
                status: health.statusCode,
                headers: health.headers,
                profile: profile,
                endpoint: "health",
                fallback: error
            )
            continuation.yield(.check(.init(stage: .authentication, state: .failed(message))))
            throw error
        }

        continuation.yield(.check(.init(stage: .health, state: .running)))
        let healthVersion: String?
        switch HealthInterpreter.interpret(health.data) {
        case let .healthy(version):
            healthVersion = version
            continuation.yield(.check(.init(
                stage: .health,
                state: .passed(version.map { "Hermes \($0)" } ?? "Hermes is healthy")
            )))
        case let .unhealthy(status):
            let error = HermesConnectionError.unavailable(health.statusCode)
            continuation.yield(.check(.init(
                stage: .health,
                state: .failed("Hermes reported status \"\(status)\".")
            )))
            throw error
        }

        continuation.yield(.check(.init(stage: .models, state: .running)))
        let modelResponse = try await client.get("v1/models")
        do {
            try requireSuccess(modelResponse.statusCode)
        } catch {
            let message = describeFailure(
                status: modelResponse.statusCode,
                headers: modelResponse.headers,
                profile: profile,
                endpoint: "v1/models",
                fallback: error
            )
            continuation.yield(.check(.init(stage: .models, state: .failed(message))))
            throw error
        }
        let models = ModelsInterpreter.modelIDs(from: modelResponse.data)
        if !models.isEmpty {
            continuation.yield(.check(.init(stage: .models, state: .passed(models.joined(separator: ", ")))))
        } else if ModelsInterpreter.isStructuredJSON(modelResponse.data) {
            // Authenticated 2xx with a recognizable JSON body, but no advertised model
            // names. Chat can still work against the server's default model.
            continuation.yield(.check(.init(stage: .models, state: .passed("Connected; no model names advertised"))))
        } else {
            let error = HermesConnectionError.invalidResponse
            let diagnostic = bodyDiagnostic(
                headers: modelResponse.headers,
                data: modelResponse.data,
                statusCode: modelResponse.statusCode
            )
            continuation.yield(.check(.init(
                stage: .models,
                state: .failed("The model list was not in a recognized format. \(diagnostic) Point the server URL at the Hermes API server (the origin that serves /v1), not the web dashboard or a landing page.")
            )))
            throw error
        }

        continuation.yield(.check(.init(stage: .capabilities, state: .running)))
        var capabilities = ServerCapabilities(
            supportsChatCompletions: true,
            supportsResponses: false,
            supportsMobileAdapter: false,
            observedVersion: healthVersion,
            models: models,
            checkedAt: .now
        )

        do {
            let response = try await client.get("v1/capabilities")
            try requireSuccess(response.statusCode)
            let document = try JSONDecoder().decode(HermesCapabilityDocument.self, from: response.data)
            capabilities = capabilities.merging(document, version: healthVersion, models: models)
            continuation.yield(.check(.init(
                stage: .capabilities,
                state: .passed(summary(of: capabilities))
            )))
        } catch {
            // An older build without the discovery endpoint still supports chat.
            continuation.yield(.check(.init(
                stage: .capabilities,
                state: .passed("Chat available; this server does not advertise capabilities")
            )))
        }

        continuation.yield(.completed(capabilities))
        continuation.finish()
    }

    /// A short, user-facing summary of the richer surfaces this server offers.
    private func summary(of capabilities: ServerCapabilities) -> String {
        var available: [String] = []
        if capabilities.supportsResponses { available.append("structured responses") }
        if capabilities.supportsSessions { available.append("sessions") }
        if capabilities.supportsRunApproval { available.append("approvals") }
        guard !available.isEmpty else { return "Chat available" }
        return "Chat, " + available.joined(separator: ", ")
    }

    private func requireSuccess(_ statusCode: Int) throws {
        switch statusCode {
        case 200..<300:
            return
        case 401:
            throw HermesConnectionError.unauthorized
        case 403:
            throw HermesConnectionError.forbidden
        default:
            throw HermesConnectionError.unavailable(statusCode)
        }
    }

    /// A short label describing which authentication scheme the client used.
    private func authMode(for profile: ServerProfile) -> String {
        HermesAuthorization.usesBearer(username: profile.username)
            ? "Accepted (API key)"
            : "Accepted (username & password)"
    }

    /// Build a specific, actionable message for a failed request.
    private func describeFailure(
        status: Int,
        headers: [AnyHashable: Any],
        profile: ServerProfile,
        endpoint: String,
        fallback: Error
    ) -> String {
        switch status {
        case 401:
            return authFailureMessage(status: status, headers: headers, profile: profile, endpoint: endpoint)
        case 403:
            return "Access to /\(endpoint) was denied (HTTP 403). The credentials are valid but lack permission."
        default:
            return (fallback as? LocalizedError)?.errorDescription ?? fallback.localizedDescription
        }
    }

    /// Interpret a `401` using the server's `WWW-Authenticate` challenge so the user
    /// learns whether the server wants an API key (Bearer) or a username/password (Basic).
    private func authFailureMessage(
        status: Int,
        headers: [AnyHashable: Any],
        profile: ServerProfile,
        endpoint: String
    ) -> String {
        let challenge = headerValue("WWW-Authenticate", in: headers)?.lowercased()
        let usingBearer = HermesAuthorization.usesBearer(username: profile.username)
        var message = "Authentication failed at /\(endpoint) (HTTP \(status))."

        switch (challenge, usingBearer) {
        case let (value?, false) where value.contains("bearer") && !value.contains("basic"):
            message += " The server expects an API key. Clear the username and enter your Hermes API key in the key field."
        case let (value?, true) where value.contains("basic") && !value.contains("bearer"):
            message += " The server expects a username and password. Enter your username, then your password."
        default:
            message += usingBearer
                ? " The API key was not accepted. Verify the key value, or add a username if your server uses a username and password."
                : " The username or password was not accepted. Verify them, or clear the username if your server uses an API key."
        }
        return message
    }

    /// Case-insensitive lookup for an HTTP response header value.
    private func headerValue(_ name: String, in headers: [AnyHashable: Any]) -> String? {
        for (key, value) in headers {
            if let keyString = key as? String,
               keyString.caseInsensitiveCompare(name) == .orderedSame {
                return value as? String
            }
        }
        return nil
    }

    /// A short, safe diagnostic describing what the server actually returned, so an
    /// unexpected body (typically an HTML landing or dashboard page) is identifiable.
    private func bodyDiagnostic(headers: [AnyHashable: Any], data: Data, statusCode: Int) -> String {
        let contentType = headerValue("Content-Type", in: headers) ?? "unknown"
        return "HTTP \(statusCode), Content-Type: \(contentType). Response began: \(ResponsePreview.text(from: data))."
    }
}
