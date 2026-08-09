import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let environment: AppEnvironment

    private(set) var activeProfile: ServerProfile?
    private(set) var capabilities: ServerCapabilities = .unknown
    private(set) var connectionState: AppConnectionState = .notConfigured
    private(set) var isRestoring = true
    var presentedError: String?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func restore() async {
        defer { isRestoring = false }
        do {
            activeProfile = try await environment.settingsStore.loadProfile()
            capabilities = await environment.settingsStore.loadCapabilities() ?? .unknown
            connectionState = activeProfile == nil ? .notConfigured : .offline
        } catch {
            presentedError = error.localizedDescription
            activeProfile = nil
            connectionState = .notConfigured
            environment.logger.error("Profile restoration failed", code: "profile_restore")
        }
        await refreshCapabilities()
    }

    /// Re-read what the server supports. Capabilities drive protocol selection and
    /// which features are offered, so a stale snapshot silently degrades the app.
    func refreshCapabilities() async {
        guard let profile = activeProfile,
              let discovery = environment.capabilityDiscovery else { return }
        do {
            guard let password = try await passwordForActiveProfile(), !password.isEmpty else { return }
            let document = try await discovery.capabilities(profile: profile, password: password)
            let refreshed = capabilities.merging(document, version: capabilities.observedVersion, models: capabilities.models)
            capabilities = refreshed
            await environment.settingsStore.save(capabilities: refreshed)
            connectionState = refreshed.supportsSessions ? .connected : .degraded
        } catch {
            environment.logger.error("Capability refresh failed", code: "capability_refresh")
        }
    }

    func passwordForActiveProfile() async throws -> String? {
        guard let activeProfile else { return nil }
        return try await environment.credentialStore.password(for: activeProfile.id)
    }

    func save(profile: ServerProfile, newPassword: String?, capabilities: ServerCapabilities) async throws {
        let oldProfile = activeProfile
        let oldPassword = try await environment.credentialStore.password(for: profile.id)
        let shouldReplacePassword = newPassword.map { !$0.isEmpty } == true

        if let newPassword, !newPassword.isEmpty {
            try await environment.credentialStore.save(password: newPassword, for: profile.id)
        } else if oldPassword == nil {
            throw CredentialStoreError.invalidPassword
        }

        do {
            try await environment.settingsStore.save(profile: profile)
        } catch {
            if shouldReplacePassword {
                if let oldPassword {
                    try? await environment.credentialStore.save(password: oldPassword, for: profile.id)
                } else {
                    try? await environment.credentialStore.deletePassword(for: profile.id)
                }
            }
            activeProfile = oldProfile
            throw error
        }

        activeProfile = profile
        self.capabilities = capabilities
        await environment.settingsStore.save(capabilities: capabilities)
        connectionState = capabilities.supportsSessions ? .connected : .degraded
    }

    func forgetServer() async throws {
        guard let profile = activeProfile else { return }
        try await environment.credentialStore.deletePassword(for: profile.id)
        try await environment.settingsStore.deleteProfile()
        await environment.settingsStore.deleteCapabilities()
        activeProfile = nil
        capabilities = .unknown
        connectionState = .notConfigured
    }

    func updateConnectionState(_ state: AppConnectionState) {
        connectionState = state
    }
}
