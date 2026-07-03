# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FitSnack is a discipline-first micro-workout iOS app (5-60 min sessions) for busy, desk-bound adults.
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

- **Strategic plan:** `.claude/agent/tasks/FitSnack-PRD-v6_070226.md` (v6.0, reconciled to ADRs 0001-0019) - the discipline-first vision plus the v6 wedge: a daily-adaptive AI Programmer that writes a per-user Session Policy the deterministic engine runs on. Supersedes `FitSnack-PRD-v5.md` (kept for reference).
- **Implementation PRD / progress tracker:** `.claude/agent/tasks/prd-fitsnack-mvp-v6_0702.md` - the comprehensive v6 MVP as ~51 user stories (US-A01 … US-N05) with acceptance criteria and validation tests. Epics A-C are built; D-N are new or reframed under v6. Supersedes `prd-fitsnack-mvp_0626.md` (v5, kept for reference).
  As each story is completed, its acceptance-criteria checkboxes are flipped to `[x]` so the PRD doubles as a live progress tracker.
- Always check the PRD for the relevant story before building a feature.

Note: the strategic plans reference a `CONTEXT.md` and `docs/adr/` that are not present in this repo; treat the two task files above as authoritative.

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

**Persistence:** CoreData backed by `NSPersistentCloudKitContainer` (entities `CDUser`, `CDWorkoutLog`, `CDSessionPolicy`).
Domain models are plain `Codable` structs; CoreData entities convert via `toUser()`/`update(from:)`-style methods, with complex nested fields stored as JSON-encoded `Data`.
The core loop works fully offline and with no iCloud account; CloudKit handles sync and backup when available.

**Apple-native integrations:** Sign in with Apple (identity), CloudKit (private DB sync), HealthKit (on-device workout writes), StoreKit 2 (free unlimited core + premium depth).
No hosting cost; an Apple Developer account is required.

**Navigation:** `AppState` (`@Observable`, persisted to UserDefaults) controls onboarding vs. the main app and the selected tab.

## The Deterministic Engine

Pure Swift, on-device, no network, no LLM, instant (latency target <100ms).
The pipeline (one step per Epic C story in the PRD):

1. **Session shape** - 5-10 min single-focus; 11-20 min blend (light); 21-40 min blend (full); 41-60 min blend (extended).
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

As of the current clean rebuild, the US-A01 scaffold (App, DesignSystem, RootView, Assets), the US-A02 canonical domain enums (`Models/Enums.swift`), the US-A03 domain model structs (`Models/Exercise.swift`, `User.swift`, `Workout.swift`, `WorkoutLog.swift`), the US-A04 CoreData stack (`Persistence/`: `FitSnack.xcdatamodeld`, `PersistenceController`, `CDUser`/`CDWorkoutLog` + conversions, `MockPersistence`), the US-A05 app shell (`Services/Protocols/ServiceProtocols.swift`, `Services/Mock/MockServices.swift`, `DI/ServiceContainer.swift`, `Utilities/AppState.swift`, and onboarding-vs-main-tabs routing in `Views/RootView.swift`), the US-B01 bundled exercise library (`Resources/Exercises.json`, 42 zero-equipment movements with valid progression chains), the US-B02 exercise service (`Services/Mock/MockExerciseService.swift`: loads/caches/validates the library, throws `ExerciseLibraryError`, and answers the by-pillar/pattern/phase/difficulty-range and next-in-chain queries), the US-C01 engine Step 1 (`Services/Engine/SessionShapeSelection.swift`: the pure `SessionShapeTemplate.select(requestedMinutes:)` that maps requested minutes to a session-shape template and resolves back to the canonical `SessionShape` - extended to the full 5-60 min range in US-E01), the US-C02 engine Step 2 (`Services/Engine/PillarBalance.swift`: `PillarStaleness` computes days-since-worked per pillar from the logs, and `PillarPlan.select` picks the stalest pillar for single-focus - with a desk-worker mobility lean - or staleness-weighted time shares for a blend), and the US-C03 engine Step 3 (`Services/Engine/MovementPatternFocus.swift`: `PatternStaleness` computes days-since-worked per movement pattern, and `PatternFocus.rank`/`select` rank the chosen pillar's candidate patterns stalest-first and pick the lead pattern - holding back the most recent session's lead pattern so it is never repeated back-to-back, while honoring an explicit request), the US-C04 engine Step 4 (`Services/Engine/ExercisePoolFilter.swift`: `InjuryContraindication` maps onboarding injury tags to contraindicated movement patterns, and `ExercisePoolFilter.eligiblePool` removes phase-gated / injury-unsafe / over-cap / repeatedly-skipped movements while enforcing the Zero-Equipment Floor, with `pool(forPattern:)` falling back to the safest bodyweight option - or reporting `.noSafeOption` - when filtering empties a needed pattern), the US-C05 engine Step 5 (`Services/Engine/ProgressionChainSelection.swift`: `AdvancementCriteria` parses an exercise's free-text `advancementCriteria` and checks it against logged performance, `ProgressionChainSelection.selectInChain` finds the user's frontier tier - the highest-order tier worked - and offers the next tier only when its criteria are cleared and that tier is still eligible, never leaping past an un-cleared or gated tier and defaulting a no-history user to the chain entry, and `select(pattern:)` integrates every chain for a pattern with the no-repeat-last-3 variety rule and an active-chain preference), and the US-C06 engine Step 6 (`Services/Engine/AdaptiveOverload.swift`: `AdaptiveOverload.target` reads the user's demonstrated capacity for the selected exercise from the most recent usable log - the worked set count and the rounded average per-set reps/hold-seconds - and prescribes a capacity-relative `OverloadTarget`, applying that session's `perceivedDifficulty` within one cycle (`tooHard` eases below capacity, `tooEasy` pushes above, `justRight`/unrated nudges progressively up, with the per-cycle bump curve as tunable constants), clamping the per-set target and set count to safety rails so a target is never a fixed heroic number, and falling back to the exercise's own `defaultReps`/`defaultDurationSeconds` when there is no usable history), and the US-C07 engine Step 7 (`Services/Engine/SessionAssembly.swift`: `SessionAssembly.assemble` chains Steps 1-6 over the eligible pool and assembles a fully-formed, playable `Workout` - always opening with a `.warmup` block, closing sessions over 10 min with a `.cooldown`, and structuring training blocks per the Step 1 shape - then a deterministic best-fit `fit` pass adds/drops whole exercises or individual sets, never the capacity-relative per-set target, until the planned `Σ(sets × est) + rests + transitions` wall-clock lands within ±1 min of the request; `MockWorkoutEngine` now drives this assembler with the validated library from the exercise service), and the US-C08 deterministic swap (`Services/Engine/ExerciseSwap.swift`: `ExerciseSwap.swap` returns a `SwapOutcome` - either an equivalent substitute drawn from the eligible pool (same pillar and pattern, within a ±1 `difficultyBandWidth`, inside the `slotToleranceSeconds` time budget, never duplicating a movement already in the session, carrying a fresh capacity-relative per-set target while preserving the original slot's set count and rest) or `.noAlternative` when no safe in-budget peer exists - exposed through `WorkoutEngineProtocol.swapExercise` and wired in `MockWorkoutEngine`) exist; with the Epic C engine pipeline (Steps 1-7 + swap) complete, only `ViewModels/` is still empty.
The v6 Epic D data foundation has begun: US-D01 (`Models/User.swift`) adds the nested `User.Why` (`statement` + optional `openingBias` pillar), `User.Duration` (`defaultMinutes`/`onboardingSeedMinutes`/`completedDurationEWMA`, with a `seeded(minutes:)` factory so `defaultMinutes == onboardingSeedMinutes`), and `User.ColdStart` (`sessionsLogged`/`active`, with a `.fresh` default) value types as three new top-level `User` fields - `primaryGoal` and the `UserProfile` shape are unchanged - each persisted as its own JSON-encoded `Data` column on `CDUser` (`whyData`/`durationData`/`coldStartData`) that decodes to documented defaults (empty `why`, duration seeded from `profile.typicalAvailableMinutes`, a fresh cold-start) when absent, so a pre-v6 record still loads.
US-D02 (`Models/WorkoutLog.swift`) adds `requestedMinutes: Int` (what the Ready Screen offered or the user set) and `wasReturn: Bool` (defaulting to `false`) as two new top-level `WorkoutLog` fields, and documents the existing `durationMinutes` as the actually-completed duration that feeds `duration.completedDurationEWMA` - the requested-vs-completed gap is the input Default Duration learning and the Disengagement signal read, and `wasReturn` marks a post-gap Return for the Re-entry Ramp; both persist as additive optional `NSNumber?` columns on `CDWorkoutLog` (`requestedMinutes`/`wasReturn`) that decode to documented defaults (`requestedMinutes == durationMinutes`, `wasReturn == false`) when absent, so a pre-v6 log still loads.
US-D03 (`Models/SessionPolicy.swift`) defines the always-valid `SessionPolicy` - `version`/`updatedAt`/`updatedBy` (`default`/`deterministic`/`llm`)/`progressionRate`/`pillarWeighting: [Pillar: Double]`/`varietyWindow` plus optional `coldStartContract` (`forceContrastSpread`, `cappedMaxDifficulty` in 1...5), `reentry` (`rampSessionsRemaining`), and `note` (`text` + `template`/`llm` `source`) - the single seam the AI Programmer (Epic F) writes and the engine (Epic E) reads; `SessionPolicy.default` is a deterministic, neutral starting policy (version 1, a fixed `unprogrammedEpoch` timestamp, progression 1.0, equal `1.0` weighting across all three pillars via `neutralPillarWeighting`, variety window 3, no situational overrides) that reproduces pre-policy engine behavior exactly, and it persists whole (JSON-encoded) as `CDSessionPolicy`, keyed by `userId` and overwritten in place so the last-written policy survives relaunch and offline use.
US-D04 (`Models/ReprogramTrigger.swift`, `Services/Protocols/ServiceProtocols.swift`, `Services/Mock/MockServices.swift`, `DI/ServiceContainer.swift`) opens the AI Programmer <-> engine seam: the new `ReprogramTrigger` value type carries a `kind` (`weekly_boundary`/`return`/`physical_stall`/`disengagement`, stable snake-case raw values) and an injected `detectedAt`, and the new `SessionPolicyServiceProtocol` (`currentPolicy(for:)`, `reprogram(user:recentLogs:trigger:)`, `dueTriggers(user:recentLogs:asOf:)`, all `async throws`) is the one seam the Programmer (Epic F) writes and the engine (Epic E) reads; `MockSessionPolicyService` hands back `SessionPolicy.default` for both policy calls and never reports a due trigger (real detection/re-weighting land in US-F01/US-F03), and it is wired into `ServiceContainer`/`.mock()`; `WorkoutEngineProtocol.generateWorkout(...)` gains a `sessionPolicy:` parameter that `MockWorkoutEngine` accepts at the seam but does not yet thread into `SessionAssembly` (that lands in US-E03, where `SessionPolicy.default`'s neutral levers keep output identical to pre-policy behavior).
US-E01 (`Services/Engine/SessionShapeSelection.swift`, `Services/Engine/PillarBalance.swift`) begins the v6 Epic E engine extensions: `SessionShapeTemplate.select` now shapes the full 5-60 min request range with four buckets - `5-10 -> singleFocus`, `11-20 -> blendLight`, `21-40 -> blendFull`, `41-60 -> blendExtended` (the new extended-blend case) - clamping out-of-range requests into a `5...60` `supportedRange` so the mapping stays total, pure, and deterministic; every blend (including `blendExtended`) still resolves to the canonical `.blend` `SessionShape` and `PillarPlan.select` treats `blendExtended` like the other blends, so the reclassified 20-min session (now `blendLight` rather than `blendFull`) is behavior-neutral downstream; the dedicated extended primal block lands in US-E02.
US-E02 (`Services/Engine/PillarBalance.swift`, `Services/Engine/SessionAssembly.swift`) promotes primal to a first-class pillar: `PillarWeights` gains a `primal` share and `PillarPlan.select` splits an extended blend across all three pillars (each kept above `minExtendedBlendShare`, the rest apportioned by weighted staleness so the shares always sum to 1) while short/full blends keep `primal == 0` (folded into strength as before, no regression); `select` also takes a `pillarWeighting: [Pillar: Double]` staleness multiplier (defaulting to `SessionPolicy.neutralPillarWeighting`, a no-op) so primal selection respects `sessionPolicy.pillarWeighting[.primal]` - the live policy is threaded through `assemble` in US-E03. In assembly, a `blendExtended` session now builds a dedicated `.primal` block from the `locomotion` pattern / `pillar == .primal` (via the same Steps 5-6 chain selection + Adaptive Overload as the strength block, Zero-Equipment Floor and difficulty gating intact), sheds primal from the strength block so no locomotion movement is double-booked, and orders the up-to-three training blocks staler-pillar-first; the block gracefully degrades to strength + mobility when the pool has no eligible primal movement.
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
| Engine - session shape (`SessionShapeSelectionTests`) | `SessionShapeTemplate.select` maps 5/10/15/20/30/45/60 and the 10/20/40 boundaries to single-focus / blend-light / blend-full / blend-extended across the full 5-60 range, clamps out-of-range requests to the `5...60` supported range, is deterministic, and resolves every blend to the canonical `.blend` `SessionShape` |
| Engine - pillar balance (`PillarBalanceTests`) | `PillarStaleness` days-since-worked (most-recent wins, skips excluded, never-worked nil); single-focus stalest-pillar selection, the `sitsLong` mobility lean and its strong-staleness exception, no-history defaults; two-pillar blend weights split by relative staleness with both pillars always included; extended blend (US-E02) splits all three pillars (even split with no history, leans toward a stale primal, never starves a pillar below `minExtendedBlendShare`, shares sum to 1, primal `pillarWeighting` measurably increases primal's share) while short/full blends keep primal at 0 |
| Engine - movement pattern (`MovementPatternFocusTests`) | `PatternStaleness` days-since-worked per pattern (most-recent wins, skips excluded, never-worked nil); `rank` stalest-first with never-worked most stale and canonical tie-break; `select` no-repeat of the recent session's lead pattern (isolated from staleness, window-bounded, pillar-aware), explicit-request override, no-history default, single-candidate fallback, determinism |
| Engine - exercise pool filter (`ExercisePoolFilterTests`) | `InjuryContraindication` tag -> pattern mapping (case/plural/separator-insensitive normalization, unknown-tag no-op, multi-injury union); each filter rule independently (phase gate, fitness-level difficulty cap, injury, recent-skip > 3, equipment floor) and combined (US-C04 validation case); per-pattern fallback (relaxed soft filters picks the safest option, injury/phase-gated empty pattern reports `.noSafeOption`); determinism / library-order preservation |
| Engine - progression chain (`ProgressionChainSelectionTests`) | `AdvancementCriteria` parses `NxM` / standalone / hold-seconds and is-met checks (reps and holds, qualifying-set count); `selectInChain` no-history entry, frontier = highest-order worked, advance only when cleared, no leap past an un-cleared tier, no advance onto an ineligible/gated next tier, clamp when the frontier tier is ineligible, skipped-work excluded; `select(pattern:)` no-repeat-last-3 variety, active-chain preference, no-history gentlest entry, determinism; PRD validation (cleared knee push-ups -> standard push-up) over the real library |
| Engine - adaptive overload (`AdaptiveOverloadTests`) | `AdaptiveOverload.target` no-history rep/hold defaults (exercise-specific, not a constant) and empty/zero-set fallback; progressive bump from capacity (unrated and `justRight`); `tooHard` ease below / `tooEasy` push above capacity, both within one cycle, with guaranteed direction on small capacities and the rep floor honored; hold logic in seconds; capacity-relative (different capacities -> different targets), most-recent-usable performance wins, skipped-work excluded, determinism; PRD validation (3x12 squats marked `too_hard` eased) over the real library |
| Engine - session assembly (`SessionAssemblyTests`) | `SessionAssembly.assemble` runs Steps 1-6 end-to-end over the real library: every session opens with a `.warmup` block (mobility-led too); a `.cooldown` closes only sessions over 10 min; `plannedSeconds` (`Σ(sets × est) + rests + transitions`) lands within ±1 min for 5/10/15/20/30 (history and fresh-user); sub-100ms latency; fully-formed, capacity-relative output (rep xor hold per `isHold`, sets >= 1, equipment floor, no cross-block repeats); structural determinism; a blend sizes its two training blocks by the Step 2 pillar weights (the staler pillar's block owns more planned time, both directions); a blend cooldown reserves more than one static hold (holds-only honored); an extended blend (US-E02) carves out a dedicated `.primal` block (`pillar == .primal`, `locomotion`, equipment floor) alongside strength + mobility and never folds primal back into the strength block, while 10/20/30-min shapes carve out no primal block (no regression), all deterministically; PRD validation (intermediate user, some history, 20 min -> warm-up first, cooldown last, 19-21 min, <100ms) |
| Engine - exercise swap (`ExerciseSwapTests`) | `ExerciseSwap.swap` valid swap stays within pillar/pattern/difficulty band and the slot time budget (PRD validation over the real library); substitute is bodyweight, discipline-phase, and carries a capacity-relative per-set target; injury-respecting (a shoulder-injured push slot refuses rather than offering an unsafe peer; a knee injury leaves a push swap intact); no-alternative cases (lone peer, phase-gated peer, out-of-budget peer); never duplicates a movement already in the session; preserves the slot's set count and rest; determinism |
| Consistency Score | Empty history, perfect run, single-miss dent (not zero), 5-min show-up, rolling weighting |
| PhaseEvaluator | Consistency-only and competence-only stay Discipline; both-met promotes; fresh user Discipline |
| Session policy (`SessionPolicyTests`) | `SessionPolicy.default` documented values / determinism / equal weighting of all three pillars; Codable round-trips (default, fully-populated, LLM note, `[Pillar: Double]` intact); `updatedBy`/`note.source` raw-value pins |
| Reprogram trigger (`ReprogramTriggerTests`) | `ReprogramTrigger.Kind` raw-value pins (the four PRD kinds) and case count; `id` is the kind raw value; Codable round-trip for every kind with `detectedAt` intact |
| Session policy service (`SessionPolicyServiceTests`) | `MockSessionPolicyService` returns `SessionPolicy.default` from `currentPolicy` and `reprogram` (every trigger kind) and an empty `dueTriggers` for a fresh user |
| Persistence | Save/fetch round-trips for `CDUser` and `CDWorkoutLog`; `CDSessionPolicy` default/fully-populated round-trip, in-place overwrite, `userId` scoping, loud failure on a missing blob |
| App shell (`AppStateTests`, `ServiceContainerTests`) | `AppState` defaults, UserDefaults persistence, invalid-tab fallback; mock `ServiceContainer` resolves every service (including the session-policy service, whose `currentPolicy` is the default and `dueTriggers` empty) |

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
