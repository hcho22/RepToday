# PRD: FitSnack Phase 1 MVP

## 1. Introduction/Overview

FitSnack is an AI-powered micro-workout iOS app designed for busy parents and professionals who need quick, effective workouts (5–30 minutes). Phase 1 delivers a fully functional MVP with mock data, local persistence via SwiftData, and a protocol-based service layer that enables zero-view-change migration to a Convex backend post-MVP.

This PRD covers the complete Phase 1 scope: project foundation, design system, data layer, onboarding, workout generation & execution, progress tracking, challenges/gamification, and profile/settings. StoreKit subscriptions, HealthKit integration, and push notifications are **deferred** to a separate PRD.

---

## 2. Goals

- Deliver a fully functional 4-tab iOS app (Home, Progress, Challenges, Profile) running on mock data
- Implement a protocol-based service architecture so that swapping mock services for Convex-backed services requires zero changes to views or viewmodels
- Bundle 30 exercises as a local JSON database with full metadata (muscle groups, equipment, difficulty, MET values, instructions)
- Build a pure-Swift workout generation engine that creates balanced, time-fitted workouts
- Implement gamification (XP, levels, streaks, 10 badges) to drive retention
- Establish a design system with color, typography, and spacing tokens used consistently across all screens
- Target iOS 17.0+, Swift 5.9, Xcode 16.3

---

## 3. User Stories

### Sprint 1: Project Foundation & Design System

---

#### US-001: Create Monorepo and Xcode Project

**Description:** As a developer, I want the project scaffolded as a monorepo with a properly configured Xcode project so that I have a clean starting point for development.

**Acceptance Criteria:**

- [x] Git repo initialized at `FitSnack/` root
- [x] Xcode project created inside `ios/FitSnack/` using SwiftUI App template
- [x] Deployment target set to iOS 17.0
- [x] Bundle ID set to `com.fitsnack.app`
- [x] `.gitignore` covers Swift/Xcode and Node.js artifacts
- [x] HealthKit and Push Notification entitlements added
- [x] `convex/` directory created with `.gitkeep`
- [x] `project.yml` for XcodeGen configured and project generates successfully
- [x] Project builds with zero errors on iOS Simulator

---

#### US-002: Create Color Design Tokens

**Description:** As a developer, I want a centralized color system so that all screens use consistent brand colors with light/dark mode support.

**Acceptance Criteria:**

- [x] 12 color sets created in `Assets.xcassets/Colors/` with light and dark variants
- [x] `DesignSystem/ColorTheme.swift` created with static `Color` references for all 12 colors
- [x] Colors accessible via `Theme.Colors` namespace
- [x] Light and dark mode variants render correctly in Xcode preview

---

#### US-003: Create Typography Design Tokens

**Description:** As a developer, I want centralized typography styles so that all text uses consistent fonts and sizes.

**Acceptance Criteria:**

- [x] `DesignSystem/Typography.swift` created with all font styles (including monospaced timer font)
- [x] Font styles accessible via `Theme.Typography` namespace
- [x] Styles cover: large title, title, headline, body, caption, button, timer display
- [x] Typecheck passes

---

#### US-004: Create Spacing Design Tokens

**Description:** As a developer, I want centralized spacing and layout constants so that all screens have consistent padding, margins, and sizing.

**Acceptance Criteria:**

- [x] `DesignSystem/Spacing.swift` created with spacing constants (4, 8, 12, 16, 20, 24, 32, 48)
- [x] Corner radii constants defined (card: 16pt, button: 12pt, chip: 8pt)
- [x] Button height constant: 56pt
- [x] Minimum touch target constant: 44pt (60pt for workout screens)
- [x] Accessible via `Theme.Spacing` namespace
- [x] Typecheck passes

---

#### US-005: Create Theme Namespace

**Description:** As a developer, I want a single `Theme` namespace aggregating colors, typography, and spacing so that design tokens are easy to discover and use.

**Acceptance Criteria:**

- [x] `DesignSystem/Theme.swift` created as namespace enum with `Colors`, `Typography`, `Spacing` nested references
- [x] All design tokens accessible via `Theme.Colors.xxx`, `Theme.Typography.xxx`, `Theme.Spacing.xxx`
- [x] Typecheck passes

---

#### US-006: Create PrimaryButtonStyle

**Description:** As a developer, I want a reusable primary button style matching the brand design so that all CTAs are consistent.

**Acceptance Criteria:**

- [x] `DesignSystem/ButtonStyles.swift` created with `PrimaryButtonStyle` conforming to `ButtonStyle`
- [x] Button uses brand color background, white text, 56pt height, full-width, rounded corners
- [x] Disabled state has reduced opacity
- [x] Pressed state has visual feedback (scale or opacity change)
- [x] Typecheck passes

---

#### US-007: Create SecondaryButtonStyle

**Description:** As a developer, I want a secondary button style for less prominent actions.

**Acceptance Criteria:**

- [x] `SecondaryButtonStyle` added to `ButtonStyles.swift`
- [x] Outlined style: brand color border, brand color text, transparent background
- [x] 56pt height, full-width, rounded corners
- [x] Disabled and pressed states styled appropriately
- [x] Typecheck passes

---

#### US-008: Create FitSnackCard Component

**Description:** As a developer, I want a reusable card component so that content sections have consistent styling.

**Acceptance Criteria:**

- [x] `Components/FitSnackCard.swift` created as a ViewModifier or container view
- [x] White background (adaptive for dark mode), 16pt corner radius, subtle shadow
- [x] 16pt internal padding
- [x] Typecheck passes

---

#### US-009: Create SelectableChip Component

**Description:** As a developer, I want a selectable chip component for multi-select and single-select UI patterns.

**Acceptance Criteria:**

- [x] `Components/SelectableChip.swift` created
- [x] Shows label text with selected/unselected visual states
- [x] Selected state: brand color fill, white text
- [x] Unselected state: border only, brand color text
- [x] 44pt minimum touch target
- [x] Typecheck passes

---

#### US-010: Create MainTabView Navigation Shell

**Description:** As a developer, I want the 4-tab navigation structure so that users can switch between main sections.

**Acceptance Criteria:**

- [x] `Views/MainTabView.swift` created with TabView containing 4 tabs
- [x] Tabs: Home (house icon), Progress (chart.bar icon), Challenges (trophy icon), Profile (person icon)
- [x] SF Symbol icons used for each tab
- [x] Each tab shows a placeholder view with tab name
- [x] Selected tab uses brand color tint
- [x] Typecheck passes

---

#### US-011: Create AppState

**Description:** As a developer, I want a central app state object to manage onboarding status and selected tab.

**Acceptance Criteria:**

- [x] `Utilities/AppState.swift` created as `@Observable` class
- [x] `isOnboarded: Bool` property persisted to UserDefaults
- [x] `selectedTab: Int` property for tracking active tab (implemented as typed `Tab` enum)
- [x] Typecheck passes

---

#### US-012: Configure FitSnackApp Entry Point

**Description:** As a developer, I want the app entry point to conditionally show onboarding or main tabs based on app state.

**Acceptance Criteria:**

- [x] `FitSnackApp.swift` checks `AppState.isOnboarded`
- [x] If not onboarded: shows onboarding container (placeholder for now)
- [x] If onboarded: shows `MainTabView`
- [x] `AppState` injected into environment
- [x] App launches successfully in simulator
- [x] Typecheck passes

---

#### US-013: Create Enum Models

**Description:** As a developer, I want all domain enums defined so that models and services can reference them.

**Acceptance Criteria:**

- [x] `Models/Enums/FitnessLevel.swift`: cases `beginner`, `intermediate`, `advanced`
- [x] `Models/Enums/PrimaryGoal.swift`: cases for 5 goals (e.g., loseWeight, buildMuscle, improveEndurance, stayActive, reduceStress)
- [x] `Models/Enums/Equipment.swift`: cases for equipment types (none/bodyweight, dumbbells, resistanceBands, pullUpBar, yogaMat)
- [x] `Models/Enums/MuscleGroup.swift`: cases for major muscle groups
- [x] `Models/Enums/MovementPattern.swift`: cases for movement patterns (push, pull, squat, hinge, core, cardio)
- [x] `Models/Enums/WorkoutStatus.swift`: cases `generated`, `inProgress`, `completed`, `cancelled`
- [x] All enums conform to `Codable`, `CaseIterable`, `Identifiable`
- [x] Typecheck passes

---

### Sprint 2: Data Models, Persistence, Services, Exercise DB

---

#### US-014: Create Exercise Domain Model

**Description:** As a developer, I want an Exercise model so that exercises can be loaded, filtered, and used in workout generation.

**Acceptance Criteria:**

- [x] `Models/Exercise.swift` created as a `Codable` struct
- [x] Properties: `id`, `name`, `description`, `instructions` (array of strings), `muscleGroups` (primary/secondary), `equipment`, `difficulty`, `movementPattern`, `metValue`, `estimatedTimePerSetSeconds`, `defaultSets`, `defaultReps`, `regressions`, `progressions`, `isWarmup`/`isCooldown` (via `category: ExerciseCategory` with `.warmup`/`.cooldown` cases)
- [x] JSON decoding works with the `Exercises.json` format
- [x] Typecheck passes

---

#### US-015: Create UserProfile Domain Model

**Description:** As a developer, I want a UserProfile model to store user preferences and physical attributes.

**Acceptance Criteria:**

- [x] `Models/UserProfile.swift` created as a `Codable` struct
- [x] Properties: `id`, `displayName`, `age`, `sex`, `heightCm`, `weightKg`, `fitnessLevel`, `primaryGoal`, `availableEquipment` (array), `weeklyWorkoutGoal` (Int), `injuries` (String), `typicalAvailableMinutes` (Int), `createdAt`, `updatedAt` — plus `unitSystem`, `Sex` and `UnitSystem` nested enums
- [x] Typecheck passes

---

#### US-016: Create Workout Domain Model

**Description:** As a developer, I want Workout, WorkoutBlock, WorkoutExercise, and SetLog models to represent a complete workout session.

**Acceptance Criteria:**

- [x] `Models/Workout.swift`: `id`, `userId`, `status` (WorkoutStatus), `requestedDurationMinutes`, blocks (`warmup`/`mainBlocks`/`cooldown`), `estimatedCalories`, `actualCalories`, `userRating` (optional Int), `perceivedDifficulty`, `xpEarned`, `startedAt`, `completedAt`, `createdAt`
- [x] `Models/WorkoutBlock.swift`: `id`, `name`, `type`, `exercises` (array of WorkoutExercise), plus `restBetweenExercisesSeconds`, `rounds`, `timeLimitSeconds`
- [x] `Models/WorkoutExercise.swift`: `id`, `exercise` (Exercise), `sets`, `reps`, `restAfterSeconds`, `completedSets` (array of SetLog), plus `durationSeconds`, `skipped`, `substitutedWith`
- [x] `Models/SetLog.swift`: `id`, `setNumber`, `completed`, `reps` (optional Int), `completedAt` (timestamp)
- [x] All models are `Codable` structs
- [x] Typecheck passes

---

#### US-017: Create Badge and WorkoutHistory Models

**Description:** As a developer, I want Badge and WorkoutHistory models for the gamification and progress features.

**Acceptance Criteria:**

- [x] `Models/Badge.swift`: `id`, `name`, `description`, `iconName` (SF Symbol), `isUnlocked`, `unlockedAt` (optional Date), `criteria` (String describing unlock condition)
- [x] `Models/WorkoutHistory.swift`: `id`, `workoutId`, `date`, `durationMinutes`, `exerciseCount`, `caloriesBurned`, `muscleGroups` (array), `rating` (optional)
- [x] Both are `Codable` structs
- [x] Typecheck passes

---

#### US-018: Create SDUserProfile SwiftData Model

**Description:** As a developer, I want a SwiftData model for user profiles so that profile data persists across app launches.

**Acceptance Criteria:**

- [x] `Persistence/SwiftDataModels/SDUserProfile.swift` created with `@Model` attribute
- [x] All UserProfile fields stored (complex fields like `availableEquipment` stored as base64-encoded JSON string)
- [x] `toUserProfile()` method converts to domain model
- [x] `update(from: UserProfile)` method updates SwiftData model from domain model
- [x] Typecheck passes

---

#### US-019: Create SDWorkout SwiftData Model

**Description:** As a developer, I want a SwiftData model for workouts so that workout data persists locally.

**Acceptance Criteria:**

- [x] `Persistence/SwiftDataModels/SDWorkout.swift` created with `@Model` attribute
- [x] Stores full workout data (blocks/exercises/setLogs as JSON-encoded `Data` in `workoutDataRaw`)
- [x] `toWorkout()` method converts to domain model
- [x] `update(from: Workout)` method updates from domain model
- [x] Typecheck passes

---

#### US-020: Configure ModelContainer

**Description:** As a developer, I want the SwiftData ModelContainer configured so that persistence works throughout the app.

**Acceptance Criteria:**

- [x] `Persistence/ModelContainer+Extension.swift` created
- [x] Static method to create configured `ModelContainer` with `SDUserProfile` and `SDWorkout` schemas
- [x] Error handling for container creation failure
- [x] Typecheck passes

---

#### US-021: Create Service Protocols

**Description:** As a developer, I want all service protocols defined so that mock and future Convex implementations share the same interface.

**Acceptance Criteria:**

- [x] `Services/Protocols/AuthServiceProtocol.swift`: `signIn(displayName:)`, `signOut()`, `currentUserId`, `isAuthenticated`
- [x] `Services/Protocols/WorkoutServiceProtocol.swift`: `generateWorkout(duration:profile:)`, `startWorkout(_:)`, `completeWorkout(_:rating:difficulty:)`, `swapExercise(in:exerciseId:reason:)`, `getHistory()`, `getTodaysWorkout()`, `saveWorkout(_:)`
- [x] `Services/Protocols/ExerciseServiceProtocol.swift`: `getAllExercises()`, `getExercise(by:)`, `filterExercises(equipment:category:muscleGroup:difficulty:)`, `searchExercises(query:)`
- [x] `Services/Protocols/UserServiceProtocol.swift`: `getProfile()`, `saveProfile(_:)`, `updateProfile(_:)`, plus gamification methods (`getGamificationStats()`, `addXP(_:)`, `getBadges()`, `unlockBadge(_:)`)
- [x] All methods are `async throws`
- [x] Typecheck passes

---

#### US-022: Create ServiceContainer and Environment Injection

**Description:** As a developer, I want a dependency injection container so that services are accessible throughout the view hierarchy via SwiftUI environment.

**Acceptance Criteria:**

- [x] `DI/ServiceContainer.swift` created as `@Observable` class
- [x] Holds instances of all service protocols (auth, workout, exercise, user, healthKit, notification, subscription)
- [x] Custom `EnvironmentKey` defined for `ServiceContainer`
- [x] `EnvironmentValues` extension adds `\.services` keypath
- [x] `ServiceContainer` injected at app root in `FitSnackApp.swift`
- [x] Views can access via `@Environment(\.services) var services`
- [x] Typecheck passes

---

#### US-023: Create MockAuthService

**Description:** As a developer, I want a mock auth service so that dev-mode login works without a real backend.

**Acceptance Criteria:**

- [x] `Services/Mock/MockAuthService.swift` conforms to `AuthServiceProtocol`
- [x] `signIn(displayName:)` stores username in UserDefaults and generates a UUID user ID
- [x] `signOut()` clears stored credentials
- [x] `currentUserId` returns stored user ID or nil
- [x] `isAuthenticated` computed property checks UserDefaults
- [x] Typecheck passes

---

#### US-024: Create Exercise Database JSON

**Description:** As a developer, I want a bundled exercise database so that workouts can be generated offline.

**Acceptance Criteria:**

- [x] `Resources/Exercises.json` created with 30 exercises
- [x] Coverage: Bodyweight Upper/Lower, Core, Dumbbell Upper/Lower, Warmup (3), Cooldown (3) — uses `category` field instead of separate booleans
- [x] Each exercise has: `id`, `name`, `displayName`, `description`, `instructions`, `muscleGroups`, `equipment`, `difficulty`, `movementPattern`, `metValue`, `estimatedTimePerSetSeconds`, `defaultSets`, `defaultReps`, `regressions`, `progressions`, `category`
- [x] JSON is valid and decodes into `[Exercise]` without errors
- [x] Typecheck passes

---

#### US-025: Create MockExerciseService

**Description:** As a developer, I want a mock exercise service that loads exercises from the bundled JSON.

**Acceptance Criteria:**

- [x] `Services/Mock/MockExerciseService.swift` conforms to `ExerciseServiceProtocol`
- [x] Loads `Exercises.json` from app bundle on initialization
- [x] `getAllExercises()` returns full list
- [x] `getExercise(by:)` returns exercise by ID or nil
- [x] `filterExercises(equipment:category:muscleGroup:difficulty:)` filters by any combination of criteria
- [x] `searchExercises(query:)` searches by name, displayName, and tags (case-insensitive)
- [x] Typecheck passes

---

#### US-026: Create MockUserService

**Description:** As a developer, I want a mock user service backed by SwiftData for profile CRUD.

**Acceptance Criteria:**

- [x] `Services/Mock/MockUserService.swift` conforms to `UserServiceProtocol`
- [x] `getProfile()` fetches from SwiftData, converts to domain model
- [x] `createProfile(_:)` creates `SDUserProfile` in SwiftData (named `saveProfile(_:)` in protocol)
- [x] `updateProfile(_:)` updates existing `SDUserProfile`
- [x] `deleteProfile()` removes profile from SwiftData
- [x] Requires `ModelContext` injected via initializer
- [x] Typecheck passes

---

### Sprint 3: Onboarding Flow (8 Screens)

---

#### US-027: Create OnboardingViewModel

**Description:** As a user, I want the onboarding flow to collect my profile information step by step so that FitSnack can personalize my workouts.

**Acceptance Criteria:**

- [x] `ViewModels/OnboardingViewModel.swift` created as `@Observable` class
- [x] `currentStep: Int` (0–7) tracks progress
- [x] Properties for all profile fields: `displayName`, `age`, `sex`, `heightCm`, `weightKg`, `fitnessLevel`, `primaryGoal`, `availableEquipment`, `weeklyWorkoutGoal`, `injuries`, `selectedDuration`
- [x] `unitSystem` toggle for imperial/metric height/weight input with conversion helpers
- [x] Validation per step (e.g., name not empty, equipment not empty)
- [x] `canAdvance: Bool` computed property for current step
- [x] `completeOnboarding()` saves profile to SwiftData via UserService and sets `AppState.isOnboarded = true`
- [x] Current step persisted to UserDefaults via `persistStep()`/`restoreStep()` so onboarding resumes if interrupted
- [x] Typecheck passes

---

#### US-028: Create OnboardingContainerView

**Description:** As a user, I want to navigate through onboarding screens with a progress indicator so I know how far along I am.

**Acceptance Criteria:**

- [x] `Views/Onboarding/OnboardingContainerView.swift` created
- [x] Paged TabView (or equivalent) containing all 8 onboarding screens
- [x] Custom progress bar at top showing step X of 8
- [x] Back button on steps 1–7 (not on step 0/Welcome)
- [x] Forward navigation controlled by "Continue" button on each step
- [x] Smooth transition animations between steps
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-029: Create WelcomeView (Onboarding Step 1)

**Description:** As a new user, I want to see a welcome screen so I understand what FitSnack does before starting.

**Acceptance Criteria:**

- [x] `Views/Onboarding/WelcomeView.swift` created
- [x] App logo or icon displayed
- [x] Tagline text (e.g., "Quick workouts that fit your life")
- [x] "Get Started" primary button triggers dev-mode auth (auto-login with name prompt)
- [x] Uses `Theme` design tokens for all styling
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-030: Create ProfileSetupView (Onboarding Step 2)

**Description:** As a new user, I want to enter my basic profile info so FitSnack can calculate calories and tailor difficulty.

**Acceptance Criteria:**

- [x] `Views/Onboarding/ProfileSetupView.swift` created
- [x] Text field for name
- [x] Number input for age
- [x] Sex selection (Male/Female/Other/Prefer not to say)
- [x] Height and weight inputs with imperial/metric toggle
- [x] Imperial: feet/inches + lbs; Metric: cm + kg
- [x] Unit conversion handled automatically
- [x] Validation: name required, age 13–99, height/weight within reasonable bounds
- [x] Uses `Theme` design tokens
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-031: Create FitnessLevelView (Onboarding Step 3)

**Description:** As a new user, I want to select my fitness level so workouts match my ability.

**Acceptance Criteria:**

- [x] `Views/Onboarding/FitnessLevelView.swift` created
- [x] 3 selectable cards: Beginner, Intermediate, Advanced
- [x] Each card has title, brief description of what that level means
- [x] Single-select: tapping one deselects the others
- [x] Uses `SelectableChip` or card styling from design system
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-032: Create GoalSelectionView (Onboarding Step 4)

**Description:** As a new user, I want to select my primary fitness goal so workouts are optimized accordingly.

**Acceptance Criteria:**

- [x] `Views/Onboarding/GoalSelectionView.swift` created
- [x] 5 goal cards: Lose Weight, Build Muscle, Improve Endurance, Stay Active, Reduce Stress
- [x] Single-select behavior
- [x] Each card has icon/emoji + title + one-line description
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-033: Create EquipmentSelectionView (Onboarding Step 5)

**Description:** As a new user, I want to select what equipment I have so workouts only use what's available to me.

**Acceptance Criteria:**

- [x] `Views/Onboarding/EquipmentSelectionView.swift` created
- [x] Multi-select grid of equipment options (Bodyweight/None, Dumbbells, Resistance Bands, Pull-Up Bar, Yoga Mat)
- [x] "Nothing / Bodyweight Only" option deselects all others when tapped
- [x] Selecting any equipment deselects "Nothing" if selected
- [x] Uses `SelectableChip` components
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-034: Create WeeklyCommitmentView (Onboarding Step 6)

**Description:** As a new user, I want to set my weekly workout goal so FitSnack can track my consistency.

**Acceptance Criteria:**

- [x] `Views/Onboarding/WeeklyCommitmentView.swift` created
- [x] Slider or stepper: range 2–7 days/week, default 3
- [x] Large number display showing current selection
- [x] Descriptive text that updates based on selection (e.g., "That's a great start!" for 2–3, "You're committed!" for 5+)
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-035: Create InjuriesView (Onboarding Step 7)

**Description:** As a new user, I want to note any injuries so FitSnack avoids exercises that could aggravate them.

**Acceptance Criteria:**

- [x] `Views/Onboarding/InjuriesView.swift` created
- [x] TextEditor for free-text injury notes
- [x] "Skip" button to proceed without entering anything
- [x] Placeholder text guiding input (e.g., "Bad left knee, shoulder impingement…")
- [x] Character limit or reasonable max height
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-036: Create FirstWorkoutView (Onboarding Step 8)

**Description:** As a new user, I want to choose my first workout duration and generate a workout to start immediately.

**Acceptance Criteria:**

- [x] `Views/Onboarding/FirstWorkoutView.swift` created
- [x] Time selector: 5, 10, 15, 20, 25, 30 minutes (buttons or slider)
- [x] "Generate My Workout" primary button
- [x] Tapping the button calls `completeOnboarding()` which saves the profile and transitions to the main app
- [x] Celebration/transition animation on completion
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

### Sprint 4: Workout Generation Engine & Home Screen

---

#### US-037: Create WorkoutGenerationEngine

**Description:** As the system, I want a pure-Swift workout generation algorithm so that workouts are intelligently created offline without network calls.

**Acceptance Criteria:**

- [x] `Services/WorkoutGenerationEngine.swift` created as a struct with a `generateWorkout(duration:profile:exercises:recentHistory:)` method
- [x] Filters exercises by user's available equipment
- [x] Filters by fitness level (beginner only gets beginner/intermediate exercises, etc.)
- [x] Excludes exercises matching injury keywords in notes
- [x] Allocates time: warmup (1–2 min) + main blocks (2–4 blocks) + cooldown (1 min if workout > 10 min)
- [x] Balances muscle groups: avoids repeating same muscle group from recent workout history
- [x] Calculates sets and reps to fit time budget using each exercise's `estimatedTimePerSetSeconds`
- [x] Returns fully formed `Workout` object with status `.generated`
- [x] Never returns an empty workout (fallback to bodyweight if filters are too restrictive)
- [x] Typecheck passes

---

#### US-038: Create CalorieCalculator

**Description:** As the system, I want MET-based calorie estimation so that users see approximate calories burned.

**Acceptance Criteria:**

- [x] `Services/CalorieCalculator.swift` created
- [x] Formula: `MET × weightKg × durationHours` per exercise
- [x] Accounts for rest periods between sets (lower MET)
- [x] Returns total estimated calories for a workout
- [x] Returns actual calories when called with completed set logs
- [x] Typecheck passes

---

#### US-039: Create MockWorkoutService

**Description:** As a developer, I want a mock workout service backed by SwiftData so that the full workout lifecycle works with local data.

**Acceptance Criteria:**

- [x] `Services/Mock/MockWorkoutService.swift` conforms to `WorkoutServiceProtocol`
- [x] `generateWorkout(duration:profile:)` uses `WorkoutGenerationEngine` and saves to SwiftData
- [x] `startWorkout(_:)` updates status to `.inProgress` and sets `startedAt`
- [x] `completeWorkout(_:rating:difficulty:)` updates status, calculates XP, saves
- [x] `cancelWorkout(_:)` updates status to `.cancelled`
- [x] `getHistory()` returns all completed workouts sorted by date descending
- [x] `getTodaysWorkout()` returns today's generated/in-progress workout or nil
- [x] Typecheck passes

---

#### US-040: Create HomeViewModel

**Description:** As a developer, I want a Home screen viewmodel managing today's workout, stats, and workout generation.

**Acceptance Criteria:**

- [x] `ViewModels/HomeViewModel.swift` created as `@Observable` class
- [x] `todaysWorkout: Workout?` — fetched on appear
- [x] `selectedDuration: Int` — default from user profile, user-adjustable
- [x] `isGenerating: Bool` — loading state during generation
- [x] `greeting: String` — time-of-day based ("Good morning", "Good afternoon", "Good evening")
- [x] `weeklyCompletedCount: Int` and `weeklyGoal: Int` from profile
- [x] `currentStreak: Int` — consecutive weeks meeting goal
- [x] `generateWorkout()` async method
- [x] `regenerateWorkout()` generates a new workout replacing current
- [x] Auto-generates workout on appear if none exists for today
- [x] Typecheck passes

---

#### US-041: Create HomeView

**Description:** As a user, I want to see my daily workout, quick stats, and quick-start options on the Home tab so I can begin a workout with minimal friction.

**Acceptance Criteria:**

- [x] `Views/Home/HomeView.swift` created as a ScrollView
- [x] Greeting text with user's name at top
- [x] Streak badge showing current streak
- [x] Workout preview card (or empty state if no workout)
- [x] Quick-start grid for duration selection
- [x] Weekly progress dots (Mon–Sun)
- [x] AI insight card at bottom
- [x] Pull-to-refresh regenerates workout
- [x] Uses `Theme` design tokens throughout
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-042: Create WorkoutPreviewCard

**Description:** As a user, I want to see a preview of today's workout so I know what to expect before starting.

**Acceptance Criteria:**

- [x] `Views/Home/WorkoutPreviewCard.swift` created
- [x] Shows: workout focus/name, total duration, estimated calories, number of exercises
- [x] Lists first 3–4 exercise names as preview
- [x] "Start Workout" primary button
- [x] "Change Duration" and "Regenerate" secondary actions
- [x] Uses `FitSnackCard` styling
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-043: Create QuickStartGrid

**Description:** As a user, I want quick-start buttons for common durations so I can start a workout at my preferred length.

**Acceptance Criteria:**

- [x] `Views/Home/QuickStartGrid.swift` created
- [x] 2×3 grid of duration buttons: 5, 10, 15, 20, 25, 30 minutes
- [x] Tapping a button sets duration and generates/regenerates workout
- [x] Currently selected duration highlighted
- [x] Uses `Theme` styling
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-044: Create WeeklyProgressDots

**Description:** As a user, I want to see my weekly workout completion at a glance.

**Acceptance Criteria:**

- [x] `Views/Home/WeeklyProgressDots.swift` created
- [x] 7 dots representing Mon–Sun
- [x] Completed days filled with brand color, incomplete days are gray outline
- [x] Today's dot has a distinct ring/highlight
- [x] "X of Y done this week" text below
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-045: Create AIInsightCard

**Description:** As a user, I want to see a motivational or educational insight on the home screen.

**Acceptance Criteria:**

- [x] `Views/Home/AIInsightCard.swift` created
- [x] Displays a rotating hardcoded insight/tip (different each day or on refresh)
- [x] Card styling with distinct accent/icon (e.g., lightbulb SF Symbol)
- [x] At least 10 unique insights hardcoded
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-046: Create StreakBadge Component

**Description:** As a user, I want to see my current streak prominently displayed.

**Acceptance Criteria:**

- [x] `Components/StreakBadge.swift` created
- [x] Shows streak count with fire/flame icon
- [x] Compact design suitable for use in Home header
- [x] 0 streak shows different styling (gray, no flame)
- [x] Typecheck passes

---

#### US-047: Create LoadingWorkoutView

**Description:** As a user, I want a loading animation while my workout generates so the app feels responsive.

**Acceptance Criteria:**

- [x] `Components/LoadingWorkoutView.swift` created
- [x] Animated loading indicator (pulsing, spinning, or skeleton)
- [x] "Generating your workout…" text
- [x] Displays for the duration of workout generation
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-048: Create TimeSelector Component

**Description:** As a user, I want a duration slider/picker for fine-grained workout length selection.

**Acceptance Criteria:**

- [x] `Views/Home/TimeSelector.swift` created
- [x] Slider or segmented control for 5–30 minutes in 5-minute increments
- [x] Current value displayed prominently
- [x] Haptic feedback on value change
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

### Sprint 5: Active Workout & Post-Workout Screens

---

#### US-049: Create WorkoutViewModel

**Description:** As a developer, I want a viewmodel managing the active workout session including exercise/set progression, timers, and state.

**Acceptance Criteria:**

- [x] `ViewModels/WorkoutViewModel.swift` created as `@Observable` class
- [x] Tracks `currentBlockIndex`, `currentExerciseIndex`, `currentSetIndex`
- [x] `elapsedTime: TimeInterval` — Date-based, not tick-based (survives backgrounding)
- [x] `restTimeRemaining: Int` — countdown for rest periods
- [x] `isResting: Bool`, `isPaused: Bool`, `isComplete: Bool` state flags
- [x] `completeSet()` advances to next set or rest period
- [x] `skipRest()` ends rest timer early
- [x] `skipExercise()` moves to next exercise
- [x] `swapExercise(reason:)` replaces current exercise with alternative
- [x] `pauseWorkout()` / `resumeWorkout()` toggle pause state
- [x] `finishWorkout()` marks workout complete, navigates to completion screen
- [x] Auto-saves state for resume if app backgrounds
- [x] Triggers haptic feedback on set completion and rest timer end
- [x] Typecheck passes

---

#### US-050: Create ActiveWorkoutView

**Description:** As a user, I want a full-screen workout view so I can follow my exercises without distractions.

**Acceptance Criteria:**

- [x] `Views/Workout/ActiveWorkoutView.swift` created as full-screen cover (hides tab bar)
- [x] Top bar: workout name, elapsed time (monospaced), pause button
- [x] Progress bar showing overall workout completion
- [x] Conditionally shows `ExerciseDisplayView` or `RestTimerView`
- [x] Swipe or button to navigate between exercises
- [x] "End Workout" button accessible from pause menu
- [x] Uses `Theme` tokens, 60pt minimum touch targets
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-051: Create ExerciseDisplayView

**Description:** As a user, I want to see the current exercise with clear instructions so I know exactly what to do.

**Acceptance Criteria:**

- [x] `Views/Workout/ExerciseDisplayView.swift` created
- [x] Exercise name prominently displayed
- [x] SF Symbol placeholder for exercise illustration
- [x] Set and rep display: "Set 2 of 3 — 12 reps"
- [x] Form tip text (first instruction line or dedicated tip)
- [x] Large "Done with Set" button (60pt+ height)
- [x] "Swap" and "Skip" buttons (secondary, smaller)
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-052: Create SetTrackerView

**Description:** As a user, I want to see which set I'm on with visual indicators.

**Acceptance Criteria:**

- [x] `Views/Workout/SetTrackerView.swift` created
- [x] Horizontal row of set indicators (circles or pills)
- [x] Completed sets: filled with brand color + checkmark
- [x] Current set: highlighted/pulsing
- [x] Upcoming sets: gray outline
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-053: Create RestTimerView

**Description:** As a user, I want a countdown timer during rest periods so I know when to start the next set.

**Acceptance Criteria:**

- [x] `Views/Workout/RestTimerView.swift` created
- [x] Large countdown number (monospaced font)
- [x] Circular progress ring showing time remaining
- [x] Next exercise preview (name and set/rep info)
- [x] "Skip Rest" button
- [x] Haptic feedback at 3, 2, 1 seconds and at 0
- [x] Audio beep at timer completion (optional, respects silent mode)
- [x] Auto-advances to next exercise when timer reaches 0
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-054: Create ExerciseSwapSheet

**Description:** As a user, I want to swap an exercise for an alternative if I can't do it.

**Acceptance Criteria:**

- [x] `Views/Workout/ExerciseSwapSheet.swift` created as a sheet/modal
- [x] Reason selection: "Too hard", "Too easy", "No equipment", "Injury", "Other"
- [x] Shows AI-selected replacement exercise (same muscle group, different exercise)
- [x] "Accept" and "Cancel" buttons
- [x] Swap is reflected immediately in the workout
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-055: Create WorkoutCompleteView

**Description:** As a user, I want a post-workout summary so I can see what I accomplished and rate the workout.

**Acceptance Criteria:**

- [x] `Views/Workout/WorkoutCompleteView.swift` created
- [x] Celebration header (e.g., "Great Job!" + confetti or animation)
- [x] Stats summary: total duration, exercises completed, estimated calories, muscle groups worked
- [x] Rating picker: 5 emoji buttons (1–5 scale)
- [x] Difficulty picker: "Too Easy" / "Just Right" / "Too Hard"
- [x] XP earned display with animation
- [x] Streak update display (e.g., "Week 3 streak!")
- [x] "Done" button returns to Home tab
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-056: Create RatingPicker Component

**Description:** As a user, I want to rate my workout with an intuitive emoji-based picker.

**Acceptance Criteria:**

- [x] `Components/RatingPicker.swift` created
- [x] 5 emoji buttons in a row (e.g., 😫😕😐😊🤩 or similar)
- [x] Selected emoji highlighted, others dimmed
- [x] Tapping updates the selection with haptic feedback
- [x] Binding to optional Int (1–5)
- [x] Typecheck passes

---

#### US-057: Create DifficultyPicker Component

**Description:** As a user, I want to report workout difficulty so the algorithm can adapt.

**Acceptance Criteria:**

- [x] `Components/DifficultyPicker.swift` created
- [x] 3 buttons: "Too Easy", "Just Right", "Too Hard"
- [x] Single-select with visual feedback
- [x] Binding to optional String
- [x] Typecheck passes

---

#### US-058: Create ProgressRing Component

**Description:** As a developer, I want a reusable circular progress ring for timers and progress displays.

**Acceptance Criteria:**

- [x] `Components/ProgressRing.swift` created
- [x] Configurable: ring color, track color, line width, progress (0.0–1.0)
- [x] Smooth animation when progress changes
- [x] Supports overlay content (e.g., text in center)
- [x] Typecheck passes

---

#### US-059: Create HapticManager

**Description:** As a developer, I want a centralized haptic manager so that tactile feedback is consistent and easy to trigger.

**Acceptance Criteria:**

- [x] `Services/HapticManager.swift` created
- [x] Static methods: `light()`, `medium()`, `heavy()`, `success()`, `warning()`, `error()`
- [x] Uses `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`
- [x] Typecheck passes

---

### Sprint 6: Progress Tab, Challenges Tab, Streaks & Gamification

---

#### US-060: Create Streak and Gamification Logic

**Description:** As the system, I want streak, XP, level, and badge calculation logic so that gamification features have a solid backend.

**Acceptance Criteria:**

- [x] `Utilities/Constants.swift` created with:
  - XP values: `durationMultiplier = 3`, rating bonus table, weekly completion bonus, streak milestone bonuses
  - Level thresholds array (e.g., 0, 100, 300, 600, 1000, …)
  - 10 badge definitions with IDs, names, descriptions, icons, unlock criteria
- [x] Streak calculation: counts consecutive weeks where completed workouts >= weekly goal (Mon–Sun windows)
- [x] XP calculation: `duration × 3` + rating bonus + weekly/streak milestones
- [x] Level calculation: derived from total XP using threshold array
- [x] Badge unlock evaluation: checks conditions against workout history/stats
- [x] All logic is pure functions (testable without UI)
- [x] Typecheck passes

---

#### US-061: Create ProgressViewModel

**Description:** As a developer, I want a Progress tab viewmodel aggregating workout history and stats.

**Acceptance Criteria:**

- [x] `ViewModels/ProgressViewModel.swift` created as `@Observable` class
- [x] `workoutHistory: [WorkoutHistory]` — all completed workouts
- [x] `monthStats` — workouts this month, total duration, total calories
- [x] `personalRecords` — longest workout, highest calories, longest streak
- [x] `calendarData: [Date: Int]` — date-to-duration mapping for heat map
- [x] `consistencyScore: Double` — percentage of weeks meeting goal
- [x] Loads data on appear from WorkoutService
- [x] Typecheck passes

---

#### US-062: Create ProgressTabView

**Description:** As a user, I want to see my workout history and stats so I can track my fitness journey.

**Acceptance Criteria:**

- [x] `Views/Progress/ProgressTabView.swift` created as ScrollView
- [x] Month summary card: workouts count, total minutes, total calories
- [x] Calendar heat map component
- [x] Consistency score display
- [x] Personal records section
- [x] Recent workouts list (last 10)
- [x] Empty state when no workouts completed yet
- [x] Uses `Theme` design tokens
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-063: Create CalendarHeatMap

**Description:** As a user, I want a calendar heat map showing my workout activity so I can visualize consistency.

**Acceptance Criteria:**

- [x] `Views/Progress/CalendarHeatMap.swift` created
- [x] LazyVGrid with 7 columns (Mon–Sun)
- [x] Shows current month by default
- [x] Cell color intensity based on workout duration (no workout = gray, short = light green, long = dark green)
- [x] Day labels at top (M, T, W, T, F, S, S)
- [x] Month/year header
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-064: Create WorkoutHistoryList and WorkoutHistoryRow

**Description:** As a user, I want to see a list of my past workouts with key details.

**Acceptance Criteria:**

- [x] `Views/Progress/WorkoutHistoryList.swift` created
- [x] `Views/Progress/WorkoutHistoryRow.swift` created
- [x] Each row shows: date, duration, exercise count, calories, muscle groups as colored dots, rating stars
- [x] List sorted by date descending
- [x] Empty state message when no history
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-065: Create ChallengesViewModel

**Description:** As a developer, I want a Challenges tab viewmodel managing badges, level, and XP.

**Acceptance Criteria:**

- [x] `ViewModels/ChallengesViewModel.swift` created as `@Observable` class
- [x] `badges: [Badge]` — all 10 badges with locked/unlocked state
- [x] `currentLevel: Int`, `currentXP: Int`, `xpToNextLevel: Int`
- [x] `xpProgress: Double` — 0.0–1.0 progress to next level
- [x] Evaluates badge unlocks on appear
- [x] Typecheck passes

---

#### US-066: Create ChallengesTabView

**Description:** As a user, I want to see my level, XP progress, and badges so I feel motivated to keep working out.

**Acceptance Criteria:**

- [x] `Views/Challenges/ChallengesTabView.swift` created as ScrollView
- [x] Level display with XP progress bar at top
- [x] Badge grid below
- [x] Leaderboard placeholder section at bottom
- [x] Uses `Theme` design tokens
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-067: Create BadgesGridView and BadgeDetailView

**Description:** As a user, I want to see all badges in a grid and tap for details.

**Acceptance Criteria:**

- [x] `Views/Challenges/BadgesGridView.swift` created as a grid (2–3 columns)
- [x] Locked badges shown as grayed-out with lock icon
- [x] Unlocked badges shown with full color and SF Symbol icon
- [x] Tapping a badge shows `BadgeDetailView` sheet
- [x] `Views/Challenges/BadgeDetailView.swift` shows: icon, name, description, unlock criteria, unlock date (if unlocked)
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-068: Create XPProgressBar Component

**Description:** As a developer, I want a reusable XP progress bar component.

**Acceptance Criteria:**

- [x] `Components/XPProgressBar.swift` created
- [x] Shows current level label, XP count, and progress bar to next level
- [x] Animated fill on value change
- [x] Configurable colors via `Theme`
- [x] Typecheck passes

---

#### US-069: Create LeaderboardPlaceholder

**Description:** As a user, I want to see a placeholder for the future leaderboard feature.

**Acceptance Criteria:**

- [x] `Views/Challenges/LeaderboardPlaceholder.swift` created
- [x] "Coming Soon" message with illustrative icon
- [x] Brief description of what leaderboard will offer
- [x] Styled consistently with the rest of the app
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

### Sprint 7: Profile & Settings (Core Only — No StoreKit/HealthKit/Notifications)

---

#### US-070: Create ProfileViewModel

**Description:** As a developer, I want a Profile tab viewmodel for displaying and editing user profile data.

**Acceptance Criteria:**

- [x] `ViewModels/ProfileViewModel.swift` created as `@Observable` class
- [x] `profile: UserProfile?` — loaded on appear
- [x] `updateProfile(_:)` saves changes via UserService
- [x] `signOut()` clears auth and resets to onboarding
- [x] Typecheck passes

---

#### US-071: Create ProfileTabView

**Description:** As a user, I want to see my profile summary and access settings.

**Acceptance Criteria:**

- [x] `Views/Profile/ProfileTabView.swift` created
- [x] Profile header: name, fitness level, member since date
- [x] Stats summary: total workouts, total XP, current level
- [x] Quick links to: Edit Profile, Equipment, Settings
- [x] Uses `Theme` design tokens
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-072: Create SettingsView

**Description:** As a user, I want a settings screen so I can manage my preferences.

**Acceptance Criteria:**

- [x] `Views/Profile/SettingsView.swift` created as a grouped List
- [x] Sections: Account (edit profile, edit equipment), Workout Preferences (default duration, weekly goal), App Preferences (units toggle), About (version number)
- [x] Each row navigates to appropriate edit view or toggles setting
- [x] Note: Notification settings, subscription, HealthKit, and privacy sections are deferred
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-073: Create ProfileEditView

**Description:** As a user, I want to edit my profile details after onboarding.

**Acceptance Criteria:**

- [x] `Views/Profile/ProfileEditView.swift` created
- [x] Editable fields: name, age, sex, height, weight, fitness level, primary goal, weekly goal, injury notes
- [x] Same unit toggle (imperial/metric) as onboarding
- [x] "Save" button persists changes
- [x] Validation matches onboarding rules
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-074: Create EquipmentEditView

**Description:** As a user, I want to update my available equipment so workouts adapt to what I have.

**Acceptance Criteria:**

- [x] `Views/Profile/EquipmentEditView.swift` created
- [x] Same multi-select grid as onboarding `EquipmentSelectionView`
- [x] Pre-populated with current equipment selections
- [x] "Save" button persists changes
- [x] Changes affect next generated workout
- [x] Typecheck passes
- [ ] **Verify in browser using dev-browser skill**

---

#### US-075: Wire All Services in ServiceContainer

**Description:** As a developer, I want all services wired up in the ServiceContainer so the full app works end-to-end.

**Acceptance Criteria:**

- [x] `ServiceContainer` initializes: `MockAuthService`, `MockExerciseService`, `MockUserService`, `MockWorkoutService`
- [x] `FitSnackApp.swift` creates `ModelContainer`, passes `ModelContext` to services that need it
- [x] All services accessible via `@Environment(\.services)`
- [x] App launches and all tabs function
- [x] Typecheck passes

---

### Sprint 8: Polish, Testing, Edge Cases

---

#### US-076: End-to-End Flow Testing

**Description:** As a developer, I want to verify the complete app flow works without errors.

**Acceptance Criteria:**

- [x] Launch → Onboarding → all 8 screens → completes successfully
- [x] Home → Generate workout → Start → Complete sets with rest timers → Exercise swap → Complete workout → Rating
- [x] Progress tab: completed workouts appear in history, stats update, calendar populates
- [x] Challenges tab: badges show correct locked/unlocked state, XP accumulates, level progresses
- [x] Profile tab: settings changes persist and affect workout generation
- [x] Navigation edge cases: back button, tab switching mid-workout, deep navigation
- [x] App backgrounding during workout: timer resumes correctly (Date-based)
- [x] Data persistence: force-quit and relaunch preserves all data

---

#### US-077: Unit Tests — Workout Generation

**Description:** As a developer, I want unit tests for workout generation to ensure the algorithm works correctly.

**Acceptance Criteria:**

- [x] `FitSnackTests/WorkoutGenerationTests.swift` created
- [x] Test: generated workout duration matches requested duration (±10%)
- [x] Test: warmup block included when duration > 5 min
- [x] Test: exercises respect equipment filter
- [x] Test: exercises balance muscle groups (no same-group repeats in consecutive blocks)
- [x] Test: injury keywords filter out matching exercises
- [x] Test: fallback to bodyweight when filters are too restrictive
- [x] All tests pass

---

#### US-078: Unit Tests — Calorie Calculator

**Description:** As a developer, I want unit tests for the calorie calculator.

**Acceptance Criteria:**

- [x] `FitSnackTests/CalorieCalculatorTests.swift` created
- [x] Test: MET calculation matches expected formula output
- [x] Test: rest periods use lower MET value
- [x] Test: zero-duration returns zero calories
- [x] All tests pass

---

#### US-079: Unit Tests — Streak Logic

**Description:** As a developer, I want unit tests for streak calculation.

**Acceptance Criteria:**

- [x] `FitSnackTests/StreakLogicTests.swift` created
- [x] Test: streak increments when weekly goal met
- [x] Test: streak resets to 0 when weekly goal missed
- [x] Test: streak handles week boundaries (Mon–Sun)
- [x] Test: first week can be streak of 1
- [x] Test: empty history returns streak of 0
- [x] All tests pass

---

#### US-080: Unit Tests — Exercise Filtering

**Description:** As a developer, I want unit tests for exercise filtering.

**Acceptance Criteria:**

- [x] `FitSnackTests/ExerciseFilterTests.swift` created
- [x] Test: filter by single equipment type
- [x] Test: filter by muscle group
- [x] Test: filter by difficulty level
- [x] Test: combined filters
- [x] Test: empty result returns empty array (not error)
- [x] All tests pass

---

#### US-081: Unit Tests — Model Encoding/Decoding

**Description:** As a developer, I want unit tests for JSON encoding/decoding of domain models.

**Acceptance Criteria:**

- [x] `FitSnackTests/ModelTests.swift` created
- [x] Test: `Exercise` decodes from `Exercises.json` sample
- [x] Test: `UserProfile` encode/decode roundtrip
- [x] Test: `Workout` encode/decode roundtrip (including nested blocks/exercises/setLogs)
- [x] Test: `Badge` encode/decode roundtrip
- [x] All tests pass

---

#### US-082: Handle Empty States

**Description:** As a user, I want meaningful empty states so the app doesn't feel broken when I have no data.

**Acceptance Criteria:**

- [x] Home: shows "Generate your first workout" prompt when no workout exists
- [x] Progress: shows "Complete your first workout to see stats" with illustration
- [x] Challenges: shows all badges as locked with encouraging message
- [x] History list: shows "No workouts yet" message
- [x] Calendar heat map: shows empty month grid
- [x] All empty states use `Theme` styling
- [x] Typecheck passes
- [x] **Verify in browser using dev-browser skill**

---

#### US-083: Handle Workout Cancellation

**Description:** As a user, I want to cancel a workout in progress and choose whether to save partial progress.

**Acceptance Criteria:**

- [x] "End Workout" shows confirmation alert
- [x] Options: "Save Progress" (saves as completed with partial data) or "Discard" (marks as cancelled)
- [x] Cancelled workouts don't count toward weekly goal or XP
- [x] Partially saved workouts calculate XP based on completed sets only
- [x] Typecheck passes
- [x] **Verify in browser using dev-browser skill**

---

#### US-084: Accessibility Pass

**Description:** As a user with accessibility needs, I want the app to be fully usable with VoiceOver and Dynamic Type.

**Acceptance Criteria:**

- [x] All interactive elements have `accessibilityLabel`
- [x] VoiceOver navigation follows logical reading order on every screen
- [x] Dynamic Type: all text scales correctly (no truncation or overlap at largest sizes)
- [x] Color contrast meets 4.5:1 WCAG AA for all text
- [x] Touch targets are 44pt minimum (60pt on workout screens)
- [x] Workout timer announces time remaining via accessibility
- [x] Typecheck passes

---

#### US-085: Dark Mode Verification

**Description:** As a user, I want the app to look great in both light and dark mode.

**Acceptance Criteria:**

- [x] All screens render correctly in dark mode
- [x] No hardcoded white/black colors — all use adaptive `Theme.Colors` tokens
- [x] Card backgrounds, shadows, and borders adapt to color scheme
- [x] Text remains readable in both modes
- [x] SF Symbols use adaptive rendering
- [x] Typecheck passes
- [x] **Verify in browser using dev-browser skill**

---

#### US-086: Visual Polish and Animations

**Description:** As a user, I want subtle animations and polished UI so the app feels professional.

**Acceptance Criteria:**

- [x] Tab switching has smooth transitions
- [x] Workout generation shows loading animation
- [x] Set completion has success animation (checkmark, confetti, or pulse)
- [x] Rest timer has smooth countdown animation
- [x] XP gain shows animated counter
- [x] Badge unlock has celebration animation
- [x] All animations respect "Reduce Motion" accessibility setting
- [x] Typecheck passes
- [x] **Verify in browser using dev-browser skill**

---

## 4. Functional Requirements

- **FR-1:** The system must create a user profile from onboarding data and persist it via SwiftData
- **FR-2:** The system must load 30 exercises from a bundled JSON file
- **FR-3:** The system must filter exercises by equipment, fitness level, and injury keywords
- **FR-4:** The system must generate a time-fitted workout with warmup, main blocks, and cooldown
- **FR-5:** The system must balance muscle groups across consecutive workouts
- **FR-6:** The system must calculate estimated calories using MET × weight × duration formula
- **FR-7:** The system must track set completion, rest periods, and exercise swaps during active workouts
- **FR-8:** The system must save completed workout data (duration, exercises, rating, difficulty, XP) to SwiftData
- **FR-9:** The system must calculate weekly streaks based on Mon–Sun windows and weekly goal
- **FR-10:** The system must calculate XP as: `duration × 3` + rating bonus + weekly/streak milestones
- **FR-11:** The system must derive user level from total XP using threshold array
- **FR-12:** The system must evaluate 10 badge unlock conditions against workout history
- **FR-13:** The system must allow users to edit their profile and equipment after onboarding
- **FR-14:** The system must display workout history with date, duration, exercises, calories, and rating
- **FR-15:** The system must show a calendar heat map of workout activity by month
- **FR-16:** The system must use Date-based timers so that backgrounding the app does not break elapsed time or rest countdowns
- **FR-17:** The system must provide exercise swap with same-muscle-group alternatives during active workout
- **FR-18:** The system must inject all services via `ServiceContainer` in the SwiftUI environment, using protocol types so implementations can be swapped without view changes
- **FR-19:** The system must persist onboarding progress so that interrupted onboarding can resume
- **FR-20:** The system must support both imperial (ft/in, lbs) and metric (cm, kg) units

---

## 5. Non-Goals (Out of Scope)

- **No StoreKit 2 subscriptions** — deferred to separate PRD
- **No HealthKit integration** — deferred to separate PRD
- **No push notifications** (local or remote) — deferred to separate PRD
- **No real backend / Convex integration** — Phase 1 is entirely mock data + SwiftData
- **No Apple Sign In** — dev-mode auth only (name + UUID)
- **No social features / leaderboard** — placeholder only
- **No exercise images or videos** — SF Symbol placeholders only
- **No AI/ML-powered workout generation** — algorithm is rule-based pure Swift
- **No iPad or Mac Catalyst support** — iPhone only
- **No localization** — English only
- **No App Store submission** — TestFlight prep only
- **No analytics or crash reporting**
- **No offline sync or conflict resolution** — no backend to sync with

---

## 6. Design Considerations

- **Design System:** All UI uses `Theme.Colors`, `Theme.Typography`, `Theme.Spacing` tokens — no hardcoded values
- **Button Height:** 56pt standard, with full-width primary CTAs
- **Card Style:** White (dark-mode adaptive) background, 16pt corner radius, subtle shadow
- **Touch Targets:** 44pt minimum, 60pt on workout screens (large "Done with Set" button)
- **Workout Screen:** Full-screen cover, no tab bar, monospaced timer font, high-contrast design for gym readability
- **Empty States:** Every list/collection has a designed empty state with helpful guidance
- **Animations:** Subtle, purposeful, respects "Reduce Motion" setting
- **Dark Mode:** Full support via adaptive color tokens

---

## 7. Technical Considerations

- **iOS 17.0+** minimum deployment target (required for `@Observable`, SwiftData)
- **Swift 5.9**, **Xcode 16.3**
- **SwiftData** for persistence — two `@Model` classes: `SDUserProfile`, `SDWorkout`
- **Domain models** are plain `Codable` structs — SwiftData models have `toX()` / `update(from:)` converters
- **Complex fields** (arrays, nested objects) stored as base64-encoded JSON strings in SwiftData
- **XcodeGen** (`project.yml`) generates `.xcodeproj` — do not manually edit project file
- **Protocol-based services** with mock implementations — future Convex swap requires zero view/viewmodel changes
- **No third-party dependencies** in Phase 1 — all native frameworks
- **Date-based timers** for workout tracking — resilient to app backgrounding

---

## 8. Success Metrics

- **Feature Completeness:** All 4 tabs functional with mock data; full workout loop (generate → execute → complete → track)
- **Code Quality:** Protocol-based architecture verified — swapping one service implementation compiles with zero view changes
- **User Experience:** Workout can be started within 2 taps from Home; onboarding completes in under 2 minutes; workout flow is uninterrupted
- **Test Coverage:** Unit tests pass for workout generation, calorie calculation, streak logic, exercise filtering, and model encoding
- **Visual Quality:** All screens render correctly in light and dark mode; no hardcoded colors/fonts; consistent design system usage
- **Accessibility:** All screens usable with VoiceOver; Dynamic Type supported; 4.5:1 contrast ratio met
- **Performance:** App launches in under 2 seconds; workout generation completes in under 1 second; no UI jank during active workout

---

## 9. Open Questions

- Should the workout generation engine prioritize variety (never repeat an exercise within a week) or allow favorites?
- What should the exact 10 badge definitions be? (First Rep, Week One, Early Bird, Speed Demon, etc. — need final list with unlock criteria)
- Should partially completed workouts (cancelled with "Save Progress") appear differently in history vs fully completed ones?
- Should the difficulty picker response ("Too Easy" / "Too Hard") affect the next generated workout immediately, or accumulate over multiple workouts?
- What are the exact XP level thresholds? (Linear scaling, exponential, or custom curve?)
- Should the calendar heat map support navigating to previous months, or only show the current month?
