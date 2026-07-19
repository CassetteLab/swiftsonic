# Security Policy

## Supported versions

| Version | Supported          |
|---------|--------------------|
| 0.5.x   | ✅ Current          |
| 0.4.x   | ✅ Security patches |
| 0.3.x   | ❌ End of life      |
| ≤ 0.2.x | ❌ End of life      |

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Instead, report them privately via [GitHub's security advisory system](https://github.com/CassetteLab/swiftsonic/security/advisories/new).

You will receive an acknowledgement within **72 hours**. If the vulnerability is confirmed, a patch and coordinated disclosure will follow within a reasonable timeframe depending on severity.

## Security model

SwiftSonic uses the Subsonic token-authentication protocol: a random salt is generated per request, and the authentication token is computed as `MD5(password + salt)`. The plaintext password is **never transmitted over the network** — it is used only locally, in memory, for the token computation.

For OpenSubsonic servers, API key authentication is also supported. The API key is equally never logged or included in any public-facing data structure.

### Protections built into the library

| Protection | Where |
|------------|-------|
| Per-request random salt (16 chars, CSPRNG) | `CryptoHelpers.randomSalt()` |
| Password / API key redacted in all string representations | `AuthMethod`, `ServerConfiguration` |
| Authentication credentials never stored in error types | `SwiftSonicError`, `SubsonicAPIError` |
| HTTP plain-text warning at client init | `SwiftSonicClient.init` |
| Cross-domain redirect blocking | `URLSessionTransport.RedirectGuard` |
| Per-request timeout floor of 1 second | `ServerConfiguration.init` |
| `LocalizedError` descriptions contain no credentials | `SwiftSonicError` |

### Known credential exposure surfaces (by design)

- The `SubsonicAPIError.message` field is returned verbatim from the server. SwiftSonic cannot control its content.
- Custom `HTTPTransport` implementations can access the raw `URLRequest`, which contains authentication query parameters. See the `HTTPTransport` documentation for safe logging guidance.

## Scope

SwiftSonic is a client library that communicates with Subsonic/OpenSubsonic servers over HTTPS. Relevant security areas include:

- Credential handling (username / password / token / API key)
- URL construction and parameter injection
- Response parsing (malformed or malicious server responses)
- Transport-layer security (TLS, redirect behaviour, timeouts)

Out of scope: vulnerabilities in the Subsonic server software itself, or in third-party Subsonic server implementations.

## Fixed vulnerabilities

### [GHSA] v0.4.1 — 2026-04-23

**[A1] Credential leak via error `requestURL`** (HIGH)

`SwiftSonicError.httpError`, `.rateLimited`, and `SubsonicAPIError` stored the full request URL (including `u`, `t`, `s`, or `apiKey` query parameters) as a public field. Fixed by replacing `requestURL: URL` with `endpoint: String` and `serverHost: String?`.

**[A2] Credential leak via default string representation** (HIGH)

`AuthMethod` and `ServerConfiguration` lacked `CustomStringConvertible` conformances. Swift's default enum description prints all associated values, so `print(config.auth)` or the Xcode debugger would reveal the plaintext password or API key. Fixed by adding redacting string representations.

### v0.5.0 — 2026-04-23

**[A3]** Salt length increased from 10 to 16 characters; `SystemRandomNumberGenerator` now used explicitly (MEDIUM)

**[D3]** Cross-domain HTTP redirects are now blocked by `URLSessionTransport`; a redirect to a different host would have silently forwarded authentication credentials (MEDIUM)

**[D2]** `SwiftSonicClient` now emits an `os.Logger` warning (subsystem `com.swiftsonic`, category `security`) when the server URL uses plain HTTP (MEDIUM)

**[D4]** `ServerConfiguration.requestTimeout` is clamped to a minimum of 1 second to prevent silent request failures (LOW)

**[C1]** `SwiftSonicError` now conforms to `LocalizedError` with credential-safe descriptions (LOW)
