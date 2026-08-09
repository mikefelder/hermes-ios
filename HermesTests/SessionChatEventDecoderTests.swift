import Foundation
import Testing
@testable import Hermes

@Suite("Session chat stream decoding")
struct SessionChatEventDecoderTests {
    private let decoder = SessionChatEventDecoder()

    private func event(_ type: String, _ data: String) -> SSEEvent {
        SSEEvent(type: type, data: data, id: nil, retry: nil)
    }

    @Test("run.started accepts the turn and carries the run identifier")
    func decodesRunStarted() {
        let events = decoder.decode(event(
            "run.started",
            #"{"session_id":"api-1","run_id":"run_9"}"#
        ))

        #expect(events == [.turnAccepted(id: "run_9")])
    }

    @Test("assistant.delta becomes transcript text")
    func decodesDelta() {
        let events = decoder.decode(event(
            "assistant.delta",
            #"{"message_id":"m1","delta":"OK","session_id":"api-1"}"#
        ))

        #expect(events == [.textDelta("OK")])
    }

    @Test("Tool progress surfaces the tool name for display")
    func decodesToolProgress() {
        let events = decoder.decode(event(
            "tool.progress",
            #"{"tool_name":"terminal","delta":"ls","session_id":"api-1"}"#
        ))

        #expect(events == [.toolActivity(name: "terminal")])
    }

    @Test("Internal reasoning is not reported as a tool")
    func ignoresThinkingPseudoTool() {
        let events = decoder.decode(event(
            "tool.progress",
            #"{"tool_name":"_thinking","delta":"OK"}"#
        ))

        #expect(events.isEmpty)
    }

    @Test("done terminates the turn")
    func decodesDone() {
        #expect(decoder.decode(event("done", #"{"session_id":"api-1","seq":7}"#)) == [.done])
    }

    @Test("Unknown events are ignored rather than failing the stream")
    func ignoresUnknownEvents() {
        #expect(decoder.decode(event("some.future.event", "{}")).isEmpty)
        #expect(decoder.decode(event("assistant.delta", "not json")).isEmpty)
    }
}

@Suite("Session transcript mapping")
struct SessionModelsTests {
    private func decode(_ json: String) throws -> [SessionMessage] {
        try JSONDecoder().decode(SessionMessagePage.self, from: Data(json.utf8)).data
    }

    @Test("Stored messages map to a display transcript")
    func mapsPlainMessages() throws {
        let messages = try decode(#"""
        {"object":"list","session_id":"api-1","data":[
          {"id":1,"session_id":"api-1","role":"user","content":"Hello","timestamp":1786313592.0},
          {"id":2,"session_id":"api-1","role":"assistant","content":"Hi there","timestamp":1786313595.0}
        ]}
        """#)

        let transcript = messages.asTranscript()

        #expect(transcript.count == 2)
        #expect(transcript.first?.role == .user)
        #expect(transcript.last?.content == "Hi there")
    }

    @Test("A tool call renders as inert fenced text, never as an instruction")
    func mapsToolCalls() throws {
        let messages = try decode(#"""
        {"object":"list","session_id":"api-1","data":[
          {"id":4,"session_id":"api-1","role":"assistant","content":"",
           "tool_calls":[{"id":"call_1","function":{"name":"terminal","arguments":"{\"command\":\"date\"}"}}],
           "timestamp":1786313652.0}
        ]}
        """#)

        let transcript = messages.asTranscript()

        #expect(transcript.count == 1)
        let rendered = try #require(transcript.first)
        #expect(rendered.role == .tool)
        #expect(rendered.content.contains("terminal"))
        #expect(rendered.content.contains("```json"))
    }

    @Test("Tool output is preserved as a fenced result block")
    func mapsToolResults() throws {
        let messages = try decode(#"""
        {"object":"list","session_id":"api-1","data":[
          {"id":5,"session_id":"api-1","role":"tool","tool_name":"terminal",
           "content":"{\"output\":\"Sunday\",\"exit_code\":0}","timestamp":1786313653.0}
        ]}
        """#)

        let transcript = messages.asTranscript()

        #expect(transcript.count == 1)
        #expect(transcript.first?.role == .tool)
        #expect(transcript.first?.content.contains("Sunday") == true)
    }

    @Test("An empty assistant turn contributes nothing to the transcript")
    func dropsEmptyMessages() throws {
        let messages = try decode(#"""
        {"object":"list","session_id":"api-1","data":[
          {"id":6,"session_id":"api-1","role":"assistant","content":"   ","timestamp":1786313656.0}
        ]}
        """#)

        #expect(messages.asTranscript().isEmpty)
    }
}
