import Foundation
import Security

protocol CredentialStoring: Sendable {
    func save(password: String, for profileID: UUID) async throws
    func password(for profileID: UUID) async throws -> String?
    func deletePassword(for profileID: UUID) async throws
}

enum CredentialStoreError: LocalizedError, Equatable {
    case invalidPassword
    case unexpectedData
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            "Enter a password."
        case .unexpectedData:
            "The saved credential could not be read."
        case let .keychain(status):
            "Keychain operation failed (\(status))."
        }
    }
}

actor KeychainCredentialStore: CredentialStoring {
    private let service: String

    /// Derived from the bundle so a fork with its own identifier gets its own
    /// Keychain namespace rather than sharing one.
    init(service: String = "\(Bundle.main.bundleIdentifier ?? "Hermes").server-credential") {
        self.service = service
    }

    func save(password: String, for profileID: UUID) throws {
        guard !password.isEmpty, let data = password.data(using: .utf8) else {
            throw CredentialStoreError.invalidPassword
        }

        let key = baseQuery(for: profileID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychain(updateStatus)
        }

        var addQuery = key
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychain(addStatus)
        }
    }

    func password(for profileID: UUID) throws -> String? {
        var query = baseQuery(for: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
        guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.unexpectedData
        }
        return password
    }

    func deletePassword(for profileID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(for profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
            kSecAttrSynchronizable as String: false
        ]
    }
}
