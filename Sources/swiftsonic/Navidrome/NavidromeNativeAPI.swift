// NavidromeNativeAPI.swift — SwiftSonic
//
// Concrete implementation of NavidromePlaylistCoverUploading.
// Uses URLSession via the HTTPTransport seam — zero additional dependencies.
// No coupling to SwiftSonicClient or the Subsonic protocol layer.

import Foundation

/// Navidrome-native REST API client for playlist cover management.
///
/// Uses the same ``HTTPTransport`` seam as the rest of SwiftSonic, making it
/// straightforward to inject mock transports in tests.
///
/// > Important: This type implements Navidrome-specific endpoints that are **not**
/// > part of the Subsonic or OpenSubsonic specifications. It requires separate
/// > JWT authentication via ``authenticate(baseURL:username:password:)``.
public struct NavidromeNativeAPI: NavidromePlaylistCoverUploading {

    private let transport: any HTTPTransport

    /// Creates an instance backed by the given transport.
    ///
    /// - Parameter transport: The HTTP transport to use. Defaults to ``URLSessionTransport``.
    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    // MARK: - NavidromePlaylistCoverUploading

    public func authenticate(
        baseURL: URL,
        username: String,
        password: String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("auth/login")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = LoginRequestBody(username: username, password: password)
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw NavidromeNativeAPIError.networkError(underlying: error)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw NavidromeNativeAPIError.networkError(underlying: error)
        }

        guard response.statusCode == 200 else {
            throw NavidromeNativeAPIError.authenticationFailed
        }

        guard let loginResponse = try? JSONDecoder().decode(LoginResponseBody.self, from: data) else {
            throw NavidromeNativeAPIError.invalidResponse
        }
        return loginResponse.token
    }

    public func uploadPlaylistCover(
        baseURL: URL,
        token: String,
        playlistId: String,
        imageData: Data,
        mimeType: String
    ) async throws {
        let url = baseURL.appendingPathComponent("api/playlist/\(playlistId)/image")
        let boundary = "SwiftSonic-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = multipartBody(imageData: imageData, mimeType: mimeType, boundary: boundary)

        let response: HTTPURLResponse
        do {
            (_, response) = try await transport.data(for: request)
        } catch {
            throw NavidromeNativeAPIError.networkError(underlying: error)
        }

        guard response.statusCode == 200 else {
            throw NavidromeNativeAPIError.uploadFailed(statusCode: response.statusCode)
        }
    }

    // MARK: - Private helpers

    private func multipartBody(imageData: Data, mimeType: String, boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"

        let filename: String
        switch mimeType {
        case "image/png":        filename = "cover.png"
        case "image/jpeg", "image/jpg": filename = "cover.jpg"
        default:                 filename = "cover"
        }

        func append(_ string: String) {
            if let d = string.data(using: .utf8) { body.append(d) }
        }

        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"playlistImage\"; filename=\"\(filename)\"\(crlf)")
        append("Content-Type: \(mimeType)\(crlf)")
        append(crlf)
        body.append(imageData)
        append(crlf)
        append("--\(boundary)--\(crlf)")

        return body
    }
}

// MARK: - Private Codable helpers

private struct LoginRequestBody: Encodable {
    let username: String
    let password: String
}

private struct LoginResponseBody: Decodable {
    let token: String
}
