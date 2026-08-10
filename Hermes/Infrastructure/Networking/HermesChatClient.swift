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

/// Which wire protocol a turn uses.
nonisolated enum ChatWireProtocol: Sendable, Equatable {
    /// Two-step: submit a run, then stream its events. The only protocol that can
    /// deliver approvals and stop remote work, at the cost of a stream that cannot
    /// be resumed after a disconnect.
    case run(sessionID: String?)
    /// Preferred for a conversation bound to a server session, so the transcript
    /// is shared with every other Hermes client.
    case sessionChat(sessionID: String)
    /// Exposes structured items and server-side continuity without a session.
    case responses
    /// Universal fallback. Stateless, so the full transcript is resent each turn.
    case chatCompletions
}

/// One turn's request, independent of transport.
nonisolated struct ChatTurnRequest: Sendable {
    var messages: [ChatMessage]
    var model: String?
    var wireProtocol: ChatWireProtocol
    /// When set, the server reconstructs history and only the newest message is sent.
    var previousResponseID: String?

    init(
        messages: [ChatMessage],
        model: String? = nil,
        wireProtocol: ChatWireProtocol = .chatCompletions,
        previousResponseID: String? = nil
    ) {
        self.messages = messages
        self.model = model
        self.wireProtocol = wireProtocol
        self.previousResponseID = previousResponseID
    }
}

/// Streams an assistant turn as transport-independent ``AgentEvent``s.
protocol ChatStreaming: Sendable {
    func stream(
        _ request: ChatTurnRequest,
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
    private let chatCompletions = ChatCompletionsEventDecoder()
    private let responses = ResponsesEventDecoder()
    private let sessionChat = SessionChatEventDecoder()
    private let runs = RunEventDecoder()

    init(transport: any StreamingTransport = URLSessionStreamingTransport()) {
        self.transport = transport
    }

    func stream(
        _ request: ChatTurnRequest,
        profile: ServerProfile,
        password: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(
                        request,
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
        _ turn: ChatTurnRequest,
        profile: ServerProfile,
        password: String,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        if case let .run(sessionID) = turn.wireProtocol {
            let runID = try await submitRun(turn, sessionID: sessionID, profile: profile, password: password)
            continuation.yield(.turnAccepted(id: runID))
            let events = try HermesEndpoint.url(base: profile.baseURL, path: "v1/runs/\(runID)/events")
            var request = URLRequest(url: events)
            request.httpMethod = "GET"
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue(
                HermesAuthorization.headerValue(username: profile.username, secret: password),
                forHTTPHeaderField: "Authorization"
            )
            try await consume(request, turn: turn, profile: profile, continuation: continuation)
            return
        }

        let request = try makeRequest(turn, profile: profile, password: password)
        try await consume(request, turn: turn, profile: profile, continuation: continuation)
    }

    /// Submit the run and read back its identifier. The response is a small JSON
    /// body rather than a stream, so it is collected in full.
    private func submitRun(
        _ turn: ChatTurnRequest,
        sessionID: String?,
        profile: ServerProfile,
        password: String
    ) async throws -> String {
        let url = try HermesEndpoint.url(base: profile.baseURL, path: "v1/runs")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            HermesAuthorization.headerValue(username: profile.username, secret: password),
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(RunSubmission(
            input: turn.messages.last?.content ?? "",
            sessionID: sessionID,
            model: turn.model
        ))

        let response = try await transport.stream(request)
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        var body: [UInt8] = []
        for try await chunk in response.bytes { body.append(contentsOf: chunk) }
        guard let accepted = try? JSONDecoder().decode(RunAccepted.self, from: Data(body)) else {
            throw HermesConnectionError.invalidResponse
        }
        return accepted.runID
    }

    private func consume(
        _ request: URLRequest,
        turn: ChatTurnRequest,
        profile: ServerProfile,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
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
                for agentEvent in decode(event, using: turn.wireProtocol) {
                    continuation.yield(agentEvent)
                    if agentEvent == .done { return }
                }
            }
        }
    }

    private func decode(_ event: SSEEvent, using wireProtocol: ChatWireProtocol) -> [AgentEvent] {
        switch wireProtocol {
        case .run: runs.decode(event)
        case .sessionChat: sessionChat.decode(event)
        case .responses: responses.decode(event)
        case .chatCompletions: chatCompletions.decode(event)
        }
    }

    private func makeRequest(
        _ turn: ChatTurnRequest,
        profile: ServerProfile,
        password: String
    ) throws -> URLRequest {
        let path = switch turn.wireProtocol {
        case .run: "v1/runs"
        case let .sessionChat(sessionID): "api/sessions/\(sessionID)/chat/stream"
        case .responses: "v1/responses"
        case .chatCompletions: "v1/chat/completions"
        }
        let url = try HermesEndpoint.url(base: profile.baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            HermesAuthorization.headerValue(username: profile.username, secret: password),
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try body(for: turn)
        return request
    }

    private func body(for turn: ChatTurnRequest) throws -> Data {
        let encoder = JSONEncoder()
        switch turn.wireProtocol {
        case .run:
            return try encoder.encode(RunSubmission(
                input: turn.messages.last?.content ?? "",
                sessionID: nil,
                model: turn.model
            ))

        case .sessionChat:
            // The server owns the transcript, so only the new message is sent.
            return try encoder.encode(SessionChatRequest(message: turn.messages.last?.content ?? ""))

        case .responses:
            // With a prior response the server rebuilds history, so only the newest
            // message is sent. Without one the whole transcript seeds the chain.
            let input = turn.previousResponseID == nil
                ? turn.messages
                : Array(turn.messages.suffix(1))
            return try encoder.encode(
                ResponsesRequest(
                    model: turn.model,
                    stream: true,
                    previousResponseID: turn.previousResponseID,
                    input: input.map { ResponsesRequest.Message(role: $0.role.rawValue, content: $0.content) }
                )
            )
        case .chatCompletions:
            return try encoder.encode(
                ChatCompletionsRequest(
                    model: turn.model,
                    stream: true,
                    messages: turn.messages.map {
                        ChatCompletionsRequest.Message(role: $0.role.rawValue, content: $0.content)
                    }
                )
            )
        }
    }
}

/// Wire model for the session-scoped chat request body.
private nonisolated struct SessionChatRequest: Encodable {
    let message: String
}

private nonisolated struct RunSubmission: Encodable {
    let input: String
    let sessionID: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case input
        case sessionID = "session_id"
        case model
    }
}

private nonisolated struct RunAccepted: Decodable {
    let runID: String

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
    }
}

/// Wire model for the Responses request body.
private nonisolated struct ResponsesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String?
    let stream: Bool
    let previousResponseID: String?
    let input: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case stream
        case previousResponseID = "previous_response_id"
        case input
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
