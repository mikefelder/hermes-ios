import Foundation

protocol ConnectionSettingsStoring: Sendable {
    func loadProfile() async throws -> ServerProfile?
    func save(profile: ServerProfile) async throws
    func deleteProfile() async throws
    func loadCapabilities() async -> ServerCapabilities?
    func save(capabilities: ServerCapabilities) async
    func deleteCapabilities() async
}

enum ConnectionSettingsError: LocalizedError {
    case encode
    case decode

    var errorDescription: String? {
        switch self {
        case .encode: "The server settings could not be saved."
        case .decode: "The saved server settings could not be read."
        }
    }
}

final class ConnectionSettingsStore: ConnectionSettingsStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let profileKey = "activeServerProfile.v1"
    private let capabilitiesKey = "serverCapabilities.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadProfile() throws -> ServerProfile? {
        guard let data = defaults.data(forKey: profileKey) else { return nil }
        do {
            return try JSONDecoder().decode(ServerProfile.self, from: data)
        } catch {
            throw ConnectionSettingsError.decode
        }
    }

    func save(profile: ServerProfile) throws {
        do {
            defaults.set(try JSONEncoder().encode(profile), forKey: profileKey)
        } catch {
            throw ConnectionSettingsError.encode
        }
    }

    func deleteProfile() {
        defaults.removeObject(forKey: profileKey)
    }

    /// The snapshot is a convenience for launch; it is refreshed from the server
    /// and carries no secret material.
    func loadCapabilities() -> ServerCapabilities? {
        guard let data = defaults.data(forKey: capabilitiesKey) else { return nil }
        return try? JSONDecoder().decode(ServerCapabilities.self, from: data)
    }

    func save(capabilities: ServerCapabilities) {
        guard let data = try? JSONEncoder().encode(capabilities) else { return }
        defaults.set(data, forKey: capabilitiesKey)
    }

    func deleteCapabilities() {
        defaults.removeObject(forKey: capabilitiesKey)
    }
}
