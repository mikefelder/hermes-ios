import Foundation
import Testing
@testable import Hermes

/// Forks are child sessions, so the list must request children — which also
/// admits sub-agent and dispatcher runs that are not conversations.
struct SessionListFilteringTests {
    private func summary(id: String, source: String?, parent: String? = nil) -> SessionSummary {
        let parentField = parent.map { #","parent_session_id":"\#($0)""# } ?? ""
        let sourceField = source.map { #","source":"\#($0)""# } ?? ""
        let json = Data(#"{"id":"\#(id)","message_count":1\#(sourceField)\#(parentField)}"#.utf8)
        return try! JSONDecoder().decode(SessionSummary.self, from: json)
    }

    @Test func treatsSubAgentAndDispatcherSessionsAsInternal() {
        #expect(summary(id: "a", source: "tool").isInternal)
        #expect(summary(id: "b", source: "kanban").isInternal)
        #expect(summary(id: "c", source: "TOOL").isInternal)
    }

    @Test func treatsUserFacingSourcesAsVisible() {
        #expect(!summary(id: "d", source: "api_server").isInternal)
        #expect(!summary(id: "e", source: nil).isInternal)
    }

    @Test func identifiesBranchesByParent() {
        #expect(summary(id: "f", source: "api_server", parent: "root").isBranch)
        #expect(!summary(id: "g", source: "api_server").isBranch)
    }

    @Test func decodesParentSessionIDFromForkResponse() throws {
        let json = Data(#"{"object":"hermes.session","session":{"id":"api_2_b","source":"api_server","message_count":6,"parent_session_id":"api_1_a"}}"#.utf8)

        let session = try HermesSessionsClient.decodeSession(from: json)

        #expect(session.parentSessionID == "api_1_a")
        #expect(session.isBranch)
    }
}
