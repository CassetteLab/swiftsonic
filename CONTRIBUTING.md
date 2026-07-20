# Contributing to SwiftSonic

Thanks for taking the time to contribute! This document covers everything you need to get started.

---

## Table of contents

- [Code of conduct](#code-of-conduct)
- [Reporting bugs](#reporting-bugs)
- [Suggesting features](#suggesting-features)
- [Development setup](#development-setup)
- [Making changes](#making-changes)
- [Coding conventions](#coding-conventions)
- [Adding an endpoint](#adding-an-endpoint)
- [Pull requests](#pull-requests)

---

## Code of conduct

Be kind and constructive. Harassment, dismissiveness, or personal attacks have no place here.

---

## Reporting bugs

Open a [GitHub issue](https://github.com/CassetteLab/swiftsonic/issues) with:

- A short, descriptive title
- The SwiftSonic version (`0.1.0`, `main`, etc.)
- A minimal reproduction — ideally a failing test or a short code snippet
- The actual vs. expected behaviour

---

## Suggesting features

Open a GitHub issue with the `enhancement` label. Describe the use case first, then the proposed API. If you have a concrete implementation in mind, feel free to sketch it out.

---

## Development setup

```bash
git clone https://github.com/CassetteLab/swiftsonic.git
cd swiftsonic
swift build
swift test
```

No external tools are required. The project has zero dependencies.

### Recommended environment

- Xcode 16+ or any editor with Swift LSP support (VS Code + SourceKit-LSP)
- Swift 6.0 toolchain (ships with Xcode 16)

---

## Making changes

1. Fork the repository and create a feature branch from `main`:
   ```bash
   git checkout -b feat/my-feature
   ```
2. Write your code and tests (see [Adding an endpoint](#adding-an-endpoint) for the standard pattern).
3. Run the full test suite locally:
   ```bash
   swift test
   ```
4. Commit with a conventional commit message (see below) and open a PR.

### Commit message format

```
<type>: <short description>

[optional body]
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `ci`, `chore`.

Examples:
```
feat: add getSimilarSongs2 endpoint
fix: correct date decoding for starred field
docs: add usage example for search3
```

---

## Coding conventions

- **Swift 6 strict concurrency** — all public types must conform to `Sendable`, zero actor-isolation warnings
- **No force unwraps** (`!`) in library code
- **No external dependencies** — only `Foundation` and `CryptoKit`
- **Formatting** — 4-space indentation, no trailing whitespace
- **Access control** — `public` for anything consumers need, `internal`/`private` for everything else
- **Tests** — every new endpoint needs at least a decode test and a params test (see below)

---

## Adding an endpoint

Follow the pattern used throughout the codebase:

### 1. Add the model (if new types are needed)

Create `Sources/SwiftSonic/Models/MyModel.swift`. Conform to `Decodable`, `Sendable`, and `Identifiable` (if the type has an `id`).

```swift
public struct MyModel: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
}
```

### 2. Add the payload type and endpoint method

In the relevant `SwiftSonicClient+Domain.swift` file (or create a new one):

```swift
private struct MyPayload: SubsonicPayload {
    static let payloadKey = "myResult"   // the JSON key inside "subsonic-response"
    let myResult: MyModel

    init(from decoder: any Decoder) throws {
        myResult = try decoder.singleValueContainer().decode(MyModel.self)
    }
}

public extension SwiftSonicClient {
    func myEndpoint(id: String) async throws -> MyModel {
        let envelope: SubsonicEnvelope<MyPayload> =
            try await performDecode(endpoint: "myEndpoint", params: ["id": id])
        guard let result = envelope.payload?.myResult else {
            throw SwiftSonicError.decoding(
                DecodingError.valueNotFound(MyModel.self,
                    DecodingError.Context(codingPath: [], debugDescription: "Missing payload")),
                rawData: Data()
            )
        }
        return result
    }
}
```

### 3. Add a JSON fixture

Create `Tests/SwiftSonicTests/Fixtures/myEndpoint.json` with a realistic sample response.

### 4. Write tests

Create or extend a test file. Every endpoint needs at minimum:

- A **decode test** — verifies the fixture decodes into the expected model values
- A **params test** — verifies the correct query parameters are sent

```swift
@Suite("myEndpoint")
struct MyEndpointTests {

    @Test("myEndpoint decodes result")
    func decodesResult() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "myEndpoint")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        let result = try await client.myEndpoint(id: "42")

        #expect(result.id == "42")
        #expect(result.name == "Expected Name")
    }

    @Test("myEndpoint sends id param")
    func sendsIdParam() async throws {
        let mock = MockHTTPTransport()
        mock.enqueue(fixture: "myEndpoint")

        let client = SwiftSonicClient(configuration: .test, transport: mock)
        _ = try await client.myEndpoint(id: "42")

        #expect(mock.queryItem(named: "id") == "42")
    }
}
```

### 5. Update the README

Add the endpoint to the coverage table in `README.md`.

---

## Pull requests

- Target the `main` branch
- One logical change per PR
- The CI must be green before merging
- Include a short description of what changed and why

For large or breaking changes, open an issue first to discuss the approach before investing time in an implementation.
