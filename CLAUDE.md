# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FitSnack is an AI-powered micro-workout iOS app (5-30 min workouts) for busy parents/professionals. Phase 1 MVP uses mock data locally; Convex backend integrates post-MVP with zero view/viewmodel changes.

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

## Convex Integration Path

Post-MVP: init Convex in `convex/`, define TS schema mirroring SwiftData models, write query/mutation/action functions, create `Convex*Service` implementations of existing protocols, swap in `ServiceContainer`. The JS/TS SDK is used for backend functions; the Swift SDK connects the iOS client.
