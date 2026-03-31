# FitSnack Phase 1 MVP — Implementation Plan

## Context

FitSnack is an AI-powered micro-workout iOS app for busy parents/professionals (5-30 min workouts). This plan covers the Phase 1 MVP (8 weeks). The user chose:
- **iOS app first** with mock data (Convex backend integrated later)
- **Convex** as backend (native Swift SDK available)
- **Monorepo**: `/ios` and `/convex` directories
- **SwiftData** for local persistence (iOS 17+ target)
- **All 4 tabs functional**: Home, Progress, Challenges, Profile
- **30 exercises** bundled as JSON
- **Dev-mode auth** (no Apple Sign In yet)
- **Protocol-based services** so mock implementations swap to Convex later with zero view changes

## Monorepo Structure

```
FitSnack/
  ios/
    FitSnack.xcodeproj/
    FitSnack/                   # Swift source
    FitSnackTests/
  convex/                       # Added post-Phase 1
    convex/
      schema.ts
      functions/
    package.json
  .gitignore
```

## Architecture: Protocol-Based Service Layer

```swift
protocol WorkoutServiceProtocol {
    func generateWorkout(duration: Int, profile: UserProfile) async throws -> Workout
    func completeWorkout(_ workout: Workout, rating: Int, difficulty: String) async throws
    func getHistory() async throws -> [Workout]
}

class MockWorkoutService: WorkoutServiceProtocol { ... }      // Phase 1
class ConvexWorkoutService: WorkoutServiceProtocol { ... }    // Future
```

All services injected via `ServiceContainer` in SwiftUI `@Environment`. State management uses `@Observable` (Observation framework, iOS 17+).

---

## Sprint 1 (Week 1): Project Foundation & Design System

### 1.1 Create Monorepo and Xcode Project
- Init git repo at `FitSnack/`
- Create Xcode project (SwiftUI App template) inside `ios/`
- Target: iOS 17.0, bundle ID: `com.fitsnack.app`
- Add `.gitignore` for Swift/Xcode + Node.js
- Add entitlements: HealthKit, Push Notifications
- Create `convex/` directory with `.gitkeep`

### 1.2 Design System: Colors
- Create 12 color sets in `Assets.xcassets/Colors/` with light/dark variants (PRD section 14.1)
- `DesignSystem/ColorTheme.swift`: static color references

### 1.3 Design System: Typography & Spacing
- `DesignSystem/Typography.swift`: all font styles from PRD 14.2 (including monospaced timer)
- `DesignSystem/Spacing.swift`: spacing constants, corner radii, button height from PRD 14.3
- `DesignSystem/Theme.swift`: namespace aggregating colors, typography, spacing

### 1.4 Reusable Components
- `DesignSystem/ButtonStyles.swift`: `PrimaryButtonStyle` (brand, 56pt, full-width), `SecondaryButtonStyle`
- `DesignSystem/CardStyle.swift`: card modifier (white bg, 16pt radius, shadow)
- `Components/PrimaryButton.swift`, `SecondaryButton.swift`, `FitSnackCard.swift`, `SelectableChip.swift`

### 1.5 Navigation Shell
- `Views/MainTabView.swift`: 4-tab TabView (Home, Progress, Challenges, Profile) with SF Symbols
- Placeholder views for each tab
- `Utilities/AppState.swift`: `@Observable` class with `isOnboarded`, `selectedTab`
- `FitSnackApp.swift`: conditionally show onboarding or main tabs

### 1.6 Enum Models
- `Models/Enums/`: `FitnessLevel`, `PrimaryGoal`, `Equipment`, `MuscleGroup`, `MovementPattern`, `WorkoutStatus`
- All conform to `Codable`, `CaseIterable`, `Identifiable`

---

## Sprint 2 (Week 2): Data Models, Persistence, Services, Exercise DB

### 2.1 Domain Models (plain Swift structs, `Codable`)
- `Models/Exercise.swift`, `UserProfile.swift`, `Workout.swift`, `WorkoutBlock.swift`, `WorkoutExercise.swift`, `SetLog.swift`, `Badge.swift`, `WorkoutHistory.swift`

### 2.2 SwiftData Persistence Models
- `Persistence/SwiftDataModels/`: `SDUserProfile`, `SDWorkout`, `SDWorkoutExercise`, `SDSetLog` (`@Model` classes)
- `Persistence/ModelContainer+Extension.swift`: configure container

### 2.3 Service Protocols
- `Services/Protocols/`: `AuthServiceProtocol`, `WorkoutServiceProtocol`, `ExerciseServiceProtocol`, `UserServiceProtocol`, `HealthKitServiceProtocol`, `NotificationServiceProtocol`, `SubscriptionServiceProtocol`

### 2.4 DI Container
- `DI/ServiceContainer.swift`: `@Observable` class holding all service instances, injected at app root

### 2.5 Mock Auth Service
- `Services/Mock/MockAuthService.swift`: stores username in UserDefaults, generates UUID

### 2.6 Exercise Database (30 exercises)
- `Resources/Exercises.json`: 30 exercises covering:
  - Bodyweight Upper (6), Lower (6), Core (5)
  - Dumbbell Upper (4), Lower (3)
  - Warmup (3), Cooldown (3)
- Full data per exercise: muscle groups, equipment, difficulty, MET, timing, instructions, regressions/progressions

### 2.7 Mock Exercise Service
- `Services/Mock/MockExerciseService.swift`: loads JSON, provides filter/search methods

### 2.8 Mock User Service
- `Services/Mock/MockUserService.swift`: SwiftData-backed profile CRUD

---

## Sprint 3 (Week 3): Onboarding Flow (8 Screens)

### 3.1 OnboardingViewModel
- `ViewModels/OnboardingViewModel.swift`: `@Observable`, tracks `currentStep` (0-7), all profile fields, validation per step, imperial/metric toggle, `completeOnboarding()` saves to SwiftData

### 3.2 OnboardingContainerView
- Paged TabView with custom progress bar, back button, persists current step to UserDefaults

### 3.3-3.10 Individual Screens
| Screen | File | Key Elements |
|--------|------|-------------|
| 1. Welcome | `WelcomeView.swift` | Tagline, "Get Started" button (dev-mode auth) |
| 2. Profile | `ProfileSetupView.swift` | Name, age, sex, height/weight with unit toggle |
| 3. Fitness Level | `FitnessLevelView.swift` | 3 selectable cards (Beginner/Intermediate/Advanced) |
| 4. Goal | `GoalSelectionView.swift` | 5 goal cards, single-select |
| 5. Equipment | `EquipmentSelectionView.swift` | Multi-select grid, "Nothing" deselects all |
| 6. Weekly Goal | `WeeklyCommitmentView.swift` | Slider 2-7, default 3 |
| 7. Injuries | `InjuriesView.swift` | TextEditor + "Skip" button |
| 8. First Workout | `FirstWorkoutView.swift` | Time selector (5-30 min), "Generate My Workout" |

---

## Sprint 4 (Week 4): Workout Generation Engine & Home Screen

### 4.1 Workout Generation Engine
- `Services/WorkoutGenerationEngine.swift`: pure Swift, no network calls
  - Filters exercises by equipment, fitness level, injuries
  - Balances muscle groups across recent workout history
  - Allocates time: warmup (1-2 min) + main blocks (2-4) + cooldown (1 min if >10 min)
  - Calculates sets/reps to fit time budget using `estimatedTimePerSetSeconds`
  - Returns fully formed `Workout` object

### 4.2 Calorie Calculator
- `Services/CalorieCalculator.swift`: `MET * weightKg * durationHours` per exercise + rest/transitions

### 4.3 Mock Workout Service
- `Services/Mock/MockWorkoutService.swift`: generate, start, complete, swap, history — all backed by SwiftData

### 4.4 HomeViewModel
- `ViewModels/HomeViewModel.swift`: `todaysWorkout`, `selectedDuration`, `isGenerating`, streak/weekly stats, time-of-day greeting, auto-generates workout on appear

### 4.5 HomeView & Components
- `Views/Home/HomeView.swift`: ScrollView matching PRD 3.2 layout
- `WorkoutPreviewCard.swift`: focus, duration, calories, exercise preview, Start/Change/Regenerate
- `QuickStartGrid.swift`: 2x3 grid of duration buttons (5-30 min)
- `WeeklyProgressDots.swift`: Mon-Sun dots + "X of Y done"
- `AIInsightCard.swift`: rotating hardcoded insights
- `TimeSelector.swift`: duration slider
- `Components/StreakBadge.swift`, `Components/LoadingWorkoutView.swift`

---

## Sprint 5 (Week 5): Active Workout & Post-Workout Screens

### 5.1 WorkoutViewModel
- `ViewModels/WorkoutViewModel.swift`: `@Observable`, manages exercise/set progression, rest timer (Date-based), elapsed time, swap logic, haptic triggers, auto-saves state for resume

### 5.2 ActiveWorkoutView
- Full-screen cover (no tab bar), top bar with name/time/pause, progress bar, conditionally shows exercise or rest

### 5.3-5.6 Workout Sub-Views
- `ExerciseDisplayView.swift`: exercise name, SF Symbol placeholder, set/rep display, form tip, large "Done with Set" button (60pt+), swap/skip
- `SetTrackerView.swift`: horizontal set indicators (completed/current/upcoming)
- `RestTimerView.swift`: countdown with circular ring, next exercise preview, skip button, haptics + audio beeps
- `ExerciseSwapSheet.swift`: reason selection sheet, shows AI replacement

### 5.7 WorkoutCompleteView (Post-Workout)
- Celebration header, stats summary (duration, exercises, calories, muscles)
- `RatingPicker.swift`: 5 emoji buttons
- `DifficultyPicker.swift`: Too Easy / Just Right / Too Hard
- XP earned, streak update, "Done" button

### 5.8 Supporting Components
- `Components/ProgressRing.swift`, `Services/HapticManager.swift`

---

## Sprint 6 (Week 6): Progress Tab, Challenges Tab, Streaks

### 6.1 Streak & Gamification Logic
- Weekly streak calculation (Mon-Sun windows, consecutive weeks meeting goal)
- XP calculation: `duration * 3` + rating bonus + weekly/streak milestones (PRD 3.6)
- Level calculation from XP thresholds
- Badge unlock evaluation (10 badges: First Rep, Week One, Early Bird, Speed Demon, etc.)
- `Utilities/Constants.swift`: XP values, level thresholds, badge definitions

### 6.2-6.4 Progress Tab
- `ProgressViewModel.swift`: history, month stats, personal records, calendar data
- `ProgressTabView.swift`: month summary, calendar heat map, consistency score, PRs, recent workouts
- `CalendarHeatMap.swift`: LazyVGrid, 7 columns, green intensity by duration
- `WorkoutHistoryList.swift` + `WorkoutHistoryRow.swift`

### 6.5-6.7 Challenges Tab
- `ChallengesViewModel.swift`: badges (locked/unlocked), level, XP
- `ChallengesTabView.swift`: XP bar + badge grid + leaderboard placeholder
- `BadgesGridView.swift`, `BadgeDetailView.swift`, `LeaderboardPlaceholder.swift`
- `Components/XPProgressBar.swift`

---

## Sprint 7 (Week 7): Profile, Settings, StoreKit 2, HealthKit, Notifications

### 7.1-7.2 Profile & Settings
- `ProfileViewModel.swift`, `ProfileTabView.swift`
- `SettingsView.swift`: grouped List per PRD 3.9 (Account, Workout Prefs, Notifications, App Prefs, Privacy, Support)
- `ProfileEditView.swift`, `EquipmentEditView.swift`, `NotificationSettingsView.swift`

### 7.3 StoreKit 2 Subscriptions
- `Services/SubscriptionService.swift`: Product loading, purchase, entitlement check, restore, transaction listener
- Product IDs: `com.fitsnack.premium.monthly` ($7.99), `com.fitsnack.premium.annual` ($59.99)
- 14-day free trial
- `SubscriptionViewModel.swift`, `SubscriptionView.swift`, `PaywallView.swift` (PRD 4.4 layout)

### 7.4 HealthKit
- `Services/HealthKitService.swift`: request write auth, write `HKWorkout` with type/duration/calories on completion
- Add entitlements + Info.plist usage descriptions

### 7.5 Push Notifications (Local)
- `Services/NotificationService.swift`: `UNUserNotificationCenter` for daily reminders, streak-at-risk warnings
- Max 1/day, configurable time

### 7.6 Wire Everything
- Update `ServiceContainer` with all real services
- Update `FitSnackApp.swift`: init ModelContainer, ServiceContainer, StoreKit listener

---

## Sprint 8 (Week 8): Polish, Testing, Integration

### 8.1 End-to-End Flow Testing
- Full flow: launch -> onboarding -> workout -> complete -> history -> badges -> settings
- Fix navigation edge cases, app backgrounding during workout, data persistence

### 8.2 Unit Tests
- `WorkoutGenerationTests.swift`: duration accuracy, warmup inclusion, equipment filtering, muscle balancing, injury avoidance
- `CalorieCalculatorTests.swift`: MET calculation accuracy
- `StreakLogicTests.swift`: increment, reset, boundary conditions
- `ExerciseFilterTests.swift`: equipment, muscle group, difficulty filters
- `ModelTests.swift`: JSON decoding, encode/decode roundtrip

### 8.3 Edge Cases
- Empty states (no history, no badges, first day of week)
- Workout cancellation (save partial or discard)
- App background/foreground during workout (Date-based timer, not tick-based)

### 8.4 Accessibility
- `accessibilityLabel` on all interactive elements
- VoiceOver navigation order
- Dynamic Type scaling
- Color contrast 4.5:1
- 44pt+ touch targets (60pt on workout screen)

### 8.5 Visual Polish
- Consistent design system usage, subtle animations, loading states, empty states, dark mode verification

### 8.6 TestFlight Prep
- Version 1.0.0, configure App Store Connect, privacy labels, archive + upload

---

## Convex Integration Path (Post Phase 1)

1. `npx convex init` in `convex/` directory
2. Define schema in `convex/schema.ts` mirroring SwiftData models
3. Write Convex functions (queries/mutations/actions including Claude API for workout generation)
4. Add `convex-swift` SPM dependency
5. Create `Convex` implementations of each service protocol
6. Swap in `ServiceContainer` (one-line change per service)
7. SwiftData becomes offline cache layer

**Zero changes to Views or ViewModels required.**

---

## Verification Plan

1. **Build & Run**: Project compiles and runs in iOS 17 Simulator
2. **Onboarding**: Complete all 8 screens, data persists in SwiftData
3. **Workout Loop**: Generate -> Start -> Complete sets -> Rest timer -> Swap -> Complete -> Rating
4. **Progress**: Completed workouts appear in history, stats update, calendar populates
5. **Streaks**: Weekly streak increments correctly, XP accumulates, badges unlock
6. **Challenges**: Badge grid shows locked/unlocked state correctly
7. **Settings**: Equipment/preference changes persist and affect workout generation
8. **StoreKit**: Paywall displays, sandbox purchase works
9. **HealthKit**: Completed workout written to Health app
10. **Notifications**: Daily reminder schedules at correct time
11. **Unit Tests**: All tests pass (`Cmd+U`)
12. **Dark Mode**: All screens render correctly in both modes
