import Foundation
import Testing
@testable import Hermes

@Suite("Run cancellation capability")
struct RunStopCapabilityTests {
    private func document(_ json: String) throws -> HermesCapabilityDocument {
        try JSONDecoder().decode(HermesCapabilityDocument.self, from: Data(json.utf8))
    }

    @Test("A server advertising run_stop enables real cancellation")
    func enablesStopWhenAdvertised() throws {
        let document = try document(#"""
        {"features":{"run_submission":true,"run_stop":true,"run_approval_response":true}}
        """#)

        let capabilities = ServerCapabilities.unknown.merging(document, version: nil, models: [])

        #expect(capabilities.supportsRunStop)
    }

    @Test("A server that does not advertise it leaves cancellation off")
    func staysOffWhenAbsent() throws {
        let document = try document(#"{"features":{"run_submission":true}}"#)

        let capabilities = ServerCapabilities.unknown.merging(document, version: nil, models: [])

        #expect(capabilities.supportsRunStop == false)
    }
}
