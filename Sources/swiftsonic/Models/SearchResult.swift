// SearchResult.swift — SwiftSonic
//
// Models for search2 and search3 endpoint results.
//
// SearchResult2 — folder-based organisation (search2).
// SearchResult3 — ID3-tagged organisation (search3, preferred).

import Foundation

// MARK: - SearchResult2 (folder-based)

/// Results returned by the `search2` endpoint.
///
/// Artist and album entries are represented as ``Song`` values with ``Song/isDir``
/// set to `true`, consistent with the folder-based browsing model.
///
/// > Important: Prefer ``SearchResult3`` (returned by
/// > ``SwiftSonicClient/search3(_:artistCount:artistOffset:albumCount:albumOffset:songCount:songOffset:musicFolderId:)``)
/// > unless you specifically need folder-structure browsing.
public struct SearchResult2: Decodable, Sendable {
    /// Matching artists (folder-based ``Song`` nodes with `isDir = true`).
    public let artist: [Song]?
    /// Matching albums (folder-based ``Song`` nodes with `isDir = true`).
    public let album: [Song]?
    /// Matching songs.
    public let song: [Song]?

    private enum CodingKeys: String, CodingKey {
        case artist, album, song
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = try c.decodeLossily([Song].self, forKey: .artist)
        album  = try c.decodeLossily([Song].self, forKey: .album)
        song   = try c.decodeLossily([Song].self, forKey: .song)
    }
}

// MARK: - SearchResult3

/// Results returned by the `search3` endpoint.
///
/// Each of the three arrays is optional — the server only includes a key when
/// it has at least one matching result.
public struct SearchResult3: Decodable, Sendable {
    /// Matching artists.
    public let artist: [ArtistID3]?
    /// Matching albums.
    public let album: [AlbumID3]?
    /// Matching songs.
    public let song: [Song]?

    private enum CodingKeys: String, CodingKey {
        case artist, album, song
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = try c.decodeLossily([ArtistID3].self, forKey: .artist)
        album  = try c.decodeLossily([AlbumID3].self, forKey: .album)
        song   = try c.decodeLossily([Song].self, forKey: .song)
    }
}
