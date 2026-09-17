# Coach iPhone synthetic QA preparation — local verification

2026-09-17. This report separates source/build preparation from signing, physical-device execution
and live service/model evidence. No credential access, production operation or paid/public-service
request was performed. Package dependency retrieval is source/build tooling, not live Coach QA.

## Executed source and offline behavior checks

| Check | Observed outcome |
| --- | --- |
| Proxy `npm test` | 162 tests passed |
| Proxy `npm run typecheck` | passed |
| Proxy `npm run test:runtime` | actual installed workerd/native crypto/Apple-verifier/API-transport/SQLite checks passed; every outbound request intercepted locally, zero external requests |
| `tools/test-coach-runtime-client.sh` | 63 XCTest cases passed against actual shared source with Apple/transport doubles, including 10 synthetic-QA view-model cases |
| `tools/test-coach-live-qa.sh` | native operator QA doubles and production-entry compilation passed; no real credential reader or live request executed |
| `tools/test-coach-production-deploy.sh` | 57 coordinator tests plus native boundary doubles/production-entry compilation passed; no network/Keychain access |
| `tools/test-coach-runtime-migration.sh` | 37 coordinator tests plus native doubles/production-entry compilation passed; no UI, Keychain, control-plane or Worker call |
| `tools/test-coach-qa-build-inspection.py` | 5 behavioral checks passed over copies of actual built plist/generated scheme output; rejects endpoint/mode/secret/flag/configuration mismatch and local StoreKit attachment |
| XcodeGen / Xcode build-settings consumer | custom QA configuration generated; app and test targets inherit `COACH_IPHONE_QA`, no `DEBUG`, with dedicated QA testability enabled |

The shared approved fixture values/prompts were moved verbatim from the existing native QA source
into `CoachSyntheticFixtures`. Both runners reference that one definition. Offline tests execute
the actual client encoding/response path, assert exact fixture/prompt injection, no bearer on the
explicit test client, no subscription purchase/restore writes, exactly two ordered explicit turns,
review-before-second-turn, persistent relaunch/interruption reservation, competing-screen safety,
consent/readiness/Premium boundaries and fixed-error/timeout recovery without retries.
No actual model reply was observed or retained. Local dummy text is not semantic/model evidence.

## Build and public configuration evidence

Local toolchain: Xcode 26.5 (17F42), iOS 26.5 SDK, iOS 17 deployment target; installed Node 20 for
proxy checks. Commands and output-contract inspector: `docs/coach-iphone-qa.md`.

| Artifact/check | Observed outcome |
| --- | --- |
| `RepTodayCoachDeviceQA`, `CoachDeviceQA`, generic iPhoneOS, signing disabled | final unsigned build passed; Mach-O arm64 executable |
| Built QA iPhone plist + generated QA scheme | approved HTTPS Coach endpoint enabled; binary Coach secret empty; exact `app-attest-storekit-v1`; synthetic QA enabled; telemetry empty; no local StoreKit attachment |
| Ordinary Release generic Simulator build | passed; inspected built plist has empty Coach endpoint/secret, exact production mode and synthetic QA disabled |
| Ordinary Debug generic Simulator test-host build | final app/test-host compilation passed; inspected built plist has empty Coach endpoint/secret, exact production mode and synthetic QA disabled (test analytics explicitly unconfigured) |
| QA generic Simulator test-host build | final app/test-host compilation passed for the optimized QA configuration, including QA bundle/entry and UIKit surface test sources; inspected QA plist/scheme passed |

A release-type test-host attempt initially failed because Swift testability was disabled. The
dedicated QA configuration now enables testability for `@testable` XCTest imports while preserving
optimized code, no `DEBUG`, no local StoreKit configuration and genuine runtime authentication.
Ordinary Release testability/authentication were not changed. The native live-QA compilation lists
now include the shared fixtures and actual runtime-authentication dependency; its operator behavior
and guard are unchanged.

The physical `.app` has **no code signature** (`codesign` reports code object not signed).
It is not an installable or production-distributed iPhone build. The source's production App Attest
entitlement is not effective signed-entitlement evidence. No archive, upload, provisioning update
or account/profile inspection ran.

## Execution/readiness gaps

- App-hosted **UIKit tests were compiled, not executed** in this preparation. A task-private
  `simctl --set` device set and iOS 26.5 iPhone booted successfully, but Xcode 26.5 did not expose
  that device as a test destination: `xcodebuild test-without-building` rejected its exact UUID and
  listed only shared destinations. Per the isolation requirement, no shared Simulator was booted,
  installed to, erased or otherwise driven. Native SwiftPM executes the actual
  client/context/configuration/QA-view-model source, but cannot establish the iOS-only configured
  runtime-transport branch, UIKit navigation/controls or native DeviceCheck behavior. Hosted
  synthetic-label/entry tests and actual-bundle configuration tests remain for tooling that can
  target a private device set, or an otherwise explicitly authorized isolated iOS test run/CI.
- Compatible existing signing/profile/distribution, actual App ID prefix/capability, effective
  production App Attest entitlement, an eligible physical iPhone and existing active production
  purchase/trial remain unconfirmed. The precise local install blocker is the unsigned artifact;
  do not infer that the Developer account lacks authority.
- Runtime service migration and genuine fresh production Apple verification were **not run**.
  A buildable public endpoint setting does not prove the service is usable. TestFlight Sandbox
  compatibility remains a separate choice; no fallback or production bypass was added.
- Real why-squats/pistol replies, local semantic review and genuine-client error/core recovery on
  device were **not run**. The existing total budget remains at most two model requests, not a
  new allowance per device/launch/authentication lane. The iPhone screen provides no retry/reset
  and must not be combined with an extra operator live-QA run. Non-empty text is not semantic proof.

## Revision coordination and handoff

The migration helper's clean-branch guard and whole-revision stage/release pin remain unchanged.
This new source revision is not accepted directly by that guard. The deployment owner must align
the final reviewed source with the guarded deployment checkout before staging, then release from
that exact staged revision; do not weaken the guard or switch HEAD between stage and release.
No different task checkout, guard, service configuration or stage/release operation was modified.

The implementation commit is ready for source review and CI after final local compilation. Use only
public product acceptance requirements as review intent; no operational records or private authority
material belongs in the PR. Source/build checks, signed-device readiness and actual live QA must
remain separate outcomes after review.
