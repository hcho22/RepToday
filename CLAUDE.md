# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

Rep Today is a discipline-first micro-workout iOS app (5-60 min sessions) for busy, desk-bound adults.
The user says how many minutes they have, and a deterministic on-device engine generates a complete zero-equipment session blending bodyweight strength and mobility - no browsing, no choosing, no thinking.
Strength is earned, not the entry promise: every user starts in the **Discipline Phase** and earns the **Strength Phase** through sustained consistency plus demonstrated competence, so all MVP users resolve to Discipline with the `PhaseEvaluator` already in place.
The MVP is Apple-native with no custom backend; AI/LLM features are deferred to Phase 2, do language only, and never generate or adapt a workout.

## Source of Truth

- **Strategic plan:** the v6.0 strategic PRD under `.claude/agent/tasks/` (supersedes v5, kept for reference).
- **Implementation PRD / live progress tracker:** `.claude/agent/tasks/prd-fitsnack-mvp-v6_0702.md` (~51 stories, US-A01 ... US-N05); acceptance checkboxes flip to `[x]` as stories land. Always check the story before building a feature.
- **What is already built:** `docs/implementation-log.md`. **Test coverage map:** `docs/test-coverage.md`. **Third-party asset source/license ledger:** `docs/asset-attribution.md` (an asset with no cleared row never ships).
- The strategic plans reference a `CONTEXT.md` and `docs/adr/` that do not exist here; the task files above are authoritative.

## Build & Run

```bash
cd ios/RepToday && xcodegen generate    # regenerate the project from project.yml
xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

One scheme, `RepToday`, builds the app and runs `RepTodayTests`; if the destination will not resolve, use `xcrun simctl list devices available` and pass `-destination 'id=<UDID>'`. Target iOS 17.0+, Swift 5.9, Xcode 16.3, bundle id `com.reptoday.app`.
`DEVELOPMENT_TEAM` is empty, so entitlement-gated paths (Sign in with Apple, CloudKit sync, HealthKit writes, live purchases) verify only on a provisioned device.

## Architecture

**Monorepo:** `ios/` is the whole MVP; `convex/` is an empty placeholder (no backend); `proxy/` is a deploy-ready but unwired Cloudflare Worker for the deferred Variety Language LLM slice (holds the Anthropic key, stores nothing, receives only two pillar values).

**MVVM + protocol-based services.** Views read services from `@Environment(\.services)`; ViewModels are `@Observable`; services are protocols in `Services/Protocols/` with mock and real implementations; `DI/ServiceContainer.swift` wires them (`mock()` for tests/previews, `live(context:)` for the app), so swapping in a real implementation is a one-line change.

**Persistence:** CoreData over `NSPersistentCloudKitContainer` with two stores - the **Cloud** configuration (`CDUser`, `CDWorkoutLog`, `CDSessionPolicy`) mirrors to the user's private iCloud database, and the **Local** configuration (`CDActiveSession`) is device-bound transient state that never syncs. The core loop works fully offline and with no iCloud account; sync is additive and falls back to local-only on any CloudKit failure. Domain models are plain `Codable` structs; nested fields persist as JSON-encoded `Data`.

**Integrations & navigation:** Sign in with Apple, CloudKit, write-only HealthKit, and StoreKit 2 (free unlimited core, premium depth only) never gate the core loop and degrade quietly; `AppState` (`@Observable`, UserDefaults-persisted) controls onboarding vs. main tabs and the selected tab.

## The Deterministic Engine

Pure Swift, on-device, no network, no LLM, <100ms. Step 0 overrides (cold start, Return) run first and are no-ops in the steady state; the cold start also carries a **Start Seed** - a difficulty band `[startingDifficultyFloor, cappedMaxDifficulty]` over strength/primal plus a volume seed, both seeded from `profile.fitnessLevel`, eased a tier per `tooHard` rating, and retired at the handoff (which records the floor the week actually ran at so Step 5 does not treat a withheld chain as fresh).

1. **Session shape** - 5-10 single-focus; 11-20 blend light; 21-40 blend full; 41-60 blend extended.
2. **Pillar balance** - stalest pillar by days-since-worked; mobility lean for desk workers; policy `pillarWeighting` scales it.
3. **Movement-pattern focus** - stalest-first; never repeat the previous session's lead pattern.
4. **Filter pool** - drop by phase, injuries, difficulty cap, recent skips; everything is bodyweight (Zero-Equipment Floor).
5. **Progression-chain selection** - the user's frontier tier, advancing only when criteria are cleared; avoid the last `varietyWindow` sessions (default 3).
6. **Adaptive Overload** - capacity-relative reps/sets/holds, never a fixed heroic number; the Asymmetric Ramp backs off fast and climbs slow, paced by `progressionRate`.
7. **Assemble + fit timing** - warm-up first, cooldown over 10 min, land within +/-1 min of the request. `SessionAssembly.workSecondsPerSet` prices a set as a fixed setup cost plus the per-unit work of the target prescribed (a hold's per-unit cost is one second per prescribed second *per side*, via `Exercise.isPerSide`/`sidesPerSet`), so a grown or seeded target is planned honestly; the work half is never timed at runtime, so this is a planning-only number where systematic bias matters and per-second precision does not.

In-session **swap** substitutes within the same pillar, pattern, difficulty band, and time budget, sized by the session's own policy (`progressionRate`, Start Seed, `varietyWindow`, Return/re-entry ease). It keeps the slot's set count whenever a peer fits at it and re-picks one inside `minTrainingSets...maxTrainingSets` only when nothing else would keep the session in its minutes - never on the single-set warm-up/cooldown bookends, which get a work-scaled tolerance instead. A deterministic on-device **AI Programmer** (`Services/Programmer/`) writes the per-user `SessionPolicy` the engine reads: it detects re-program triggers, diagnoses plateaus, learns the Default Duration, and never returns a workout.

## Consistency & Phase (no gamification)

No XP, no levels, no badges, no streak to break.

- **Consistency Score** - `weeklyAdherence = min(1, workoutsCompleted / weeklyGoal)`, a recency-weighted rolling average x 100. A 5-min session is a full show-up; a miss dents but never zeroes; a Return excuses the gap weeks it closed. `longestChain` is an all-time maximum surfaced as earned pride.
- **PhaseEvaluator** - deterministic, never user-selectable; Strength requires both sustained consistency and cleared entry tiers across push/squat/hinge/core.
- All copy is identity-framed ("you're someone who moves"), never loss-framed.

## Key Conventions

- `@Observable` only, never `ObservableObject`/`@Published`. All service methods are `async throws`.
- Enums are `Codable`, `CaseIterable`, and `Identifiable` where they have a stable id.
- Always use `Theme.Colors` / `Theme.Typography` / `Theme.Spacing`; never hardcode colors, fonts, or spacing.
- Button height 56pt, card radius 16pt, touch targets 44pt (60pt on active workout screens).
- Exercise library: 57 bodyweight movements in `Resources/Exercises.json`, all `equipment == []`, load-time-validated.
- Accessibility throughout: VoiceOver, Dynamic Type, Reduce Motion, haptics with an audio alternative.
- Pure engine/evaluator logic takes an injected `asOf` clock; never read the wall clock inside it.
- Tests live in `ios/RepToday/RepTodayTests/` (`XCTestCase` + `@testable import RepToday`); all new logic needs tests, and each story adds a row to `docs/test-coverage.md`.

## Project Structure (ios/RepToday/RepToday)

```
App/ DesignSystem/ Models/   Entry point, Theme tokens, domain enums + Codable structs
Persistence/                CoreData stack, conversions, CoreData-backed services
Services/Protocols/ Mock/    Service definitions and mock implementations
Services/Engine/            Deterministic pipeline (Steps 0-7 + swap)
Services/Programmer/        Trigger detection, plateau diagnosis, duration learning, policy writer
Services/Language/          Variety Language template, resolver, proxy client
Services/Consistency/       Consistency Score, PhaseEvaluator, ConsistencyTrend
Services/Progress/          Progress-tab analytics (free + premium-gated deep layer)
Services/ActiveSession/     Resume store, completion recorder, session summary
Services/Auth|Health|Subscription/   Sign in with Apple, HealthKit writes, StoreKit 2
DI/ ViewModels/ Views/      Container + injection, @Observable view models, SwiftUI screens
Utilities/ Resources/       AppState and helpers; Exercises.json, assets, .storekit (no demo animation ships yet)
```

## Out of Scope (MVP Non-Goals)

No LLM/AI calls in the loop, no custom backend, no XP/levels/badges, no social/leaderboards/challenges, no equipment-based exercises, no full Strength-Phase catalog, no Android/widgets/Live Activities/Apple Watch (see the PRD's Non-Goals for the full list).

## Artifact Locations

PRDs and task briefs live in `.claude/agent/tasks/`; work products go under `artifacts/` - `reports/` (engineering, QA, test results), `specs/`, `learning-logs/` - created on demand.
