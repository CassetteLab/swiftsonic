// ResilienceTests.swift — SwiftSonicTests
//
// White-box tests for resilience primitives:
//   - RetryPolicy delay math (backoff, jitter bounds)
//   - SwiftSonicError classification helpers (isTransient, isAuthenticationFailure, suggestedRetryDelay)
//   - Metrics collector event sequence
//   - URLRequest timeout configuration

import Testing
import Foundation
@testable import SwiftSonic

// MARK: - SpyCollector (metrics test double)

/// A metrics collector that records every event for later inspection.
private final class SpyCollector: SwiftSonicMetricsCollector, @unchecked Sendable {
    private(set) var events: [SwiftSonicRequestEvent] = []
    func record(_ event: SwiftSonicRequestEvent) {
        events.append(event)
    }
}

// MARK: - RetryPolicy delay math

@Suite("RetryPolicy delay calculation")
struct RetryPolicyDelayTests {

    @Test("delay is always zero for a single-attempt policy")
    func delayIsZeroForNonePolicy() {
        let policy = RetryPolicy.none
        #expect(policy.delay(for: 0) == 0)
        #expect(policy.delay(for: 5) == 0)
    }

    @Test("delay doubles with each attempt when jitter is zero")
    func delayDoublesWithMultiplier() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1.0, multiplier: 2.0, jitterFactor: 0)
        #expect(policy.delay(for: 0) == 1.0)  // 1.0 × 2⁰
        #expect(policy.delay(for: 1) == 2.0)  // 1.0 × 2¹
        #expect(policy.delay(for: 2) == 4.0)  // 1.0 × 2²
        #expect(policy.delay(for: 3) == 8.0)  // 1.0 × 2³
    }

    @Test("delay is never negative regardless of jitter")
    func delayIsNeverNegative() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.1, multiplier: 2.0, jitterFactor: 1.0)
        for i in 0..<10 {
            #expect(policy.delay(for: i) >= 0)
        }
    }
}

// MARK: - SwiftSonicError.isTransient

@Suite("SwiftSonicError.isTransient")
struct IsTransientTests {

    @Test("transient URLError codes return true")
    func transientNetworkErrors() {
        let transientCodes: [URLError.Code] = [
            .networkConnectionLost,
            .timedOut,
            .notConnectedToInternet,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .cannotFindHost,
            .dataNotAllowed,
            .internationalRoamingOff
        ]
        for code in transientCodes {
            #expect(
                SwiftSonicError.network(URLError(code)).isTransient == true,
                "Expected URLError.\(code) to be transient"
            )
        }
    }

    @Test("non-transient URLError codes return false")
    func nonTransientNetworkErrors() {
        #expect(SwiftSonicError.network(URLError(.cancelled)).isTransient == false)
        #expect(SwiftSonicError.network(URLError(.badURL)).isTransient == false)
    }

    @Test("rateLimited is always transient")
    func rateLimitedIsTransient() {
        #expect(SwiftSonicError.rateLimited(retryAfter: nil, endpoint: "ping", serverHost: "test.example.com").isTransient == true)
        #expect(SwiftSonicError.rateLimited(retryAfter: 5.0, endpoint: "ping", serverHost: "test.example.com").isTransient == true)
    }

    @Test("HTTP 5xx is transient, 4xx is not")
    func httpErrors() {
        #expect(SwiftSonicError.httpError(statusCode: 500, endpoint: "ping", serverHost: "test.example.com").isTransient == true)
        #expect(SwiftSonicError.httpError(statusCode: 503, endpoint: "ping", serverHost: "test.example.com").isTransient == true)
        #expect(SwiftSonicError.httpError(statusCode: 400, endpoint: "ping", serverHost: "test.example.com").isTransient == false)
        #expect(SwiftSonicError.httpError(statusCode: 401, endpoint: "ping", serverHost: "test.example.com").isTransient == false)
        #expect(SwiftSonicError.httpError(statusCode: 404, endpoint: "ping", serverHost: "test.example.com").isTransient == false)
    }

    @Test("API and configuration errors are never transient")
    func apiAndConfigNeverTransient() {
        let apiError = SubsonicAPIError(code: .generic, message: "error", helpURL: nil, endpoint: "ping", serverHost: "test.example.com")
        #expect(SwiftSonicError.api(apiError).isTransient == false)
        #expect(SwiftSonicError.invalidConfiguration("bad config").isTransient == false)
    }

    @Test("insecureRedirect is never transient")
    func insecureRedirectIsNotTransient() {
        let from = URL(string: "https://music.example.com/rest/ping")!
        let to   = URL(string: "https://evil.example.com/steal")!
        #expect(SwiftSonicError.insecureRedirect(from: from, to: to).isTransient == false)
    }
}

// MARK: - SwiftSonicError.isAuthenticationFailure

@Suite("SwiftSonicError.isAuthenticationFailure")
struct IsAuthenticationFailureTests {

    @Test("API auth error codes return true")
    func apiAuthErrors() {
        let authCodes: [SubsonicErrorCode] = [
            .wrongCredentials,
            .tokenAuthNotSupportedForLDAP,
            .authMechanismNotSupported,
            .conflictingAuthMechanisms,
            .invalidAPIKey,
            .unauthorized
        ]
        for code in authCodes {
            let apiError = SubsonicAPIError(code: code, message: "auth error", helpURL: nil, endpoint: "ping", serverHost: "test.example.com")
            #expect(
                SwiftSonicError.api(apiError).isAuthenticationFailure == true,
                "Expected SubsonicErrorCode.\(code) to be an auth failure"
            )
        }
    }

    @Test("HTTP 401 and 403 are authentication failures")
    func httpAuthErrors() {
        #expect(SwiftSonicError.httpError(statusCode: 401, endpoint: "ping", serverHost: "test.example.com").isAuthenticationFailure == true)
        #expect(SwiftSonicError.httpError(statusCode: 403, endpoint: "ping", serverHost: "test.example.com").isAuthenticationFailure == true)
        #expect(SwiftSonicError.httpError(statusCode: 500, endpoint: "ping", serverHost: "test.example.com").isAuthenticationFailure == false)
        #expect(SwiftSonicError.httpError(statusCode: 404, endpoint: "ping", serverHost: "test.example.com").isAuthenticationFailure == false)
    }

    @Test("network and rate-limit errors are not authentication failures")
    func networkNotAuthFailure() {
        #expect(SwiftSonicError.network(URLError(.timedOut)).isAuthenticationFailure == false)
        #expect(SwiftSonicError.rateLimited(retryAfter: nil, endpoint: "ping", serverHost: "test.example.com").isAuthenticationFailure == false)
    }

    @Test("insecureRedirect is not an authentication failure")
    func insecureRedirectNotAuthFailure() {
        let from = URL(string: "https://music.example.com/rest/ping")!
        let to   = URL(string: "https://evil.example.com/steal")!
        #expect(SwiftSonicError.insecureRedirect(from: from, to: to).isAuthenticationFailure == false)
    }
}

// MARK: - SwiftSonicError.suggestedRetryDelay

@Suite("SwiftSonicError.suggestedRetryDelay")
struct SuggestedRetryDelayTests {

    @Test("rateLimited with Retry-After returns the parsed delay")
    func rateLimitedWithRetryAfter() {
        #expect(SwiftSonicError.rateLimited(retryAfter: 5.0, endpoint: "ping", serverHost: "test.example.com").suggestedRetryDelay == 5.0)
        #expect(SwiftSonicError.rateLimited(retryAfter: 0.0, endpoint: "ping", serverHost: "test.example.com").suggestedRetryDelay == 0.0)
    }

    @Test("rateLimited without Retry-After returns nil")
    func rateLimitedWithoutRetryAfter() {
        #expect(SwiftSonicError.rateLimited(retryAfter: nil, endpoint: "ping", serverHost: "test.example.com").suggestedRetryDelay == nil)
    }

    @Test("other error cases always return nil")
    func otherCasesReturnNil() {
        #expect(SwiftSonicError.network(URLError(.timedOut)).suggestedRetryDelay == nil)
        #expect(SwiftSonicError.httpError(statusCode: 503, endpoint: "ping", serverHost: "test.example.com").suggestedRetryDelay == nil)
        let from = URL(string: "https://music.example.com/rest/ping")!
        let to   = URL(string: "https://evil.example.com/steal")!
        #expect(SwiftSonicError.insecureRedirect(from: from, to: to).suggestedRetryDelay == nil)
    }
}

// MARK: - SwiftSonicError.isDNSFailure

@Suite("SwiftSonicError.isDNSFailure")
struct IsDNSFailureTests {

    @Test("cannotFindHost and dnsLookupFailed return true")
    func dnsCodes() {
        #expect(SwiftSonicError.network(URLError(.cannotFindHost)).isDNSFailure == true)
        #expect(SwiftSonicError.network(URLError(.dnsLookupFailed)).isDNSFailure == true)
    }

    @Test("out-of-scope network codes return false")
    func outOfScopeNetworkCodes() {
        #expect(SwiftSonicError.network(URLError(.timedOut)).isDNSFailure == false)
        #expect(SwiftSonicError.network(URLError(.cannotConnectToHost)).isDNSFailure == false)
    }

    @Test("non-network error cases return false")
    func nonNetworkCasesReturnFalse() {
        let apiError = SubsonicAPIError(code: .generic, message: "error", helpURL: nil, endpoint: "ping", serverHost: "test.example.com")
        #expect(SwiftSonicError.api(apiError).isDNSFailure == false)
        #expect(SwiftSonicError.httpError(statusCode: 503, endpoint: "ping", serverHost: "test.example.com").isDNSFailure == false)
        #expect(SwiftSonicError.rateLimited(retryAfter: nil, endpoint: "ping", serverHost: "test.example.com").isDNSFailure == false)
    }
}

// MARK: - SwiftSonicError.isCertificateError

@Suite("SwiftSonicError.isCertificateError")
struct IsCertificateErrorTests {

    @Test("all certificate URLError codes return true")
    func certCodes() {
        let certCodes: [URLError.Code] = [
            .serverCertificateUntrusted,
            .serverCertificateHasBadDate,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired,
        ]
        for code in certCodes {
            #expect(
                SwiftSonicError.network(URLError(code)).isCertificateError == true,
                "Expected URLError.\(code) to be a certificate error"
            )
        }
    }

    @Test("out-of-scope network codes return false")
    func outOfScopeNetworkCodes() {
        #expect(SwiftSonicError.network(URLError(.timedOut)).isCertificateError == false)
        #expect(SwiftSonicError.network(URLError(.cannotConnectToHost)).isCertificateError == false)
    }

    @Test("non-network error cases return false")
    func nonNetworkCasesReturnFalse() {
        let apiError = SubsonicAPIError(code: .generic, message: "error", helpURL: nil, endpoint: "ping", serverHost: "test.example.com")
        #expect(SwiftSonicError.api(apiError).isCertificateError == false)
        #expect(SwiftSonicError.httpError(statusCode: 503, endpoint: "ping", serverHost: "test.example.com").isCertificateError == false)
        #expect(SwiftSonicError.rateLimited(retryAfter: nil, endpoint: "ping", serverHost: "test.example.com").isCertificateError == false)
    }
}

// MARK: - Metrics collector

@Suite("Metrics collector")
struct MetricsCollectorTests {

    @Test("collector receives started/failed/retryScheduled/started/succeeded on one retry")
    func eventSequenceOnOneRetry() async throws {
        let mock = MockHTTPTransport()
        mock.enqueueError(URLError(.networkConnectionLost))
        mock.enqueue(fixture: "ping_ok")

        let spy = SpyCollector()
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, jitterFactor: 0)
        let client = SwiftSonicClient(
            configuration: .test,
            transport: mock,
            retryPolicy: policy,
            metricsCollector: spy
        )

        try await client.ping()

        #expect(spy.events.count == 5)

        if case .started(let ep, let att) = spy.events[0] {
            #expect(ep == "ping"); #expect(att == 0)
        } else { Issue.record("events[0] should be .started(\"ping\", 0)") }

        if case .failed(let ep, let att, _, _) = spy.events[1] {
            #expect(ep == "ping"); #expect(att == 0)
        } else { Issue.record("events[1] should be .failed") }

        if case .retryScheduled(let ep, let att, _) = spy.events[2] {
            #expect(ep == "ping"); #expect(att == 0)
        } else { Issue.record("events[2] should be .retryScheduled") }

        if case .started(let ep, let att) = spy.events[3] {
            #expect(ep == "ping"); #expect(att == 1)
        } else { Issue.record("events[3] should be .started(\"ping\", 1)") }

        if case .succeeded(let ep, let att, _) = spy.events[4] {
            #expect(ep == "ping"); #expect(att == 1)
        } else { Issue.record("events[4] should be .succeeded") }
    }

    @Test("no retryScheduled event when error is not transient")
    func noRetryScheduledOnNonTransientError() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_error_40") // wrongCredentials — non-transient

        let spy = SpyCollector()
        let client = SwiftSonicClient(
            configuration: .test,
            transport: mock,
            retryPolicy: .none,
            metricsCollector: spy
        )

        await #expect(throws: SwiftSonicError.self) {
            try await client.ping()
        }

        // Only started + failed; no retryScheduled
        #expect(spy.events.count == 2)
        if case .started = spy.events[0] {} else { Issue.record("events[0] should be .started") }
        if case .failed  = spy.events[1] {} else { Issue.record("events[1] should be .failed") }
    }
}

// MARK: - Request configuration

@Suite("Request configuration")
struct RequestConfigurationTests {

    @Test("URLRequest.timeoutInterval reflects configuration.requestTimeout")
    func timeoutIntervalIsApplied() async throws {
        let config = ServerConfiguration(
            serverURL: URL(string: "https://test.example.com")!,
            username: "u",
            password: "p",
            requestTimeout: 42
        )
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")

        let client = SwiftSonicClient(configuration: config, transport: mock, retryPolicy: .none)
        try await client.ping()

        let req = try #require(mock.lastRequest)
        #expect(req.timeoutInterval == 42)
    }
}
