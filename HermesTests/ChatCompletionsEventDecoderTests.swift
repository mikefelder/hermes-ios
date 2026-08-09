import Foundation
import Testing
@testable import Hermes

@Suite("Chat Completions event decoder")
struct ChatCompletionsEventDecoderTests {
    private let decoder = ChatCompletionsEventDecoder()

    private func event(_ data: String) -> SSEEvent {
        SSEEvent(type: "message", data: data, id: nil, retry: nil)
    }

    @Test("Maps a role delta to messageStarted")
    func roleDelta() {
        let result = decoder.decode(event(#"{"choices":[{"delta":{"role":"assistant"}}]}"#))
        #expect(result == [.messageStarted(role: .assistant)])
    }

    @Test("Maps a content delta to textDelta")
    func contentDelta() {
        let result = decoder.decode(event(#"{"choices":[{"delta":{"content":"Hi"}}]}"#))
        #expect(result == [.textDelta("Hi")])
    }

    @Test("Emits both messageStarted and textDelta for a combined delta")
    func roleAndContent() {
        let result = decoder.decode(event(#"{"choices":[{"delta":{"role":"assistant","content":"Hi"}}]}"#))
        #expect(result == [.messageStarted(role: .assistant), .textDelta("Hi")])
    }

    @Test("Maps a finish_reason to finished")
    func finishReason() {
        let result = decoder.decode(event(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#))
        #expect(result == [.finished(reason: "stop")])
    }

    @Test("Maps the [DONE] sentinel to done")
    func doneSentinel() {
        #expect(decoder.decode(event("[DONE]")) == [.done])
        #expect(decoder.decode(event("  [DONE]  ")) == [.done])
    }

    @Test("Ignores an empty content delta")
    func emptyContent() {
        #expect(decoder.decode(event(#"{"choices":[{"delta":{"content":""}}]}"#)).isEmpty)
    }

    @Test("Ignores an unknown role without failing")
    func unknownRole() {
        #expect(decoder.decode(event(#"{"choices":[{"delta":{"role":"function"}}]}"#)).isEmpty)
    }

    @Test("Yields no events for malformed JSON")
    func malformedJSON() {
        #expect(decoder.decode(event("{not json")).isEmpty)
        #expect(decoder.decode(event("")).isEmpty)
    }

    @Test("Yields no events when there are no choices")
    func noChoices() {
        #expect(decoder.decode(event(#"{"choices":[]}"#)).isEmpty)
    }

    @Test("Decodes a realistic assistant streaming sequence end to end")
    func realisticSequence() throws {
        let chunks = [
            #"{"choices":[{"delta":{"role":"assistant"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"content":"lo"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "[DONE]"
        ]
        // Each SSE event is terminated by a blank line, matching real servers.
        let raw = chunks.map { "data: \($0)\n\n" }.joined()

        var parser = SSEParser()
        let sseEvents = try parser.consume(Array(raw.utf8))
        let agentEvents = sseEvents.flatMap(decoder.decode)

        #expect(agentEvents == [
            .messageStarted(role: .assistant),
            .textDelta("Hel"),
            .textDelta("lo"),
            .finished(reason: "stop"),
            .done
        ])

        let text = agentEvents.compactMap { event -> String? in
            if case let .textDelta(fragment) = event { return fragment }
            return nil
        }.joined()
        #expect(text == "Hello")
    }
}
