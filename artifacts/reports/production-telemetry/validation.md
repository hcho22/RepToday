# Production telemetry validation — 2026-08-31

## Production identity and ownership

- Convex team/project: `hcho22/reptoday-telemetry` (the existing project already used by development deployment `courteous-dogfish-560`; no second project was created).
- Default production deployment: `sensible-spider-810`.
- HTTP-action origin: `https://sensible-spider-810.convex.site`; client route: `POST /logEvent`.
- Convex ownership remains with team `hcho22`. Release-token custody is the captain-owned macOS login Keychain item with service `com.reptoday.analytics.production` and account `release-archive`.
- The production token is 256 bits of random hex, production-only, and was never printed. It exists in exactly the Keychain item above and the production deployment variable `ANALYTICS_SHARED_SECRET`. Equality was checked in memory without writing or displaying either value.
- The token is an extractable client-shipped abuse deterrent, not strong authentication. The per-install ceiling (60/minute) and per-IP ceiling (600/minute) in `convex/rateLimit.ts` are the authoritative abuse bound.

## Release injection and inert failure posture

`ios/RepToday/project.yml` commits only the production `.site` origin. Its Release token default remains empty. `tools/archive-release.sh <archive-path>` reads the Keychain item, validates its expected 64-hex-character shape, writes it to a mode-600 temporary xcconfig, passes only that file path to `xcodebuild`, and removes it on exit. The token does not enter Git, `project.yml`, the generated `.xcodeproj`, a committed xcconfig, logs, reports, PR text, or command text.

`LiveAnalyticsService.configured(...)` still requires both a usable HTTPS endpoint and a non-empty token. Missing/empty/malformed configuration returns `nil`; `ServiceContainer.live(...)` selects `NoOpAnalyticsService`; the app remains nonfatal and sends nothing. Emptying both Release settings is therefore the client rollback/disable posture.

## Commands and results

All token positions below are intentionally redacted.

```text
npm ci
npm run typecheck
npm test
```

Result: Convex deploy and test TypeScript both type-checked; Vitest/`convex-test` passed 88/88.

```text
CONVEX_DEPLOYMENT='dev:courteous-dogfish-560' \
  npx convex deploy --yes --typecheck enable --message 'Wire first production telemetry build'
npx convex env set ANALYTICS_SHARED_SECRET '<redacted>' \
  --deployment hcho22:reptoday-telemetry:prod
npx convex env list --names-only --deployment hcho22:reptoday-telemetry:prod
```

Result: the current repository schema/functions deployed to production; `rateLimits.by_bucketKey` and `rateLimits.by_windowStart` were created; the names-only environment read returned `ANALYTICS_SHARED_SECRET`.

```text
tools/validate-production-telemetry.sh
```

Result against production:

- correct token: `204`; exactly one persisted, recognizable row for install `prod-smoke-20260831T214131Z`, marked by its `validation_marker` property;
- missing token: `401`, zero rows for its unique install id;
- wrong token: `401`, zero rows for its unique install id;
- rate ceiling: 60 pre-ceiling requests reached the post-rate-limit invalid-props rejection (`400`) and inserted zero rows; request 61 returned `429`; the rate-test install had zero rows. This shapes the test so proving the ceiling does not add 60 junk evidence rows.

```text
xcodebuild ... -configuration Debug ... test \
  -only-testing:RepTodayTests/AppStateTests \
  -only-testing:RepTodayTests/AccountDeletionServiceTests \
  -only-testing:RepTodayTests/LiveAnalyticsServiceTests
```

Result: 70 focused tests passed. Coverage includes persisted identifier rotation on account deletion, the already-built transport reading the rotated id on its next event, missing configuration remaining inert, the opt-out gate creating zero intercepted requests, and the live wire contract.

```text
tools/validate-release-telemetry-client.sh <simulator-udid>
```

Result: a clean optimized Release simulator build contained the production origin and a token byte-for-byte equal to the Keychain value (values compared without printing). The same built app was installed fresh twice:

- default opted-in launch: two production rows, including exactly one `app_install`;
- launch with `-AppState.analyticsEnabled NO`: zero production rows.

The live positive control proves this Release artifact's endpoint/token can persist. The paired production-code `LiveAnalyticsServiceTests.testDisabledGateEmitsNothing` intercepts below the gate and proves the opted-out branch creates no request at all, rather than merely no row.

## Rotation

Coordinate a token rotation with a replacement app release: changing the server value immediately makes older binaries receive `401`. With shell tracing disabled, generate a new 32-byte hex value into a shell variable, update the Keychain item and production `ANALYTICS_SHARED_SECRET` from that variable without echoing it, unset the variable, run both production validators, then archive through `tools/archive-release.sh`. Never paste the value into source, an xcconfig in the repository, a report, an issue, a PR, or a status message.

If a token is ever exposed in committed history, a remote log, or a public artifact, treat it as compromised: replace both stores immediately, validate, and ship the replacement build. Do not reproduce the exposed value in the incident record.

## Disable and rollback

- Client-side: build with empty `REPTODAY_ANALYTICS_ENDPOINT` and `REPTODAY_ANALYTICS_SECRET`; the existing configuration factory selects the inert no-op sink.
- Server-side emergency stop: remove `ANALYTICS_SHARED_SECRET` from production. The HTTP action fails closed with `500` and inserts nothing until a replacement is set.
- Code rollback: redeploy the preceding known-good Convex commit to the same project/deployment; do not create another project. The `events` row shape was not changed by this launch wiring.

## Measurement limitations intentionally left open

- Telemetry is fire-and-forget with no queue/retry. iOS suspension or termination can lose in-flight requests, so production counts are a lower bound on events the app attempted to emit.
- A later trial-to-paid StoreKit conversion still undercounts `subscribe`, because the out-of-band transaction observer is not connected to the analytics seam. Direct paid grants are counted; conversions after a trial may be absent.

No queue/retry subsystem or StoreKit conversion observer was added here. The removed public `gtm/` package was not recreated or edited; the already-approved collecting App Store privacy posture remains the controlling disclosure.
