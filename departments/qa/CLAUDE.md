# QA Context — FitSnack iOS

For project-wide context (build commands, architecture), see root `CLAUDE.md`.

## How to Run Tests

```bash
# Generate project first if .xcodeproj is stale
cd ios/FitSnack && xcodegen generate

# Run all tests (the single FitSnack scheme builds the app and runs the FitSnackTests target)
xcodebuild -project ios/FitSnack/FitSnack.xcodeproj -scheme FitSnack \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Tests use `@testable import FitSnack` and `XCTestCase`.

## Existing Test Coverage

Clean rebuild in progress - only the US-A01 scaffold test exists today; the rest lands with its owning story.

| Test File | What It Covers |
|-----------|---------------|
| `ScaffoldTests.swift` | Design-token values (button/card/touch sizes) |

Planned coverage, added as each story lands: deterministic engine (session shape, pillar/pattern staleness, filtering, progression chains, Adaptive Overload, timing fit, swap); Consistency Score (empty history, perfect run, single-miss dent, 5-min show-up, rolling weighting); `PhaseEvaluator` (consistency-only and competence-only stay Discipline, both-met promotes, fresh user Discipline); models/enums (Codable round-trips, stable raw values); persistence (`CDUser`/`CDWorkoutLog` save/fetch round-trips).

## Critical Paths to Test

- **Session generation:** exercises match phase, injury, and difficulty filters; everything is bodyweight; primary pattern never repeats yesterday's; session lands within ±1 min of the requested time; warmup always present, cooldown over 10 min
- **Consistency Score:** a single miss dents but never zeroes; a 5-min session counts as a full show-up; recent weeks weighted more; `longestChain` tracked correctly
- **PhaseEvaluator:** consistency-only and competence-only stay Discipline; both-met promotes to Strength; a fresh user resolves to Discipline
- **Onboarding:** the flow stores all profile fields (fitness level, goals, injuries, sitting hours, weekly goal) correctly
- **Persistence:** domain model ↔ CoreData entity conversion (`toUser()`/`update(from:)`), especially JSON-encoded `Data` fields for complex types
- **Service protocol compliance:** every mock service fully implements its protocol

## Common Edge Cases

- Empty exercise database or all exercises filtered out should fall back gracefully
- Consistency Score with an empty history; a single missed week (dents, not zeroes)
- Rolling-window weighting at week boundaries
- A profile with an empty injuries array should not filter any exercises
- Every exercise carries `equipment == []` (Zero-Equipment Floor); flag any that do not
- PhaseEvaluator with zero history resolves to the Discipline Phase

## Report Location

Save test reports to `artifacts/reports/test-results/` using the format defined in `agent.md`.
