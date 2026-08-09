import Foundation

struct AppEnvironment: Sendable {
    let settingsStore: any ConnectionSettingsStoring
    let credentialStore: any CredentialStoring
    let connectionTester: any ConnectionTesting
    let chatClient: any ChatStreaming
    let sessionsClient: (any TranscriptReconciling)?
    let capabilityDiscovery: (any CapabilityDiscovering)?
    let logger: HermesLogger

    static func production() -> AppEnvironment {
        AppEnvironment(
            settingsStore: ConnectionSettingsStore(),
            credentialStore: KeychainCredentialStore(),
            connectionTester: ConnectionTestService(),
            chatClient: HermesChatClient(),
            sessionsClient: HermesSessionsClient(),
            capabilityDiscovery: HermesCapabilitiesClient(),
            logger: HermesLogger(category: "app")
        )
    }
}
