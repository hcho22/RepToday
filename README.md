# FitSnack - Discipline-First Micro-Workout App

**Open the app. Tell it how many minutes you have. Press play.**

FitSnack is an iOS app for busy, desk-bound adults who can give exercise 5-60 minutes a day.
It exists to build one thing: the discipline of showing up.
The user says how many minutes they have, and a deterministic on-device engine generates a complete zero-equipment session that blends bodyweight strength and mobility.
No browsing, no choosing, no thinking.

> **Status:** clean rebuild in progress.
> The previous app (XP/badges/streaks, AI services, SwiftData) was removed and lives only in git history as reference.
> Work proceeds story-by-story against the PRD; today the US-A01 scaffold, US-A02 domain enums, US-A03 domain models, the US-A04 CoreData stack, the US-A05 app shell (service container and app state), the US-B01 bundled exercise library, the US-B02 exercise service (loads, validates, and queries the library), the US-C01 engine Step 1 (session-shape selection from requested minutes), the US-C02 engine Step 2 (pillar balance by staleness), the US-C03 engine Step 3 (movement-pattern focus by staleness, never repeating yesterday's lead pattern), the US-C04 engine Step 4 (exercise-pool filtering by phase, injuries, difficulty cap, and recent skips, with a safe bodyweight fallback when a needed pattern empties), the US-C05 engine Step 5 (progression-chain selection: pick the user's current chain position, offer the next tier only when its advancement criteria are met, and avoid the last 3 sessions for variety), the US-C06 engine Step 6 (Adaptive Overload: prescribe capacity-relative rep/set/hold targets from the user's demonstrated capacity, easing or intensifying within one cycle from the last session's perceived difficulty, never a fixed heroic number), the US-C07 engine Step 7 (session assembly and timing fit: chain Steps 1-6 into a fully-formed, playable session that opens with a warm-up, adds a cooldown over 10 min, and lands within ±1 min of the requested time), the US-C08 deterministic swap (an in-session substitute for one prescribed slot within the same pillar, pattern, and difficulty band that fits the same time budget, or a clear "no alternative" result when no safe peer fits), and the v6 Epic D data foundation - US-D01 (the `User` model's `why`/`duration`/`coldStart` fields) and US-D02 (the `WorkoutLog` model's `requestedMinutes`/`wasReturn` fields), both additive and backward-compatible so pre-v6 records still load, plus US-D03 (the always-valid `SessionPolicy` and its neutral `SessionPolicy.default`, persisted as `CDSessionPolicy`) and US-D04 (the `ReprogramTrigger` type and the `SessionPolicyServiceProtocol` seam between the AI Programmer and the engine), and the v6 Epic E engine extensions US-E01 (engine Step 1 now shapes the full 5-60 min range: 5-10 single-focus, 11-20 blend-light, 21-40 blend-full, 41-60 the new extended blend, every blend resolving to the canonical shape), US-E02 (primal promoted to a first-class pillar - the longest 41-60 min extended blend now earns a dedicated primal block instead of folding primal into strength), US-E03 (the deterministic engine now consumes the per-user Session Policy - its `pillarWeighting`, `varietyWindow`, and `progressionRate` levers scale Step 2's pillar staleness, Step 5's no-repeat window, and Step 6's overload bump, while `SessionPolicy.default` reproduces pre-policy output exactly), US-E04 (the engine's Step 0 cold-start override caps a brand-new user's first sessions at the policy's Starting Difficulty and forces a vivid First-Week Contrast spanning strength/mobility/primal, a no-op once the user warms up so a settled user runs exactly the US-E03 pipeline), US-E05 (the Asymmetric Ramp tunes Step 6's bump curve to back off fast and climb slow: a recent `too_hard` or a skip eases the next target eagerly while `too_easy` climbs only patiently, the down-step always at least as large as the up-step), and US-E06 (the Return override and Re-entry Ramp: a gap of 7+ days serves an easy, winnable session - mobility-led, difficulty-capped, volume eased - regardless of staleness, then the Re-entry Ramp walks difficulty back up over the following sessions, the readjustment never loaded onto the Return itself), and the complete v6 Epic F AI Programmer - US-F01 (on-device, deterministic re-program trigger detection with Trigger Precedence: on open the client learns which of `weekly_boundary`/`return`/`physical_stall`/`disengagement` are due in precedence order, with `disengagement` suppressing `physical_stall` so a user pulling away is never handed more challenge), US-F02 (plateau diagnosis: a pure function that tells a physical stall - capacity earned but gated - apart from disengagement - pulling away - and maps each to explicit Session Policy levers, raising `progressionRate`/variety on a stall and easing them on disengagement, clamped to safety rails, with the same Trigger Precedence so a disengaging user is never handed more challenge), US-F04 (Default Duration learning - an EWMA of completed, not requested, minutes that snaps the Ready-Screen default to a valid chip so it tracks what the user actually finishes - plus the honest templated policy note that names only the change the diff actually shows and never invokes the user's `why`), and US-F03 (the real, persistence-backed `DeterministicSessionPolicyService` that composes those four pure pieces into the `SessionPolicyServiceProtocol`: it re-diagnoses the trigger so Trigger Precedence holds end-to-end, seeds the `reentry` ramp on a Return, folds Default Duration learning over only the non-Return sessions since the last write, writes the honest note, and persists the policy - `CDSessionPolicy` in the running app - and the learned duration, never generating a workout), and the complete v6 Epic G (cold start & Variety Language) - US-G01 (the deterministic cold-start Starting Difficulty seed onboarding will call, mapping the self-reported fitness level to a provisional capped band - beginner 2, intermediate 3, advanced 4 - layered onto the neutral `SessionPolicy.default` and moving no other lever) US-G02 (the First-Week Contrast enforcement contract - proving the seeded `forceContrastSpread` flag makes a brand-new user's first week visibly span strength/mobility/primal with no pillar repeating back-to-back, even for a desk worker whose staleness bias alone would collapse the week to all-mobility), and US-G03 (the Variety Language slice - a short, honest line naming today's session and its contrast with the last one, "Today's a mobility day - yesterday was strength", read straight off the engine's own output with a deterministic template that is always the offline-safe fallback for the deferred day-one LLM upgrade), and US-G04 (the cold-start handoff - the one-way retirement that, after 5 completed sessions, flips `coldStart.active` off and clears the policy's `coldStartContract` so the Step 0 overrides retire and the self-driving engine drives sessions unassisted via staleness and Adaptive Overload) - exist.

---

## Why FitSnack?

Most fitness apps assume you have an hour to spare and the mental bandwidth to pick a routine.
FitSnack assumes the opposite:

- **Zero-decision workouts** - a deterministic on-device engine builds a complete session the moment you select a duration.
- **Time-flexible by design** - every session is 5-60 minutes, generated to land within ±1 minute of the time you asked for.
- **Discipline first, strength earned** - consistency is the entry promise; strength is earned over time, never the headline.
- **Forgiving, not fragile** - a rolling Consistency Score replaces the brittle streak, so a single miss dents but never zeroes your progress.

---

## Target Audience

**Primary:** busy, desk-bound adults (working parents, professionals) who previously moved regularly but lost the routine.
They don't lack motivation - they lack time and mental bandwidth.

**Secondary:** people who travel frequently or work unpredictable hours and can't commit to a fixed gym schedule.

---

## The Two-Phase Journey

The product builds the habit of moving; strength is *earned*, never the launch headline.

- **Discipline Phase** - where every user starts. Consistency is the only goal; sessions stay short and simple.
- **Strength Phase** - earned over time by sustaining the habit *and* progressing the foundational movement chains.

The `PhaseEvaluator` is deterministic and never user-selectable.
At launch no user has earned the Strength Phase, so the MVP ships the Discipline-Phase experience with the evaluator already in place.

---

## Features

### Core Workout Loop

- **Deterministic session generation** - select a duration (5-60 min) and the engine assembles a structured session (warm-up, main work, cooldown over 10 min) on-device, with no network and no LLM.
- **Smart movement selection** - balances the stalest pillar and movement pattern, filters by phase, injuries, difficulty cap, and recent skips, and never repeats yesterday's primary pattern.
- **Adaptive Overload** - prescribes capacity-relative reps/sets/holds (never a fixed heroic number); an asymmetric ramp adjusts within one cycle - a `too_hard` or a skip backs off fast, `too_easy` climbs slow.
- **In-session swap** - substitutes deterministically within the same pillar, pattern, difficulty band, and time budget.

### Active Session Experience

- Large touch targets (60pt minimum on active workout screens).
- Set-by-set tracking with haptic feedback (and an audio alternative).
- Accessibility throughout: VoiceOver, Dynamic Type, and a static demo fallback for Reduce Motion.

### Consistency, Not Gamification

There is no XP, no levels, and no badges in the MVP.

- **Consistency Score** - a rolling, weighted measure of showing up; a 5-minute session counts as a full show-up, and recent weeks weigh more.
- **Longest chain** - tracked and surfaced as an earned point of pride, never as a threat.
- **Identity-framed copy** - "you're someone who moves," never loss-framed.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Platform** | iOS 17.0+, Swift 5.9, Xcode 16.3 |
| **UI Framework** | SwiftUI with the Observation framework (`@Observable`) |
| **Architecture** | MVVM + protocol-based service injection |
| **Persistence** | CoreData backed by `NSPersistentCloudKitContainer` (entities `CDUser`, `CDWorkoutLog`, `CDSessionPolicy`) |
| **Engine** | Pure Swift, on-device, deterministic (no network, no LLM, <100ms) |
| **Apple integrations** | Sign in with Apple, CloudKit (private DB sync), HealthKit, StoreKit 2 |
| **Backend** | None in the MVP (`convex/` is an empty placeholder) |
| **Bundle ID** | `com.fitsnack.app` |

AI/LLM features are deferred to Phase 2 and, when they arrive, do language only (summaries, weekly narratives) - they never generate or adapt a workout.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Views (SwiftUI)                                │
│  Access services via @Environment(\.services)   │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  ViewModels (@Observable classes)                │
│  Async service calls, UI state management       │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  Service Protocols (Services/Protocols/)         │
│  All methods async throws; mock implementations │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  ServiceContainer (DI/)                          │
│  Holds all services, injected at the app root    │
│  Swap one line to replace a mock with the real   │
└─────────────────────────────────────────────────┘
```

**Key design decisions:**

- **Protocol-based services** - all services are protocol-defined with mock implementations. To swap a mock for a real implementation, change one line in `ServiceContainer`; views and viewmodels remain untouched.
- **CoreData with domain separation** - domain models are plain `Codable` structs; CoreData entities convert via `toUser()`/`update(from:)`-style methods, with complex nested fields stored as JSON-encoded `Data`. The core loop works fully offline; CloudKit handles sync and backup when available.
- **Deterministic engine** - the workout engine runs entirely on-device with no network or LLM calls (see below).
- **Environment-based DI** - `ServiceContainer` holds all service instances, injected at the app root via a custom `EnvironmentKey`.

---

## The Deterministic Engine

The on-device engine runs this pipeline (one step per Epic C story in the PRD):

1. **Session shape** - 5-10 min single-focus; 11-20 min blend (light); 21-40 min blend (full); 41-60 min blend (extended).
2. **Pillar balance** - choose the stalest pillar by days-since-worked; bias short sessions toward mobility when the user sits 6+ hours.
3. **Movement-pattern focus** - rank patterns by staleness; never repeat yesterday's primary pattern.
4. **Filter pool** - drop by phase, injuries, difficulty cap, and recent skips; everything is bodyweight (Zero-Equipment Floor).
5. **Progression-chain selection** - pick the current chain position; offer the next when advancement criteria are met; avoid the last few sessions (a policy-tunable `varietyWindow`, default 3).
6. **Adaptive Overload** - prescribe capacity-relative reps/sets/holds; feedback (or a skip) adjusts within one cycle via an asymmetric ramp (back off fast, climb slow), the advancing bump paced by the policy's `progressionRate`.
7. **Assemble + fit timing** - always open with a warm-up, add a cooldown over 10 min, and land within ±1 min of the requested time.

In-session **swap** substitutes deterministically within the same pillar, pattern, difficulty band, and time budget, or returns a clear "no alternative" when no safe peer fits.

---

## Project Structure

```
FitSnack/
├── ios/FitSnack/FitSnack/
│   ├── App/                 # App entry point (FitSnackApp.swift)
│   ├── DesignSystem/        # Theme tokens (Theme.swift)
│   ├── Models/              # Domain enums and Codable structs
│   ├── Persistence/         # CoreData stack (NSPersistentCloudKitContainer) + conversions
│   ├── Services/
│   │   ├── Protocols/       # Service protocol definitions
│   │   ├── Mock/            # Mock implementations wired in ServiceContainer
│   │   ├── Engine/          # Deterministic workout-engine pipeline steps (pure, on-device)
│   │   └── Programmer/      # Deterministic AI Programmer (re-program trigger detection, plateau diagnosis, Default Duration learning, templated policy note, and the persistence-backed re-weighting service that composes them; pure logic on-device)
│   ├── DI/                  # ServiceContainer + environment injection
│   ├── ViewModels/          # @Observable view models
│   ├── Views/               # SwiftUI screens (Onboarding, Home, Active session, Post-session, Progress)
│   ├── Utilities/           # AppState and shared helpers
│   └── Resources/           # Exercises.json, Assets.xcassets, animations
├── convex/                  # Empty placeholder; the MVP has no custom backend
├── .claude/agent/tasks/     # Strategic plan + implementation PRD (source of truth)
└── CLAUDE.md                # Repo guidance and architecture reference
```

As of the current clean rebuild, the US-A01 scaffold (App, DesignSystem, RootView, Assets), the US-A02 canonical domain enums (`Models/Enums.swift`), the US-A03 domain model structs (`Models/Exercise.swift`, `User.swift`, `Workout.swift`, `WorkoutLog.swift`), the US-A04 CoreData stack (`Persistence/`: `FitSnack.xcdatamodeld`, `PersistenceController`, `CDUser`/`CDWorkoutLog` + conversions, `MockPersistence`), the US-A05 app shell (service protocols and mocks, `ServiceContainer`, `AppState`, and onboarding-vs-main-tabs routing in `RootView`), the US-B01 bundled exercise library (`Resources/Exercises.json`, 42 zero-equipment movements with valid progression chains), the US-B02 exercise service (`Services/Mock/MockExerciseService.swift`: loads/caches/validates the library, throws `ExerciseLibraryError`, and answers the by-pillar/pattern/phase/difficulty-range and next-in-chain queries), the US-C01 engine Step 1 (`Services/Engine/SessionShapeSelection.swift`: the pure `SessionShapeTemplate.select(requestedMinutes:)` that maps requested minutes to a session-shape template and resolves back to the canonical `SessionShape` - extended to the full 5-60 min range in US-E01), the US-C02 engine Step 2 (`Services/Engine/PillarBalance.swift`: `PillarStaleness` computes days-since-worked per pillar from the logs, and `PillarPlan.select` picks the stalest pillar for single-focus - with a desk-worker mobility lean - or staleness-weighted time shares for a blend), and the US-C03 engine Step 3 (`Services/Engine/MovementPatternFocus.swift`: `PatternStaleness` computes days-since-worked per movement pattern, and `PatternFocus.rank`/`select` rank the chosen pillar's candidate patterns stalest-first and pick the lead pattern - holding back the most recent session's lead pattern so it is never repeated back-to-back, while honoring an explicit request), and the US-C04 engine Step 4 (`Services/Engine/ExercisePoolFilter.swift`: `InjuryContraindication` maps onboarding injury tags to contraindicated movement patterns, and `ExercisePoolFilter.eligiblePool` removes phase-gated / injury-unsafe / over-cap / repeatedly-skipped movements while enforcing the Zero-Equipment Floor, with `pool(forPattern:)` falling back to the safest bodyweight option - or reporting `.noSafeOption` - when filtering empties a needed pattern), the US-C05 engine Step 5 (`Services/Engine/ProgressionChainSelection.swift`: `AdvancementCriteria` parses an exercise's free-text `advancementCriteria` and checks it against logged performance, `ProgressionChainSelection.selectInChain` finds the user's frontier tier - the highest-order tier worked - and offers the next tier only when its criteria are cleared and that tier is still eligible, never leaping past an un-cleared or gated tier and defaulting a no-history user to the chain entry, and `select(pattern:)` integrates every chain for a pattern with the no-repeat-last-3 variety rule and an active-chain preference), and the US-C06 engine Step 6 (`Services/Engine/AdaptiveOverload.swift`: `AdaptiveOverload.target` reads the user's demonstrated capacity for the selected exercise from the most recent usable log - the worked set count and the rounded average per-set reps/hold-seconds - and prescribes a capacity-relative `OverloadTarget`, applying that session's `perceivedDifficulty` within one cycle (`tooHard` eases below capacity, `tooEasy` pushes above, `justRight`/unrated nudges progressively up, with the per-cycle bump curve as tunable constants), clamping the per-set target and set count to safety rails so a target is never a fixed heroic number, and falling back to the exercise's own `defaultReps`/`defaultDurationSeconds` when there is no usable history), and the US-C07 engine Step 7 (`Services/Engine/SessionAssembly.swift`: `SessionAssembly.assemble` chains Steps 1-6 over the eligible pool and assembles a fully-formed, playable `Workout` - always opening with a `.warmup` block, closing sessions over 10 min with a `.cooldown`, and structuring training blocks per the Step 1 shape - then a deterministic best-fit `fit` pass adds/drops whole exercises or individual sets, never the capacity-relative per-set target, until the planned `Σ(sets × est) + rests + transitions` wall-clock lands within ±1 min of the request; `MockWorkoutEngine` now drives this assembler with the validated library from the exercise service), and the US-C08 deterministic swap (`Services/Engine/ExerciseSwap.swift`: `ExerciseSwap.swap` returns a `SwapOutcome` - either an equivalent substitute drawn from the eligible pool (same pillar and pattern, within a ±1 `difficultyBandWidth`, inside the `slotToleranceSeconds` time budget, never duplicating a movement already in the session, carrying a fresh capacity-relative per-set target while preserving the original slot's set count and rest) or `.noAlternative` when no safe in-budget peer exists - exposed through `WorkoutEngineProtocol.swapExercise` and wired in `MockWorkoutEngine`) exist; with the Epic C engine pipeline (Steps 1-7 + swap) complete, only `ViewModels/` is still empty.
The v6 Epic D data foundation has begun: US-D01 (`Models/User.swift`) adds the nested `User.Why` (`statement` + optional `openingBias` pillar), `User.Duration` (`defaultMinutes`/`onboardingSeedMinutes`/`completedDurationEWMA`, with a `seeded(minutes:)` factory so `defaultMinutes == onboardingSeedMinutes`), and `User.ColdStart` (`sessionsLogged`/`active`, with a `.fresh` default) value types as three new top-level `User` fields - `primaryGoal` and the `UserProfile` shape are unchanged - each persisted as its own JSON-encoded `Data` column on `CDUser` (`whyData`/`durationData`/`coldStartData`) that decodes to documented defaults (empty `why`, duration seeded from `profile.typicalAvailableMinutes`, a fresh cold-start) when absent, so a pre-v6 record still loads.
US-D02 (`Models/WorkoutLog.swift`) adds `requestedMinutes: Int` (what the Ready Screen offered or the user set) and `wasReturn: Bool` (defaulting to `false`) as two new top-level `WorkoutLog` fields, and documents the existing `durationMinutes` as the actually-completed duration that feeds `duration.completedDurationEWMA` - the requested-vs-completed gap is the input Default Duration learning and the Disengagement signal read, and `wasReturn` marks a post-gap Return for the Re-entry Ramp; both persist as additive optional `NSNumber?` columns on `CDWorkoutLog` (`requestedMinutes`/`wasReturn`) that decode to documented defaults (`requestedMinutes == durationMinutes`, `wasReturn == false`) when absent, so a pre-v6 log still loads.
US-D03 (`Models/SessionPolicy.swift`) defines the always-valid `SessionPolicy` - `version`/`updatedAt`/`updatedBy` (`default`/`deterministic`/`llm`)/`progressionRate`/`pillarWeighting: [Pillar: Double]`/`varietyWindow` plus optional `coldStartContract`, `reentry`, and `note` - the single seam the AI Programmer (Epic F) writes and the deterministic engine (Epic E) reads; `SessionPolicy.default` is a deterministic, neutral starting policy (progression 1.0, equal weighting across all three pillars, variety window 3, no situational overrides) that reproduces pre-policy engine behavior exactly and persists whole (JSON-encoded) as `CDSessionPolicy`, keyed by `userId` and overwritten in place so the last-written policy survives relaunch and offline use.
US-D04 (`Models/ReprogramTrigger.swift`) opens the AI Programmer <-> engine seam: the new `ReprogramTrigger` value type carries a `kind` (`weekly_boundary`/`return`/`physical_stall`/`disengagement`, stable snake-case raw values) and an injected `detectedAt`, and the new `SessionPolicyServiceProtocol` (`currentPolicy(for:)`, `reprogram(user:recentLogs:trigger:)`, `dueTriggers(user:recentLogs:asOf:)`, all `async throws`) is the one seam the Programmer (Epic F) writes and the engine (Epic E) reads; `MockSessionPolicyService` hands back `SessionPolicy.default` and never reports a due trigger (real detection/re-weighting land in Epic F), and it is wired into `ServiceContainer`; `WorkoutEngineProtocol.generateWorkout(...)` gains a `sessionPolicy:` parameter that the mock accepts and (as of US-E03) threads into `SessionAssembly`, where `SessionPolicy.default`'s neutral levers keep output identical to pre-policy behavior.
US-E01 (`Services/Engine/SessionShapeSelection.swift`, `Services/Engine/PillarBalance.swift`) begins the v6 Epic E engine extensions: `SessionShapeTemplate.select` now shapes the full 5-60 min request range with four buckets - `5-10 -> singleFocus`, `11-20 -> blendLight`, `21-40 -> blendFull`, `41-60 -> blendExtended` (the new extended-blend case) - clamping out-of-range requests into a `5...60` `supportedRange` so the mapping stays total, pure, and deterministic; every blend (including `blendExtended`) still resolves to the canonical `.blend` `SessionShape` and `PillarPlan.select` treats `blendExtended` like the other blends, so the reclassified 20-min session (now `blendLight` rather than `blendFull`) is behavior-neutral downstream; the dedicated extended primal block lands in US-E02.
US-E02 (`Services/Engine/PillarBalance.swift`, `Services/Engine/SessionAssembly.swift`) promotes primal to a first-class pillar: `PillarWeights` gains a `primal` share and `PillarPlan.select` splits an extended blend across all three pillars (each kept above `minExtendedBlendShare`, the rest apportioned by weighted staleness so the shares always sum to 1) while short/full blends keep `primal == 0` (folded into strength as before, no regression); `select` also takes a `pillarWeighting: [Pillar: Double]` staleness multiplier (defaulting to `SessionPolicy.neutralPillarWeighting`, a no-op) so primal selection respects `sessionPolicy.pillarWeighting[.primal]` - the live policy is threaded through `assemble` in US-E03. In assembly, a `blendExtended` session now builds a dedicated `.primal` block from the `locomotion` pattern / `pillar == .primal` (via the same Steps 5-6 chain selection + Adaptive Overload as the strength block, Zero-Equipment Floor and difficulty gating intact), sheds primal from the strength block so no locomotion movement is double-booked, and orders the up-to-three training blocks staler-pillar-first; the block gracefully degrades to strength + mobility when the pool has no eligible primal movement.
US-E03 (`Services/Engine/SessionAssembly.swift`, `Services/Engine/AdaptiveOverload.swift`, `Services/Engine/ProgressionChainSelection.swift`, `Services/Mock/MockServices.swift`) makes the engine consume the live Session Policy: `SessionAssembly.assemble`/`planBlocks` take a `sessionPolicy:` parameter (defaulting to `SessionPolicy.default`, a no-op that reproduces pre-policy output exactly) and thread its three levers into the pipeline - `pillarWeighting` scales Step 2's staleness split (a heavier weight measurably grows that pillar's block time), `varietyWindow` replaces Step 5's hardcoded no-repeat window (`ProgressionChainSelection.select` now takes a `varietyWindow:`, still defaulting to `recentSessionWindow`, and the assembler's mobility variety ordering mirrors it), and `progressionRate` paces Step 6's Adaptive Overload bump (`AdaptiveOverload.target` now takes a `progressionRate:`, scaling only the advancing `progressiveStep`/`easyStep` around `1.0` via `paced(_:rate:)` - never the `tooHard` ease, which is US-E05's Asymmetric Ramp - still clamped to the rep/hold safety rails); `MockWorkoutEngine` now passes its `sessionPolicy` straight through to `assemble`, finally wiring the US-D04 seam end-to-end.
US-E04 (`Services/Engine/ColdStartOverride.swift`, `Services/Engine/SessionAssembly.swift`) adds the engine's Step 0 cold-start override: `ColdStartOverride` runs before Steps 1-6 but only while `user.coldStart.active` and the live `sessionPolicy.coldStartContract != nil` (both no-ops once US-G04 retires cold-start, so a warmed-up user runs exactly the US-E03 pipeline). It touches two pipeline inputs and leaves everything else to Steps 1-6: `cappedPool` restricts the eligible pool to movements at or below the contract's `cappedMaxDifficulty` (the "served at the gentle end" promise then falls out of Step 5's existing no-history entry-tier selection, and the cap never empties the pool - it returns the uncapped pool rather than break generation), and `overridePlan` (gated additionally on `forceContrastSpread`) forces First-Week Contrast by rotating the day's lead pillar deterministically by `coldStart.sessionsLogged` from an onboarding-derived start (`why.openingBias`, else mobility for a desk worker, else strength), so consecutive cold-start days never repeat a pillar and the first week spans strength/mobility/primal instead of a desk worker's all-mobility bias; single-focus days take the rotated pillar directly (a new `.single(.primal)` path in `SessionAssembly.buildBlocks` builds a dedicated locomotion block, degrading to strength then mobility if the capped pool has no eligible primal), and blend days re-point the Step 2 shares so the rotated pillar leads (preserving the shares' sum-to-1 and floors). Step 0 stays a pure function of its inputs (the "day" is read from `sessionsLogged`, no wall clock), so determinism holds.
US-E05 (`Services/Engine/AdaptiveOverload.swift`) tunes Step 6's per-cycle bump curve into the **Asymmetric Ramp** - back off fast, climb slow: a single recent `too_hard` or a **skip** of the exercise pulls the next target down eagerly (`hardStep` steepened to `0.80`, a 20% back-off), while `too_easy` climbs only patiently (`easyStep` gentled to `1.10`, a 10% rise) and `justRight`/unrated nudges up by the gentlest `progressiveStep` (`1.05`), so the down-step magnitude is always >= the up-step (`(1 - hardStep) >= (easyStep - 1)`, asserted on the constants) and every signal still moves by at least one so direction is never lost to rounding. The `too_hard`/`too_easy` mapping plus the new skip signal are resolved into a private `RampSignal` (`eased`/`intensify`/`progress`): `demonstratedCapacity` now scans past a skipped most-recent entry to read the set count and per-set value from the earlier worked session but remembers the skip and forces `.eased`, so a recent bail eases the target (below capacity) even over an earlier `too_easy`, without the skip becoming the capacity *source*. The ramp composes with US-E03's `progressionRate` unchanged - the rate still paces only the two advancing steps, never the eager down-step - and stays within the existing rep/hold/set rails.
US-E06 (`Services/Engine/ReturnOverride.swift`, `Services/Engine/SessionAssembly.swift`, `Services/Engine/AdaptiveOverload.swift`, `Services/Engine/PillarBalance.swift`, `Models/Workout.swift`) completes the Epic E engine extensions with the **Return override** and the **Re-entry Ramp** - discipline overriding optimization after a gap. `ReturnOverride.isReturn` flags the next session a Return once the calendar-day gap since the most recent logged session reaches `returnThresholdDays` (7, pure over the injected `asOf`, and `false` for a fresh no-history user), and while a Return is active - and cold-start is not, since the two are mutually exclusive (cold-start already serves gentle capped sessions, so the Return is gated off by `ColdStartOverride.isActive`) - `SessionAssembly` serves an easy, winnable session *regardless of staleness or the policy's optimization levers*: `overridePlan` leads with mobility (a single-focus Return trains it directly, a blend re-points its shares to favor mobility via the now-shared `PillarWeights.favoring`), `returnPool` caps the eligible pool at `returnMaxDifficulty` (2, never emptying it), and `reentryScale` eases Step 6's volume to the gentle `reentryFloorScale` (0.70). The Return itself carries no readjustment; that lives in the Re-entry Ramp: `sessionPolicy.reentry.rampSessionsRemaining` (seeded to `rampSessions` = 3 by the Programmer after a Return, US-F03) drives `ReturnOverride.rampScale`, which walks the volume scale from the floor back to neutral `1.0` as the counter decrements, so `AdaptiveOverload.target` (now taking a `reentryScale:` - neutral `1.0` by default, applied only to capacity-derived per-set targets, always landing at least one below the un-held target down to the rails) holds difficulty below normal on the sessions after a Return and climbs it back. The Return decision is made once (`SessionAssembly.isReturnSession`, gating both the overrides and the flag) and stamped on the assembled `Workout.wasReturn`, so the post-session log-writer (US-L01) records it onto `WorkoutLog.wasReturn` (US-D02) rather than re-deriving detection at a different `asOf`. Every override is a pure function of its inputs and a no-op in the steady state, so a present, warmed-up user runs exactly the US-E03 pipeline; with US-E06 the Epic E engine extensions are complete and Epic F (the AI Programmer that writes the policy, including seeding the `reentry` ramp on a `return` trigger) is next.
The v6 Epic F AI Programmer has begun: US-F01 (`Services/Programmer/ReprogramTriggerDetection.swift`) opens the on-device, deterministic Programmer with re-program trigger detection and **Trigger Precedence** - the detection half of the seam whose re-weighting lands in US-F02/US-F03. `ReprogramTriggerDetection.dueTriggers(user:recentLogs:library:asOf:calendar:)` is a pure function returning the due `ReprogramTrigger`s (US-D04) in precedence order, so on open the client can re-program against the highest-precedence one without any server clock and the new policy applies one open later. It detects the four PRD kinds: `weekly_boundary` (the injected calendar's week for `asOf` is strictly later than the most recent log's week, so a just-closed Consistency-Score week exists to re-tune against - never for a no-history user), `return` (reuses `ReturnOverride.isReturn`, the single Return-detection seam so the Programmer and engine can never disagree), `physical_stall` (a worked chain's frontier tier has an existing next tier (`progressionId != nil`) yet its parsed `AdvancementCriteria` are cleared across 2+ distinct sessions while the frontier never rises - meaning that real next tier is gated and the user is genuinely stuck, so a single-tier or top-of-chain movement never misreads a healthy user as a plateau), and `disengagement` (over the most recent completed sessions the per-session completion ratio `durationMinutes / requestedMinutes` forms a declining run falling to <= 0.6, or the window skip rate reaches 0.5 - reading the requested-vs-completed gap rather than absolute completed minutes per US-D02, so a user who intentionally requests shorter sessions and finishes them is never misread as pulling away). **Trigger Precedence** is enforced at the source - when both apply, `disengagement` suppresses `physical_stall` so a user pulling away is never handed more challenge - and the returned order (`return` < `disengagement` < `physical_stall` < `weekly_boundary`) mirrors it. Detection is pure and deterministic over `(user, recentLogs, library, asOf)` with the clock injected and stamped onto each trigger's `detectedAt`; the concrete `SessionPolicyServiceProtocol` (US-F03) will supply the validated `library` and adapt this to the protocol's library-free `dueTriggers(user:recentLogs:asOf:)` (the shell `MockSessionPolicyService` still reports no triggers until then).
US-F02 (`Services/Programmer/PlateauDiagnosis.swift`) adds the Programmer's **plateau diagnosis** - telling a *physical stall* (capacity earned but gated) apart from *disengagement* (pulling away) and mapping each to the Session Policy levers US-F03 writes. The two plateau predicates US-F01 detected inline (`isPhysicallyStalled(recentLogs:library:)` and `isDisengaging(recentLogs:)`, with their tuning constants) now live here as the single seam that `ReprogramTriggerDetection.dueTriggers` composes rather than re-derives, so detection and diagnosis can never disagree about what a stall or a disengagement is - a behavior-preserving move that leaves US-F01's trigger output unchanged. `PlateauDiagnosis.diagnose(recentLogs:library:) -> Plateau?` returns the single plateau in force (`.physicalStall`/`.disengagement`) or `nil`, applying the same Trigger Precedence at the source (disengagement wins, so a diagnosis can never hand more challenge to a user pulling away); it is pure over `(recentLogs, library)`, reading only log history (the completion ratio and skip rate are the consistency signals, straight off the logs per US-D02) with no clock, and needs the `library` only to resolve advancement criteria and chain position for the stall. The **explicit lever mapping** `PlateauDiagnosis.reweighted(_:for:)` moves only the affected levers on a passed-in policy and leaves `version`/`updatedBy`/`note`/persistence to US-F03: a `.physicalStall` multiplies `progressionRate` by `stallProgressionBoost` (1.15) and widens `varietyWindow` by `stallVarietyWiden` (+1), while a `.disengagement` eases `progressionRate` by `disengagementProgressionEase` (0.85) and narrows `varietyWindow` by `disengagementVarietyNarrow` (-1) - lower difficulty, less novelty - and never raises challenge; both are clamped to the rails (`progressionRate` 0.5...2.0, `varietyWindow` 1...6) so recurring plateaus accelerate or ease without running away. The session-length half of "less friction" for disengagement is delivered by Default Duration learning (US-F04) - the policy carries no session-length lever, so the mapping does not fabricate one.
US-F04 (`Services/Programmer/DefaultDurationLearning.swift`, `Services/Programmer/PolicyNote.swift`) adds the Programmer's two honesty pieces - both pure and deterministic, left to be wired by the re-weighting service (US-F03) just as US-F01/US-F02 provide pure logic no service yet calls. `DefaultDurationLearning.learned(_:completing:)` folds newly-completed session `durationMinutes` (what the user *finishes*, never what they *request*, per US-D02) into `User.Duration.completedDurationEWMA` - a 0.3-smoothing EWMA anchored to the existing average, else the onboarding seed - and snaps `defaultMinutes` to the nearest valid chip (5/10/15/20/30/45/60, a boundary resolving to the shorter chip), never mutating the onboarding seed, so a user who requests 20 but completes ~12 drifts the Ready-Screen default to 10 or 15. `PolicyNote.templated(policyBefore:policyAfter:durationChange:)` builds the user-visible note (always `source == template`) from the **real diff** - the direction `progressionRate`/`varietyWindow` actually moved plus any Default Duration change - naming a stepped-up challenge or eased intensity only when it happened, appending the new go-to duration only when it changed, returning `nil` when nothing observable moved, and never invoking the user's `why`, so the note can only ever claim a change the sessions actually reflect.
US-F03 (`Services/Programmer/DeterministicSessionPolicyService.swift`, `Persistence/CoreDataSessionPolicyStore.swift`, `DI/ServiceContainer.swift`) completes Epic F with the real, persistence-backed re-weighting service that composes the Programmer's four pure pieces (US-F01 detection, US-F02 diagnosis + lever mapping, US-F04 Default Duration learning + templated note) into the `SessionPolicyServiceProtocol` the client calls on open. `currentPolicy(for:)` reads the last-written policy from an injected `SessionPolicyStore` (or `SessionPolicy.default` until one exists), and `dueTriggers(user:recentLogs:asOf:)` adapts US-F01's library-taking detection to the protocol by supplying the validated catalog from the exercise service. `reprogram(user:recentLogs:trigger:)` writes a fresh policy: it moves the optimization levers for the trigger (`physical_stall`/`disengagement` re-diagnose the freshest history so **Trigger Precedence holds end-to-end** - a stall trigger can never accelerate a now-disengaging user; `return` seeds the `reentry` ramp and touches no optimization lever; `weekly_boundary` moves no lever on its own), folds Default Duration learning over only the non-Return sessions completed since the last policy write (a dedup boundary so the EWMA folds each session once, and `wasReturn` sessions are excluded so a short, capped comeback never drags the learned default down), stamps `version += 1` / `updatedBy == .deterministic` / `updatedAt = trigger.detectedAt`, attaches the honest templated note from the real diff, and persists the learned `user.duration` first (when it moved) then the policy - so the `updatedAt` dedup boundary only advances after the derived duration is durably saved. The service **never generates or returns a workout**; it only writes policy. Persistence is a `SessionPolicyStore` protocol with an `InMemorySessionPolicyStore` (tests/previews/the mock container) and a `CoreDataSessionPolicyStore` (the running app, backed by `CDSessionPolicy` so the policy survives relaunch and offline use); the real service replaces `MockSessionPolicyService` in `ServiceContainer.mock()`, returning the default until it has written a policy so pre-programming behavior is unchanged. With US-F03 done the Epic F AI Programmer is complete; the on-open client invocation of `dueTriggers`/`reprogram` lands with the Ready Screen (US-J02).
The v6 Epic G (cold start & Variety Language) has begun: US-G01 (`Models/SessionPolicy.swift`) adds the deterministic cold-start Starting Difficulty seeding onboarding will call - `SessionPolicy.ColdStartContract.cappedMaxDifficulty(for:)` maps the self-reported `profile.fitnessLevel` to a provisional capped band (beginner 2, intermediate 3, advanced 4), deliberately at or below the steady-state `ExercisePoolFilter.difficultyCap` (it tightens only the advanced user, 5 -> 4) so an over-rated self-report still gets a winnable first day; `ColdStartContract.seeded(for:)` builds the onboarding contract (First-Week Contrast forced on for US-G02, the level's cap for US-G01) and `SessionPolicy.seeded(forFitnessLevel:)` layers exactly that contract onto the neutral `SessionPolicy.default` and moves no other lever, so once cold-start retires (US-G04 clears the contract) the engine behaves exactly as `default`. The engine already serves the gentle end of the capped band (US-E04's `ColdStartOverride.cappedPool` + Step 5's no-history entry-tier selection) and leaves upward correction to the Asymmetric Ramp (US-E05), so US-G01 is purely the write-side seed the onboarding flow (US-I01) will call with `profile.fitnessLevel`; the pure mapping/factory and the end-to-end gentle-end selection are both under test.
US-G02 (`FitSnackTests/FirstWeekContrastTests.swift`) lands the First-Week Contrast enforcement contract without any production change: the *mechanism* is US-E04's Step 0 `ColdStartOverride` pillar rotation and the *switch* is the `coldStartContract.forceContrastSpread` flag US-G01's `seeded(for:)` sets true, so US-G02 is the seam that binds and proves them - that the seeded flag actually produces a visible strength/mobility/primal spread across the first week with no pillar repeating back-to-back, even for a `sitsLong` desk worker whose staleness bias alone would collapse the week to all-mobility. The new suite owns that contract at three altitudes: the pure `ColdStartOverride` rule in isolation (the rotation spans all three pillars with no back-to-back repeat, and the flag is the on/off switch - off, a mobility-biased plan passes through untouched), the real onboarding seed end-to-end through `SessionAssembly.assemble` (driven by the actual `SessionPolicy.seeded(forFitnessLevel:)`: a desk-worker beginner's first four sessions span >= 2 pillars with no back-to-back repeat), and a control proving the spread comes from the contract, not staleness (the same desk worker on the neutral `SessionPolicy.default` collapses to all-mobility every day).
US-G03 (`Services/Language/VarietyLanguage.swift`, `Services/Language/VarietyLanguageResolver.swift`) adds the Variety Language slice - the short, honest line naming what today is and how it differs from yesterday ("Today's a mobility day - yesterday was strength"), so a new user feels the variety wedge from session one. `VarietyLanguage` is the deterministic template and the single source of truth for the contrast: it reads the lead pillar straight off the engine's own output (a `Workout`'s `focusPillar`, else its first training block; a `WorkoutLog`'s `focusPillar`, else a blend's most-worked non-skipped pillar), so the line can only name a contrast the engine *actually produced* - the "yesterday" clause is kept only when the prior session genuinely led with a different pillar, the first session is only named, a warm-up-only session yields no note, and the user's `why` is never invoked (no hollow callback); the note is always `source == .template`, offline-safe and non-blocking. `VarietyLanguageResolver` composes the optional LLM upgrade over that template via the `VarietyLanguageProvider` seam (fulfilled by the thin stateless proxy, US-N05, deferred - no provider ships in the MVP, so every note is template-sourced): it attempts the LLM at most once and only when the user is cold-start-active, online, and a provider is wired (marking success `source == .llm`), and on *any* failure - offline, no provider, warmed-up user, a thrown error/timeout, or an empty line - falls back to the template, so the app never blocks or shows a blank; the on-open wiring into the Ready Screen lands with US-J02.
US-G04 (`Services/Engine/ColdStartHandoff.swift`) closes Epic G's cold-start arc with the cold-start handoff - the one-way retirement that hands a warmed-up user off from the Step 0 overrides (US-E04) to the self-driving engine once there is enough history for staleness and Adaptive Overload to steer unassisted. It is a thin, pure bookkeeping step (no service yet calls it; the post-session log-writer US-L01 will) touching exactly the two pieces of state Step 0 reads: `advanced(_:)` increments `user.coldStart.sessionsLogged` on each completed session and flips `active` off the moment the count reaches `handoffThreshold` (5, tunable; v6 range 5-7) - a one-way retirement (once inactive the state is frozen, so a later gap is the Return override's job, not a cold-start relapse); `reconciled(_:with:)` clears `sessionPolicy.coldStartContract` to `nil` once cold-start is inactive and moves no other lever (the version/`updatedBy` are the Programmer's), leaving the policy in exactly `default`'s cold-start shape so Step 0 (gated on both the `active` flag and the contract) is a no-op and the engine runs the plain US-E03 pipeline from the sixth session on; and the combined `afterCompletedSession(user:sessionPolicy:)` advances the user then reconciles the policy against that advanced state, returning both aggregates (persisted separately) as a `ColdStartHandoff.Outcome`. Pure and deterministic (the signal is the logged-session count, no wall clock); with US-G04 done Epic G is complete.
The app root (`FitSnackApp`) injects the CoreData view context, the `ServiceContainer` (via `\.services`), and `AppState`; the CoreData stack is local-only until CloudKit sync lands in US-J02.
The rest lands story-by-story per the PRD.

---

## Source of Truth

| Document | Purpose |
|----------|---------|
| `.claude/agent/tasks/FitSnack-PRD-v6_070226.md` | Strategic plan (v6.0) - the discipline-first vision plus the v6 wedge (a daily-adaptive AI Programmer that writes a per-user Session Policy the deterministic engine runs on). Supersedes `FitSnack-PRD-v5.md` (kept for reference). |
| `.claude/agent/tasks/prd-fitsnack-mvp-v6_0702.md` | Implementation PRD and live progress tracker - the v6 MVP as ~51 user stories (US-A01 … US-N05) with acceptance criteria. Supersedes `prd-fitsnack-mvp_0626.md` (v5, kept for reference). |
| `CLAUDE.md` | Repo conventions and architecture for contributors and AI assistants. |

Always check the PRD for the relevant story before building a feature.

---

## Getting Started

### Prerequisites

- **Xcode 16.3+**
- **iOS 17.0+ Simulator or device**
- **XcodeGen** (to generate the project from `project.yml`)

```bash
brew install xcodegen
```

### Build & Run

```bash
# Generate the Xcode project
cd ios/FitSnack && xcodegen generate

# Build for the simulator
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build

# Or open in Xcode
open ios/FitSnack/FitSnack.xcodeproj
```

### Run Tests

There is a single scheme, `FitSnack`, which builds the app and runs the `FitSnackTests` target.

```bash
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

If xcodebuild cannot resolve the destination, list installed simulators with `xcrun simctl list devices available` and pass `-destination 'id=<UDID>'`.

---

## Design System

FitSnack uses a consistent design token system via `Theme.*` (`Theme.Colors`, `Theme.Typography`, `Theme.Spacing`) - always use these, never hardcode colors, fonts, or spacing.

| Token | Value |
|-------|-------|
| **Button Height** | 56pt |
| **Card Corner Radius** | 16pt |
| **Min Touch Target** | 44pt (60pt on active workout screens) |
| **Typography** | SF Pro (system, rounded) with a semantic scale; Dynamic Type out of the box |

Colors resolve from the asset catalog where a named color exists and fall back to a sensible system color otherwise, so the app always renders.

---

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| **MVP** | Discipline-Phase loop: deterministic engine, Consistency Score, PhaseEvaluator, onboarding, CoreData/CloudKit | In Progress |
| **Phase 2** | Language-only LLM features (template-free summaries, weekly narratives), full Strength-Phase catalog, equipment variants | Planned |

The MVP never calls an LLM (summaries are template-based) and ships no gamification, social features, or equipment-based exercises.
See the PRD's Non-Goals section for the full list.

---

## License

All rights reserved. This is a private project.
