import Foundation
import Testing
@testable import Hermes

@Suite("Redirect credential policy")
struct RedirectPolicyTests {
    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test("Allows a same-host redirect that changes only the path")
    func sameHostDifferentPath() throws {
        let base = try url("https://hermes.example.ts.net/health")
        let target = try url("https://hermes.example.ts.net/health/")
        #expect(RedirectPolicy.allowsCredentialForwarding(base: base, target: target))
    }

    @Test("Allows a same-host redirect that changes only the port")
    func sameHostDifferentPort() throws {
        let base = try url("https://hermes.example.ts.net")
        let target = try url("https://hermes.example.ts.net:8642/v1/models")
        #expect(RedirectPolicy.allowsCredentialForwarding(base: base, target: target))
    }

    @Test("Allows a scheme written in uppercase")
    func uppercaseHTTPS() throws {
        let base = try url("https://hermes.example.ts.net")
        let target = try url("HTTPS://hermes.example.ts.net/x")
        #expect(RedirectPolicy.allowsCredentialForwarding(base: base, target: target))
    }

    @Test("Rejects a redirect to a different host")
    func differentHost() throws {
        let base = try url("https://hermes.example.ts.net")
        let target = try url("https://login.example.com/oauth")
        #expect(RedirectPolicy.allowsCredentialForwarding(base: base, target: target) == false)
    }

    @Test("Rejects an attacker subdomain")
    func subdomainMismatch() throws {
        let base = try url("https://hermes.example.ts.net")
        let target = try url("https://hermes.example.ts.net.evil.com/")
        #expect(RedirectPolicy.allowsCredentialForwarding(base: base, target: target) == false)
    }

    @Test("Rejects an HTTPS to HTTP downgrade on the same host")
    func downgrade() throws {
        let base = try url("https://hermes.example.ts.net")
        let target = try url("http://hermes.example.ts.net/health")
        #expect(RedirectPolicy.allowsCredentialForwarding(base: base, target: target) == false)
    }

    @Test("Rejects a target without a host")
    func missingHost() throws {
        let base = try url("https://hermes.example.ts.net")
        let target = try url("https:///health")
        #expect(RedirectPolicy.allowsCredentialForwarding(base: base, target: target) == false)
    }
}
