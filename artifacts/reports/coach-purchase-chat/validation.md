# Coach purchase-to-chat and local availability follow-up

Source baseline: `d1acf59` (Release Coach enablement, PR #169). This follow-up changes
presentation, tests and documentation; the current Release/Debug/CoachDeviceQA configuration
contracts remain intact. Current deployment/distribution evidence belongs to
[`docs/coach-runtime-authentication.md`](../../../docs/coach-runtime-authentication.md).

## Product behavior

`CoachViewModel.LocalAvailability` describes whether a local client exists: `enabled` or
`notEnabledInBuild`. Missing and invalid local configuration both select the latter. It is
independent of Premium eligibility, disclosure consent and send-time service health.

The disabled screen says “Coach is not enabled in this build,” suggests contacting Rep Today
support about a Coach-enabled build, and reassures the user that workouts are unaffected.
VoiceOver receives the full next step and reassurance through combined text. The copy does not
suggest purchasing/restoring again, waiting or retrying will enable this build and does not
claim an update exists.

Device/proof/network/service failures keep the configured conversation, its question and its
existing retry behavior. No entitlement semantics, endpoint, authentication mode, embedded secret,
workout logic or send-time error policy changed.

## Permanent regression coverage

- `CoachGatingEvidenceTests`: the production Profile Coach row opens the production paywall.
  A trusted subscription-service double supplies the already-verified purchase or restore grant
  while every entitlement reread remains free. The shared Premium authority keeps the row
  unlocked, including after rehosting. Both actions are tested with enabled and disabled clients.
- Enabled cases use `CoachProxyClient.configured`: Debug supplies the exact public Release
  configuration via a test bundle; optimized Release reads the actual processed app bundle.
  The real runtime-authenticated client is constructed, but no send is made. The production
  `CoachView(services:)` presents disclosure, persists explicit acknowledgement and shows chat,
  with no build-disabled screen.
- Disabled cases preserve the Premium row after the same grant and stale reads, then show the
  build-disabled production destination with support/workout copy and no disclosure, chat or retry.
- `CoachViewEvidenceTests`: the real runtime transport receives unsupported-device and missing-proof
  doubles, stays in chat after send and retry, and makes no HTTP calls. A proof call counter
  distinguishes the two gates. Offline, HTTP 401 and HTTP 503 doubles retain the conversation;
  invoking the production `retryLastMessage()` method recovers with a stub reply without duplicating
  the question, and the hosted conversation updates in place.
- `CoachProxyClientConfiguredTests`: missing/empty endpoint, wrong production path, wrong mode and
  embedded secret fail closed into local build-disabled state, not a retryable send error. Existing
  endpoint/origin and configuration-specific rejection tests remain intact.

## Evidence limits

These are hosted Simulator surfaces and trusted doubles, not genuine StoreKit purchases,
App Attest proofs, TestFlight distribution, server admission or model answers. The hosted
accessibility proxy does not reliably push a SwiftUI `NavigationLink`: the tests assert the
unlocked production row, then explicitly mount its exact production destination. They do not
prove an actual navigation tap. The subscription double represents a verified grant already
returned by StoreKit; it does not verify a transaction itself. Runtime doubles prove failure
routing only, not Apple cryptography or device support.

The hosted accessibility tree also combines the failure banner without exposing a separately
activatable “Try again” element. Retry is driven through the production view-model method while
asserting the hosted error/conversation before and after it. Source review confirmed that the real
`CoachView` button calls `beginRetry()`, which delegates through `beginDelivery` to that same
`viewModel.retryLastMessage()` method. The button, its accessibility hint and its existing grouping
were not changed. Neither this source review nor the hosted test proves a physical retry tap;
live VoiceOver/touch activation remains device QA.

Remaining device-only coverage: actual purchase and restore, force quit/relaunch, Profile → Coach
navigation, disclosure accessibility/focus, App Attest enrollment/assertion, matched Sandbox
Premium admission and a separately authorized model response. No genuine-device success is
claimed by this evidence.

## Validation

- Focused Debug suite: **57 tests passed, 0 failures** on iPhone 16 / iOS 18.6 Simulator.
- The same focused optimized Release suite: **57 tests passed, 0 failures**, using the test-only
  `ENABLE_TESTABILITY=YES` override and the actual processed Release app bundle.
- Processed Release configuration inspector passed: approved endpoint, exact runtime mode, empty
  Coach secret, synthetic QA off, no bundled StoreKit fixture; generated ArchiveAction selects
  Release without a local StoreKit attachment. Release app metadata inspection also passed.
- Native runtime/client harness (`bash tools/test-coach-runtime-client.sh`): **84 tests passed**.
- Processed Debug configuration inspector passed: endpoint empty, secret empty, runtime mode exact,
  synthetic QA off. App metadata validator and its **6 tests** passed.
- The initial Debug run failed only the new hosted retry activation attempt (56/57); the narrower
  selector attempt confirmed the same limitation. The corrected full run uses the production
  retry method as documented above. The initial native harness compilation exposed an iOS-only
  view-model assertion in the shared configuration suite; gating that UI assertion to iOS restored
  the native suite without removing its configuration rejection tests.
- The archive inspection test was attempted without its required prebuilt archive and could not
  run its archive-dependent cases. No archive evidence is claimed; the Release Simulator bundle
  is inspected separately. Archive/distribution and genuine-device evidence remain separate.

Focused command (use `Release ENABLE_TESTABILITY=YES` in place of `Debug` for the optimized test run;
the testability override does not change shipping settings):

```sh
xcodebuild test -project ios/RepToday/RepToday.xcodeproj -scheme RepToday \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=32039CCE-BE1D-4233-A4D4-19CA9428DBF3' \
  -derivedDataPath build/purchase-chat/DerivedData \
  -only-testing:RepTodayTests/CoachGatingEvidenceTests \
  -only-testing:RepTodayTests/CoachViewEvidenceTests \
  -only-testing:RepTodayTests/CoachViewModelTests \
  -only-testing:RepTodayTests/CoachProxyClientConfiguredTests
```

The unavailable-screen PNG under `../US-AC02/03-coach-unavailable.png` was regenerated and visually
inspected. Local run logs/result bundles are under ignored `build/purchase-chat/`.

Implementation risk is limited to local-state presentation and copy. The optional client remains
immutable, send/retry and entitlement semantics are unchanged, and the existing configuration
rejection paths remain covered. Full repository validation and PR/CI delivery run through the
separate no-mistakes stage; the local checks above do not claim a completed CI run.
