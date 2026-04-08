# QA Context — FitSnack iOS

For project-wide context (build commands, architecture), see root `CLAUDE.md`.

## How to Run Tests

```bash
# Generate project first if .xcodeproj is stale
cd ios/FitSnack && xcodegen generate

# Run all tests
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnackTests -sdk iphonesimulator -configuration Debug test
```

Tests use `@testable import FitSnack` and `XCTestCase`.

## Existing Test Coverage

| Test File | What It Covers |
|-----------|---------------|
| `WorkoutGenerationTests.swift` | Duration matching, warmup inclusion, equipment filtering, muscle group balancing, injury filtering, bodyweight fallback |
| `CalorieCalculatorTests.swift` | MET formula, multiple exercises, rest overhead, zero duration, skipped exercises, empty workout, set timestamps |
| `StreakLogicTests.swift` | Empty history, consecutive weeks, missed week reset, ISO week boundaries |
| `ExerciseFilterTests.swift` | Equipment filtering, difficulty matching, injury avoidance |
| `ModelTests.swift` | Model encoding/decoding, Codable conformance |
| `ColorAssetTests.swift` | Design system color asset verification |
| `FitSnackTests.swift` | Basic app test scaffold |

## Critical Paths to Test

- **Workout generation:** Exercises match equipment, difficulty, and injury filters; time budget not exceeded; muscle groups balanced; bodyweight fallback works
- **Gamification:** XP = `(durationMinutes × 3) + ratingBonus[rating]`; level thresholds [0,100,300,600,1000,1500,2100,2800,3600,4500,5500]; 10 badge unlock conditions; weekly streak calculation
- **Onboarding:** 8-screen flow stores all profile fields correctly in SwiftData
- **Persistence:** Domain model ↔ SwiftData model conversion, especially base64 JSON fields for complex types
- **Service protocol compliance:** All 7 mock services fully implement their protocol

## Common Edge Cases

- Empty exercise database or all exercises filtered out → should fallback to bodyweight
- Zero-duration workout → CalorieCalculator should return minimum of 1, not 0
- Streak calculation at ISO week boundaries (Sunday/Monday transitions)
- UserProfile with empty injuries array → should not filter any exercises
- Equipment set containing `.none` (bodyweight) mixed with other equipment types
- Badge evaluation with zero workouts, zero streak, empty collections

## Report Location

Save test reports to `artifacts/reports/test-results/` using the format defined in `agent.md`.
