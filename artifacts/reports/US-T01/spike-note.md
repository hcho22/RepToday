# US-T01 Spike Note - de-risking the Convex transport (`convex-swift`)

**Story:** US-T01 of `.claude/agent/tasks/prd-funnel-instrumentation_260803.md` - prove one event can reach a Convex deployment before any app code is written.
**Date:** 2026-08-03
**Verdict:** NO-GO on `get-convex/convex-swift` for the app.
**Adopted transport instead:** a Convex HTTP action (`POST /logEvent`) reached by a plain `URLSession` POST - zero new Swift Package dependencies.

---

## TL;DR

`convex-swift` builds and links cleanly against an iOS 17.0 deployment target, so iOS 17 is a non-issue.
The blocker is that the package ships an **arm64-only** binary xcframework with no `x86_64` slice, which makes every Simulator-hosted test suite in this repo unbuildable on an Intel Mac.
For a pipeline that needs one fire-and-forget JSON POST, the package is also massive over-provisioning: ~147 MB of opaque Rust maintaining a persistent WebSocket and a reactive query stack the app would never use.
The recommended replacement - a Convex HTTP action reached by `URLSession` - was validated end to end during this spike (HTTP 204, row confirmed persisted server-side) and carries no new dependency, so Lottie stays the app's only third-party Swift package.

---

## What was proven

### 1. A scratch Convex deployment accepts and persists an event

A scratch project `ust01-spike` with dev deployment `determined-vulture-542` was deployed, holding one append-only table `events { name, installId, clientTs, serverTs, props }` and one `logEvent` mutation that inserts a row (stamping `serverTs = Date.now()`) and returns the doc id - a dumb sink, no aggregation or dedup.
An event was sent two ways (a JS-client mutation via the Convex CLI runner, and an HTTPS POST) and then **read back from the deployment** with `npx convex data events`:

```
_id          | clientTs      | installId               | name                   | props                                       | serverTs
-------------|---------------|-------------------------|------------------------|---------------------------------------------|--------------
j57f03m...   | 1785780300000 | "urlsession-spike-C3D4" | "onboarding_completed" | { "step":"final","transport":"https-post" } | 1785780607474
j5703qt...   | 1000          | "cli-smoke-0001"        | "app_install"          | { "source":"cli" }                          | 1785780205942
```

`npx convex data events` is not a "no error thrown locally" check: it is an authenticated query round-trip that returns the rows actually persisted in the deployment, and both `serverTs` values were stamped server-side, so a false local success is ruled out.

### 2. `convex-swift` builds against an iOS 17.0 deployment target - iOS 17 is NOT the blocker

The package `ConvexMobile` declares `platforms: [.iOS(.v13), .macOS(.v10_15)]`, so its declared minimum is iOS 13, well below iOS 17.
A throwaway iOS app target with `IPHONEOS_DEPLOYMENT_TARGET = 17.0` and the SPM dependency added built cleanly for a generic arm64 iOS device:

```
xcodebuild ... -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **
```

Swift compiles and the arm64 `ios-arm64` slice links at deployment target 17.0.

### 3. The arm64-only constraint (the actual blocker)

`libconvexmobile-rs.xcframework/Info.plist` lists three library identifiers, every one arm64:

| LibraryIdentifier     | Platform | Variant   | Archs   |
|-----------------------|----------|-----------|---------|
| `ios-arm64`           | ios      | (device)  | `arm64` |
| `ios-arm64-simulator` | ios      | simulator | `arm64` |
| `macos-arm64`         | macos    | -         | `arm64` |

`lipo -archs` on each `libconvexmobile.a` returns `arm64`; there is no `x86_64` slice anywhere.
On an Intel (x86_64) host the Simulator build fails at link:

```
note: 'libconvexmobile-rs.xcframework' is missing architecture(s) required by this target (x86_64), but may still be link-compatible.
Undefined symbols for architecture x86_64:
ld: symbol(s) not found for architecture x86_64
```

Rosetta on Intel cannot run arm64, so there is no execution path here at all: the Swift client could not be run on the Simulator or as a macOS tool on this host.
On an Apple Silicon Mac the `ios-arm64-simulator` slice would run, and real iPhones (all arm64) are fine everywhere.
Rep Today leans heavily on Simulator-hosted test suites (the evidence, snapshot, and XCUITest suites documented in `CLAUDE.md`), so adding this package to the app target would make every one of them unbuildable on any Intel machine - including the captain's Intel Core i9 development machine.

---

## Integration shape (for reference, were `convex-swift` ever reconsidered)

### Version pin and dependency graph

- **Version pinned:** `0.8.1` (tag), revision `125b71b2f8725931a5b0e8252f0799ef2adad120` - the latest tag as of the spike.
- **Resolved graph:** a single package with zero transitive SPM dependencies (`swift-tools-version: 5.10`):

  ```
  ConvexMobile (product "ConvexMobile")
    └─ UniFFI                    (generated Swift bindings, in-package target)
        └─ ConvexMobileCoreRS    (.binaryTarget -> libconvexmobile-rs.xcframework, Rust)
  ```

  The static lib is ~49 MB per slice (~147 MB xcframework) of opaque, non-inspectable, non-patchable Rust.

### Connection / auth shape

- Construct with just the deployment client URL (the `.convex.cloud` one), no credential:

  ```swift
  let client = ConvexClient(deploymentUrl: "https://<deployment>.convex.cloud")
  ```

- Under the hood the Rust core opens and holds a persistent WebSocket (`clientId: "swift-<version>"`), exposed through a `watchWebSocketState()` publisher.
- No auth is needed for an unauthenticated (public) mutation like `logEvent`; auth is a separate opt-in path (`ConvexClientWithAuth` + an `AuthProvider` returning a JWT id token) and is irrelevant to anonymous telemetry.

### How a mutation is called from Swift

```swift
import ConvexMobile

let client = ConvexClient(deploymentUrl: "https://<deployment>.convex.cloud")

// props is itself a [String: ConvexEncodable?], which conforms to ConvexEncodable (nesting works).
let props: [String: ConvexEncodable?] = [
    "source": "ios17-xctest",
    "generation_ms": 42.0,          // Double -> float64
]
let args: [String: ConvexEncodable?] = [
    "name": "session_completed",
    "installId": installId,
    "clientTs": 1785780200000.0 as Double,   // see encoding gotcha below
    "props": props,
]

// Two overloads: one returns Decodable, one returns Void.
let id: String = try await client.mutation("events:logEvent", with: args)   // module:function
```

### Argument-encoding gotcha

`ConvexEncodable` maps Swift scalars onto Convex's two distinct numeric types:

- Swift `Int` / `Int32` / `Int64` -> Convex `int64` (encoded as `{"$integer": <base64>}`).
- Swift `Double` / `Float` -> Convex `float64` (`v.number()`).

So if a schema field is `v.number()` (float64) and the client sends a Swift `Int`, the mutation is rejected on a type mismatch.
The two sides have to agree: either declare integer fields as `v.int64()` and send Swift `Int`, or keep `v.number()` and send Swift `Double`.
This spike sent `clientTs` as `Double` against `v.number()` and it validated.
The adopted `URLSession` transport sidesteps this entirely, because the HTTP action coerces with `Number(...)` and the client sends plain JSON with no `$integer` encoding dance.

---

## Adopted transport: `URLSession` POST to a Convex HTTP action

The app needs only best-effort, fire-and-forget ingest - no live queries, no subscriptions, no auth - so a plain HTTPS POST to a Convex HTTP action is a strictly better fit and carries zero new Swift dependencies.
This was validated live in the spike.

Backend side (US-T03 adds `convex/http.ts` alongside the `logEvent` mutation):

```ts
import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { api } from "./_generated/api";

const http = httpRouter();
http.route({
  path: "/logEvent",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const body = await request.json();
    await ctx.runMutation(api.events.logEvent, {
      name: String(body.name),
      installId: String(body.installId),
      clientTs: Number(body.clientTs),
      props: body.props ?? {},
    });
    return new Response(null, { status: 204 });
  }),
});
export default http;
```

Client side (US-T04, no dependency, trivially mockable with a `URLProtocol` stub in tests):

```swift
func record(_ event: AnalyticsEvent) {            // reads fire-and-forget at the call site
    Task.detached(priority: .background) {
        var req = URLRequest(url: URL(string: "https://<deployment>.convex.site/logEvent")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(event)   // plain JSON, no $integer encoding dance
        _ = try? await URLSession.shared.data(for: req)   // best-effort; swallow all failures
    }
}
```

Live proof from the spike (`URLSession`-equivalent POST to the `.site` endpoint):

```
POST https://<deployment>.convex.site/logEvent  ->  HTTP 204
# row "urlsession-spike-C3D4" then confirmed present via `npx convex data events`
```

Why this wins for this app:

- **Zero new dependencies**, works on every arch (Intel and Apple Silicon), every Simulator, and CI - no arm64-only breakage of the existing test suites.
- Fire-and-forget maps naturally onto `Task.detached` + `try?`: there is no client object to hold, no WebSocket lifecycle, no reactive stack to reason about.
- Plain `Codable` JSON sidesteps the `$integer` vs `float64` encoding gotcha entirely.
- Testable with a `URLProtocol` stub, so no unit test performs a real network call (satisfies FR-13).
- The only real trade-off versus `convex-swift` is no built-in retry/offline queue, but telemetry is explicitly best-effort and offline-first-lossy per the PRD goals, so this is acceptable; a durable outbox, if ever wanted, is a small local buffer with still no third-party dependency.

---

## Go / no-go and what changes downstream

**No-go on `convex-swift`; adopt the HTTP action + `URLSession` transport.**

- **US-T03 (backend):** add a `convex/http.ts` HTTP action (`POST /logEvent`) wrapping the same append-only `logEvent` mutation, so the client needs no Convex SDK. The mutation still needs the real input validation US-T03 calls for (reject unknown event names, reject an oversized property bag); pin the numeric convention up front, noting that the HTTP action's `Number(...)` coercion makes the `int64`/`float64` gotcha moot for the client.
- **US-T04 (live service):** implement `LiveAnalyticsService` over `URLSession` posting to the deployment's `.site/logEvent` endpoint, strictly fire-and-forget. Do **not** add `convex-swift` to `ios/RepToday/project.yml`.
- If `convex-swift` is ever reconsidered (for example, if the app later wants live reactive queries), the first blocker to re-check is the arm64-only xcframework against whatever Macs and CI runners are in use, not the iOS deployment target.

## Dashboard note (why no browser screenshot)

The Convex web dashboard (`dashboard.convex.dev/d/<deployment>/data`) sits behind an interactive OAuth sign-in (Google/GitHub/email), and this spike did not improvise a browser login.
The equivalent authoritative evidence is the `npx convex data events` round-trip: authenticated by the existing CLI token, it reads the deployment's persisted rows directly - the same data the dashboard renders - with a server-stamped `serverTs` on every row and the returned document ids.
If a literal dashboard screenshot is ever required for sign-off, a human with the Convex account can open the URL above; the two rows will be present.
