import Foundation
import Testing
@testable import Hermes

/// `POST /api/sessions` wraps its result in `session`, while `PATCH` and `fork`
/// have been observed returning the session directly. Both shapes must decode.
struct SessionMutationDecodingTests {
    @Test func decodesEnvelopedSession() throws {
        let json = Data(#"{"session":{"id":"abc","title":"Renamed","message_count":4}}"#.utf8)

        let session = try HermesSessionsClient.decodeSession(from: json)

        #expect(session.id == "abc")
        #expect(session.title == "Renamed")
        #expect(session.messageCount == 4)
    }

    @Test func decodesBareSession() throws {
        let json = Data(#"{"id":"def","title":"Forked","message_count":9}"#.utf8)

        let session = try HermesSessionsClient.decodeSession(from: json)

        #expect(session.id == "def")
        #expect(session.title == "Forked")
        #expect(session.messageCount == 9)
    }

    @Test func rejectsUnrelatedPayload() {
        let json = Data(#"{"error":"not found"}"#.utf8)

        #expect(throws: (any Error).self) {
            try HermesSessionsClient.decodeSession(from: json)
        }
    }
}
