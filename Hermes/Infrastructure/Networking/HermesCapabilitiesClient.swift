import Foundation

/// Reads the API server's capability document.
protocol CapabilityDiscovering: Sendable {
    func capabilities(profile: ServerProfile, password: String) async throws -> HermesCapabilityDocument
}

nonisolated struct HermesCapabilitiesClient: CapabilityDiscovering {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 12) {
        self.timeout = timeout
    }

    func capabilities(profile: ServerProfile, password: String) async throws -> HermesCapabilityDocument {
        let response = try await HermesHTTPClient(profile: profile, password: password, timeout: timeout)
            .get("v1/capabilities")
        guard (200..<300).contains(response.statusCode) else {
            throw HermesConnectionError.from(statusCode: response.statusCode)
        }
        return try JSONDecoder().decode(HermesCapabilityDocument.self, from: response.data)
    }
}
