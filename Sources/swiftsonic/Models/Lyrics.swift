// Lyrics.swift — SwiftSonic
//
// Data models for song lyrics.
//
// Lyrics      — plain-text lyrics returned by the legacy getLyrics endpoint.
// LyricsList  — structured (optionally time-synced) lyrics returned by the
//               OpenSubsonic getLyricsBySongId endpoint (songLyrics extension).

import Foundation

// MARK: - Lyrics (legacy)

/// Song lyrics returned by ``SwiftSonicClient/getLyrics(artist:title:)``.
///
/// If the server cannot find lyrics for the requested song, the method returns `nil`
/// rather than a `Lyrics` value with an empty ``value``.
public struct Lyrics: Decodable, Sendable {

    /// The artist name associated with these lyrics.
    public let artist: String?

    /// The song title associated with these lyrics.
    public let title: String?

    /// The full lyrics text.
    ///
    /// This is always non-empty when returned from
    /// ``SwiftSonicClient/getLyrics(artist:title:)`` — the method returns `nil`
    /// when the server responds with an absent or empty value.
    public let value: String?
}

// MARK: - LyricsList (OpenSubsonic songLyrics extension)

/// A collection of structured lyrics sets for a single song.
///
/// Returned by ``SwiftSonicClient/getLyricsBySongId(id:)``.
/// May contain multiple entries for different languages or lyric types.
///
/// To check server support before calling:
/// ```swift
/// let caps = try await client.loadCapabilities()
/// if caps.supports(.songLyrics) {
///     let list = try await client.getLyricsBySongId(id: song.id)
/// }
/// ```
public struct LyricsList: Decodable, Sendable, Equatable, Hashable {

    /// All structured lyrics sets for this song.
    ///
    /// May be empty if the server has no lyrics for the track.
    public let structuredLyrics: [StructuredLyrics]

    public init(structuredLyrics: [StructuredLyrics] = []) {
        self.structuredLyrics = structuredLyrics
    }

    private enum CodingKeys: String, CodingKey {
        case structuredLyrics
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        structuredLyrics = try container.decodeIfPresent([StructuredLyrics].self, forKey: .structuredLyrics) ?? []
    }
}

// MARK: - StructuredLyrics

/// A single set of lyrics for a song, with optional per-line timing.
///
/// `synced` indicates whether ``line`` entries carry ``Line/start`` timestamps.
/// For synced lyrics, lines are ordered by their `start` time;
/// for unsynced lyrics, lines appear in reading order.
public struct StructuredLyrics: Decodable, Sendable, Equatable, Hashable {

    /// The language of the lyrics (ideally ISO 639).
    ///
    /// `nil` when the server omits the field.
    /// The values `"und"` and `"xxx"` both indicate an unspecified language —
    /// SwiftSonic preserves the raw value; interpretation is left to the caller.
    public let lang: String?

    /// `true` if lines carry timing information (``Line/start`` is present).
    public let synced: Bool

    /// The lyric lines, in order.
    public let line: [Line]

    /// Artist name for display purposes.
    public let displayArtist: String?

    /// Song title for display purposes.
    public let displayTitle: String?

    /// Offset in milliseconds to apply to all line start times.
    ///
    /// Positive values shift lyrics earlier; negative values shift them later.
    /// Defaults to `0` when absent from the server response.
    public let offset: Int

    public init(
        lang: String? = nil,
        synced: Bool,
        line: [Line] = [],
        displayArtist: String? = nil,
        displayTitle: String? = nil,
        offset: Int = 0
    ) {
        self.lang          = lang
        self.synced        = synced
        self.line          = line
        self.displayArtist = displayArtist
        self.displayTitle  = displayTitle
        self.offset        = offset
    }

    private enum CodingKeys: String, CodingKey {
        case lang, synced, line, displayArtist, displayTitle, offset
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lang          = try container.decodeIfPresent(String.self,   forKey: .lang)
        synced        = try container.decodeIfPresent(Bool.self,     forKey: .synced)  ?? false
        line          = try container.decodeIfPresent([Line].self,   forKey: .line)    ?? []
        displayArtist = try container.decodeIfPresent(String.self,   forKey: .displayArtist)
        displayTitle  = try container.decodeIfPresent(String.self,   forKey: .displayTitle)
        offset        = try container.decodeIfPresent(Int.self,      forKey: .offset)  ?? 0
    }
}

// MARK: - Line

/// A single lyric line, with optional synchronisation timestamp.
public struct Line: Decodable, Sendable, Equatable, Hashable {

    /// The text of the lyric line.
    public let value: String

    /// Start time of this line in milliseconds from the beginning of the track.
    ///
    /// Present only for synced lyrics (``StructuredLyrics/synced`` is `true`).
    /// Absent for unsynced lyrics — do not treat absence as `0`.
    public let start: Int?

    public init(value: String, start: Int? = nil) {
        self.value = value
        self.start = start
    }
}

/// Convenience alias — prefer `LyricsLine` at call sites for clarity.
public typealias LyricsLine = Line
