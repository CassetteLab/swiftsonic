// NavidromeNativeAPIError.swift — SwiftSonic
//
// Typed errors thrown by NavidromeNativeAPI.
// All description strings are credential-safe: no JWT token, username, or password
// is ever included in any observable string representation of these errors.

import Foundation

/// Errors thrown by ``NavidromeNativeAPI``.
///
/// All description strings are credential-safe — no JWT token or password
/// is ever interpolated into `localizedDescription`, `description`, or
/// `debugDescription`.
public enum NavidromeNativeAPIError: Error, Sendable {
    /// The server rejected the login credentials.
    case authenticationFailed
    /// The image upload request returned an unexpected HTTP status code.
    case uploadFailed(statusCode: Int)
    /// A network-level failure occurred before a response was received.
    case networkError(underlying: Error)
    /// The server returned an unrecognisable or malformed response body.
    case invalidResponse
}

// MARK: - LocalizedError

extension NavidromeNativeAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Navidrome authentication failed: invalid credentials or server error."
        case .uploadFailed(let statusCode):
            return "Playlist cover upload failed with HTTP \(statusCode)."
        case .networkError(let underlying):
            return "Network error during Navidrome request: \(underlying.localizedDescription)"
        case .invalidResponse:
            return "Navidrome returned an unrecognisable response."
        }
    }
}
