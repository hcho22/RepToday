# US-AC04 - Consent and disclosure for coach data

FR-8, and the last story of Slice 2 (the monetization test).
Before first use of the premium AI coach, a plain, unavoidable, one-time disclosure states that a coach message **plus a short summary of training context** is sent to Claude to answer and is **not stored** - the one honest break in Rep Today's on-device privacy posture (content leaves the device in the moment of a call).
It is a consent gesture: the user taps **I understand** for the coach to become usable, or **Not now** to back out sending nothing.

## What shipped

- **`CoachDataDisclosureView`** (`Views/Coach/CoachDataDisclosureView.swift`): the one-time pre-use disclosure, presented as an overlay layer (not a `.sheet`, so the entrance stills under Reduce Motion), `.isModal` for VoiceOver focus-trapping, 60pt controls, a `ScrollView` for Dynamic Type, `Theme` tokens only. Its copy lives in **`CoachDataDisclosureCopy`** - the single source both the modal and the Settings entry read, so they cannot drift.
- **`CoachViewModel` send gate** (`ViewModels/CoachViewModel.swift`): `isDataSharingAcknowledged` (starts `false`), `needsDataSharingConsent`, `grantDataSharingConsent()`. The **load-bearing guarantee** is here, in the send path: `deliver` (plus `send`/`retryLastMessage`) hard-guards on acknowledgement, and `canSend` folds it in - so no coach request leaves the device before consent, on any path.
- **`CoachView` orchestration** (`Views/Coach/CoachView.swift`): reads `@Environment(AppState.self)` (optional, like `ActiveSessionView`), and in `onAppear` either opens the gate silently (already acknowledged) or presents the disclosure. "I understand" grants consent + persists the one-shot + dismisses; "Not now" `dismiss()`es the coach and records nothing, so it re-shows on the next open.
- **`AppState` one-shot** (`Utilities/AppState.swift`): `hasAcknowledgedCoachDataSharing` / `shouldShowCoachDataDisclosure` / `markCoachDataSharingAcknowledged()`, UserDefaults-backed, default not-acknowledged. Flipped **only on explicit acknowledgement** (never on presentation), so a force-quit mid-disclosure re-shows it and nothing was ever sent. Deliberately **independent of** `analyticsEnabled`.
- **`SettingsView` AI Coach section** (`Views/Settings/SettingsView.swift`): its own Privacy section, separate from the telemetry toggle above it (touching neither its flag nor its footer), whose footer states the same facts and names the separation from the anonymous usage data explicitly.

## Acceptance criteria

| # | Criterion | Evidence |
|---|-----------|----------|
| 1 | Before first use, a plain disclosure states message + training-context summary are sent to Claude to answer and are not stored | `CoachDataDisclosureEvidenceTests.testDisclosureStatesHonestFactsAndOffersBothControls` (names Claude, the training-context summary, and "not stored" on the live a11y tree) + `testRealCoachViewPresentsTheDisclosureBeforeFirstUse` (it presents on the real `CoachView` before any send) - `01-coach-data-disclosure.png` |
| 2 | Honest about the one break in the on-device posture (content leaves the device), not buried in fine print | The disclosure names it plainly ("This is the one moment Rep Today sends your content off your phone"); the evidence asserts "off your" present. It is a full-screen modal, not fine print |
| 3 | A Settings entry documents the same, consistent with the Privacy-section pattern | `TelemetryConsentSurfaceTests.testSettingsMirrorsTheCoachDataDisclosureSeparatelyFromTelemetry` - the coach disclosure row + footer coexist with the telemetry toggle, naming Claude / "not stored" via the shared `CoachDataDisclosureCopy` |
| 4 | Separate from, and does not weaken, the telemetry opt-out | `AppStateTests.testCoachDisclosureIsIndependentOfTheTelemetryOptOut` - acknowledging the coach disclosure never touches `analyticsEnabled`, and turning telemetry off never touches coach consent; the Settings footer declares the separation |
| 5 | Accessibility + `Theme`; `docs/test-coverage.md` row | `Theme` tokens only, `.isModal`, 60pt controls, `ScrollView` for Dynamic Type; a11y asserted on the hosted tree; test-coverage row added |
| 6 | Build and suites pass | `xcodebuild ... build` -> BUILD SUCCEEDED; the full `RepToday` unit suite green |

## Validation test

- **Setup:** a Premium user opening the coach for the first time (modeled as the real `CoachView` over a fresh, un-acknowledged `AppState`).
- **Open the coach** -> the disclosure presents before first use, and the send gate is closed behind it: `testRealCoachViewPresentsTheDisclosureBeforeFirstUse` asserts the disclosure copy on the real surface, the transport uncalled, `needsDataSharingConsent == true`, `canSend == false`.
- **Read the disclosure** -> it states the facts honestly: `testDisclosureStatesHonestFactsAndOffersBothControls` (message + training summary to Claude, leaves the device, not stored; both "I understand" / "Not now" controls) - `01-coach-data-disclosure.png`.
- **Check Settings** -> Settings mirrors it, separately from telemetry: `testSettingsMirrorsTheCoachDataDisclosureSeparatelyFromTelemetry`.
- **Declining sends nothing** -> `testDecliningSendsNothing` (a send attempt while un-acknowledged reaches the transport zero times and records no consent).
- **Failure indicator (none observed):** no disclosure, misleading wording, or a message sent before consent - all excluded by the tests above.

## Screens

- `01-coach-data-disclosure.png` - the pre-use disclosure: "How the coach uses your messages", what's sent (message + training summary to Claude), that it leaves the device just for this and isn't stored, with the prominent "I understand" and the "Not now" back-out. (The third point scrolls into view on-device; the whole disclosure is a Dynamic-Type `ScrollView`.)

## Notes / scope

- The consent gesture is **disclosure-then-acknowledge** (an explicit one-time "I understand" before the first request, "Not now" to back out sending nothing) - the honest reading of the AC's "declining does not send anything", implemented within the accepted story per the established one-shot-flag pattern (`AppState.hasSeenContinuousCircuitExplainer`, the US-SP06 ratcheting one-shot).
- The **send gate**, not the view's appearance, is the guarantee: even a caller that reached `deliver` another way sends nothing until consent (unit-pinned in `CoachViewModelTests`).
- iOS-only: **no** proxy/Convex change, **no** new emission site, **no** wire change. The coach itself stays inert until the proxy is deployed (US-AC02), independent of this disclosure.
- The PNG is captured by hosting `CoachDataDisclosureView` directly (the `ContinuousCircuitExplainerTests` precedent), because `layer.render(in:)` composites a transitioned SwiftUI overlay unreliably; the real-`CoachView` integration proof is a separate a11y-tree assertion in the same suite.
- Captain-verifiable manual QA: the overlay's Reduce-Motion entrance stilling (the `accessibilityReduceMotion` env is read-only, so not hostable - enforced by the animation gate) and live on-device VoiceOver modal focus-trapping.

## How to regenerate

```
cd ios/RepToday
xcodebuild -project RepToday.xcodeproj -scheme RepToday \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  REPTODAY_WRITE_EVIDENCE=1 \
  -only-testing:RepTodayTests/CoachDataDisclosureEvidenceTests test
```
