# SwiftSonic

[![CI](https://github.com/MathieuDubart/swiftsonic/actions/workflows/ci.yml/badge.svg)](https://github.com/MathieuDubart/swiftsonic/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-4BC51D)](https://swift.org/package-manager)
[![GitHub release](https://img.shields.io/github/v/release/MathieuDubart/swiftsonic?color=4BC51D)](https://github.com/MathieuDubart/swiftsonic/releases)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2016%20%7C%20macOS%2013%20%7C%20tvOS%2016%20%7C%20watchOS%209%20%7C%20visionOS%201-lightgrey)](https://developer.apple.com/swift/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A modern, Swift-native client for the [Subsonic](http://www.subsonic.org/pages/api.jsp) and [OpenSubsonic](https://opensubsonic.netlify.app/) APIs.

```swift
import SwiftSonic

let client = SwiftSonicClient(
    serverURL: URL(string: "https://music.example.com")!,
    username: "alice",
    password: "secret"
)
let artists = try await client.getArtists()
```

That's it. No setup, no singleton, no global state.

---

## Why SwiftSonic?

Every existing Swift Subsonic client is either abandoned, built on Alamofire, or missing OpenSubsonic support entirely. SwiftSonic fills that gap:

| | SwiftSonic | SubsonicKit | SubSonicAPI |
|---|---|---|---|
| Swift 6 strict concurrency | ✅ | ❌ | ❌ |
| OpenSubsonic extensions | ✅ | ❌ | ❌ |
| Zero dependencies | ✅ | ❌ (Alamofire) | ❌ |
| async/await native | ✅ | ✅ | ❌ |
| Typed error codes | ✅ | ❌ | ❌ |
| Injectable transport | ✅ | ❌ | ❌ |
| Actively maintained | ✅ | ⚠️ | ❌ |
| Automatic retry | ✅ | ❌ | ❌ |
| Observability hook | ✅ | ❌ | ❌ |

---

## Requirements

- iOS 16+ / macOS 13+ / tvOS 16+ / watchOS 9+ / visionOS 1+
- Swift 5.9+
- Xcode 15+

---

## Installation

### Swift Package Manager

Add SwiftSonic to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/MathieuDubart/swiftsonic.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "SwiftSonic", package: "swiftsonic")]
    )
]
```

Or in Xcode: **File → Add Package Dependencies** → paste the repo URL.

---

## Usage

### Basic setup

```swift
import SwiftSonic

// Standard token auth (most servers)
let client = SwiftSonicClient(
    serverURL: URL(string: "https://music.example.com")!,
    username: "alice",
    password: "secret"
)

// API key auth (OpenSubsonic servers)
let client = SwiftSonicClient(
    configuration: ServerConfiguration(
        serverURL: URL(string: "https://music.example.com")!,
        auth: .apiKey("my-api-key")
    )
)
```

### Checking server capabilities

```swift
// Lazy — fetches once, caches for all subsequent calls
let caps = try await client.loadCapabilities()
print("Server: \(caps.serverType ?? "unknown") \(caps.serverVersion ?? "")")
print("OpenSubsonic: \(caps.isOpenSubsonic)")

// String overload
if caps.supports("songLyrics") { … }

// Typed KnownExtension overload (compile-time safe)
if caps.supports(.songLyrics) { … }
if caps.supports(.apiKeyAuthentication) { … }

// Force a fresh fetch (e.g. after re-auth)
let refreshed = try await client.refreshCapabilities()
```

### Browsing

```swift
// All artists, grouped by index letter
let indexes = try await client.getArtists()
for index in indexes {
    for artist in index.artist {
        print(artist.name)
    }
}

// Music folders
let folders = try await client.getMusicFolders()
```

### Search

```swift
let results = try await client.search3("bohemian", songCount: 10)
print(results.song?.first?.title)   // "Bohemian Rhapsody"
print(results.artist?.first?.name)  // "Queen"
```

### Playlists

```swift
// List all playlists
let playlists = try await client.getPlaylists()

// Fetch a specific playlist with its tracks
let playlist = try await client.getPlaylist(id: "42")
for song in playlist.entry ?? [] {
    print("\(song.title) — \(song.artist ?? "")")
}

// Create
let newPlaylist = try await client.createPlaylist(name: "Road Trip", songIds: ["101", "202"])
try await client.updatePlaylist(id: newPlaylist.id, isPublic: true, songIdsToAdd: ["303"])
try await client.deletePlaylist(id: newPlaylist.id)

// Replace mode — reorder or overwrite an existing playlist's tracks atomically
try await client.createPlaylist(playlistId: "42", songIds: ["303", "101", "202"])
```

### Media URLs

Media URL methods are `nonisolated` — no `await` needed:

```swift
// Stream a song in AVPlayer
if let url = client.streamURL(id: "101", maxBitRate: 320, format: "mp3") {
    let player = AVPlayer(url: url)
    player.play()
}

// Cover art for AsyncImage
if let url = client.coverArtURL(id: "al-10", size: 300) {
    AsyncImage(url: url)
}

// Download
let downloadLink = client.downloadURL(id: "101")
```

### Annotations

```swift
// Star songs and albums (multiple IDs)
try await client.star(songIds: ["101", "201"], albumIds: ["10"])
try await client.unstar(songIds: ["101"])

// Single-item convenience overloads
try await client.star(songId: "101")
try await client.star(albumId: "10")
try await client.unstar(artistId: "5")

// Rate (1–5, or 0 to remove)
try await client.setRating(id: "101", rating: 5)

// Scrobble (now playing or completed play)
try await client.scrobble(id: "101", submission: false) // now playing
try await client.scrobble(id: "101")                    // completed
```

### Error handling

```swift
do {
    try await client.ping()
} catch SwiftSonicError.api(let error) {
    switch error.code {
    case .wrongCredentials:
        // prompt re-auth
    case .notFound:
        // resource missing
    default:
        print("Server error \(error.code.rawValue): \(error.message)")
    }
} catch SwiftSonicError.network(let urlError) {
    // no connectivity
} catch SwiftSonicError.httpError(let statusCode, _) {
    // non-2xx response
}
```

SwiftSonicError also exposes convenience helpers for common checks:

| Helper | Returns `true` when… |
|---|---|
| `isTransient` | error is safe to retry (timeouts, 5xx, rate limits) |
| `isAuthenticationFailure` | auth failed (wrong credentials, 401, 403) |
| `isDNSFailure` | DNS resolution failed (`.cannotFindHost`, `.dnsLookupFailed`) |
| `isCertificateError` | TLS certificate validation failed (server or client cert) |
| `suggestedRetryDelay` | *(non-nil)* `Retry-After` seconds from a rate-limit response |

### Retry and resilience

SwiftSonicClient automatically retries transient failures (network errors, HTTP 5xx, HTTP 429) with exponential back-off. The default policy makes up to 3 attempts:

```swift
// Default: 3 attempts, ~0.5s → ~1s → ~2s (±20% jitter)
let client = SwiftSonicClient(configuration: config)

// Custom policy
let client = SwiftSonicClient(
    configuration: config,
    retryPolicy: RetryPolicy(maxAttempts: 5, baseDelay: 1.0)
)

// Disable retries entirely
let client = SwiftSonicClient(
    configuration: config,
    retryPolicy: .none
)
```

Non-transient errors (authentication failures, 4xx, decoding errors) are **never** retried. A 429 response honours the `Retry-After` header when present.

### Observability

#### Logging

Pass `logSubsystem:` to enable `os.Logger` output under the `SwiftSonicClient` category. The client logs every attempt, retry, success, and failure — visible in Console.app and Instruments.

```swift
let client = SwiftSonicClient(
    configuration: config,
    logSubsystem: "com.example.MyApp"   // silent by default
)
```

#### Metrics hook

Implement `SwiftSonicMetricsCollector` to integrate with your observability backend (Datadog, Sentry, custom analytics):

```swift
final class AppMetrics: SwiftSonicMetricsCollector, @unchecked Sendable {
    func record(_ event: SwiftSonicRequestEvent) {
        switch event {
        case .succeeded(let endpoint, _, let duration):
            Analytics.track("api_request", ["endpoint": endpoint, "duration": duration])
        case .failed(let endpoint, _, let error, _):
            Crashlytics.recordError(error, userInfo: ["endpoint": endpoint])
        case .retryScheduled(let endpoint, let attempt, let delay):
            print("[\(endpoint)] retry \(attempt + 1) in \(String(format: "%.2f", delay))s")
        default:
            break
        }
    }
}

let client = SwiftSonicClient(
    configuration: config,
    metricsCollector: AppMetrics()
)
```

### Custom transport (logging, cert pinning, proxies)

```swift
struct LoggingTransport: HTTPTransport {
    let underlying: any HTTPTransport = URLSessionTransport()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        print("→ \(request.url!)")
        let result = try await underlying.data(for: request)
        print("← \(result.1.statusCode)")
        return result
    }
}

let client = SwiftSonicClient(
    configuration: config,
    transport: LoggingTransport()
)
```

---

## Endpoint coverage

### System
| Endpoint | Swift API |
|---|---|
| `ping` | `ping()` |
| `getLicense` | `getLicense()` |
| `getOpenSubsonicExtensions` | `getOpenSubsonicExtensions()` / `fetchCapabilities()` / `loadCapabilities()` / `refreshCapabilities()` |

### Browsing (ID3)
| Endpoint | Swift API |
|---|---|
| `getMusicFolders` | `getMusicFolders()` |
| `getArtists` | `getArtists(musicFolderId:)` |
| `getArtist` | `getArtist(id:)` |
| `getAlbum` | `getAlbum(id:)` |
| `getSong` | `getSong(id:)` |
| `getGenres` | `getGenres()` |
| `getIndexes` | `getIndexes(musicFolderId:ifModifiedSince:)` |
| `getMusicDirectory` | `getMusicDirectory(id:)` |
| `getArtistInfo2` | `getArtistInfo2(id:count:includeNotPresent:)` |
| `getAlbumInfo2` | `getAlbumInfo2(id:)` |

### Browsing (folder-based)
| Endpoint | Swift API |
|---|---|
| `getArtistInfo` | `getArtistInfo(id:count:includeNotPresent:)` |
| `getAlbumInfo` | `getAlbumInfo(id:)` |

### Lists (ID3)
| Endpoint | Swift API |
|---|---|
| `getAlbumList2` | `getAlbumList2(type:size:offset:…)` |
| `getRandomSongs` | `getRandomSongs(size:genre:fromYear:toYear:musicFolderId:)` |
| `getSongsByGenre` | `getSongsByGenre(_:count:offset:musicFolderId:)` |
| `getStarred2` | `getStarred2(musicFolderId:)` |

### Lists (folder-based)
| Endpoint | Swift API | Note |
|---|---|---|
| `getAlbumList` | `getAlbumList(type:size:offset:…)` | Prefer `getAlbumList2` for ID3 browsing |
| `getStarred` | `getStarred(musicFolderId:)` | Prefer `getStarred2` for ID3 browsing |

### Search
| Endpoint | Swift API | Note |
|---|---|---|
| `search3` | `search3(_:artistCount:albumCount:songCount:musicFolderId:)` | |
| `search2` | `search2(_:artistCount:albumCount:songCount:musicFolderId:)` | Prefer `search3` for ID3 browsing |

### Discovery
| Endpoint | Swift API |
|---|---|
| `getSimilarSongs` | `getSimilarSongs(id:count:)` |
| `getSimilarSongs2` | `getSimilarSongs2(id:count:)` |
| `getTopSongs` | `getTopSongs(artist:count:)` |

### Playlists
| Endpoint | Swift API |
|---|---|
| `getPlaylists` | `getPlaylists(username:)` |
| `getPlaylist` | `getPlaylist(id:)` |
| `createPlaylist` | `createPlaylist(name:playlistId:songIds:)` |
| `updatePlaylist` | `updatePlaylist(id:name:comment:isPublic:songIdsToAdd:songIndexesToRemove:)` |
| `deletePlaylist` | `deletePlaylist(id:)` |

### Media URLs (nonisolated, no `await` needed)
| Endpoint | Swift API |
|---|---|
| `stream` | `streamURL(id:maxBitRate:format:timeOffset:size:estimateContentLength:converted:)` |
| `download` | `downloadURL(id:)` |
| `getCoverArt` | `coverArtURL(id:size:)` |
| `hls` | `hlsURL(id:bitRate:audioTrack:)` |
| `getAvatar` | `avatarURL(username:)` |

### Annotations
| Endpoint | Swift API |
|---|---|
| `star` | `star(songIds:albumIds:artistIds:)`, `star(songId:)`, `star(albumId:)`, `star(artistId:)` |
| `unstar` | `unstar(songIds:albumIds:artistIds:)`, `unstar(songId:)`, `unstar(albumId:)`, `unstar(artistId:)` |
| `setRating` | `setRating(id:rating:)` |
| `scrobble` | `scrobble(id:time:submission:)` |

### Now Playing
| Endpoint | Swift API |
|---|---|
| `getNowPlaying` | `getNowPlaying()` |

### Chat
| Endpoint | Swift API |
|---|---|
| `getChatMessages` | `getChatMessages(since:)` |
| `addChatMessage` | `addChatMessage(_:)` |

### Lyrics
| Endpoint | Swift API | Notes |
|---|---|---|
| `getLyrics` | `getLyrics(artist:title:)` | Legacy Subsonic |
| `getLyricsBySongId` | `getLyricsBySongId(id:)` | OpenSubsonic `songLyrics` extension |

```swift
// Legacy plain-text lyrics
if let lyrics = try await client.getLyrics(artist: "Nine Inch Nails", title: "Hurt") {
    print(lyrics.value ?? "")
}

// OpenSubsonic structured lyrics (synced + multi-language)
let list = try await client.getLyricsBySongId(id: song.id)
for set in list.structuredLyrics {
    print("\(set.lang) synced=\(set.synced)")
    for line in set.line {
        if let ms = line.start {
            print("[\(ms)ms] \(line.value)")
        } else {
            print(line.value)
        }
    }
}
```

### User management
| Endpoint | Swift API |
|---|---|
| `getUser` | `getUser(username:)` |
| `getUsers` | `getUsers()` |
| `createUser` | `createUser(_:)` |
| `updateUser` | `updateUser(_:)` |
| `deleteUser` | `deleteUser(username:)` |
| `changePassword` | `changePassword(username:newPassword:)` |

### Bookmarks
| Endpoint | Swift API |
|---|---|
| `getBookmarks` | `getBookmarks()` |
| `createBookmark` | `createBookmark(songId:position:comment:)` |
| `deleteBookmark` | `deleteBookmark(songId:)` |

### Play Queue
| Endpoint | Swift API |
|---|---|
| `getPlayQueue` | `getPlayQueue()` |
| `savePlayQueue` | `savePlayQueue(ids:current:position:)` |

### Shares
| Endpoint | Swift API |
|---|---|
| `getShares` | `getShares()` |
| `createShare` | `createShare(ids:description:expires:)` |
| `updateShare` | `updateShare(id:description:expires:)` |
| `deleteShare` | `deleteShare(id:)` |

### Podcasts
| Endpoint | Swift API |
|---|---|
| `getPodcasts` | `getPodcasts(id:includeEpisodes:)` |
| `getNewestPodcasts` | `getNewestPodcasts(count:)` |
| `refreshPodcasts` | `refreshPodcasts()` |
| `createPodcastChannel` | `createPodcastChannel(url:)` |
| `deletePodcastChannel` | `deletePodcastChannel(id:)` |
| `downloadPodcastEpisode` | `downloadPodcastEpisode(id:)` |
| `deletePodcastEpisode` | `deletePodcastEpisode(id:)` |

### Jukebox
| Endpoint | Swift API |
|---|---|
| `jukeboxControl` | `jukeboxGet()`, `jukeboxStatus()`, `jukeboxStart()`, `jukeboxStop()`, `jukeboxSkip(index:offset:)`, `jukeboxAdd(ids:)`, `jukeboxSet(ids:)`, `jukeboxRemove(index:)`, `jukeboxClear()`, `jukeboxShuffle()`, `jukeboxSetGain(_:)` |

### Internet Radio
| Endpoint | Swift API |
|---|---|
| `getInternetRadioStations` | `getInternetRadioStations()` |
| `createInternetRadioStation` | `createInternetRadioStation(streamURL:name:homepageURL:)` |
| `updateInternetRadioStation` | `updateInternetRadioStation(id:streamURL:name:homepageURL:)` |
| `deleteInternetRadioStation` | `deleteInternetRadioStation(id:)` |

### Scan
| Endpoint | Swift API |
|---|---|
| `getScanStatus` | `getScanStatus()` |
| `startScan` | `startScan()` |

---

## Design principles

- **Thread-safe by construction** — `SwiftSonicClient` is a Swift actor
- **Zero dependencies** — only `Foundation` and `CryptoKit`
- **Sendable everywhere** — all public types conform to `Sendable`, zero warnings in strict concurrency
- **Injectable transport** — swap out `URLSession` for testing, proxying, or cert pinning
- **No UI coupling** — `Data` and `URL` only, never `UIImage` or `SwiftUI.Image`
- **Resilient by default** — 3-attempt exponential back-off retry, configurable via `RetryPolicy`
- **Observable** — `logSubsystem:` for `os.Logger` output; `metricsCollector:` for custom metrics

---

## Documentation

Design decisions, the internal security audit, and cross-cutting technical notes live
in the **[CassetteLab knowledge vault](https://github.com/CassetteLab/obsidian)** — an
Obsidian vault versioned with Git, shared across the whole ecosystem.

Anything that explains **why** a choice was made lives there rather than in this repo.
`README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, and `LICENSE` stay here.

> The vault is private to the organisation — open an issue if you need access.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

MIT — see [LICENSE](LICENSE).
