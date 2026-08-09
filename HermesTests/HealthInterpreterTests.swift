import Foundation
import Testing
@testable import Hermes

@Suite("Health interpreter")
struct HealthInterpreterTests {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    @Test("Plain text ok is healthy")
    func plainTextOk() {
        #expect(HealthInterpreter.interpret(data("ok")) == .healthy(version: nil))
        #expect(HealthInterpreter.interpret(data("OK")) == .healthy(version: nil))
    }

    @Test("An empty body is healthy")
    func emptyBody() {
        #expect(HealthInterpreter.interpret(Data()) == .healthy(version: nil))
    }

    @Test("A JSON status of ok is healthy")
    func jsonOk() {
        #expect(HealthInterpreter.interpret(data(#"{"status":"ok"}"#)) == .healthy(version: nil))
    }

    @Test("An unknown JSON status is still treated as healthy")
    func unknownStatusHealthy() {
        #expect(HealthInterpreter.interpret(data(#"{"status":"operational"}"#)) == .healthy(version: nil))
    }

    @Test("A version field is extracted from either key")
    func versionExtraction() {
        #expect(HealthInterpreter.interpret(data(#"{"status":"ok","version":"1.4.2"}"#)) == .healthy(version: "1.4.2"))
        #expect(HealthInterpreter.interpret(data(#"{"hermes_version":"2026.8.1"}"#)) == .healthy(version: "2026.8.1"))
    }

    @Test("A JSON array body is healthy")
    func jsonArrayHealthy() {
        #expect(HealthInterpreter.interpret(data("[1,2,3]")) == .healthy(version: nil))
    }

    @Test("HTML or unexpected text is healthy")
    func htmlHealthy() {
        #expect(HealthInterpreter.interpret(data("<html><body>OK</body></html>")) == .healthy(version: nil))
    }

    @Test("An explicit non-healthy status fails", arguments: [
        "error", "down", "unavailable", "offline", "failed", "unhealthy", "critical"
    ])
    func unhealthyStatuses(token: String) {
        let payload = #"{"status":"\#(token)"}"#
        #expect(HealthInterpreter.interpret(data(payload)) == .unhealthy(status: token))
    }

    @Test("Status matching is case- and whitespace-insensitive")
    func statusNormalization() {
        #expect(HealthInterpreter.interpret(data(#"{"status":"  DOWN  "}"#)) == .unhealthy(status: "down"))
    }
}
