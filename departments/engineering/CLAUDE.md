# Engineering Context — FitSnack iOS

For project-wide context (build commands, bundle ID, targets), see root `CLAUDE.md`.

## Architecture Deep Dive

**Service Protocol Pattern:** Define abstractions in `Services/Protocols/`, implement in `Services/Mock/`. To swap a mock for a real implementation later, change one line in `ServiceContainer`. Views and ViewModels never change.

**Environment Injection:** `ServiceContainer` is injected via `@Environment(\.services)`. All service methods are `async throws`.

**ViewModels:** Always `@Observable` (Observation framework). Never use `ObservableObject`/`@Published`/Combine.

**CoreData Persistence:** Domain models are plain `Codable` structs. CoreData entities (`CDUser`, `CDWorkoutLog`), backed by `NSPersistentCloudKitContainer`, convert via `toUser()`/`update(from:)`-style methods. Complex nested fields are stored as JSON-encoded `Data`. The core loop works fully offline; CloudKit handles sync and backup when an iCloud account is available.

**Navigation:** `AppState` (`@Observable`, persisted to UserDefaults) drives onboarding vs. the main app and the selected tab.

## Deterministic Engine

The session engine is pure Swift, runs entirely on-device with no network and no LLM, and targets sub-100ms latency. The pipeline (one step per Epic C story):

1. **Session shape** - 5-10 min single-focus; 15 min light blend; 20-30 min full blend
2. **Pillar balance** - pick the stalest pillar by days-since-worked; bias short sessions toward mobility for heavy sitters
3. **Movement-pattern focus** - rank patterns by staleness; never repeat yesterday's primary pattern
4. **Filter pool** - drop by phase, injuries, difficulty cap, and recent skips; everything is bodyweight (Zero-Equipment Floor)
5. **Progression-chain selection** - pick the current chain position; offer the next when advancement criteria are met
6. **Adaptive Overload** - prescribe capacity-relative reps/sets/holds; `too_easy`/`too_hard` feedback adjusts within one cycle
7. **Assemble + fit timing** - open with a warmup, add a cooldown over 10 min, land within ±1 min of the requested time

In-session **swap** substitutes deterministically within the same pillar, pattern, difficulty band, and time budget. No step ever calls a model or a server.

## Code Standards

- Files under 200 lines - smaller files are easier to learn from
- Always use `Theme.Colors`, `Theme.Typography`, `Theme.Spacing` - never hardcode
- Button height: 56pt. Card corner radius: 16pt. Touch targets: 44pt min (60pt on workout screens)
- Enums conform to `Codable`, `CaseIterable`, and `Identifiable` where they have a stable id
- New logic must have corresponding tests in `FitSnackTests/`

## Where Things Live

All paths relative to `ios/FitSnack/FitSnack/` unless noted.

> **Clean rebuild in progress.** The previous Phase 2 app was removed (git history, commit `23fd56f`); only the US-A01 scaffold (`App/`, `DesignSystem/Theme.swift`, `Views/RootView.swift`) exists today. The rest lands story-by-story per the PRD. The table below is the target layout each story fills in.

| Area | Path |
|------|------|
| App entry point | `App/FitSnackApp.swift` |
| Domain models | `Models/` (Codable structs and enums) |
| Service protocols | `Services/Protocols/` |
| Mock implementations | `Services/Mock/` (wired in `ServiceContainer`) |
| Core engine | `Services/` (deterministic session engine + `PhaseEvaluator`/Consistency Score) |
| Dependency injection | `DI/ServiceContainer.swift` |
| ViewModels | `ViewModels/` |
| Views by feature | `Views/{Onboarding,Home,Workout,Progress}/` |
| Design system | `DesignSystem/Theme.swift` |
| Persistence | `Persistence/` (CoreData stack + conversions) |
| Exercise data | `Resources/Exercises.json` (~38 bodyweight movements, all `equipment == []`) |
| Tests | `ios/FitSnack/FitSnackTests/` |

## Report Location

Save completion reports to `.claude/agent/report/` and `artifacts/reports/`.
