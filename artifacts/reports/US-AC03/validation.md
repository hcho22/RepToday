# US-AC03 - Premium gating for the coach

FR-7 (the gate). The talking coach (US-AC02) becomes reachable only for premium subscribers; free users get an upsell entry point that opens the existing paywall.
The free core loop is never gated.

## What shipped

- **`CoachGateViewModel`** (`ViewModels/CoachGateViewModel.swift`): an `@Observable` gate that reads the StoreKit 2 entitlement through the existing `SubscriptionServiceProtocol` - the same plumbing the paywall and the Progress-tab deep layer use, **no new billing path**. Its one-line read (`currentSubscription().tier == .premium`) is identical to `ProgressViewModel`'s deep-layer gate, so the two cannot drift. It **fails safe**: `isPremium` starts `false` and a throwing read leaves it `false` (show the upsell, never silently unlock a paid surface).
- **`CoachEntryRow`** (`Views/Coach/CoachEntryRow.swift`): the single coach entry point on the Profile tab, replacing US-AC02's ungated `NavigationLink`. A Premium subscriber navigates straight into `CoachView`; a free user's tap opens the existing US-N04 `PaywallView` carrying `EntryPoint.coachUpsell`. The entitlement read is best-effort in `.task`, off the Home/Ready critical path, and never gates the tab from rendering.
- **`EntryPoint.coachUpsell`** (`Models/AnalyticsEvent.swift`, raw value `coach_upsell`): a new closed-enum case so the US-T12 funnel can tell a coach upsell apart from the Progress-tab one. `paywall_shown` is emitted by the paywall itself (`PaywallViewModel.load()`) - this story adds no new emission site, only a new entry-point value into the existing one.
- **`ProfileRowLabel`** made internal + gained an optional `badge` (the "Premium" tag on the free upsell row), so the gate row reuses the same list-row styling the Settings row uses.

## Acceptance criteria

| # | Criterion | Evidence |
|---|-----------|----------|
| 1 | Coach reachable only for `.premium`; free users see an upsell that opens the paywall + emits `paywall_shown` (reusing the US-T12 entry-point pattern) | `CoachGateViewModelTests.testFreeUserIsBlocked` / `testPremiumUserIsAllowed`; `CoachGatingEvidenceTests` (free row is the Premium-tagged upsell, Premium row reaches the coach); the free branch presents `PaywallView(entryPoint: .coachUpsell)`, which emits `paywall_shown` carrying `coach_upsell` (`PaywallViewModelTests` already covers the emission) - `01-free-user-coach-upsell.png`, `02-premium-user-coach.png` |
| 2 | The free core loop (generate, play, log, consistency, phase, phase-progress, progression map) is unchanged and never gated | Only the coach entry row changed; every "never gated" free surface in `ProgressTabView` and the Home tab is untouched. `RootView.swift` diff touches only the coach row |
| 3 | Entitlement checks reuse existing StoreKit 2 plumbing; no new billing path | `CoachGateViewModel` reads `SubscriptionServiceProtocol.currentSubscription()` - the identical read `ProgressViewModel:139` uses; no new StoreKit product, facade method, or purchase path |
| 4 | Tests cover free-blocked-with-upsell and premium-allowed; `docs/test-coverage.md` row | `CoachGateViewModelTests` (5 cases incl. the fail-safe) + `CoachGatingEvidenceTests` (2 hosted cases); test-coverage row added |
| 5 | Build and suites pass | `xcodebuild ... build` -> BUILD SUCCEEDED; the `RepToday` unit suite green |

## Validation test

- **Free user opens the coach entry point** -> the row is the upsell (Premium badge, hint "A Premium feature. Opens Premium to unlock the coach."), a tap opens the paywall, and it does **not** reach the coach: `CoachGatingEvidenceTests.testFreeUserSeesUpsellNotCoach` asserts the upsell hint present and the coach's "ask the coach" affordance absent - `01-free-user-coach-upsell.png`.
- **Premium user opens the coach entry point** -> the row navigates into `CoachView`: `testPremiumUserReachesCoach` asserts the "ask the coach" affordance present and the upsell hint absent - `02-premium-user-coach.png`.
- **No core-loop screen becomes gated** - the change is confined to the one coach entry row.

## Screens

- `01-free-user-coach-upsell.png` - a free user's Coach row: a "Premium"-tagged upsell entry that opens the paywall, not the coach.
- `02-premium-user-coach.png` - a Premium user's Coach row: navigates into the talking coach.

## Notes / scope

- The gate is at the **entry point**, not inside `CoachView` - a free user never reaches the coach surface (which itself stays inert until the proxy is deployed, per US-AC02). The paywall sheet presentation and the navigation push are the standard SwiftUI transitions; the hosted evidence asserts the branch (which row renders) rather than driving the transition, which is captain-verifiable manual QA.
- **No new emission site:** `paywall_shown` already fires from the paywall; this story only adds the `coach_upsell` entry-point value it can carry.
- **Later stories now landed:** the OpenAI/provider-retention disclosure (US-AC04), Coach-sourced policy writes (US-AC05/06/07), the injury-flag routing UI (US-AC08), and premium analytics narration (US-AN01/02).

## How to regenerate

```
cd ios/RepToday
xcodebuild -project RepToday.xcodeproj -scheme RepToday \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  REPTODAY_WRITE_EVIDENCE=1 \
  -only-testing:RepTodayTests/CoachGatingEvidenceTests test
```
