# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FitSnack is an AI-powered micro-workout iOS app (5-30 min workouts) for busy parents/professionals. Phase 1 MVP uses mock data locally; Convex backend integrates post-MVP with zero view/viewmodel changes.

## Department System

The project uses persona-based agents invoked via slash commands:

| Command | Department | Persona | Role |
|---------|-----------|---------|------|
| `/eng` | Engineering | John | Writes clear, well-commented code with tests |
| `/qa` | QA | Bryan | Tests thoroughly, explains findings for beginners |
| `/pm` | PM | Peter | Translates tech to plain English, writes PRDs |

**Context composition chain:** Root `CLAUDE.md` (project-wide) → `departments/{dept}/CLAUDE.md` (domain knowledge) → `departments/{dept}/agent.md` (persona & rules).

Commands live in `.claude/commands/`. PRD generation skill: `.claude/skills/prd/PRD_SKILL.md`.

## Build & Run

```bash
# Generate Xcode project from project.yml (requires xcodegen)
cd ios/FitSnack && xcodegen generate

# Build
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack -sdk iphonesimulator -configuration Debug build

# Run tests
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnackTests -sdk iphonesimulator -configuration Debug test

# Open in Xcode
open ios/FitSnack/FitSnack.xcodeproj
```

Target: iOS 17.0+, Swift 5.9, Xcode 16.3. Bundle ID: `com.fitsnack.app`.

## Architecture

**Monorepo:** `ios/` (SwiftUI app) + `convex/` (backend, placeholder for now).

**MVVM + Protocol-Based Services:**
- **Views** access services via `@Environment(\.services)` (custom `EnvironmentKey`)
- **ViewModels** are `@Observable` classes (Observation framework, not ObservableObject)
- **Services** are protocol-defined (`Services/Protocols/`) with mock implementations (`Services/Mock/`)
- **ServiceContainer** (`DI/ServiceContainer.swift`) holds all service instances, injected at app root

To swap a mock for a real implementation, change one line in `ServiceContainer` — views and viewmodels remain untouched.

**Persistence:** SwiftData with two models (`SDUserProfile`, `SDWorkout`). Domain models are plain `Codable` structs; SwiftData models use `toUserProfile()`/`update(from:)` conversion methods. Complex fields stored as base64-encoded JSON strings.

**Navigation:** `AppState` (`@Observable`) controls onboarding vs main tabs. 4 tabs: Home, Progress, Challenges, Profile.

## Key Conventions

- Use `@Observable` (Observation framework), never `ObservableObject`/`@Published`
- All service methods are `async throws`
- Enums conform to `Codable`, `CaseIterable`, `Identifiable`
- Design system tokens via `Theme.Colors`, `Theme.Typography`, `Theme.Spacing` — always use these, never hardcode colors/fonts/spacing
- Button height: 56pt. Card corner radius: 16pt. Touch targets: 44pt minimum (60pt on workout screens)
- Exercise database: 30 exercises in `Resources/Exercises.json`, loaded by `MockExerciseService`
- Workout generation: `WorkoutGenerationEngine` — pure Swift, no network calls, uses MET-based calorie calculation
- Gamification logic lives in `Utilities/Constants.swift` — XP, levels, badges, streaks (see Gamification section below)
- Check `.claude/agent/tasks/` for the relevant PRD before building new features

## Testing

Tests live in `ios/FitSnack/FitSnackTests/` (7 test files). Pattern: `XCTestCase` + `@testable import FitSnack`.

| Test File | Coverage |
|-----------|----------|
| `WorkoutGenerationTests` | Duration, warmup, equipment filtering, muscle balancing, injury filtering, bodyweight fallback |
| `CalorieCalculatorTests` | MET formula, rest overhead, zero duration, empty workout |
| `StreakLogicTests` | Empty history, consecutive weeks, missed week reset, week boundaries |
| `ExerciseFilterTests` | Equipment, difficulty, injury avoidance |
| `ModelTests` | Encoding/decoding, Codable conformance |
| `ColorAssetTests` | Design system color asset verification |

All new logic must have corresponding tests.

## Key Files

| File | Role |
|------|------|
| `FitSnackApp.swift` | App entry point, ModelContainer + ServiceContainer init |
| `DI/ServiceContainer.swift` | All service protocols composed; environment injection |
| `Services/WorkoutGenerationEngine.swift` | Workout algorithm: filter → time allocation → muscle balancing → set/rep fitting |
| `Services/CalorieCalculator.swift` | MET × weight × duration formula |
| `Utilities/Constants.swift` | XP values, level thresholds, 10 badge definitions |
| `Utilities/AppState.swift` | `isOnboarded`, `selectedTab` — persisted to UserDefaults |
| `Resources/Exercises.json` | 30-exercise database with full metadata |
| `Persistence/ModelContainer+Extension.swift` | SwiftData schema configuration |

## Gamification System

All logic in `Utilities/Constants.swift`.

**XP:** `(durationMinutes × 3) + ratingBonus[rating]`. Rating bonus: 1→0, 2→5, 3→10, 4→15, 5→25. Weekly goal bonus: 50. Streak milestone bonus: 100.

**Levels:** 11 levels with XP thresholds: `[0, 100, 300, 600, 1000, 1500, 2100, 2800, 3600, 4500, 5500]`.

**Badges** (10 total):
- `first_rep` — 1 workout | `week_one` — 7 consecutive days | `early_bird` — workout before 7 AM
- `speed_demon` — 5-min workout | `endurance_king` — 30-min workout
- `streak_starter` — 2-week streak | `iron_will` — 4-week streak | `centurion` — 100 workouts
- `variety_pack` — 5 equipment types | `full_body` — all 6 major muscle groups in one week

**Weekly Streak:** Counts consecutive ISO weeks where workouts ≥ weeklyGoal, walking backwards from current week.

## Artifact Locations

| Artifact | Path |
|----------|------|
| PRDs / task briefs | `.claude/agent/tasks/` |
| Completion reports | `.claude/agent/report/` |
| Engineering reports | `artifacts/reports/` |
| QA test results | `artifacts/reports/test-results/` |
| PM learning summaries | `artifacts/learning-logs/` |
| Specs / briefs | `artifacts/specs/` |

## Convex Integration Path

Post-MVP: init Convex in `convex/`, define TS schema mirroring SwiftData models, write query/mutation/action functions, create `Convex*Service` implementations of existing protocols, swap in `ServiceContainer`. The JS/TS SDK is used for backend functions; the Swift SDK connects the iOS client.
