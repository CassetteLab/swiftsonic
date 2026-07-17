// SwiftSonicClient+PlaybackReport.swift — SwiftSonic
//
// The OpenSubsonic "Playback Report" extension: reportPlayback.
//
// Reports the client's playback timeline to the server — playing / paused / stopped
// with a position — so integrations (a server-side Discord Rich Presence, for one)
// can show real playback state rather than a bare now-playing.
//
// Gate calls behind `capabilities.supports(.playbackReport)`: it is an extension, not
// core Subsonic, so most servers do not answer it.
//
// Returns an empty response on success, so it goes through performVoid.

import Foundation

public extension SwiftSonicClient {

    /// Playback state reported to the server.
    ///
    /// `starting` is the buffering/preparing moment before audio; the others are what
    /// they say.
    enum PlaybackReportState: String, Sendable, Hashable, CaseIterable {
        case starting
        case playing
        case paused
        case stopped
    }

    /// What `mediaId` refers to, so the server knows how to read it.
    enum PlaybackReportMediaType: String, Sendable, Hashable, CaseIterable {
        case song
        case podcast
    }

    /// Reports the current playback timeline (OpenSubsonic `reportPlayback`).
    ///
    /// - Parameters:
    ///   - mediaId: The id of the media being reported.
    ///   - mediaType: Whether `mediaId` is a song or a podcast episode. Defaults to song.
    ///   - positionMs: The playback position, in milliseconds.
    ///   - state: The playback state.
    ///   - playbackRate: Speed multiplier. Omit for the server default (1.0).
    ///   - ignoreScrobble: When `true`, the server updates now-playing/state display only
    ///     and does not scrobble or bump the play count. Use this to send rich state
    ///     alongside a separate scrobble, without double-counting the play.
    /// - Throws: ``SwiftSonicError`` — including ``SwiftSonicError/api(_:)`` when the
    ///   server does not implement the extension, which is why callers should gate on
    ///   ``ServerCapabilities/supports(_:)-...`` with ``ServerCapabilities/KnownExtension/playbackReport``.
    func reportPlayback(
        mediaId: String,
        mediaType: PlaybackReportMediaType = .song,
        positionMs: Int,
        state: PlaybackReportState,
        playbackRate: Double? = nil,
        ignoreScrobble: Bool? = nil
    ) async throws {
        var params: [String: String] = [
            "mediaId": mediaId,
            "mediaType": mediaType.rawValue,
            // Never a negative position: a seek-to-zero or a rounding glitch would send
            // a nonsense value the server may reject.
            "positionMs": String(max(0, positionMs)),
            "state": state.rawValue,
        ]

        if let playbackRate {
            params["playbackRate"] = String(playbackRate)
        }
        if let ignoreScrobble {
            params["ignoreScrobble"] = ignoreScrobble ? "true" : "false"
        }

        try await performVoid(endpoint: "reportPlayback", params: params)
    }
}
