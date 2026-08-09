import Foundation

protocol ConnectionSettingsStoring: Sendable {
    func loadProfile() async throws -> ServerProfile?
    func save(profile: ServerProfile) async throws
    func deleteProfile() async throws
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
}
