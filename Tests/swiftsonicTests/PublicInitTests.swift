// PublicInitTests.swift — SwiftSonicTests
//
// Verifies that core models and shared types expose a public initializer
// usable from outside the module (the test target acts as an external consumer).

import Testing
import Foundation
@testable import SwiftSonic

// MARK: - Song

@Suite("Song publicInit")
struct SongPublicInitTests {

    @Test("constructs Song with required fields and nil defaults")
    func constructsWithDefaults() {
        let s = Song(id: "101", title: "Bohemian Rhapsody")
        #expect(s.id == "101")
        #expect(s.title == "Bohemian Rhapsody")
        #expect(s.artist == nil)
        #expect(s.album == nil)
        #expect(s.duration == nil)
        #expect(s.starred == nil)
        #expect(s.replayGain == nil)
        #expect(s.contributors == nil)
    }

    @Test("constructs Song with common fields")
    func constructsWithCommonFields() {
        let now = Date()
        let s = Song(
            id: "102", title: "Stairway to Heaven",
            album: "Led Zeppelin IV", artist: "Led Zeppelin",
            track: 8, year: 1971,
            duration: 482, bitRate: 320,
            starred: now, albumId: "20", artistId: "5"
        )
        #expect(s.album == "Led Zeppelin IV")
        #expect(s.artist == "Led Zeppelin")
        #expect(s.track == 8)
        #expect(s.year == 1971)
        #expect(s.duration == 482)
        #expect(s.starred == now)
        #expect(s.albumId == "20")
        #expect(s.artistId == "5")
    }
}

// MARK: - AlbumID3

@Suite("AlbumID3 publicInit")
struct AlbumID3PublicInitTests {

    @Test("constructs AlbumID3 with required fields and nil defaults")
    func constructsWithDefaults() {
        let a = AlbumID3(id: "10", name: "A Night at the Opera", songCount: 12, duration: 2640)
        #expect(a.id == "10")
        #expect(a.name == "A Night at the Opera")
        #expect(a.songCount == 12)
        #expect(a.duration == 2640)
        #expect(a.artist == nil)
        #expect(a.artistId == nil)
        #expect(a.coverArt == nil)
        #expect(a.starred == nil)
        #expect(a.year == nil)
        #expect(a.song == nil)
    }

    @Test("constructs AlbumID3 with all optional fields")
    func constructsWithAllFields() {
        let now = Date()
        let a = AlbumID3(
            id: "11", name: "OK Computer", songCount: 12, duration: 3120,
            artist: "Radiohead", artistId: "2",
            coverArt: "art-11", playCount: 99,
            created: now, starred: now,
            year: 1997, genre: "Alternative",
            userRating: 5, isCompilation: false
        )
        #expect(a.artist == "Radiohead")
        #expect(a.artistId == "2")
        #expect(a.year == 1997)
        #expect(a.genre == "Alternative")
        #expect(a.userRating == 5)
        #expect(a.isCompilation == false)
    }
}

// MARK: - ArtistIndex

@Suite("ArtistIndex publicInit")
struct ArtistIndexPublicInitTests {

    @Test("constructs ArtistIndex with default empty artist array")
    func constructsWithDefaults() {
        let idx = ArtistIndex(name: "Q")
        #expect(idx.name == "Q")
        #expect(idx.artist.isEmpty)
    }

    @Test("constructs ArtistIndex with artists")
    func constructsWithArtists() {
        let a = ArtistID3(id: "1", name: "Queen")
        let idx = ArtistIndex(name: "Q", artist: [a])
        #expect(idx.artist.count == 1)
        #expect(idx.artist[0].id == "1")
    }
}

// MARK: - ArtistID3

@Suite("ArtistID3 publicInit")
struct ArtistID3PublicInitTests {

    @Test("constructs ArtistID3 with required fields and nil defaults")
    func constructsWithDefaults() {
        let a = ArtistID3(id: "1", name: "Queen")
        #expect(a.id == "1")
        #expect(a.name == "Queen")
        #expect(a.albumCount == nil)
        #expect(a.coverArt == nil)
        #expect(a.starred == nil)
        #expect(a.userRating == nil)
        #expect(a.musicBrainzId == nil)
        #expect(a.sortName == nil)
        #expect(a.roles == nil)
        #expect(a.album == nil)
    }

    @Test("constructs ArtistID3 with all fields")
    func constructsWithAllFields() {
        let now = Date()
        let a = ArtistID3(
            id: "2", name: "Radiohead",
            albumCount: 10, coverArt: "art-2",
            starred: now, userRating: 5,
            musicBrainzId: "mb-2", sortName: "Radiohead",
            roles: ["composer"], album: []
        )
        #expect(a.albumCount == 10)
        #expect(a.coverArt == "art-2")
        #expect(a.starred == now)
        #expect(a.userRating == 5)
        #expect(a.musicBrainzId == "mb-2")
        #expect(a.roles == ["composer"])
        #expect(a.album?.isEmpty == true)
    }
}

// MARK: - SharedModels

@Suite("SharedModels publicInit")
struct SharedModelsPublicInitTests {

    @Test("ItemGenre constructs with name")
    func itemGenre() {
        let g = ItemGenre(name: "Jazz")
        #expect(g.name == "Jazz")
    }

    @Test("ReplayGain constructs with all optional fields nil by default")
    func replayGainDefaults() {
        let rg = ReplayGain()
        #expect(rg.trackGain == nil)
        #expect(rg.albumGain == nil)
        #expect(rg.trackPeak == nil)
        #expect(rg.albumPeak == nil)
        #expect(rg.baseGain == nil)
        #expect(rg.fallbackGain == nil)
    }

    @Test("ReplayGain constructs with all fields")
    func replayGainAllFields() {
        let rg = ReplayGain(trackGain: -3.5, albumGain: -2.0, trackPeak: 0.98,
                            albumPeak: 0.95, baseGain: 0.0, fallbackGain: -2.5)
        #expect(rg.trackGain == -3.5)
        #expect(rg.albumGain == -2.0)
        #expect(rg.trackPeak == 0.98)
        #expect(rg.fallbackGain == -2.5)
    }

    @Test("ItemDate constructs with partial date")
    func itemDate() {
        let d = ItemDate(year: 1997, month: 5)
        #expect(d.year == 1997)
        #expect(d.month == 5)
        #expect(d.day == nil)
    }

    @Test("DiscTitle constructs with disc and title")
    func discTitle() {
        let dt = DiscTitle(disc: 2, title: "Side B")
        #expect(dt.disc == 2)
        #expect(dt.title == "Side B")
    }

    @Test("RecordLabel constructs with name")
    func recordLabel() {
        let rl = RecordLabel(name: "XL Recordings")
        #expect(rl.name == "XL Recordings")
    }

    @Test("ContributorArtist constructs with required fields and nil defaults")
    func contributorArtistDefaults() {
        let ca = ContributorArtist(id: "a1", name: "Trent Reznor")
        #expect(ca.id == "a1")
        #expect(ca.name == "Trent Reznor")
        #expect(ca.musicBrainzId == nil)
        #expect(ca.sortName == nil)
    }

    @Test("Contributor constructs with role and artist")
    func contributor() {
        let artist = ContributorArtist(id: "a1", name: "Trent Reznor",
                                       musicBrainzId: "mb-1", sortName: "Reznor, Trent")
        let c = Contributor(role: "composer", subRole: "orchestrator", artist: artist)
        #expect(c.role == "composer")
        #expect(c.subRole == "orchestrator")
        #expect(c.artist.id == "a1")
        #expect(c.artist.sortName == "Reznor, Trent")
    }

    @Test("Contributor constructs with nil subRole by default")
    func contributorNilSubRole() {
        let artist = ContributorArtist(id: "a2", name: "Atticus Ross")
        let c = Contributor(role: "producer", artist: artist)
        #expect(c.subRole == nil)
    }
}

// MARK: - OpenSubsonicExtension

@Suite("OpenSubsonicExtension publicInit")
struct OpenSubsonicExtensionPublicInitTests {

    @Test("constructs with name and versions")
    func constructs() {
        let ext = OpenSubsonicExtension(name: "songLyrics", versions: [1, 2])
        #expect(ext.name == "songLyrics")
        #expect(ext.versions == [1, 2])
    }
}

// MARK: - LyricsList / StructuredLyrics / Line

@Suite("LyricsList publicInit")
struct LyricsListPublicInitTests {

    @Test("LyricsList constructs with empty default")
    func lyricsListDefaults() {
        let ll = LyricsList()
        #expect(ll.structuredLyrics.isEmpty)
    }

    @Test("StructuredLyrics constructs with required fields and defaults")
    func structuredLyricsDefaults() {
        let sl = StructuredLyrics(lang: "en", synced: false)
        #expect(sl.lang == "en")
        #expect(sl.synced == false)
        #expect(sl.line.isEmpty)
        #expect(sl.displayArtist == nil)
        #expect(sl.displayTitle == nil)
        #expect(sl.offset == 0)
    }

    @Test("StructuredLyrics constructs with all fields")
    func structuredLyricsAllFields() {
        let lines = [Line(value: "Hello", start: 0), Line(value: "World", start: 1000)]
        let sl = StructuredLyrics(
            lang: "fr", synced: true,
            line: lines,
            displayArtist: "Artist", displayTitle: "Title",
            offset: -200
        )
        #expect(sl.lang == "fr")
        #expect(sl.synced == true)
        #expect(sl.line.count == 2)
        #expect(sl.displayArtist == "Artist")
        #expect(sl.offset == -200)
    }

    @Test("Line constructs with value and nil start by default")
    func lineDefaults() {
        let l = Line(value: "Some lyric text")
        #expect(l.value == "Some lyric text")
        #expect(l.start == nil)
    }

    @Test("Line constructs with start time")
    func lineWithStart() {
        let l = Line(value: "Synced line", start: 4200)
        #expect(l.value == "Synced line")
        #expect(l.start == 4200)
    }
}

// MARK: - Song v0.7 new fields

@Suite("Song v0.7 new fields publicInit")
struct SongV07FieldsTests {

    @Test("Song accepts mediaType and displayComposer")
    func newFields() {
        let s = Song(
            id: "200", title: "Hurt",
            displayComposer: "Trent Reznor",
            mediaType: "song"
        )
        #expect(s.mediaType == "song")
        #expect(s.displayComposer == "Trent Reznor")
    }

    @Test("Song mediaType and displayComposer default to nil")
    func newFieldsDefaultNil() {
        let s = Song(id: "201", title: "Hurt")
        #expect(s.mediaType == nil)
        #expect(s.displayComposer == nil)
    }
}

// MARK: - AlbumID3 v0.7 new fields

@Suite("AlbumID3 v0.7 new fields publicInit")
struct AlbumID3V07FieldsTests {

    @Test("AlbumID3 accepts explicitStatus and version")
    func newFields() {
        let a = AlbumID3(
            id: "50", name: "The Fragile", songCount: 23, duration: 5400,
            explicitStatus: "explicit",
            version: "Deluxe Edition"
        )
        #expect(a.explicitStatus == "explicit")
        #expect(a.version == "Deluxe Edition")
    }

    @Test("AlbumID3 explicitStatus and version default to nil")
    func newFieldsDefaultNil() {
        let a = AlbumID3(id: "51", name: "OK Computer", songCount: 12, duration: 3120)
        #expect(a.explicitStatus == nil)
        #expect(a.version == nil)
    }
}
