import Foundation

struct BasicAuthentication: Equatable, Sendable {
    let username: String
    let password: String

    var authorizationValue: String {
        let value = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(value)"
    }
}

/// Builds the `Authorization` header for a Hermes request.
///
/// Hermes deployments authenticate one of two ways:
/// - A username/password validated by an edge proxy (HTTP Basic).
/// - A single `API_SERVER_KEY` sent directly to the Hermes API server (Bearer).
///
/// The user expresses intent by whether they provide a username: a blank username
/// means "use the secret as a Bearer API key", otherwise Basic credentials are sent.
nonisolated enum HermesAuthorization {
    static func headerValue(username: String, secret: String) -> String {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if user.isEmpty {
            let token = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Bearer \(token)"
        }
        let encoded = Data("\(user):\(secret)".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    /// Whether the given username selects Bearer (API key) authentication.
    static func usesBearer(username: String) -> Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct HermesHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let headers: [AnyHashable: Any]
}

/// Decides whether the `Authorization` header may follow an HTTP redirect.
///
/// Credentials may only follow a redirect that stays on the same host and remains
/// HTTPS. A host change or a downgrade to HTTP is treated as unsafe and blocked.
/// Port and path changes on the same host — common with reverse proxies and
/// Tailscale front ends in front of Hermes — are permitted.
nonisolated enum RedirectPolicy {
    static func allowsCredentialForwarding(base: URL, target: URL) -> Bool {
        guard target.scheme?.lowercased() == "https" else { return false }
        guard let baseHost = base.host?.lowercased(),
              let targetHost = target.host?.lowercased(),
              !baseHost.isEmpty else {
            return false
        }
        return baseHost == targetHost
    }
}

/// Follows redirects that stay on the same host over HTTPS and rejects any redirect
/// that would change host or downgrade transport, so the `Authorization` header is
/// never sent to a different origin.
private final class OriginRedirectPolicyDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let baseURL: URL
    private let authorizationHeader: String

    init(baseURL: URL, authorizationHeader: String) {
        self.baseURL = baseURL
        self.authorizationHeader = authorizationHeader
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let target = request.url,
              RedirectPolicy.allowsCredentialForwarding(base: baseURL, target: target) else {
            completionHandler(nil) // Reject cross-host or downgraded redirects.
            return
        }
        // Re-apply the Authorization header explicitly; the redirect stays on the same host.
        var followed = request
        followed.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        completionHandler(followed)
    }
}

final class HermesHTTPClient: @unchecked Sendable {
    private let profile: ServerProfile
    private let authorizationHeader: String
    private let session: URLSession

    init(profile: ServerProfile, password: String, timeout: TimeInterval = 12) {
        self.profile = profile
        self.authorizationHeader = HermesAuthorization.headerValue(
            username: profile.username,
            secret: password
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        self.session = URLSession(
            configuration: configuration,
            delegate: OriginRedirectPolicyDelegate(
                baseURL: profile.baseURL,
                authorizationHeader: authorizationHeader
            ),
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    func get(_ endpoint: String) async throws -> HermesHTTPResponse {
        let url = try endpointURL(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HermesConnectionError.invalidResponse
            }
            // The final URL must remain on the configured host over HTTPS. A rejected
            // cross-host redirect surfaces here as an unfollowed 3xx response.
            if let finalURL = response.url,
               !RedirectPolicy.allowsCredentialForwarding(base: profile.baseURL, target: finalURL) {
                throw HermesConnectionError.redirectedOutsideServer
            }
            if (300..<400).contains(httpResponse.statusCode) {
                throw HermesConnectionError.redirectedOutsideServer
            }
            return HermesHTTPResponse(
                data: data,
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields
            )
        } catch let error as HermesConnectionError {
            throw error
        } catch let error as URLError {
            throw map(error)
        } catch is CancellationError {
            throw HermesConnectionError.cancelled
        } catch {
            throw HermesConnectionError.other("The connection failed. Try again.")
        }
    }

    private func endpointURL(_ endpoint: String) throws -> URL {
        guard profile.baseURL.scheme?.lowercased() == "https",
              profile.baseURL.host != nil else {
            throw HermesConnectionError.invalidConfiguration("Hermes requires a valid HTTPS server URL.")
        }
        let components = endpoint.split(separator: "/").map(String.init)
        let url = components.reduce(profile.baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
        guard isSameOrigin(url) else {
            throw HermesConnectionError.invalidConfiguration("The requested endpoint is outside the configured server.")
        }
        return url
    }

    private func isSameOrigin(_ url: URL) -> Bool {
        guard let left = URLComponents(url: profile.baseURL, resolvingAgainstBaseURL: false),
              let right = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && effectivePort(left) == effectivePort(right)
            && right.path.hasPrefix(left.path)
    }

    private func effectivePort(_ components: URLComponents) -> Int? {
        components.port ?? (components.scheme?.lowercased() == "https" ? 443 : nil)
    }

    private func map(_ error: URLError) -> HermesConnectionError {
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
}
