import Foundation
import Testing
@testable import Hermes

@Suite("Server profile validation")
struct ServerProfileValidationTests {
    @Test("Normalizes host, scheme, and trailing slash")
    func normalizesURL() throws {
        let profile = try ServerProfile.validated(
            name: "  Azure Hermes  ",
            urlText: "Hermes.Example.TS.NET/gateway/",
            username: " mike "
        )

        #expect(profile.name == "Azure Hermes")
        #expect(profile.baseURL.absoluteString == "https://hermes.example.ts.net/gateway")
        #expect(profile.username == "mike")
    }

    @Test("Preserves explicit HTTPS port and path case")
    func preservesPortAndPath() throws {
        let profile = try ServerProfile.validated(
            name: "Hermes",
            urlText: "https://host.ts.net:8443/Hermes/API///",
            username: "owner"
        )

        #expect(profile.baseURL.absoluteString == "https://host.ts.net:8443/Hermes/API")
    }

    @Test("Rejects insecure and credential-bearing URLs", arguments: [
        "http://host.ts.net",
        "https://user:secret@host.ts.net",
        "https://host.ts.net?token=secret",
        "https://host.ts.net/#fragment"
    ])
    func rejectsUnsafeURLs(value: String) {
        #expect(throws: ServerProfileValidationError.self) {
            try ServerProfile.validated(name: "Hermes", urlText: value, username: "owner")
        }
    }

    @Test("Rejects a colon in a Basic Authentication username")
    func rejectsColonUsername() {
        #expect(throws: ServerProfileValidationError.usernameContainsColon) {
            try ServerProfile.validated(name: "Hermes", urlText: "https://host.ts.net", username: "owner:admin")
        }
    }
}

@Suite("Basic authentication")
struct BasicAuthenticationTests {
    @Test("Encodes the complete UTF-8 credential once")
    func authorizationValue() {
        let authentication = BasicAuthentication(username: "user", password: "p@ss:word")
        #expect(authentication.authorizationValue == "Basic dXNlcjpwQHNzOndvcmQ=")
    }
}

@Suite("Connection settings", .serialized)
struct ConnectionSettingsTests {
    @Test("Persists profile metadata without a password")
    func profileContainsNoPassword() async throws {
        let suiteName = "HermesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ConnectionSettingsStore(defaults: defaults)
        let profile = try ServerProfile.validated(
            name: "Test",
            urlText: "https://host.ts.net",
            username: "owner"
        )
        try store.save(profile: profile)

        let loaded = try store.loadProfile()
        #expect(loaded == profile)
        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        #expect(!String(describing: domain).contains("canary-password"))
    }

    @Test("Delete is idempotent")
    func deleteIsIdempotent() async throws {
        let suiteName = "HermesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ConnectionSettingsStore(defaults: defaults)

        store.deleteProfile()
        store.deleteProfile()
        #expect(try store.loadProfile() == nil)
    }
}

@Suite("Keychain credentials", .serialized)
struct KeychainCredentialStoreTests {
    @Test("Saves, replaces, loads, and removes a device-only password")
    func roundTrip() async throws {
        let store = KeychainCredentialStore(service: "HermesTests.\(UUID().uuidString)")
        let profileID = UUID()
        defer {
            Task { try? await store.deletePassword(for: profileID) }
        }

        try await store.save(password: "canary-password", for: profileID)
        #expect(try await store.password(for: profileID) == "canary-password")

        try await store.save(password: "replacement", for: profileID)
        #expect(try await store.password(for: profileID) == "replacement")

        try await store.deletePassword(for: profileID)
        #expect(try await store.password(for: profileID) == nil)
        try await store.deletePassword(for: profileID)
    }
}
 
