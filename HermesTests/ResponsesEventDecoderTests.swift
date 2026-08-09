import Foundation
import Testing
@testable import Hermes

@Suite("Responses event decoding")
struct ResponsesEventDecoderTests {
    private let decoder = ResponsesEventDecoder()

    private func event(_ data: String, type: String = "message") -> SSEEvent {
        SSEEvent(type: type, data: data, id: nil, retry: nil)
    }

    @Test("response.created marks the turn accepted and carries the response ID")
    func decodesAcceptance() {
        let events = decoder.decode(event(
            #"{"type":"response.created","response":{"id":"resp_abc","status":"in_progress"}}"#
        ))

        #expect(events == [.turnAccepted(id: "resp_abc")])
    }

    @Test("A message output item starts the assistant message")
    func decodesMessageStart() {
        let events = decoder.decode(event(
            #"{"type":"response.output_item.added","output_index":0,"item":{"id":"msg_1","type":"message","role":"assistant"}}"#
        ))

        #expect(events == [.messageStarted(role: .assistant)])
    }

    @Test("Text deltas become text events")
    func decodesTextDelta() {
        let events = decoder.decode(event(
            #"{"type":"response.output_text.delta","item_id":"msg_1","delta":"OK"}"#
        ))

        #expect(events == [.textDelta("OK")])
    }

    @Test("response.completed terminates the turn without a DONE sentinel")
    func decodesCompletion() {
        let events = decoder.decode(event(
            #"{"type":"response.completed","response":{"id":"resp_abc","status":"completed"}}"#
        ))

        #expect(events == [.finished(reason: "completed"), .done])
    }

    @Test("A failed response still terminates the stream")
    func decodesFailure() {
        let events = decoder.decode(event(
            #"{"type":"response.failed","response":{"id":"resp_abc","status":"failed"}}"#
        ))

        #expect(events == [.finished(reason: "failed"), .done])
    }

    @Test("Bookkeeping and unknown events produce nothing and never abort the turn")
    func ignoresNoise() {
        let payloads = [
            #"{"type":"response.output_text.done","text":"OK"}"#,
            #"{"type":"response.output_item.done","item":{"type":"message"}}"#,
            #"{"type":"response.reasoning.delta","delta":"hidden"}"#,
            #"{"type":"some.future.event"}"#,
            "not json"
        ]

        for payload in payloads {
            #expect(decoder.decode(event(payload)).isEmpty, "\(payload) must yield no events")
        }
    }

    @Test("A server-executed tool item is not surfaced as a call to perform")
    func ignoresFunctionCallItems() {
        let events = decoder.decode(event(
            #"{"type":"response.output_item.added","item":{"type":"function_call","status":"completed"}}"#
        ))

        #expect(events.isEmpty)
    }
}

@Suite("Capability discovery")
struct HermesCapabilitiesTests {
    private func document(_ json: String) throws -> HermesCapabilityDocument {
        try JSONDecoder().decode(HermesCapabilityDocument.self, from: Data(json.utf8))
    }

    @Test("A live capability document enables the richer surfaces")
    func mergesLiveDocument() throws {
        let document = try document(#"""
        {"object":"hermes.api_server.capabilities","platform":"hermes-agent","model":"hermes-agent",
         "features":{"chat_completions":true,"chat_completions_streaming":true,"responses_api":true,
         "responses_streaming":true,"session_resources":true,"run_approval_response":true,
         "tool_progress_events":true,"session_continuity_header":"X-Hermes-Session-Id"}}
        """#)

        let capabilities = ServerCapabilities.unknown.merging(document, version: "0.20.0", models: ["hermes-agent"])

        #expect(capabilities.supportsChatCompletions)
        #expect(capabilities.supportsResponses)
        #expect(capabilities.supportsSessions)
        #expect(capabilities.supportsRunApproval)
        #expect(capabilities.supportsToolProgress)
        #expect(capabilities.supportsServerSideContinuity)
        #expect(capabilities.sessionContinuityHeader == "X-Hermes-Session-Id")
        #expect(capabilities.observedVersion == "0.20.0")
    }

    @Test("An older server that advertises nothing degrades to chat only")
    func degradesWhenFeaturesAbsent() throws {
        let document = try document(#"{"platform":"hermes-agent","model":"hermes-agent"}"#)

        let capabilities = ServerCapabilities.unknown.merging(document, version: nil, models: [])

        #expect(capabilities.supportsResponses == false)
        #expect(capabilities.supportsSessions == false)
        #expect(capabilities.supportsRunApproval == false)
        #expect(capabilities.supportsServerSideContinuity == false)
        #expect(capabilities.models == ["hermes-agent"])
    }
}
