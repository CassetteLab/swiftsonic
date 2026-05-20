// SwiftSonicError.swift — SwiftSonic
//
// Defines the complete error hierarchy for the SwiftSonic library.
// All errors are Sendable and can be safely propagated across concurrency boundaries.
//
// Top-level: SwiftSonicError (the type callers catch)
// Nested:    SubsonicAPIError (server-reported error with typed code)
//            SubsonicErrorCode (exhaustive enum of Subsonic error codes)

import Foundation

// MARK: - Top-level error

/// The error type thrown by all `SwiftSonicClient` methods.
///
/// Use a `switch` statement to handle each case:
/// ```swift
/// do {
///     let artists = try await client.getArtists()
/// } catch let error as SwiftSonicError {
///     switch error {
///     case .api(let apiError) where apiError.code == .wrongCredentials:
///         // prompt re-authentication
///     case .network(let urlError):
///         // show connectivity error
///     default:
///         break
///     }
/// }
/// ```
public enum SwiftSonicError: Error, Sendable {
    /// The server responded with `status: "failed"` and a typed error code.
    case api(SubsonicAPIError)

    /// A network-level error occurred before a response was received.
    case network(URLError)

    /// The server returned a 2xx response but the JSON could not be decoded.
    /// The raw `Data` is included to aid debugging.
    case decoding(DecodingError, rawData: Data)

    /// The server returned a non-2xx HTTP status code (excluding 429).
    ///
    /// `endpoint` identifies the Subsonic endpoint that failed (e.g. `"getArtists"`).
    /// `serverHost` is the hostname from ``ServerConfiguration/serverURL``
    /// (e.g. `"music.example.com"`). Neither field contains authentication credentials.
    case httpError(statusCode: Int, endpoint: String, serverHost: String?)

    /// The server returned HTTP 429 (Too Many Requests).
    ///
    /// `retryAfter` is the server's suggested delay in seconds, parsed from the
    /// `Retry-After` header. When present, ``SwiftSonicClient`` uses this value
    /// instead of the configured ``RetryPolicy/baseDelay``.
    /// `endpoint` and `serverHost` identify the request without exposing credentials.
    case rateLimited(retryAfter: TimeInterval?, endpoint: String, serverHost: String?)

    /// A client-side configuration problem prevented building the request.
    case invalidConfiguration(String)

    /// A cross-domain HTTP redirect was detected and blocked.
    ///
    /// Subsonic authentication credentials are embedded as query parameters in
    /// every request URL. Following a redirect to a different host would silently
    /// forward those credentials to an untrusted third party.
    ///
    /// `from` is the URL of the original request; `to` is the redirect destination
    /// that was blocked. Neither field contains authentication credentials — only
    /// the host and path components are relevant here.
    case insecureRedirect(from: URL, to: URL)
}

// MARK: - LocalizedError conformance

/// Provides human-readable, credential-safe error descriptions.
///
/// Credential values (usernames, passwords, API keys) are **never** included
/// in any description string. Only structural information safe to surface in
/// UI, logs, or crash reports is included.
extension SwiftSonicError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .api(let error):
            return "Server error \(error.code.rawValue) from \(error.serverHost ?? "unknown"): \(error.message)"
        case .network(let urlError):
            return "Network error: \(urlError.localizedDescription)"
        case .decoding(let decodingError, _):
            return "Response decoding failed: \(decodingError.localizedDescription)"
        case .httpError(let statusCode, let endpoint, let serverHost):
            return "HTTP \(statusCode) from \(serverHost ?? "unknown") on endpoint '\(endpoint)'"
        case .rateLimited(_, let endpoint, let serverHost):
            return "Rate limited by \(serverHost ?? "unknown") on endpoint '\(endpoint)'"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .insecureRedirect(let from, let to):
            return "Blocked cross-domain redirect from '\(from.host ?? "unknown")' to '\(to.host ?? "unknown")'"
        }
    }
}

// MARK: - Convenience helpers

public extension SwiftSonicError {
    /// Whether this error is likely transient and safe to retry.
    ///
    /// `true` for network timeouts/resets, HTTP 5xx, and `.rateLimited`.
    /// `false` for auth failures, decoding errors, and other client errors.
    var isTransient: Bool {
        switch self {
        case .network(let urlError):
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost,
                 .dataNotAllowed, .internationalRoamingOff:
                return true
            default:
                return false
            }
        case .rateLimited:
            return true
        case .httpError(let statusCode, _, _):
            return (500...599).contains(statusCode)
        case .api, .decoding, .invalidConfiguration, .insecureRedirect:
            return false
        }
    }

    /// Whether this error indicates an authentication or authorisation failure.
    var isAuthenticationFailure: Bool {
        switch self {
        case .api(let error):
            switch error.code {
            case .wrongCredentials, .tokenAuthNotSupportedForLDAP,
                 .authMechanismNotSupported, .conflictingAuthMechanisms,
                 .invalidAPIKey, .unauthorized:
                return true
            default:
                return false
            }
        case .httpError(let statusCode, _, _):
            return statusCode == 401 || statusCode == 403
        default:
            return false
        }
    }

    /// The server-suggested delay before retrying, in seconds.
    ///
    /// Non-nil only for `.rateLimited` responses that include a `Retry-After` header.
    var suggestedRetryDelay: TimeInterval? {
        if case .rateLimited(let retryAfter, _, _) = self { return retryAfter }
        return nil
    }

    /// Whether this error is a DNS resolution failure.
    ///
    /// Returns `true` when the underlying `URLError` has code `.cannotFindHost`
    /// or `.dnsLookupFailed`.
    ///
    /// > Note: On iOS, a Local Network Privacy permission block typically surfaces
    /// > as `.cannotFindHost` and is therefore indistinguishable from a genuine
    /// > DNS failure via this helper.
    var isDNSFailure: Bool {
        guard case .network(let urlError) = self else { return false }
        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    /// Whether this error is a TLS certificate validation failure.
    ///
    /// Covers both server-side errors (`.serverCertificateUntrusted`,
    /// `.serverCertificateHasBadDate`, `.serverCertificateHasUnknownRoot`,
    /// `.serverCertificateNotYetValid`) and client-side errors
    /// (`.clientCertificateRejected`, `.clientCertificateRequired`).
    var isCertificateError: Bool {
        guard case .network(let urlError) = self else { return false }
        switch urlError.code {
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            return true
        default:
            return false
        }
    }
}

// MARK: - API error detail

/// Carries the structured error information returned by a Subsonic/OpenSubsonic server
/// when `status` is `"failed"`.
public struct SubsonicAPIError: Error, Sendable {
    /// The machine-readable error code.
    public let code: SubsonicErrorCode

    /// The human-readable message provided by the server.
    ///
    /// > Note: This value is returned verbatim by the server. While SwiftSonic servers
    /// > should not include credential information in error messages, the content of
    /// > this field is outside the library's control.
    public let message: String

    /// An optional URL to documentation for this error (OpenSubsonic servers only).
    public let helpURL: URL?

    /// The Subsonic endpoint that produced this error (e.g. `"getArtists"`).
    ///
    /// Does not contain authentication credentials.
    public let endpoint: String

    /// The hostname of the server (e.g. `"music.example.com"`), or `nil` if unavailable.
    ///
    /// Does not contain authentication credentials.
    public let serverHost: String?
}

// MARK: - Subsonic error codes

/// Exhaustive enumeration of the error codes defined by the Subsonic and OpenSubsonic specs.
///
/// Unknown codes (from future server versions) are represented as ``unknown``.
public enum SubsonicErrorCode: Int, Sendable, Codable, Equatable {
    /// A generic, unspecified server error.
    case generic = 0
    /// A required parameter was missing from the request.
    case missingParameter = 10
    /// The client needs to upgrade its protocol version.
    case clientMustUpgrade = 20
    /// The server needs to upgrade to support the requested feature.
    case serverMustUpgrade = 30
    /// Wrong username or password.
    case wrongCredentials = 40
    /// Token authentication is not supported for LDAP users.
    case tokenAuthNotSupportedForLDAP = 41
    /// The requested authentication mechanism is not supported by this server.
    case authMechanismNotSupported = 42
    /// Multiple conflicting authentication mechanisms were provided.
    case conflictingAuthMechanisms = 43
    /// The provided API key is invalid.
    case invalidAPIKey = 44
    /// The authenticated user is not authorized for this operation.
    case unauthorized = 50
    /// The Subsonic server's trial period has expired.
    case trialExpired = 60
    /// The requested data was not found.
    case notFound = 70
    /// An unrecognized error code returned by the server.
    case unknown = -1

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = SubsonicErrorCode(rawValue: raw) ?? .unknown
    }
}
