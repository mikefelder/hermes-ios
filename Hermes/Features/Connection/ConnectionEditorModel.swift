import Foundation
import Observation

@MainActor
@Observable
final class ConnectionEditorModel {
    var name: String
    var urlText: String
    var username: String
    var password = "" {
        didSet {
            if oldValue != password { passwordRevision &+= 1 }
        }
    }
    var isPasswordVisible = false
    private(set) var hasSavedPassword: Bool
    private(set) var isTesting = false
    private(set) var isSaving = false
    private(set) var checks: [ConnectionCheck] = []
    private(set) var testedCapabilities: ServerCapabilities?
    var errorMessage: String?

    private let appModel: AppModel
    private let originalProfile: ServerProfile?
    private var testedFingerprint: String?
    private var testedProfile: ServerProfile?
    private var passwordRevision = 0

    init(appModel: AppModel, profile: ServerProfile? = nil) {
        self.appModel = appModel
        self.originalProfile = profile
        self.name = profile?.name ?? "Hermes"
        self.urlText = profile?.baseURL.absoluteString ?? ""
        self.username = profile?.username ?? ""
        self.hasSavedPassword = profile != nil
    }

    var canTest: Bool {
        !isTesting && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (hasSavedPassword || !password.isEmpty)
    }

    var canSave: Bool {
        !isTesting && !isSaving && testedCapabilities != nil && testedFingerprint == currentFingerprint
    }

    func testConnection() async {
        guard !isTesting else { return }
        errorMessage = nil
        checks = []
        testedCapabilities = nil
        testedFingerprint = nil
        isTesting = true
        appModel.updateConnectionState(.connecting)
        defer { isTesting = false }

        do {
            let profile = try makeProfile()
            let credential = try await passwordForTest(profile: profile)
            let fingerprint = currentFingerprint

            for try await event in appModel.environment.connectionTester.test(profile: profile, password: credential) {
                switch event {
                case let .check(check):
                    update(check)
                case let .completed(capabilities):
                    testedProfile = profile
                    testedCapabilities = capabilities
                    testedFingerprint = fingerprint
                    appModel.updateConnectionState(capabilities.supportsMobileAdapter ? .connected : .degraded)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            appModel.updateConnectionState(connectionState(for: error))
        }
    }

    func save() async throws {
        guard canSave, let profile = testedProfile, let testedCapabilities else {
            throw HermesConnectionError.invalidConfiguration("Test these settings successfully before saving.")
        }
        isSaving = true
        defer { isSaving = false }
        try await appModel.save(
            profile: profile,
            newPassword: password.isEmpty ? nil : password,
            capabilities: testedCapabilities
        )
        password = ""
        hasSavedPassword = true
        testedFingerprint = currentFingerprint
    }

    private var currentFingerprint: String {
        [
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            urlText.trimmingCharacters(in: .whitespacesAndNewlines),
            username.trimmingCharacters(in: .whitespacesAndNewlines),
            String(passwordRevision)
        ].joined(separator: "|")
    }

    private func makeProfile() throws -> ServerProfile {
        try ServerProfile.validated(
            id: originalProfile?.id ?? UUID(),
            name: name,
            urlText: urlText,
            username: username,
            createdAt: originalProfile?.createdAt ?? .now
        )
    }

    private func passwordForTest(profile: ServerProfile) async throws -> String {
        if !password.isEmpty { return password }
        guard originalProfile?.id == profile.id,
              let saved = try await appModel.environment.credentialStore.password(for: profile.id),
              !saved.isEmpty else {
            hasSavedPassword = false
            throw CredentialStoreError.invalidPassword
        }
        hasSavedPassword = true
        return saved
    }

    private func update(_ check: ConnectionCheck) {
        if let index = checks.firstIndex(where: { $0.stage == check.stage }) {
            checks[index] = check
        } else {
            checks.append(check)
        }
    }

    private func connectionState(for error: Error) -> AppConnectionState {
        switch error as? HermesConnectionError {
        case .unauthorized, .forbidden:
            .unauthorized
        case .invalidResponse:
            .incompatible
        case .offline, .timedOut, .tlsFailure:
            .offline
        default:
            .degraded
        }
    }
}
