import Foundation
import Testing
@testable import Hermes

/// Serves canned bytes so streaming behavior is exercised without a network.
private struct StubTransport: StreamingTransport {
    let statusCode: Int
    let finalURL: URL?
    let chunks: [String]
    let recorder: RequestRecorder?

    init(statusCode: Int = 200, finalURL: URL? = nil, chunks: [String], recorder: RequestRecorder? = nil) {
        self.statusCode = statusCode
        self.finalURL = finalURL
        self.chunks = chunks
        self.recorder = recorder
    }

    func stream(_ request: URLRequest) async throws -> StreamingResponse {
        await recorder?.record(request)
        let chunks = chunks
        let bytes = AsyncThrowingStream<[UInt8], Error> { continuation in
            for chunk in chunks {
                continuation.yield(Array(chunk.utf8))
            }
            continuation.finish()
        }
        return StreamingResponse(statusCode: statusCode, finalURL: finalURL, bytes: bytes)
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}

@Suite("Hermes chat client")
struct HermesChatClientTests {
    private func profile(_ urlText: String = "https://hermes.example.ts.net:8443") throws -> ServerProfile {
        try ServerProfile.validated(name: "Hermes", urlText: urlText, username: "")
    }

    private func collect(
        _ client: HermesChatClient,
        profile: ServerProfile,
        request: ChatTurnRequest? = nil
    ) async throws -> [AgentEvent] {
        let turn = request ?? ChatTurnRequest(messages: [ChatMessage(role: .user, content: "hi")])
        var events: [AgentEvent] = []
        for try await event in client.stream(turn, profile: profile, password: "sk-test") {
            events.append(event)
        }
        return events
    }

    @Test("A streamed turn decodes into ordered agent events")
    func decodesStreamedTurn() async throws {
        let client = HermesChatClient(transport: StubTransport(chunks: [
            "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
            "data: [DONE]\n\n"
        ]))

        let events = try await collect(client, profile: try profile())

        #expect(events == [
            .messageStarted(role: .assistant),
            .textDelta("Hel"),
            .textDelta("lo"),
            .finished(reason: "stop"),
            .done
        ])
    }

    @Test("Events split across chunk boundaries are reassembled")
    func reassemblesSplitEvents() async throws {
        let client = HermesChatClient(transport: StubTransport(chunks: [
            "data: {\"choices\":[{\"delta\":{\"cont",
            "ent\":\"partial\"}}]}\n\n",
            "data: [DONE]\n\n"
        ]))

        let events = try await collect(client, profile: try profile())

        #expect(events == [.textDelta("partial"), .done])
    }

    @Test("Streaming stops at the terminator and ignores trailing bytes")
    func stopsAtTerminator() async throws {
        let client = HermesChatClient(transport: StubTransport(chunks: [
            "data: [DONE]\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"ignored\"}}]}\n\n"
        ]))

        let events = try await collect(client, profile: try profile())

        #expect(events == [.done])
    }

    @Test("Comments and unknown payloads never abort the stream")
    func toleratesNoiseAndMalformedPayloads() async throws {
        let client = HermesChatClient(transport: StubTransport(chunks: [
            ": heartbeat\n\n",
            "data: not json\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n",
            "data: [DONE]\n\n"
        ]))

        let events = try await collect(client, profile: try profile())

        #expect(events == [.textDelta("ok"), .done])
    }

    @Test("An unauthorized response surfaces as an authentication failure")
    func mapsUnauthorized() async throws {
        let client = HermesChatClient(transport: StubTransport(statusCode: 401, chunks: []))

        await #expect(throws: HermesConnectionError.unauthorized) {
            _ = try await collect(client, profile: try profile())
        }
    }

    @Test("A response from another origin is rejected before its body is read")
    func rejectsCrossOriginResponse() async throws {
        let client = HermesChatClient(transport: StubTransport(
            finalURL: URL(string: "https://evil.example.com/v1/chat/completions"),
            chunks: ["data: {\"choices\":[{\"delta\":{\"content\":\"leak\"}}]}\n\n"]
        ))

        await #expect(throws: HermesConnectionError.redirectedOutsideServer) {
            _ = try await collect(client, profile: try profile())
        }
    }

    @Test("The request targets /v1/chat/completions with streaming and bearer auth")
    func buildsRequest() async throws {
        let recorder = RequestRecorder()
        let client = HermesChatClient(transport: StubTransport(
            chunks: ["data: [DONE]\n\n"],
            recorder: recorder
        ))

        _ = try await collect(client, profile: try profile())

        let request = await recorder.request
        #expect(request?.url?.absoluteString == "https://hermes.example.ts.net:8443/v1/chat/completions")
        #expect(request?.httpMethod == "POST")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request?.value(forHTTPHeaderField: "Accept") == "text/event-stream")

        let body = try #require(request?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["stream"] as? Bool == true)
        #expect(json["model"] == nil)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages.first?["role"] as? String == "user")
        #expect(messages.first?["content"] as? String == "hi")
    }

    @Test("A Responses turn posts to /v1/responses and seeds the chain with history")
    func buildsResponsesRequest() async throws {
        let recorder = RequestRecorder()
        let client = HermesChatClient(transport: StubTransport(
            chunks: [#"data: {"type":"response.completed","response":{"status":"completed"}}"# + "\n\n"],
            recorder: recorder
        ))

        _ = try await collect(client, profile: try profile(), request: ChatTurnRequest(
            messages: [
                ChatMessage(role: .user, content: "first"),
                ChatMessage(role: .assistant, content: "reply"),
                ChatMessage(role: .user, content: "second")
            ],
            wireProtocol: .responses
        ))

        let request = await recorder.request
        #expect(request?.url?.absoluteString == "https://hermes.example.ts.net:8443/v1/responses")

        let body = try #require(request?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["stream"] as? Bool == true)
        #expect(json["previous_response_id"] == nil)
        #expect((json["input"] as? [[String: Any]])?.count == 3)
    }

    @Test("A continued Responses turn sends only the newest message")
    func continuesWithPreviousResponseID() async throws {
        let recorder = RequestRecorder()
        let client = HermesChatClient(transport: StubTransport(
            chunks: [#"data: {"type":"response.completed","response":{"status":"completed"}}"# + "\n\n"],
            recorder: recorder
        ))

        _ = try await collect(client, profile: try profile(), request: ChatTurnRequest(
            messages: [
                ChatMessage(role: .user, content: "first"),
                ChatMessage(role: .assistant, content: "reply"),
                ChatMessage(role: .user, content: "second")
            ],
            wireProtocol: .responses,
            previousResponseID: "resp_abc"
        ))

        let body = try #require(await recorder.request?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["previous_response_id"] as? String == "resp_abc")
        let input = try #require(json["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect(input.first?["content"] as? String == "second")
    }

    @Test("A Responses stream decodes through to acceptance and completion")
    func streamsResponsesProtocol() async throws {
        let client = HermesChatClient(transport: StubTransport(chunks: [
            "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\"}}\n\n",
            "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"OK\"}\n\n",
            "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
        ]))

        let events = try await collect(client, profile: try profile(), request: ChatTurnRequest(
            messages: [ChatMessage(role: .user, content: "hi")],
            wireProtocol: .responses
        ))

        #expect(events == [
            .turnAccepted(id: "resp_1"),
            .textDelta("OK"),
            .finished(reason: "completed"),
            .done
        ])
    }
}
