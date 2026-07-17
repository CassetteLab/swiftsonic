// PlaybackReportTests.swift — SwiftSonicTests
//
// Tests for the OpenSubsonic reportPlayback endpoint: the exact query it sends.
//
// The parameter names come straight from the spec (mediaId, mediaType, positionMs,
// state, playbackRate, ignoreScrobble) — a typo here is silent, the server just
// ignores the call, so the tests assert the wire names literally.

import Testing
import Foundation
@testable import SwiftSonic

@Suite("reportPlayback")
struct PlaybackReportTests {

    @Test("sends the required params with the spec's names")
    func sendsRequiredParams() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        try await client.reportPlayback(mediaId: "42", positionMs: 12_345, state: .playing)

        #expect(mock.queryItem(named: "mediaId") == "42")
        #expect(mock.queryItem(named: "mediaType") == "song")
        #expect(mock.queryItem(named: "positionMs") == "12345")
        #expect(mock.queryItem(named: "state") == "playing")

        let req = try #require(mock.lastRequest)
        #expect(req.url?.path.hasSuffix("/rest/reportPlayback.view") == true)
    }

    @Test("state serialises to the four spec values", arguments: [
        (SwiftSonicClient.PlaybackReportState.starting, "starting"),
        (.playing, "playing"),
        (.paused, "paused"),
        (.stopped, "stopped"),
    ])
    func serialisesState(state: SwiftSonicClient.PlaybackReportState, expected: String) async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        try await client.reportPlayback(mediaId: "1", positionMs: 0, state: state)

        #expect(mock.queryItem(named: "state") == expected)
    }

    @Test("podcast media type is sent when asked")
    func sendsPodcastMediaType() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        try await client.reportPlayback(mediaId: "9", mediaType: .podcast, positionMs: 0, state: .playing)

        #expect(mock.queryItem(named: "mediaType") == "podcast")
    }

    @Test("optional params are omitted unless set")
    func omitsOptionalParams() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        try await client.reportPlayback(mediaId: "1", positionMs: 0, state: .paused)

        #expect(mock.queryItem(named: "playbackRate") == nil)
        #expect(mock.queryItem(named: "ignoreScrobble") == nil)
    }

    @Test("optional params are sent when provided")
    func sendsOptionalParams() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        try await client.reportPlayback(
            mediaId: "1",
            positionMs: 0,
            state: .playing,
            playbackRate: 1.5,
            ignoreScrobble: true
        )

        #expect(mock.queryItem(named: "playbackRate") == "1.5")
        #expect(mock.queryItem(named: "ignoreScrobble") == "true")
    }

    @Test("a negative position is clamped to zero, never sent negative")
    func clampsNegativePosition() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "ping_ok")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        try await client.reportPlayback(mediaId: "1", positionMs: -500, state: .stopped)

        #expect(mock.queryItem(named: "positionMs") == "0")
    }
}
