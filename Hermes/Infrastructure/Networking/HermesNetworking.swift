import Foundation

/// Builds request URLs that stay inside a profile's configured HTTPS origin.
///
/// Shared by every Hermes client so endpoint construction and the same-origin rule
/// have exactly one implementation.
nonisolated enum HermesEndpoint {
    static func url(base: URL, path: String, query: [URLQueryItem] = []) throws -> URL {
        guard base.scheme?.lowercased() == "https", base.host != nil else {
            throw HermesConnectionError.invalidConfiguration("Hermes requires a valid HTTPS server URL.")
        }
        let url = path
            .split(separator: "/")
            .map(String.init)
            .reduce(base) { partial, component in partial.appendingPathComponent(component) }
        guard isSameOrigin(base: base, url) else {
            throw HermesConnectionError.invalidConfiguration("The requested endpoint is outside the configured server.")
        }
        guard !query.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = query
        return components.url ?? url
    }

    static func isSameOrigin(base: URL, _ url: URL) -> Bool {
        guard let left = URLComponents(url: base, resolvingAgainstBaseURL: false),
              let right = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && effectivePort(left) == effectivePort(right)
            && right.path.hasPrefix(left.path)
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        components.port ?? (components.scheme?.lowercased() == "https" ? 443 : nil)
    }
}

extension HermesConnectionError {
    /// Maps a transport-level `URLError` onto a user-facing connection state.
    static func from(_ error: URLError) -> HermesConnectionError {
        switch error.code {
        case .cancelled:
            .cancelled
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
            .offline
        case .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired,
             .secureConnectionFailed:
            .tlsFailure
        case .httpTooManyRedirects, .redirectToNonExistentLocation:
            .redirectedOutsideServer
        default:
            .other("The secure connection failed (\(error.code.rawValue)).")
        }
    }

    /// Maps an HTTP status outside the success range onto a connection state.
    static func from(statusCode: Int) -> HermesConnectionError {
        switch statusCode {
        case 401: .unauthorized
        case 403: .forbidden
        default: .unavailable(statusCode)
        }
    }
}
