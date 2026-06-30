# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FitSnack is a discipline-first micro-workout iOS app (5-30 min sessions) for busy, desk-bound adults.
It exists to build the habit of showing up: the user says how many minutes they have, and a deterministic on-device engine generates a complete zero-equipment session blending bodyweight strength and mobility.
No browsing, no choosing, no thinking.

Strength is earned over time, not the entry promise.
Every user starts in the **Discipline Phase** (consistency is the only goal) and earns the **Strength Phase** by sustaining the habit and progressing their movements.
At launch no user has earned the Strength Phase, so the MVP ships the Discipline-Phase experience with the `PhaseEvaluator` already in place.

The MVP runs entirely on an Apple-native stack with no custom backend.
AI/LLM features are deferred to Phase 2 and, when they arrive, do language only (summaries, weekly narratives) - they never generate or adapt a workout.

**Status:** clean rebuild in progress.
The previous Phase 2 app (XP/badges/streaks, AI services, SwiftData) was removed and lives only in git history (commit `23fd56f`) as reference.
Work proceeds story-by-story against the PRD (see below).

## Source of Truth

- **Strategic plan:** `.claude/agent/tasks/FitSnack-PRD-v5.md` - the discipline-first vision, domain concepts, engine design, and phase model.
- **Implementation PRD / progress tracker:** `.claude/agent/tasks/prd-fitsnack-mvp_0626.md` - 30 user stories (US-A01 … US-J04) with acceptance criteria and validation tests.
  As each story is completed, its acceptance-criteria checkboxes are flipped to `[x]` so the PRD doubles as a live progress tracker.
- Always check the PRD for the relevant story before building a feature.

Note: the v5 plan references a `CONTEXT.md` and `docs/adr/` that are not present in this repo; treat the two files above as authoritative.

## Build & Run

```bash
# Generate Xcode project from project.yml (requires xcodegen)
cd ios/FitSnack && xcodegen generate

# Build
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build

# Run tests (the FitSnack scheme runs the FitSnackTests target)
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# Open in Xcode
open ios/FitSnack/FitSnack.xcodeproj
```

There is a single scheme, `FitSnack`, which builds the app and runs the tests.
If xcodebuild cannot resolve the destination, list installed simulators with `xcrun simctl list devices available` and pass `-destination 'id=<UDID>'`.

Target: iOS 17.0+, Swift 5.9, Xcode 16.3. Bundle ID: `com.fitsnack.app`.

## Architecture

**Monorepo:**
- `ios/` - the SwiftUI app (the entire MVP).
- `convex/` - empty placeholder (`.gitkeep`); the MVP has no custom backend.
- A minimal API-key proxy (Cloudflare/Wrangler) for the deferred Phase 2 LLM language features is **not part of the MVP** and will be added when those features land.

**MVVM + Protocol-Based Services:**
- **Views** access services via `@Environment(\.services)` (a custom `EnvironmentKey`).
- **ViewModels** are `@Observable` classes (Observation framework, never `ObservableObject`/`@Published`).
- **Services** are protocol-defined (`Services/Protocols/`) with mock implementations (`Services/Mock/`).
- **ServiceContainer** (`DI/ServiceContainer.swift`) holds all service instances, injected at the app root.

To swap a mock for a real implementation, change one line in `ServiceContainer` - views and viewmodels remain untouched.

**Persistence:** CoreData backed by `NSPersistentCloudKitContainer` (entities `CDUser`, `CDWorkoutLog`).
Domain models are plain `Codable` structs; CoreData entities convert via `toUser()`/`update(from:)`-style methods, with complex nested fields stored as JSON-encoded `Data`.
The core loop works fully offline and with no iCloud account; CloudKit handles sync and backup when available.

**Apple-native integrations:** Sign in with Apple (identity), CloudKit (private DB sync), HealthKit (on-device workout writes), StoreKit 2 (free unlimited core + premium depth).
No hosting cost; an Apple Developer account is required.

**Navigation:** `AppState` (`@Observable`, persisted to UserDefaults) controls onboarding vs. the main app and the selected tab.

## The Deterministic Engine

Pure Swift, on-device, no network, no LLM, instant (latency target <100ms).
The pipeline (one step per Epic C story in the PRD):

1. **Session shape** - 5-10 min single-focus; 15 min blend (light); 20-30 min blend (full).
2. **Pillar balance** - choose the stalest pillar by days-since-worked; bias short sessions toward mobility when the user sits 6+ hours.
3. **Movement-pattern focus** - rank patterns by staleness; never repeat yesterday's primary pattern.
4. **Filter pool** - drop by phase, injuries, difficulty cap, recent skips; everything is bodyweight (Zero-Equipment Floor).
5. **Progression-chain selection** - pick the user's current chain position; offer the next when advancement criteria are met; avoid the last 3 sessions.
6. **Adaptive Overload** - prescribe capacity-relative reps/sets/holds, never a fixed heroic number; feedback (`too_easy`/`too_hard`) adjusts within one cycle.
7. **Assemble + fit timing** - always open with a warm-up, add a cooldown over 10 min, land within ±1 min of requested time.

In-session **swap** substitutes deterministically within the same pillar, pattern, difficulty band, and time budget.

## Consistency & Phase (no gamification)

There is no XP, no levels, and no badges in the MVP (deferred to Phase 2, and kept off the core loop).
The fragile streak is replaced by a forgiving system:

- **Consistency Score** - a rolling, weighted measure of showing up.
  `weeklyAdherence = min(1, workoutsCompleted / weeklyGoal)`; the score is a weighted rolling average × 100, recent weeks weighted more.
  A 5-minute session counts as a full show-up; a single miss dents the score but never zeroes it.
  `longestChain` is tracked and surfaced as an earned point of pride, never as a threat.
  All copy is identity-framed ("you're someone who moves"), never loss-framed.
- **PhaseEvaluator** - deterministic, never user-selectable.
  A user reaches the Strength Phase only when both consistency (sustained score over a rolling window) and competence (cleared the entry tiers of the foundational chains) hold.
  All MVP users resolve to the Discipline Phase.

## Key Conventions

- Use `@Observable` (Observation framework), never `ObservableObject`/`@Published`.
- All service methods are `async throws`.
- Enums conform to `Codable`, `CaseIterable`, and `Identifiable` where they have a stable id.
- Design system tokens via `Theme.Colors`, `Theme.Typography`, `Theme.Spacing` - always use these, never hardcode colors/fonts/spacing.
- Button height: 56pt. Card corner radius: 16pt. Touch targets: 44pt minimum (60pt on active workout screens).
- Exercise library: 42 bodyweight movements in `Resources/Exercises.json`, all `equipment == []` (Zero-Equipment Floor); loaded once, cached, and load-time-validated by `MockExerciseService` (US-B02, which throws a descriptive `ExerciseLibraryError` on a malformed library), with the data's shape independently gated by `ExerciseLibraryTests`.
- Accessibility throughout: VoiceOver, Dynamic Type, Reduce Motion (static demo fallback), haptics with an audio alternative.

## Project Structure (ios/FitSnack/FitSnack)

```
App/            App entry point (FitSnackApp.swift)
DesignSystem/   Theme tokens (Theme.swift)
Models/         Domain enums and Codable structs
Persistence/    CoreData stack (NSPersistentCloudKitContainer) + conversions
Services/       Service implementations
  Protocols/    Service protocol definitions
  Mock/         Mock implementations wired in ServiceContainer
  Engine/       Deterministic workout-engine pipeline steps (pure, on-device)
DI/             ServiceContainer + environment injection
ViewModels/     @Observable view models
Views/          SwiftUI screens (Onboarding, Home, Active session, Post-session, Progress)
Utilities/      AppState and shared helpers
Resources/      Exercises.json, Assets.xcassets, animations
```

As of the current clean rebuild, the US-A01 scaffold (App, DesignSystem, RootView, Assets), the US-A02 canonical domain enums (`Models/Enums.swift`), the US-A03 domain model structs (`Models/Exercise.swift`, `User.swift`, `Workout.swift`, `WorkoutLog.swift`), the US-A04 CoreData stack (`Persistence/`: `FitSnack.xcdatamodeld`, `PersistenceController`, `CDUser`/`CDWorkoutLog` + conversions, `MockPersistence`), the US-A05 app shell (`Services/Protocols/ServiceProtocols.swift`, `Services/Mock/MockServices.swift`, `DI/ServiceContainer.swift`, `Utilities/AppState.swift`, and onboarding-vs-main-tabs routing in `Views/RootView.swift`), the US-B01 bundled exercise library (`Resources/Exercises.json`, 42 zero-equipment movements with valid progression chains), the US-B02 exercise service (`Services/Mock/MockExerciseService.swift`: loads/caches/validates the library, throws `ExerciseLibraryError`, and answers the by-pillar/pattern/phase/difficulty-range and next-in-chain queries), the US-C01 engine Step 1 (`Services/Engine/SessionShapeSelection.swift`: the pure `SessionShapeTemplate.select(requestedMinutes:)` that maps minutes to single-focus / blend-light / blend-full and resolves back to the canonical `SessionShape`), the US-C02 engine Step 2 (`Services/Engine/PillarBalance.swift`: `PillarStaleness` computes days-since-worked per pillar from the logs, and `PillarPlan.select` picks the stalest pillar for single-focus - with a desk-worker mobility lean - or staleness-weighted time shares for a blend), and the US-C03 engine Step 3 (`Services/Engine/MovementPatternFocus.swift`: `PatternStaleness` computes days-since-worked per movement pattern, and `PatternFocus.rank`/`select` rank the chosen pillar's candidate patterns stalest-first and pick the lead pattern - holding back the most recent session's lead pattern so it is never repeated back-to-back, while honoring an explicit request), the US-C04 engine Step 4 (`Services/Engine/ExercisePoolFilter.swift`: `InjuryContraindication` maps onboarding injury tags to contraindicated movement patterns, and `ExercisePoolFilter.eligiblePool` removes phase-gated / injury-unsafe / over-cap / repeatedly-skipped movements while enforcing the Zero-Equipment Floor, with `pool(forPattern:)` falling back to the safest bodyweight option - or reporting `.noSafeOption` - when filtering empties a needed pattern), and the US-C05 engine Step 5 (`Services/Engine/ProgressionChainSelection.swift`: `AdvancementCriteria` parses an exercise's free-text `advancementCriteria` and checks it against logged performance, `ProgressionChainSelection.selectInChain` finds the user's frontier tier - the highest-order tier worked - and offers the next tier only when its criteria are cleared and that tier is still eligible, never leaping past an un-cleared or gated tier and defaulting a no-history user to the chain entry, and `select(pattern:)` integrates every chain for a pattern with the no-repeat-last-3 variety rule and an active-chain preference) exist; only `ViewModels/` is still empty.
The app root (`FitSnackApp`) injects the CoreData view context, the `ServiceContainer` (via `\.services`), and `AppState`; the CoreData stack is local-only until CloudKit sync lands in US-J02.
The rest lands story-by-story per the PRD.

## Testing

Tests live in `ios/FitSnack/FitSnackTests/`. Pattern: `XCTestCase` + `@testable import FitSnack`.
All new logic must have corresponding tests.

Current and planned coverage (added as the owning story lands):

| Area | Coverage |
|------|----------|
| Scaffold (`ScaffoldTests`) | Design-token values (button/card/touch sizes) |
| Models / enums | Codable round-trips, stable raw values |
| Exercise library (`ExerciseLibraryTests`) | Bundled `Exercises.json` decodes; per-pattern/pillar counts, contiguous progression chains with resolving links, Zero-Equipment Floor, phase gating, hold/rep field contract |
| Exercise service (`ExerciseServiceTests`) | Real library loads/caches; by-pillar/pattern/phase/difficulty-range and next-in-chain queries; each validation rule (duplicate id, equipment floor, dangling chain link, non-contiguous chain) throws a descriptive `ExerciseLibraryError` from a broken fixture; missing-resource and decode failures |
| Engine - session shape (`SessionShapeSelectionTests`) | `SessionShapeTemplate.select` maps 5/10/15/20/30 and the 10/15/20 boundaries to single-focus / blend-light / blend-full, is deterministic, and resolves to the canonical `SessionShape` |
| Engine - pillar balance (`PillarBalanceTests`) | `PillarStaleness` days-since-worked (most-recent wins, skips excluded, never-worked nil); single-focus stalest-pillar selection, the `sitsLong` mobility lean and its strong-staleness exception, no-history defaults; blend weights split by relative staleness with both pillars always included |
| Engine - movement pattern (`MovementPatternFocusTests`) | `PatternStaleness` days-since-worked per pattern (most-recent wins, skips excluded, never-worked nil); `rank` stalest-first with never-worked most stale and canonical tie-break; `select` no-repeat of the recent session's lead pattern (isolated from staleness, window-bounded, pillar-aware), explicit-request override, no-history default, single-candidate fallback, determinism |
| Engine - exercise pool filter (`ExercisePoolFilterTests`) | `InjuryContraindication` tag -> pattern mapping (case/plural/separator-insensitive normalization, unknown-tag no-op, multi-injury union); each filter rule independently (phase gate, fitness-level difficulty cap, injury, recent-skip > 3, equipment floor) and combined (US-C04 validation case); per-pattern fallback (relaxed soft filters picks the safest option, injury/phase-gated empty pattern reports `.noSafeOption`); determinism / library-order preservation |
| Engine - progression chain (`ProgressionChainSelectionTests`) | `AdvancementCriteria` parses `NxM` / standalone / hold-seconds and is-met checks (reps and holds, qualifying-set count); `selectInChain` no-history entry, frontier = highest-order worked, advance only when cleared, no leap past an un-cleared tier, no advance onto an ineligible/gated next tier, clamp when the frontier tier is ineligible, skipped-work excluded; `select(pattern:)` no-repeat-last-3 variety, active-chain preference, no-history gentlest entry, determinism; PRD validation (cleared knee push-ups -> standard push-up) over the real library |
| Engine - remaining steps | Adaptive Overload, timing fit, swap |
| Consistency Score | Empty history, perfect run, single-miss dent (not zero), 5-min show-up, rolling weighting |
| PhaseEvaluator | Consistency-only and competence-only stay Discipline; both-met promotes; fresh user Discipline |
| Persistence | Save/fetch round-trips for `CDUser` and `CDWorkoutLog` |
| App shell (`AppStateTests`, `ServiceContainerTests`) | `AppState` defaults, UserDefaults persistence, invalid-tab fallback; mock `ServiceContainer` resolves every service |

## Out of Scope (MVP Non-Goals)

No LLM/AI calls (summaries are template-based in MVP); no custom backend; no XP/levels/badges; no social/leaderboards/challenges; no equipment-based exercises; no full Strength-Phase catalog; no Android/widgets/Live Activities/Apple Watch.
See the PRD's Non-Goals section for the full list.

## Artifact Locations

Conventional paths for work products. Only `.claude/agent/tasks/` exists today; the `artifacts/` subdirectories are created on demand as work produces them.

| Artifact | Path |
|----------|------|
| Strategic plan + implementation PRDs / task briefs | `.claude/agent/tasks/` |
| Engineering / QA reports | `artifacts/reports/` |
| Test results | `artifacts/reports/test-results/` |
| Specs / briefs | `artifacts/specs/` |
| Learning logs | `artifacts/learning-logs/` |
