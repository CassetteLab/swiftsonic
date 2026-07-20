# SwiftSonic v0.5.0 — Security Audit

**Audit date:** 2026-04-23  
**Scope:** Sources/ + Tests/ fixtures + transport layer (v0.4.0 codebase)  
**Auditor:** Claude Sonnet 4.6 (automated + manual review)  
**Status:** Pre-implementation, awaiting developer review

---

## Summary

| Risk    | Count | Items |
|---------|-------|-------|
| HIGH    | 2     | A1, B3 |
| MEDIUM  | 7     | A2, A3, B1, B2, D1, D2, D3 |
| LOW     | 6     | A4, B4, C1, C2, D4, F1 |

---

## Bloc A — Credentials

### A1 — `requestURL` dans les erreurs publiques contient les credentials [HIGH]

**Fichiers concernés :**
- `Core/SwiftSonicClient.swift:321,328,364`
- `Core/SwiftSonicError.swift:43,50,126`

**Problème :**  
`executeOnce` passe `request.url` (URL complète avec query params) aux cases d'erreur publiques :

```swift
// SwiftSonicClient.swift:321,328,364
requestURL: request.url ?? configuration.serverURL
```

Cette URL contient en clair : `?f=json&v=1.16.1&c=SwiftSonic&u=alice&t=<md5>&s=<salt>` ou `&apiKey=<key>`.

Ces URLs transitent dans :
- `SwiftSonicError.httpError(statusCode:requestURL:)` — public associated value
- `SwiftSonicError.rateLimited(retryAfter:requestURL:)` — public associated value
- `SubsonicAPIError.requestURL: URL` — public stored property
- `SwiftSonicRequestEvent.failed(endpoint:attempt:error:duration:)` — le `SwiftSonicError` complet passe au `metricsCollector`

**Risque réel :** Toute app qui passe ses erreurs à Crashlytics, Sentry, Datadog, `print`, `os_log`, etc. leak les credentials (token MD5 + salt, ou apiKey). Combiné salt+token = replay attack possible.

**Action corrective :**  
Remplacer `request.url` par une URL sanitisée (sans params d'auth) dans toutes les constructions d'erreur. Créer un helper `URL.removingAuthParams()` qui strip `u`, `t`, `s`, `apiKey` des query items avant de créer l'erreur. L'URL résultante reste utile pour le debug (on voit l'endpoint) sans leaker les secrets.

**Breaking change ?** Non — le type de `requestURL` reste `URL`, mais sa valeur change. Acceptable car la valeur précédente était incorrecte (fuite de secret).

---

### A2 — `AuthMethod.tokenAuth` : représentation string par défaut inclut le password [HIGH]

**Fichiers concernés :**
- `Core/ServerConfiguration.swift:28`
- `Core/SwiftSonicClient.swift:59` (`public let configuration: ServerConfiguration`)

**Problème :**  
`AuthMethod` est un `public enum` sans `CustomStringConvertible`. Le comportement par défaut de Swift pour les enums imprime les associated values :

```
tokenAuth(username: "alice", password: "s3cr3t!", reusesSalt: false)
```

Si un dev fait `print(client.configuration)`, `String(describing: config.auth)`, ou si le debugger Xcode affiche `configuration` dans la zone Variables, le password plaintext apparaît.

De plus, `SwiftSonicClient.configuration` est une propriété `public let` — un appelant peut accéder directement à `client.configuration.auth` et obtenir le password.

**Action corrective :**
1. Ajouter `CustomStringConvertible` + `CustomDebugStringConvertible` sur `AuthMethod` et `ServerConfiguration` qui masquent les secrets :
   - `.tokenAuth` → `"tokenAuth(username: \"alice\", password: \"***\")"`
   - `.apiKey` → `"apiKey(\"***\")"`
2. Ne pas conformer ces types à `Codable` (voir A4).

**Breaking change ?** Non — les conformances sont ajoutées, pas modifiées.

---

### A3 — Salt de longueur 10 et non-utilisation explicite de `SystemRandomNumberGenerator` [MEDIUM]

**Fichier :** `Internal/CryptoHelpers.swift:32-44`

**Problème (1) :** `Int.random(in:)` sans générateur explicite utilise `SystemRandomNumberGenerator` par défaut, ce qui est cryptographiquement sûr — mais implicite. Le commentaire le mentionne, mais le code ne le garantit pas à la compilation.

**Problème (2) :** Salt de 10 caractères parmi 62 → ~59,5 bits d'entropie. La spec Subsonic n'impose pas de longueur, mais les recommandations modernes suggèrent ≥ 128 bits (22 caractères du même alphabet).

**Action corrective :**
1. Passer explicitement `using: &SystemRandomNumberGenerator()` à `Int.random` pour rendre la dépendance cryptographique visible à la compilation.
2. Augmenter la longueur par défaut de `randomSalt` à 16 (99 bits) ou 24 (143 bits).

**Breaking change ?** Non — changement interne uniquement.

---

### A4 — Password stocké dans `AuthMethod.tokenAuth` en clair [MEDIUM]

**Fichier :** `Core/ServerConfiguration.swift:28`, `Internal/RequestBuilder.swift:67-73`

**Problème :**  
`AuthMethod.tokenAuth(username:password:reusesSalt:)` stocke le password en tant que `String` associé. Il est conservé aussi longtemps que `ServerConfiguration` est en vie (= durée de vie de `SwiftSonicClient`).

Alternatives :
- Si `reusesSalt: false` (défaut), le password est nécessaire à chaque requête pour calculer le token → on ne peut pas l'effacer.
- Si `reusesSalt: true`, le salt+token sont pré-calculés à l'init → le password pourrait être effacé après l'init (mais l'architecture actuelle le conserve).

**Action corrective recommandée :**
- Pour `reusesSalt: true` : `RequestBuilder.init` peut stocker `cachedToken` + `cachedSalt` plutôt que le password, et l'architecture pourrait exposer un `SecureCredentials` qui zero-remplit la string après calcul du token. C'est complexe (les Swift `String` ne supportent pas le zero-fill garanti), **différer à v0.6**.
- Pour `reusesSalt: false` : documenter explicitement que le password est nécessaire en mémoire pour chaque requête, et recommander aux consumers de stocker `ServerConfiguration` dans le Keychain plutôt qu'en mémoire partagée.

**Breaking change ?** Non pour la doc. Oui pour un éventuel `SecureCredentials` (v0.6).

---

## Bloc B — Logs

### B1 — Aucune fuite directe dans les logs [LOW — validé OK]

**Fichier :** `Core/SwiftSonicClient.swift:194,214,222,237,244`

Les 5 appels `logger.debug(...)` loggent uniquement :
- Nom d'endpoint (e.g. `"getArtists"`)
- Numéros d'attempt
- Durée en secondes
- Flag `openSubsonic`

Aucun credentials, aucune URL, aucune response body. **Pas de fuite directe.**

---

### B2 — Documentation `HTTPTransport` encourage le logging d'URLs complètes [MEDIUM]

**Fichier :** `Transport/HTTPTransport.swift:24`

```swift
/// print("→ \(request.url?.absoluteString ?? "")")
```

Cet exemple dans la DocC encourage les consommateurs de la lib à logger l'URL complète (avec credentials). Risque indirect mais réel.

**Action corrective :**  
Remplacer l'exemple par un snippet qui montre comment logger uniquement `scheme://host/path` sans query params, et ajouter un avertissement explicite.

---

### B3 — `metricsCollector` reçoit `SwiftSonicError` avec `requestURL` contenant les credentials [HIGH → dérivé de A1]

**Fichier :** `Core/SwiftSonicClient.swift:230`

```swift
metricsCollector?.record(.failed(endpoint: endpoint, attempt: attempt, error: sse, duration: duration))
```

Le `SwiftSonicError` passé contient une `requestURL` avec credentials (voir A1). Toute implémentation de `SwiftSonicMetricsCollector` qui inspecte `error.requestURL` ou sérialise l'erreur complète leak les credentials.

**Action corrective :** Corrigée automatiquement par A1 (sanitiser `requestURL` à la construction de l'erreur).

---

### B4 — Pas de `CustomStringConvertible` sur les types sensibles [MEDIUM → voir A2]

Les types `ServerConfiguration` et `AuthMethod` n'ont aucune conformance custom de description. Corrigé par A2.

---

## Bloc C — Erreurs

### C1 — `SwiftSonicError` : pas de `LocalizedError` ni de `description` explicite [LOW]

**Fichier :** `Core/SwiftSonicError.swift`

`SwiftSonicError` ne conforme pas `LocalizedError` ni `CustomStringConvertible`. La représentation par défaut de Swift inclut les associated values, donc pour `.httpError`, l'URL complète avec credentials apparaît dans toute conversion string de l'erreur.

**Action corrective :** Ajouter `var localizedDescription: String` (ou conformance `LocalizedError`) qui :
- Pour `.httpError(statusCode:requestURL:)` → `"HTTP \(statusCode) — \(requestURL.sanitized)"` (sanitized = sans auth params)
- Pour `.rateLimited(retryAfter:requestURL:)` → `"Rate limited — \(requestURL.sanitized)"`
- Pour `.api(let e)` → `"API error \(e.code.rawValue): \(e.message)"`
- Pour `.network(let e)` → `"Network error: \(e.localizedDescription)"` (URLError ne contient pas de credentials car l'URL failing est la même URL du serveur, sans query params nécessairement — à vérifier)
- Pour `.decoding` → `"Decoding error"` sans inclure `rawData`

---

### C2 — `SubsonicAPIError.requestURL` : URL publique contenant les credentials [HIGH → dérivé de A1]

**Fichier :** `Core/SwiftSonicError.swift:126`

```swift
public let requestURL: URL
```

La valeur actuellement stockée contient les credentials dans les query params. Corrigé par A1.

---

### C3 — Fixtures : URL de `demo.navidrome.org` dans `getShares.json` [LOW]

**Fichier :** `Tests/swiftsonicTests/Fixtures/getShares.json`

```json
"url": "https://demo.navidrome.org/share/sh-abc123"
```

Il s'agit d'un serveur de démo public (pas de credentials réels). Risque minimal, mais par cohérence les fixtures devraient utiliser `https://music.example.com` systématiquement.

---

## Bloc D — Réseau

### D1 — Aucune validation TLS custom — comportement URLSession par défaut [MEDIUM]

**Fichier :** `Transport/URLSessionTransport.swift`

**Bon point :** La lib ne désactive pas la validation TLS. `URLSession.shared` et `URLSession(configuration:)` valident les certificats par défaut.

**Problème :** Rien n'empêche un consommateur de créer une `URLSessionTransport` avec une session dont le delegate bypass la validation TLS. La lib ne documente pas que cette pratique est dangereuse.

**Action corrective :**  
Ajouter dans la DocC de `URLSessionTransport` et de `HTTPTransport` : "Do not disable TLS certificate validation. SwiftSonic transmits authentication credentials on every request. For development against servers with self-signed certificates, see [link to Security Guide]."

---

### D2 — Pas de warning pour connexion HTTP plain-text [MEDIUM]

**Fichier :** `Internal/RequestBuilder.swift:54`

Si `serverURL.scheme == "http"`, les credentials (token+salt ou apiKey) sont transmis en clair. La lib ne fait aucun warning.

**Action corrective :**  
Dans `SwiftSonicClient.init`, après initialisation du logger : si `configuration.serverURL.scheme == "http"`, émettre un `logger.warning(...)`. Documenter ce comportement dans la DocC de `ServerConfiguration`.

Pas de refus bloquant (certains setups locaux légitimes n'ont pas TLS), mais warning visible en debug.

---

### D3 — Pas de protection contre les redirections cross-domain [MEDIUM]

**Fichier :** `Transport/URLSessionTransport.swift`

`URLSession` suit les redirections 3xx par défaut. Une redirection cross-domain enverrait les credentials auth params vers un hôte tiers. `URLSessionTransport` n'implémente pas de `URLSessionTaskDelegate` pour valider l'hôte de destination.

**Action corrective :**  
Implémenter `URLSessionTaskDelegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` dans un delegate interne qui :
- Si `newRequest.url?.host != originalHost` → appeler `completionHandler(nil)` et throw `.insecureRedirect`
- Sinon → suivre la redirection normalement

Ajouter `SwiftSonicError.insecureRedirect(from: URL, to: URL)` (breaking : nouvelle case, mais additive).

---

### D4 — Pas de plancher minimum sur `requestTimeout` [LOW]

**Fichier :** `Core/ServerConfiguration.swift:104`

Un timeout de 0 est accepté (`requestTimeout: 0`). En pratique, `URLRequest.timeoutInterval = 0` interprété par Foundation comme "infini" ou très court selon la plateforme — comportement non défini.

**Action corrective :**  
Dans `ServerConfiguration.init`, imposer `self.requestTimeout = max(1.0, requestTimeout)`. Documenter ce minimum.

---

## Bloc E — Dépendances & Build

### E1 — Zéro dépendance confirmé [OK]

Seuls `Foundation` et `CryptoKit` (Apple system frameworks) sont utilisés. Aucune dépendance SPM tierce. Validé via structure `Package.swift`.

### E2 — `Double.random` dans `RetryPolicy.delay(for:)` [LOW — OK pour cet usage]

**Fichier :** `Core/RetryPolicy.swift:109`

`Double.random(in: -1...1)` est utilisé pour le jitter de retry. Cet usage n'est PAS de la crypto — c'est du timing aléatoire pour éviter les thundering herds. L'utilisation de `Double.random` (PRNG standard) est correcte et appropriée ici.

---

## Bloc F — Documentation

### F1 — `SECURITY.md` outdated et incomplet [LOW]

**Fichier :** `SECURITY.md`

Problèmes :
- "Supported versions" liste v0.2.x comme current — devrait être v0.4.x (bientôt v0.5.x)
- Pas de threat model
- Pas de best practices pour les consommateurs (Keychain, etc.)
- Pas d'historique d'audit

**Action corrective :** Complet refactor dans l'étape F.

---

## Récapitulatif priorité d'implémentation

### Priorité 1 — Avant tout (risque de fuite réelle en prod avec v0.4.0)
| ID | Action | Type |
|----|--------|------|
| A1 | Sanitiser `requestURL` dans toutes les constructions d'erreur | `fix(security):` |
| A2 | `CustomStringConvertible` sur `AuthMethod` + `ServerConfiguration` | `fix(security):` |
| C1 | `LocalizedError` sur `SwiftSonicError` avec descriptions sanitisées | `fix(security):` |

### Priorité 2 — Hardening (bonne pratique, pas de fuite active connue)
| ID | Action | Type |
|----|--------|------|
| A3 | Longueur salt → 16, `SystemRandomNumberGenerator` explicite | `refactor(security):` |
| B2 | DocC transport : avertissement logging URL | `docs(security):` |
| D2 | Warning HTTP plain-text dans le logger | `fix(security):` |
| D3 | Redirect cross-domain → throw `.insecureRedirect` | `fix(security):` |

### Priorité 3 — Polish (faible risque, mais attendu pour v0.5.0)
| ID | Action | Type |
|----|--------|------|
| C3 | Fixtures `getShares.json` : remplacer `demo.navidrome.org` par `music.example.com` | `chore(security):` |
| D1 | DocC TLS warning | `docs(security):` |
| D4 | `requestTimeout` plancher 1s | `refactor(security):` |
| F1 | `SECURITY.md` + DocC Security Guide + CHANGELOG 0.5.0 | `docs(security):` |

---

## Breaking changes à discuter

| Change | Raison | Proposé dans |
|--------|--------|-------------|
| `SwiftSonicError.insecureRedirect(from:to:)` nouvelle case | Protection redirections cross-domain (D3) | Étape 9.4 |
| `requestURL` sanitisée dans erreurs | Les query params auth sont supprimés | Étape 9.2 (non-breaking car corrige une fuite) |
| `ServerConfiguration.requestTimeout` plancher 1s | Valeur 0 interdite | Étape 9.4 (potentiellement breaking si un test passe 0) |

---

## Note : pas de credentials réels détectés dans l'historique

Grep sur les fixtures : aucun password, token, apiKey réel trouvé. Les seules URLs non-`example.com` sont `demo.navidrome.org` (serveur de démo public) et `last.fm`/`lastfm.freetls.fastly.net` (CDN public). Pas de `gitleaks` scan nécessaire en urgence, mais recommandé en E4 pour exhaustivité.

