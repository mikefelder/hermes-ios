import Foundation
import Testing
@testable import Hermes

@Suite("Hermes authorization")
struct HermesAuthorizationTests {
    @Test("A username selects Basic and encodes the credential once")
    func basicAuthorization() {
        let value = HermesAuthorization.headerValue(username: "user", secret: "p@ss:word")
        #expect(value == "Basic dXNlcjpwQHNzOndvcmQ=")
        #expect(HermesAuthorization.usesBearer(username: "user") == false)
    }

    @Test("A blank username selects a Bearer API key")
    func bearerAuthorization() {
        #expect(HermesAuthorization.headerValue(username: "", secret: "sk-hermes-123") == "Bearer sk-hermes-123")
        #expect(HermesAuthorization.usesBearer(username: "") == true)
    }

    @Test("A whitespace-only username still selects a Bearer API key")
    func whitespaceUsernameIsBearer() {
        #expect(HermesAuthorization.usesBearer(username: "   ") == true)
        #expect(HermesAuthorization.headerValue(username: "  ", secret: "key") == "Bearer key")
    }

    @Test("Bearer tokens are trimmed of surrounding whitespace and newlines")
    func bearerTrimsToken() {
        #expect(HermesAuthorization.headerValue(username: "", secret: "  key\n") == "Bearer key")
    }

    @Test("Basic usernames are trimmed before encoding")
    func basicTrimsUsername() {
        #expect(HermesAuthorization.headerValue(username: " user ", secret: "p@ss:word") == "Basic dXNlcjpwQHNzOndvcmQ=")
    }
}
