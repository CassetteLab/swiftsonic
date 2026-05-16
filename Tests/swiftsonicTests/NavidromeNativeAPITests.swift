// NavidromeNativeAPITests.swift — SwiftSonicTests
//
// Unit tests for NavidromeNativeAPI: JWT authentication, playlist cover upload,
// and a credential-canary suite that verifies no token escapes into error output.

import Testing
import Foundation
@testable import SwiftSonic

// MARK: - authenticate

@Suite("NavidromeNativeAPI.authenticate")
struct NavidromeNativeAPIAuthenticateTests {

    @Test("returns token extracted from JSON response")
    func returnsTokenOnSuccess() async throws {
        let mock = MockHTTPTransport()
        let json = #"{"token":"test_jwt_token","name":"alice","isAdmin":true}"#
        mock.enqueue(Data(json.utf8), statusCode: 200)

        let api = NavidromeNativeAPI(transport: mock)
        let token = try await api.authenticate(
            baseURL: URL(string: "https://music.example.com")!,
            username: "alice",
            password: "s3cr3t"
        )

        #expect(token == "test_jwt_token")
    }

    @Test("sends POST to /auth/login with JSON Content-Type")
    func sendsCorrectRequestShape() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data(#"{"token":"tok"}"#.utf8), statusCode: 200)

        let api = NavidromeNativeAPI(transport: mock)
        _ = try await api.authenticate(
            baseURL: URL(string: "https://music.example.com")!,
            username: "alice",
            password: "s3cr3t"
        )

        let req = try #require(mock.lastRequest)
        #expect(req.httpMethod == "POST")
        #expect(req.url?.path.hasSuffix("/auth/login") == true)
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("throws authenticationFailed on non-200 response")
    func throwsOnNon200() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data(), statusCode: 401)

        let api = NavidromeNativeAPI(transport: mock)

        await #expect(throws: NavidromeNativeAPIError.self) {
            _ = try await api.authenticate(
                baseURL: URL(string: "https://music.example.com")!,
                username: "alice",
                password: "wrongpassword"
            )
        }
    }

    @Test("throws networkError when transport throws")
    func throwsNetworkErrorOnTransportFailure() async throws {
        let mock = MockHTTPTransport()
        mock.enqueueError(URLError(.notConnectedToInternet))

        let api = NavidromeNativeAPI(transport: mock)

        do {
            _ = try await api.authenticate(
                baseURL: URL(string: "https://music.example.com")!,
                username: "alice",
                password: "s3cr3t"
            )
            Issue.record("Expected NavidromeNativeAPIError to be thrown")
        } catch let error as NavidromeNativeAPIError {
            if case .networkError = error { /* expected */ } else {
                Issue.record("Expected .networkError, got \(error)")
            }
        }
    }

    @Test("throws invalidResponse when body is not a login JSON")
    func throwsInvalidResponseOnBadBody() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data("not json at all".utf8), statusCode: 200)

        let api = NavidromeNativeAPI(transport: mock)

        do {
            _ = try await api.authenticate(
                baseURL: URL(string: "https://music.example.com")!,
                username: "alice",
                password: "s3cr3t"
            )
            Issue.record("Expected NavidromeNativeAPIError to be thrown")
        } catch let error as NavidromeNativeAPIError {
            if case .invalidResponse = error { /* expected */ } else {
                Issue.record("Expected .invalidResponse, got \(error)")
            }
        }
    }
}

// MARK: - uploadPlaylistCover

@Suite("NavidromeNativeAPI.uploadPlaylistCover")
struct NavidromeNativeAPIUploadTests {

    @Test("sends multipart/form-data Content-Type with boundary")
    func sendsMultipartContentType() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data(), statusCode: 200)

        let api = NavidromeNativeAPI(transport: mock)
        try await api.uploadPlaylistCover(
            baseURL: URL(string: "https://music.example.com")!,
            token: "some_token",
            playlistId: "playlist-42",
            imageData: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            mimeType: "image/jpeg"
        )

        let req = try #require(mock.lastRequest)
        let contentType = try #require(req.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
    }

    @Test("sends POST to /api/playlist/{id}/image")
    func sendsCorrectURL() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data(), statusCode: 200)

        let api = NavidromeNativeAPI(transport: mock)
        try await api.uploadPlaylistCover(
            baseURL: URL(string: "https://music.example.com")!,
            token: "some_token",
            playlistId: "playlist-99",
            imageData: Data([0x89, 0x50, 0x4E, 0x47]),
            mimeType: "image/png"
        )

        let req = try #require(mock.lastRequest)
        #expect(req.httpMethod == "POST")
        #expect(req.url?.path.hasSuffix("/api/playlist/playlist-99/image") == true)
    }

    @Test("sets x-nd-authorization Bearer header")
    func setsBearerAuthorizationHeader() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data(), statusCode: 200)

        let api = NavidromeNativeAPI(transport: mock)
        try await api.uploadPlaylistCover(
            baseURL: URL(string: "https://music.example.com")!,
            token: "my_jwt_token",
            playlistId: "p1",
            imageData: Data([0x00]),
            mimeType: "image/jpeg"
        )

        let req = try #require(mock.lastRequest)
        let auth = try #require(req.value(forHTTPHeaderField: "x-nd-authorization"))
        #expect(auth == "Bearer my_jwt_token")
    }

    @Test("body contains image field and image MIME type")
    func bodyContainsExpectedMultipartFields() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data(), statusCode: 200)

        let imageData = Data("fake_image_bytes".utf8)
        let api = NavidromeNativeAPI(transport: mock)
        try await api.uploadPlaylistCover(
            baseURL: URL(string: "https://music.example.com")!,
            token: "some_token",
            playlistId: "p1",
            imageData: imageData,
            mimeType: "image/png"
        )

        let req = try #require(mock.lastRequest)
        let bodyString = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        #expect(bodyString.contains("name=\"image\""))
        #expect(bodyString.contains("Content-Type: image/png"))
        #expect(bodyString.contains("fake_image_bytes"))
    }

    @Test("throws uploadFailed with statusCode on non-200 response")
    func throwsUploadFailedOnNon200() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data(), statusCode: 403)

        let api = NavidromeNativeAPI(transport: mock)

        do {
            try await api.uploadPlaylistCover(
                baseURL: URL(string: "https://music.example.com")!,
                token: "some_token",
                playlistId: "p1",
                imageData: Data([0x00]),
                mimeType: "image/jpeg"
            )
            Issue.record("Expected NavidromeNativeAPIError to be thrown")
        } catch let error as NavidromeNativeAPIError {
            if case .uploadFailed(let code) = error {
                #expect(code == 403)
            } else {
                Issue.record("Expected .uploadFailed(statusCode: 403), got \(error)")
            }
        }
    }

    @Test("throws networkError when transport throws during upload")
    func throwsNetworkErrorOnTransportFailure() async throws {
        let mock = MockHTTPTransport()
        mock.enqueueError(URLError(.networkConnectionLost))

        let api = NavidromeNativeAPI(transport: mock)

        do {
            try await api.uploadPlaylistCover(
                baseURL: URL(string: "https://music.example.com")!,
                token: "some_token",
                playlistId: "p1",
                imageData: Data([0x00]),
                mimeType: "image/jpeg"
            )
            Issue.record("Expected NavidromeNativeAPIError to be thrown")
        } catch let error as NavidromeNativeAPIError {
            if case .networkError = error { /* expected */ } else {
                Issue.record("Expected .networkError, got \(error)")
            }
        }
    }
}

// MARK: - Credential canary: token must not appear in any error output

/// Canary tests that inject a unique, recognisable JWT token marker and verify
/// it does not leak into any observable string output after an upload failure.
/// Any future regression that accidentally embeds the token in an error message
/// will cause these tests to fail immediately.
@Suite("NavidromeNativeAPI — JWT token never leaks into error output")
struct NavidromeNativeAPITokenLeakTests {

    private static let canaryToken = "jwt_canary_token_unique_marker_value_7f3a"

    @Test("token not in localizedDescription of upload error")
    func tokenNotInUploadErrorLocalizedDescription() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data(), statusCode: 403)

        let api = NavidromeNativeAPI(transport: mock)

        do {
            try await api.uploadPlaylistCover(
                baseURL: URL(string: "https://music.example.com")!,
                token: Self.canaryToken,
                playlistId: "p1",
                imageData: Data([0xFF, 0xD8]),
                mimeType: "image/jpeg"
            )
            Issue.record("Expected an error to be thrown")
        } catch {
            let desc = error.localizedDescription
            #expect(!desc.contains(Self.canaryToken), "token canary leaked into localizedDescription: \(desc)")
        }
    }

    @Test("token not in String(describing:) of upload error")
    func tokenNotInStringDescribingUploadError() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(Data(), statusCode: 500)

        let api = NavidromeNativeAPI(transport: mock)

        do {
            try await api.uploadPlaylistCover(
                baseURL: URL(string: "https://music.example.com")!,
                token: Self.canaryToken,
                playlistId: "p1",
                imageData: Data([0xFF, 0xD8]),
                mimeType: "image/jpeg"
            )
            Issue.record("Expected an error to be thrown")
        } catch {
            let debugDesc = String(describing: error)
            #expect(!debugDesc.contains(Self.canaryToken), "token canary leaked into String(describing:): \(debugDesc)")
        }
    }

    @Test("token not in any NavidromeNativeAPIError description case")
    func tokenNotInAnyErrorDescriptionCase() {
        let errors: [NavidromeNativeAPIError] = [
            .authenticationFailed,
            .uploadFailed(statusCode: 403),
            .networkError(underlying: URLError(.timedOut)),
            .invalidResponse,
        ]
        for error in errors {
            let desc      = error.localizedDescription
            let strDesc   = String(describing: error)
            #expect(!desc.contains(Self.canaryToken),    "\(error): token canary in localizedDescription")
            #expect(!strDesc.contains(Self.canaryToken), "\(error): token canary in String(describing:)")
        }
    }
}
