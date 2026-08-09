import Foundation

struct AppEnvironment: Sendable {
    let settingsStore: any ConnectionSettingsStoring
    let credentialStore: any CredentialStoring
    let connectionTester: any ConnectionTesting
    let logger: HermesLogger

    static func production() -> AppEnvironment {
        AppEnvironment(
            settingsStore: ConnectionSettingsStore(),
            credentialStore: KeychainCredentialStore(),
            connectionTester: ConnectionTestService(),
            logger: HermesLogger(category: "app")
        )
    }
}
