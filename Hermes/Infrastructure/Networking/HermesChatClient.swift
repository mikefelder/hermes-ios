import Foundation

/// One in-flight streaming HTTP response.
nonisolated struct StreamingResponse: Sendable {
    let statusCode: Int
    let finalURL: URL?
    let bytes: AsyncThrowingStream<[UInt8], Error>
}

/// Performs a streaming HTTP request.
///
/// Injectable so chat streaming can be exercised with canned bytes and without a
/// network in tests.
protocol StreamingTransport: Sendable {
    func stream(_ request: URLRequest) async throws -> StreamingResponse
}

/// Streams an assistant turn as transport-independent ``AgentEvent``s.
protocol ChatStreaming: Sendable {
    func stream(
        messages: [ChatMessage],
        model: String?,
        profile: ServerProfile,
        password: String
    ) -> AsyncThrowingStream<AgentEvent, Error>
}

/// Streams `POST /v1/chat/completions` and normalizes the Server-Sent Event body
/// into ``AgentEvent``s.
///
/// Inline assistant text is display content only. It is never interpreted as
/// structured tool metadata or as an approval.
nonisolated struct HermesChatClient: ChatStreaming {
    private let transport: any StreamingTransport
    private let decoder = ChatCompletionsEventDecoder()

    init(transport: any StreamingTransport = URLSessionStreamingTransport()) {
        self.transport = transport
    }

    func stream(
        messages: [ChatMessage],
        model: String?,
        profile: ServerProfile,
        password: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(
                        messages: messages,
                        model: model,
                        profile: profile,
                        password: password,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: HermesConnectionError.cancelled)
                } catch let error as HermesConnectionError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: HermesConnectionError.from(error))
                } catch {
                    continuation.finish(throwing: HermesConnectionError.other("The chat stream failed. Try again."))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        messages: [ChatMessage],
        model: String?,
        profile: ServerProfile,
        password: String,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        let request = try makeRequest(
            messages: messages,
            model: model,
            profile: profile,
            password: password
        )
        let response = try await transport.stream(request)

        // A redirect that left the configured origin must never be consumed, even
        // though the delegate already refuses to forward credentials to it.
        if let finalURL = response.finalURL,
           !HermesEndpoint.isSameOrigin(base: profile.baseURL, finalURL) {
            throw HermesConnectionError.redirectedOutsideServer
        }
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }

        var parser = SSEParser()
        for try await chunk in response.bytes {
            try Task.checkCancellation()
            for event in try parser.consume(chunk) {
                for agentEvent in decoder.decode(event) {
                    continuation.yield(agentEvent)
                    if agentEvent == .done { return }
                }
            }
        }
    }

    private func makeRequest(
        messages: [ChatMessage],
        model: String?,
        profile: ServerProfile,
        password: String
    ) throws -> URLRequest {
        let url = try HermesEndpoint.url(base: profile.baseURL, path: "v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            HermesAuthorization.headerValue(username: profile.username, secret: password),
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionsRequest(
                model: model,
                stream: true,
                messages: messages.map {
                    ChatCompletionsRequest.Message(role: $0.role.rawValue, content: $0.content)
                }
            )
        )
        return request
    }
}

/// Wire model for the request body. Omitting `model` lets Hermes pick its default.
private nonisolated struct ChatCompletionsRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String?
    let stream: Bool
    let messages: [Message]
}

/// `URLSession`-backed transport that keeps credentials inside the configured origin.
nonisolated struct URLSessionStreamingTransport: StreamingTransport {
    /// An agent turn can idle between tokens, so the inactivity budget is generous
    /// while the overall resource budget still bounds a stuck stream.
    private let requestTimeout: TimeInterval
    private let resourceTimeout: TimeInterval

    init(requestTimeout: TimeInterval = 120, resourceTimeout: TimeInterval = 3600) {
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
    }

    func stream(_ request: URLRequest) async throws -> StreamingResponse {
        guard let url = request.url,
              let authorization = request.value(forHTTPHeaderField: "Authorization") else {
            throw HermesConnectionError.invalidConfiguration("The chat request was not configured correctly.")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false

        let session = URLSession(
            configuration: configuration,
            delegate: OriginRedirectPolicyDelegate(baseURL: url, authorizationHeader: authorization),
            delegateQueue: nil
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            session.invalidateAndCancel()
            throw HermesConnectionError.invalidResponse
        }

        let stream = AsyncThrowingStream<[UInt8], Error> { continuation in
            let task = Task {
                var buffer: [UInt8] = []
                buffer.reserveCapacity(4096)
                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        // Flush on line boundaries so events surface as they arrive.
                        if byte == 0x0A || buffer.count >= 4096 {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                session.finishTasksAndInvalidate()
            }
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
        }

        return StreamingResponse(
            statusCode: httpResponse.statusCode,
            finalURL: response.url,
            bytes: stream
        )
    }
}
