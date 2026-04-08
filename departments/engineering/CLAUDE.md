# Engineering Context — FitSnack iOS

For project-wide context (build commands, bundle ID, targets), see root `CLAUDE.md`.

## Architecture Deep Dive

**Service Protocol Pattern:** Define abstractions in `Services/Protocols/`, implement in `Services/Mock/` (Phase 1). Post-MVP, create `Convex*Service` implementations and swap one line in `ServiceContainer`. Views and ViewModels never change.

**Environment Injection:** `ServiceContainer` is composed in `FitSnackApp.swift` and injected via `@Environment(\.services)`. All service methods are `async throws`.

**ViewModels:** Always `@Observable` (Observation framework). Never use `ObservableObject`/`@Published`/Combine.

**SwiftData Persistence:** Domain models are plain `Codable` structs. SwiftData models (`SDUserProfile`, `SDWorkout`) convert via `toUserProfile()`/`update(from:)`. Complex fields (arrays, nested objects) stored as base64-encoded JSON strings.

**Navigation:** `AppState` (`@Observable`) drives onboarding vs main tabs. 4 tabs: Home, Progress, Challenges, Profile.

## Workout Generation Engine

`WorkoutGenerationEngine.swift` — pure Swift, no network calls:

1. **Filter** exercises by equipment + difficulty + injury avoidance
2. **Fallback** to bodyweight if all exercises filtered out
3. **Allocate** warmup (3 min) and cooldown (2 min)
4. **Divide** remaining time into blocks
5. **Balance** muscle groups via least-used priority
6. **Fit** sets/reps within time budget per exercise

Calorie calculation: `CalorieCalculator.swift` uses MET × weight × duration with 1.1× rest overhead.

## Code Standards

- Files under 200 lines — smaller files are easier to learn from
- Always use `Theme.Colors`, `Theme.Typography`, `Theme.Spacing` — never hardcode
- Button height: 56pt. Card corner radius: 16pt. Touch targets: 44pt min (60pt on workout screens)
- Reusable UI components live in `Components/` (10 components)
- Enums conform to `Codable`, `CaseIterable`, `Identifiable`
- New logic must have corresponding tests in `FitSnackTests/`

## Where Things Live

All paths relative to `ios/FitSnack/FitSnack/` unless noted.

| Area | Path |
|------|------|
| Domain models | `Models/` (8 structs) + `Models/Enums/` (8 enums) |
| Service protocols | `Services/Protocols/` (7 protocols) |
| Mock implementations | `Services/Mock/` (7 mocks) |
| Core algorithms | `Services/WorkoutGenerationEngine.swift`, `Services/CalorieCalculator.swift` |
| ViewModels | `ViewModels/` (7 view models) |
| Views by feature | `Views/{Home,Progress,Challenges,Workout,Profile,Onboarding,Settings,Paywall}/` |
| Design system | `DesignSystem/` |
| Reusable components | `Components/` (10 components) |
| Persistence | `Persistence/SwiftDataModels/` |
| Exercise data | `Resources/Exercises.json` (30 exercises) |
| Tests | `ios/FitSnack/FitSnackTests/` (7 test files) |

## Report Location

Save completion reports to `.claude/agent/report/` and `artifacts/reports/`.
