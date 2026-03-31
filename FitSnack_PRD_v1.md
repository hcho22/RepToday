# Product Requirements Document: FitSnack — AI-Powered Micro-Workout App

**Version:** 1.0
**Last Updated:** March 24, 2026
**Platform:** iOS (SwiftUI, iOS 17+)
**Status:** Pre-Development

---

## 1. Executive Summary

FitSnack is an iOS-first AI-powered workout app designed for busy working parents and professionals who have between 5 and 30 minutes per day to exercise. The app uses generative AI to create personalized daily workouts that adapt to the user's available time, equipment, fitness history, goals, and recovery state — eliminating decision fatigue entirely.

The core promise: **Open the app, tell it how many minutes you have, press play.** No browsing. No choosing. No thinking.

### 1.1 Core Value Proposition

- **Zero-decision workouts:** AI generates a complete, personalized workout the moment you tell it how much time you have
- **Time-flexible by design:** Every workout is 5–30 minutes, generated dynamically — not pre-recorded videos cut to length
- **Progressive and intelligent:** The AI tracks your history, manages fatigue across muscle groups, and ensures progressive overload even in short sessions
- **Built for consistency, not intensity:** The app rewards showing up, even for 5 minutes, over grinding through hour-long sessions

### 1.2 Target Users

**Primary:** Working parents aged 28–45 with children under 12, household income $75K+, who previously exercised regularly but lost their routine after having kids.

**Secondary:** Busy professionals aged 25–40 without children who travel frequently or work unpredictable hours and cannot commit to a fixed gym schedule.

**Psychographic profile:** These users don't lack motivation — they lack time and mental bandwidth. They feel guilty about not exercising. They've tried and abandoned 2–3 fitness apps. They want to feel like they're "doing something" even on their worst days.

---

## 2. Technical Architecture

### 2.1 Tech Stack

```
┌─────────────────────────────────────────────────────┐
│                    iOS Client                        │
│  SwiftUI · iOS 17+ · Swift 5.9+                     │
│  HealthKit · CoreData · CloudKit · StoreKit 2        │
│  Lottie (animations) · Charts (Swift Charts)         │
└──────────────────────┬──────────────────────────────┘
                       │ REST + WebSocket
┌──────────────────────▼──────────────────────────────┐
│                   Backend API                        │
│  Node.js (Fastify) or Python (FastAPI)               │
│  PostgreSQL · Redis · S3                             │
│  Hosted on: AWS / Railway / Fly.io                   │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│               AI / ML Services                       │
│  LLM API (Claude / GPT-4) — workout generation       │
│  Custom ML model — progressive overload engine        │
│  Recommendation engine — exercise selection            │
└─────────────────────────────────────────────────────┘
```

### 2.2 Data Models

#### User

```typescript
interface User {
  id: string;                          // UUID
  email: string;
  displayName: string;
  avatarUrl?: string;
  createdAt: Date;
  updatedAt: Date;

  // Onboarding profile
  profile: {
    age: number;
    sex: 'male' | 'female' | 'other';
    heightCm: number;
    weightKg: number;
    fitnessLevel: 'beginner' | 'intermediate' | 'advanced';
    primaryGoal: 'lose_weight' | 'build_muscle' | 'stay_active' | 'increase_energy' | 'reduce_stress';
    secondaryGoals: string[];
    injuries: string[];                // Free text, parsed by AI
    availableEquipment: Equipment[];
    preferredWorkoutDays: DayOfWeek[];  // Suggested, not enforced
    typicalAvailableMinutes: number;    // Default time when not specified
    workoutEnvironment: 'home' | 'gym' | 'outdoors' | 'office' | 'any';
  };

  // Subscription
  subscription: {
    tier: 'free' | 'premium';
    provider: 'apple';
    expiresAt?: Date;
    trialEndsAt?: Date;
  };

  // Streaks and gamification
  gamification: {
    currentWeeklyStreak: number;       // Weeks where goal was met
    longestWeeklyStreak: number;
    weeklyWorkoutGoal: number;         // Default: 3
    workoutsThisWeek: number;
    totalWorkoutsCompleted: number;
    totalMinutesExercised: number;
    xp: number;
    level: number;
    badges: Badge[];
    streakFreezes: number;             // Available streak freezes
  };

  // Preferences
  preferences: {
    notificationsEnabled: boolean;
    preferredNotificationTimes: string[];  // ISO time strings
    hapticFeedback: boolean;
    soundEffects: boolean;
    countdownBeeps: boolean;
    restTimerAutoStart: boolean;
    unitSystem: 'metric' | 'imperial';
  };
}
```

#### Exercise

```typescript
interface Exercise {
  id: string;
  name: string;
  displayName: string;
  description: string;
  instructions: string[];              // Step-by-step cues
  commonMistakes: string[];
  thumbnailUrl: string;
  videoUrl?: string;                   // Short demo loop (5-10s)
  animationUrl?: string;              // Lottie animation alternative

  // Classification
  muscleGroups: {
    primary: MuscleGroup[];
    secondary: MuscleGroup[];
  };
  movementPattern: 'push' | 'pull' | 'squat' | 'hinge' | 'lunge' | 'carry' | 'rotation' | 'plank' | 'cardio';
  category: 'strength' | 'cardio' | 'flexibility' | 'warmup' | 'cooldown';
  difficulty: 1 | 2 | 3 | 4 | 5;
  equipment: Equipment[];              // Empty = bodyweight
  isUnilateral: boolean;
  
  // Timing
  defaultReps?: number;
  defaultDurationSeconds?: number;     // For timed exercises
  defaultSets: number;
  restBetweenSetsSeconds: number;
  estimatedTimePerSetSeconds: number;  // Including reps + transitions
  
  // Scaling
  regressions: string[];               // Exercise IDs for easier versions
  progressions: string[];              // Exercise IDs for harder versions
  
  // Metadata
  metValue: number;                    // Metabolic Equivalent for calorie calc
  tags: string[];
}

type MuscleGroup = 
  | 'chest' | 'upper_back' | 'lower_back' | 'shoulders' | 'biceps' | 'triceps'
  | 'forearms' | 'core' | 'obliques' | 'quads' | 'hamstrings' | 'glutes'
  | 'calves' | 'hip_flexors' | 'adductors' | 'abductors';

type Equipment = 
  | 'none' | 'dumbbells' | 'resistance_bands' | 'pull_up_bar' | 'kettlebell'
  | 'yoga_mat' | 'jump_rope' | 'foam_roller' | 'bench' | 'stability_ball';
```

#### Workout

```typescript
interface Workout {
  id: string;
  userId: string;
  createdAt: Date;
  
  // Generation context
  requestedDurationMinutes: number;
  actualDurationMinutes?: number;      // Filled after completion
  generationPrompt: string;            // AI prompt used (for debugging)
  
  // Structure
  warmup: WorkoutBlock;
  mainBlocks: WorkoutBlock[];          // 2-4 blocks
  cooldown: WorkoutBlock;
  
  // Status
  status: 'generated' | 'in_progress' | 'completed' | 'skipped' | 'partial';
  startedAt?: Date;
  completedAt?: Date;
  
  // Post-workout
  userRating?: 1 | 2 | 3 | 4 | 5;    // "How was that workout?"
  perceivedDifficulty?: 'too_easy' | 'just_right' | 'too_hard';
  caloriesBurned?: number;
  heartRateData?: HeartRateDataPoint[];  // From HealthKit
  
  // AI insights
  aiSummary?: string;                  // Post-workout summary
  muscleGroupsWorked: Record<MuscleGroup, 'primary' | 'secondary'>;
  focusAreas: string[];
}

interface WorkoutBlock {
  id: string;
  name: string;                        // "Upper Body Push", "Core Finisher"
  type: 'warmup' | 'strength' | 'circuit' | 'hiit' | 'emom' | 'amrap' | 'cooldown';
  exercises: WorkoutExercise[];
  restBetweenExercisesSeconds: number;
  rounds?: number;                     // For circuits
  timeLimitSeconds?: number;           // For AMRAP/EMOM
}

interface WorkoutExercise {
  exerciseId: string;
  exercise: Exercise;                  // Populated reference
  sets: number;
  reps?: number;
  durationSeconds?: number;
  weight?: number;                     // In user's preferred unit
  restAfterSeconds: number;
  notes?: string;                      // AI-generated form cues
  
  // Tracking (filled during workout)
  completedSets: SetLog[];
  skipped: boolean;
  substitutedWith?: string;            // Exercise ID if swapped
}

interface SetLog {
  setNumber: number;
  reps?: number;
  weight?: number;
  durationSeconds?: number;
  completedAt: Date;
  rpe?: number;                        // Rate of Perceived Exertion 1-10
}
```

#### WorkoutHistory (for AI context)

```typescript
interface WorkoutHistory {
  userId: string;
  
  // Rolling summaries (updated after each workout)
  last7Days: {
    workoutsCompleted: number;
    totalMinutes: number;
    muscleGroupFrequency: Record<MuscleGroup, number>;
    averageDifficulty: number;
    averageRating: number;
  };
  
  last30Days: {
    workoutsCompleted: number;
    totalMinutes: number;
    muscleGroupFrequency: Record<MuscleGroup, number>;
    exerciseFrequency: Record<string, number>;  // exerciseId -> count
    progressionData: ProgressionEntry[];
    averageDifficulty: number;
    averageRating: number;
    averageDurationMinutes: number;
    preferredTimeOfDay: string;
  };
  
  // Personal records
  personalRecords: Record<string, {
    exerciseId: string;
    maxWeight?: number;
    maxReps?: number;
    maxDuration?: number;
    achievedAt: Date;
  }>;
  
  // AI learning signals
  exercisesRatedPoorly: string[];      // Exercises the user consistently rates low
  exercisesSkipped: string[];          // Exercises the user tends to skip
  preferredExercises: string[];        // Exercises the user rates highly
}
```

### 2.3 API Endpoints

```
AUTH
  POST   /api/auth/register           — Create account (email + Apple Sign In)
  POST   /api/auth/login              — Login
  POST   /api/auth/refresh            — Refresh JWT token
  DELETE /api/auth/account            — Delete account + all data

USER
  GET    /api/user/profile            — Get user profile
  PUT    /api/user/profile            — Update profile
  PUT    /api/user/preferences        — Update preferences
  GET    /api/user/stats              — Get gamification stats
  POST   /api/user/equipment          — Update available equipment

WORKOUTS
  POST   /api/workouts/generate       — Generate a new workout
    Body: { durationMinutes: number, focusArea?: string, mood?: string }
    Response: Workout object with full exercise details
  
  GET    /api/workouts/:id            — Get workout details
  PUT    /api/workouts/:id/start      — Mark workout as started
  PUT    /api/workouts/:id/complete   — Mark workout as completed
    Body: { completedExercises: SetLog[], rating, difficulty, caloriesBurned }
  
  POST   /api/workouts/:id/swap       — Swap an exercise mid-workout
    Body: { exerciseId: string, reason: 'too_hard' | 'no_equipment' | 'injury' | 'preference' }
    Response: { replacement: WorkoutExercise }
  
  GET    /api/workouts/history        — Get workout history (paginated)
  GET    /api/workouts/preview        — Preview tomorrow's suggested workout
  
EXERCISES
  GET    /api/exercises               — List all exercises (with filters)
  GET    /api/exercises/:id           — Get exercise details + demo media
  GET    /api/exercises/search        — Search exercises by name/muscle/equipment

AI
  POST   /api/ai/summary              — Generate post-workout AI summary
  POST   /api/ai/weekly-report        — Generate weekly progress report
  POST   /api/ai/form-tips            — Get AI form tips for specific exercise
  GET    /api/ai/next-workout-preview  — AI preview of recommended next workout

SOCIAL
  GET    /api/social/leaderboard      — Weekly XP leaderboard (friends)
  POST   /api/social/share            — Generate shareable workout card
  POST   /api/social/invite           — Send app invite
  GET    /api/social/challenges       — Active challenges
  POST   /api/social/challenges/:id/join — Join a challenge

SUBSCRIPTIONS
  POST   /api/subscriptions/verify    — Verify Apple receipt
  GET    /api/subscriptions/status    — Get current subscription status
```

### 2.4 AI Workout Generation

The workout generation engine is the core differentiator. It uses a structured LLM prompt with the user's full context.

#### Generation Flow

```
User taps "Start Workout" and selects duration (5-30 min slider)
                    │
                    ▼
        ┌─────────────────────┐
        │  Gather Context      │
        │  - User profile      │
        │  - 7-day history     │
        │  - Muscle fatigue    │
        │  - Equipment avail.  │
        │  - Time of day       │
        │  - Injury list       │
        │  - Mood (optional)   │
        └──────────┬──────────┘
                    │
                    ▼
        ┌─────────────────────┐
        │  Build AI Prompt     │
        │  (structured JSON    │
        │   request format)    │
        └──────────┬──────────┘
                    │
                    ▼
        ┌─────────────────────┐
        │  LLM API Call        │
        │  Claude / GPT-4      │
        │  Response: JSON      │
        └──────────┬──────────┘
                    │
                    ▼
        ┌─────────────────────┐
        │  Validate & Enrich   │
        │  - Check exercise IDs│
        │  - Calculate timing  │
        │  - Add media URLs    │
        │  - Estimate calories │
        └──────────┬──────────┘
                    │
                    ▼
        ┌─────────────────────┐
        │  Return Workout      │
        │  to Client           │
        └─────────────────────┘
```

#### AI Prompt Template (System)

```
You are FitSnack's workout generation engine. You create personalized workouts
that fit within a specific time constraint. Your workouts must be:

1. COMPLETABLE within the requested time (including warmup, transitions, rest)
2. PROGRESSIVE — build on the user's history, don't repeat yesterday's workout
3. BALANCED — distribute muscle group work across the week
4. APPROPRIATE — match the user's fitness level and available equipment
5. ENGAGING — vary exercise selection, use different workout formats

RULES:
- Always include a 1-2 minute warmup (dynamic stretches, not static)
- Always include a 1 minute cooldown for workouts > 10 minutes
- Never program an exercise the user has flagged as causing pain
- Prefer exercises the user rates highly (4-5 stars)
- Avoid exercises the user frequently skips
- For 5-minute workouts: 1 warmup move + 1 circuit (3-4 exercises, no rest)
- For 10-minute workouts: 2 warmup moves + 2 blocks
- For 15-minute workouts: 2 warmup moves + 2-3 blocks + cooldown
- For 20-30 minute workouts: 3 warmup moves + 3-4 blocks + cooldown
- Calculate total time including: exercise time + rest + transitions (10s each)
- If the user worked a muscle group yesterday, avoid it today unless requested
- Estimate MET-based calories: calories = MET × weight_kg × duration_hours

Respond ONLY with valid JSON matching the Workout schema. No markdown, no explanation.
```

#### AI Prompt Template (User message — sent per generation)

```json
{
  "requested_duration_minutes": 15,
  "user_context": {
    "fitness_level": "intermediate",
    "age": 34,
    "sex": "female",
    "weight_kg": 68,
    "height_cm": 165,
    "primary_goal": "stay_active",
    "injuries": ["mild lower back pain"],
    "available_equipment": ["dumbbells", "yoga_mat", "resistance_bands"],
    "environment": "home"
  },
  "history_context": {
    "last_workout": {
      "date": "2026-03-23",
      "duration_minutes": 20,
      "focus": "lower_body",
      "muscle_groups": ["quads", "glutes", "hamstrings", "calves"],
      "difficulty_rating": "just_right",
      "user_rating": 4
    },
    "workouts_this_week": 2,
    "weekly_goal": 3,
    "muscle_group_frequency_last_7_days": {
      "chest": 1, "upper_back": 1, "shoulders": 0,
      "quads": 2, "glutes": 2, "core": 1, "arms": 0
    },
    "frequently_skipped_exercises": ["burpees", "mountain_climbers"],
    "preferred_exercises": ["goblet_squats", "dumbbell_rows", "plank_variations"]
  },
  "time_of_day": "morning",
  "mood": "energized",
  "special_request": null
}
```

#### Calorie Calculation

```
Calories Burned = Σ (MET_value × weight_kg × duration_hours) for each exercise

MET Reference Values:
- Bodyweight exercises (moderate): 3.5–5.0
- Resistance training (moderate): 3.5–6.0
- HIIT / Circuit training: 8.0–12.0
- Stretching / Yoga: 2.5–3.0
- Walking lunges: 5.0
- Push-ups (vigorous): 8.0
- Burpees: 10.0

Adjustment factors:
- Rest periods: MET 1.0
- Transitions: MET 2.0
- Apply ±15% based on reported RPE vs expected
```

---

## 3. Feature Specifications

### 3.1 Onboarding Flow

**Goal:** Get the user to complete their first workout within 5 minutes of opening the app.

```
Screen 1: Welcome
  "Workouts that fit your life, not the other way around."
  [Continue with Apple] or [Continue with Email]

Screen 2: Quick Profile (single scrollable form)
  - Name (text field)
  - Age (number picker)
  - Sex (segmented control: Male / Female / Other)
  - Height + Weight (with unit toggle)
  
Screen 3: Fitness Level
  "How would you describe your current fitness?"
  [Beginner] — "I'm just starting out or getting back into it"
  [Intermediate] — "I exercise sometimes but not consistently"
  [Advanced] — "I'm experienced but short on time"

Screen 4: Primary Goal (single select)
  "What matters most to you right now?"
  🏃 Stay Active — "Just keep moving consistently"
  💪 Build Strength — "Get stronger with what I have"
  ⚡ Boost Energy — "Feel more energized daily"
  🧘 Reduce Stress — "Move to decompress"
  🔥 Lose Weight — "Burn calories efficiently"

Screen 5: Equipment (multi-select with icons)
  "What do you have at home? (Select all that apply)"
  [Nothing — just me!]
  [Dumbbells]
  [Resistance Bands]
  [Yoga Mat]
  [Pull-up Bar]
  [Kettlebell]
  [Jump Rope]
  
Screen 6: Weekly Commitment
  "How many workouts per week feels realistic?"
  Slider: 2 — 3 — 4 — 5 — 6 — 7
  Default position: 3
  Helper text: "Most FitSnack users start with 3. You can always adjust."

Screen 7: Injuries / Limitations (optional, skip-able)
  "Anything we should know about?"
  Free-text field with placeholder: "E.g., bad left knee, lower back issues, shoulder pain..."
  [Skip — I'm good!]

Screen 8: First Workout
  "Let's do your first workout right now!"
  Time selector: circular dial, 5 to 30 minutes, default 10
  "How many minutes do you have?"
  [Generate My Workout →]
```

**Technical notes:**
- Store all onboarding data locally first, sync to server in background
- Apple Sign In is the primary auth method (required for iOS)
- Email auth as fallback
- Onboarding completion event triggers first workout generation
- If user kills app mid-onboarding, resume from last completed screen

### 3.2 Home Screen (Daily View)

The home screen is the app's most critical surface. It should convey one clear action: **start today's workout.**

```
┌──────────────────────────────────┐
│  Good morning, Sarah! ☀️          │
│  Week 4 · 🔥 3-week streak       │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  TODAY'S WORKOUT              │ │
│  │                               │ │
│  │  💪 Upper Body + Core         │ │
│  │  🕐 15 min · 🔥 ~120 cal      │ │
│  │                               │ │
│  │  Preview:                     │ │
│  │  • DB Shoulder Press  3×10    │ │
│  │  • Push-up Variations 3×12   │ │
│  │  • Plank to Row       3×8    │ │
│  │  • Dead Bugs          3×10   │ │
│  │  + warmup & cooldown          │ │
│  │                               │ │
│  │  ┌───────────────────────┐    │ │
│  │  │   ▶  START WORKOUT    │    │ │
│  │  └───────────────────────┘    │ │
│  │                               │ │
│  │  ⏱ Change time  🔀 Regenerate │ │
│  └──────────────────────────────┘ │
│                                   │
│  This Week                        │
│  [●] Mon  [●] Wed  [○] Fri       │
│  2 of 3 workouts done             │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  QUICK START                  │ │
│  │  [5 min] [10 min] [15 min]    │ │
│  │  [20 min] [25 min] [30 min]   │ │
│  └──────────────────────────────┘ │
│                                   │
│  AI Insight 💡                    │
│  "You've been crushing upper body │
│   this week! Tomorrow I'll focus  │
│   on legs to keep things balanced"│
│                                   │
└──────────────────────────────────┘
```

**Behavior:**
- On app open, if no workout generated today, auto-generate one using `typicalAvailableMinutes`
- "Change time" opens the duration slider and regenerates
- "Regenerate" creates a completely new workout for the same duration
- Quick Start buttons generate and immediately start a workout
- Workout preview shows 3-4 main exercises (not warmup/cooldown)
- AI Insight rotates daily: progress observations, tips, encouragement
- Weekly dots show completion status at a glance

### 3.3 Active Workout Screen

The workout screen must be usable with sweaty hands, at arm's length, with minimal cognitive load.

```
┌──────────────────────────────────┐
│  Upper Body + Core     12:34     │
│  ████████████░░░░  Exercise 3/6  │
│                                   │
│  ┌──────────────────────────────┐ │
│  │                               │ │
│  │    [Exercise Animation/Demo]  │ │
│  │    (looping Lottie or video)  │ │
│  │                               │ │
│  └──────────────────────────────┘ │
│                                   │
│  PUSH-UPS                         │
│  Set 2 of 3 · 12 reps            │
│                                   │
│  Form tip: "Keep elbows at 45°,   │
│  not flared out to the sides"     │
│                                   │
│  ┌─────┐  ┌─────┐  ┌─────┐      │
│  │ ✓ 12│  │● 12 │  │  12 │      │
│  │Set 1│  │Set 2│  │Set 3│      │
│  └─────┘  └─────┘  └─────┘      │
│                                   │
│  ┌───────────────────────────┐    │
│  │       ✓  DONE WITH SET    │    │
│  └───────────────────────────┘    │
│                                   │
│  [🔀 Swap Exercise] [⏭ Skip]     │
│                                   │
└──────────────────────────────────┘
```

**After tapping "Done with Set":**

```
┌──────────────────────────────────┐
│  REST                             │
│                                   │
│        ┌─────────────┐           │
│        │              │           │
│        │    0:28      │           │
│        │              │           │
│        └─────────────┘           │
│                                   │
│  Next: Plank to Row · 3×8        │
│                                   │
│  ┌───────────────────────────┐    │
│  │       ⏭  SKIP REST        │    │
│  └───────────────────────────┘    │
│                                   │
└──────────────────────────────────┘
```

**Workout screen features:**
- Large, tappable buttons (minimum 60pt touch targets)
- Exercise demo plays automatically (looping animation or short video)
- Haptic feedback on set completion
- Audio countdown beeps for timed exercises (last 3 seconds)
- Rest timer with haptic pulse when done
- "Swap Exercise" calls `/api/workouts/:id/swap` and shows replacement inline
- Progress bar shows overall workout progress
- Elapsed time always visible
- If user leaves app mid-workout, save state locally and resume on return
- Lock screen / Dynamic Island integration showing current exercise + timer

**Swap Exercise flow:**
1. User taps "Swap"
2. Bottom sheet shows reason: "Too hard" / "No equipment" / "Hurts" / "Don't like it"
3. AI returns substitute matching same muscle group and time budget
4. New exercise slides in with animation
5. Swap reason stored for future generation learning

### 3.4 Post-Workout Screen

This is the **peak emotional moment** — the user just accomplished something. This screen must celebrate and create sharing opportunities.

```
┌──────────────────────────────────┐
│                                   │
│         🎉  GREAT WORK!           │
│                                   │
│  ┌──────────────────────────────┐ │
│  │      15 min · 6 exercises     │ │
│  │      🔥 127 cal burned        │ │
│  │      💪 4 muscle groups       │ │
│  │                               │ │
│  │  [Body Heat Map Graphic]      │ │
│  │  Showing worked muscles       │ │
│  │  in orange/red gradient       │ │
│  │                               │ │
│  └──────────────────────────────┘ │
│                                   │
│  AI Summary:                      │
│  "Strong session! You increased   │
│  your push-up reps by 2 since     │
│  last week. Your shoulder press   │
│  is ready to go up 2.5 lbs."     │
│                                   │
│  How was this workout?            │
│  [😫] [😐] [😊] [💪] [🔥]       │
│                                   │
│  Difficulty?                      │
│  [Too Easy] [Just Right] [Too Hard│
│                                   │
│  🔥 Streak: 3 weeks!             │
│  +45 XP earned                    │
│                                   │
│  ┌───────────────────────────┐    │
│  │   📤 Share Workout Card    │    │
│  └───────────────────────────┘    │
│                                   │
│  [Done]                           │
│                                   │
└──────────────────────────────────┘
```

**Post-workout data collection:**
- Rating (1-5 emoji) — required, affects future generation
- Difficulty — required, affects progressive overload
- Both captured with single taps, no friction
- Share button generates a styled card (see 3.8)
- XP animation plays (numbers ticking up)
- If streak milestone hit, special celebration animation

### 3.5 History & Progress Tab

```
┌──────────────────────────────────┐
│  Progress                         │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  This Month                   │ │
│  │  12 workouts · 186 min        │ │
│  │  ~1,540 cal · 28 exercises    │ │
│  │                               │ │
│  │  [Monthly Calendar Heat Map]  │ │
│  │  Green dots on workout days   │ │
│  └──────────────────────────────┘ │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  Consistency Score: 87%       │ │
│  │  ████████████████░░░          │ │
│  │  You hit your goal 87% of    │ │
│  │  weeks since starting!        │ │
│  └──────────────────────────────┘ │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  Muscle Balance (30 days)     │ │
│  │  [Radar/Spider Chart]         │ │
│  │  Showing distribution across  │ │
│  │  major muscle groups          │ │
│  └──────────────────────────────┘ │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  Personal Records 🏆          │ │
│  │  Push-ups: 20 reps (Mar 20)   │ │
│  │  Plank: 1:45 (Mar 18)         │ │
│  │  DB Press: 25 lbs (Mar 15)    │ │
│  └──────────────────────────────┘ │
│                                   │
│  Recent Workouts                  │
│  [List of past workout cards]     │
│                                   │
└──────────────────────────────────┘
```

**Charts and visualizations:**
- Built with Swift Charts (iOS 16+)
- Calendar heat map (GitHub-style, green intensity = workout duration)
- Muscle group radar chart (6-axis: push, pull, legs, core, cardio, flexibility)
- Volume over time line chart (total weekly minutes)
- All data stored locally in CoreData, synced to server

### 3.6 Streak & Gamification System

**Weekly Streak (primary mechanic):**
- A "streak week" is defined as completing `weeklyWorkoutGoal` workouts (default 3) within Mon–Sun
- Current streak = consecutive weeks where goal was met
- Missing a week resets the streak to 0

**Streak Saver:**
- If a user has completed `weeklyWorkoutGoal - 1` workouts and it's Sunday
- App offers a "Streak Saver" — a 2-3 minute minimal workout
- Completing it counts as the final workout to preserve the streak
- Users get 1 free streak freeze per month (auto-applied if a week is missed)
- Premium users get unlimited streak freezes

**XP System:**
- Completing a workout: `duration_minutes × 3` XP (e.g., 15 min = 45 XP)
- Rating a workout: +5 XP
- Hitting weekly goal: +50 XP bonus
- Streak milestone (4 weeks): +100 XP
- Streak milestone (12 weeks): +500 XP
- Streak milestone (26 weeks): +1000 XP
- Personal record: +25 XP
- Sharing a workout card: +10 XP

**Levels:**
- Level 1: 0 XP (Couch Explorer)
- Level 5: 500 XP (Routine Builder)
- Level 10: 2,000 XP (Consistency Champion)
- Level 20: 8,000 XP (Iron Parent)
- Level 30: 20,000 XP (Fitness Machine)
- Level 50: 50,000 XP (Living Legend)

**Badges (unlockable achievements):**
- "First Rep" — Complete your first workout
- "Week One" — Complete your first full week
- "Early Bird" — Complete a workout before 7 AM
- "Night Owl" — Complete a workout after 9 PM
- "Speed Demon" — Complete a 5-minute workout
- "Marathon" — Complete a 30-minute workout
- "Full House" — Work all 6 major muscle groups in one week
- "Comeback Kid" — Return after 7+ days away
- "Century" — Complete 100 total workouts
- "Year Strong" — Maintain a 52-week streak

### 3.7 Notification Strategy

**Principles:**
- Never guilt-trip. Always encouraging and light.
- Personalized timing based on when user actually exercises (learned over time)
- Max 1 notification per day
- Reduce frequency as user builds habit (high-frequency first 2 weeks, then taper)

**Notification types:**

| Trigger | Timing | Example Copy |
|---------|--------|--------------|
| Daily reminder | User's typical workout time | "15 minutes today? Your upper body workout is ready 💪" |
| Streak at risk | Sunday evening, goal not yet met | "One more workout keeps your 6-week streak alive! How about 5 minutes?" |
| Comeback | After 3 days inactive | "Hey! Even 5 minutes counts. Your muscles miss you 🫶" |
| PR celebration | Immediately after PR | "NEW RECORD! 15 push-ups in a set! 🏆" |
| Weekly summary | Monday morning | "Last week: 3 workouts, 45 min, 380 cal. Solid week! 📊" |
| Streak milestone | After achieving milestone | "🔥 4 WEEKS STRONG! You're in the top 15% of FitSnack users!" |

### 3.8 Shareable Workout Card

A beautifully designed, auto-generated image card that users share to Instagram Stories, iMessage, etc.

**Card contents:**
- App logo (small, corner)
- Workout type + duration
- Muscles worked (mini body heat map)
- Calories burned
- Streak count
- Date
- Fun AI-generated stat: "You did 180 push-ups this month — that's like pushing a car uphill!"
- QR code or deep link to app
- User's chosen background theme (5-6 options)

**Card dimensions:** 1080×1920 (Instagram Story format) and 1080×1080 (square for feed)

**Technical implementation:**
- Rendered natively in SwiftUI
- Exported as UIImage via `ImageRenderer`
- Shared via `UIActivityViewController`
- Deep link format: `fitsnack://invite?ref={userId}`

### 3.9 Settings & Profile

```
Profile & Settings
├── Account
│   ├── Name, Email, Avatar
│   ├── Apple Health Connection
│   ├── Subscription Status
│   └── Delete Account
├── Workout Preferences
│   ├── Available Equipment (multi-select)
│   ├── Injuries & Limitations (text)
│   ├── Weekly Workout Goal (slider)
│   ├── Preferred Workout Duration (default)
│   ├── Fitness Level
│   └── Primary Goal
├── Notifications
│   ├── Enable/Disable
│   ├── Preferred Time
│   └── Notification Types (toggles)
├── App Preferences
│   ├── Units (Imperial/Metric)
│   ├── Sound Effects
│   ├── Haptic Feedback
│   ├── Countdown Beeps
│   └── Auto-start Rest Timer
├── Data & Privacy
│   ├── Export My Data
│   ├── Privacy Policy
│   └── Terms of Service
└── Support
    ├── FAQ
    ├── Contact Us
    └── Rate on App Store
```

---

## 4. Subscription & Monetization

### 4.1 Free Tier

- 3 AI-generated workouts per week
- Basic workout history (last 7 days)
- Weekly streak tracking
- 1 streak freeze per month
- Standard exercise library
- Post-workout rating

### 4.2 Premium Tier ($7.99/month or $59.99/year)

Everything in Free, plus:
- Unlimited AI-generated workouts
- Full workout history with analytics
- Muscle balance radar chart
- Personal records tracking
- AI post-workout summaries and insights
- AI weekly progress reports
- Workout preview for tomorrow
- Unlimited streak freezes
- Shareable workout cards (premium designs)
- Priority workout generation (faster API response)
- Advanced exercise swapping with AI reasoning

### 4.3 Trial Strategy

- 14-day free trial of Premium on first install
- No credit card required to start trial
- Trial countdown shown in Settings (not aggressively)
- At trial end: paywall screen showing what they'll lose
- Offer annual plan prominently (highlight savings: "Save 37%")

### 4.4 Paywall Design

Triggered after trial expires when user tries a premium feature.

```
┌──────────────────────────────────┐
│                                   │
│  Unlock Your Full Potential       │
│                                   │
│  ✓ Unlimited AI workouts          │
│  ✓ Detailed progress analytics    │
│  ✓ AI coaching insights           │
│  ✓ Unlimited streak freezes       │
│  ✓ Shareable workout cards        │
│                                   │
│  ┌───────────────────────────┐    │
│  │ BEST VALUE                │    │
│  │ Annual: $59.99/year       │    │
│  │ That's just $4.99/month   │    │
│  │ Save 37%                  │    │
│  └───────────────────────────┘    │
│                                   │
│  ┌───────────────────────────┐    │
│  │ Monthly: $7.99/month      │    │
│  └───────────────────────────┘    │
│                                   │
│  [Restore Purchases]              │
│  [Not now]                        │
│                                   │
└──────────────────────────────────┘
```

---

## 5. HealthKit Integration

### 5.1 Data Read (with user permission)

- Resting heart rate (for calorie calculation accuracy)
- Active energy burned (cross-reference with app estimates)
- Workout heart rate data (if Apple Watch available)
- Step count (for overall activity context)
- Body weight (auto-update profile)
- Sleep data (future: adjust workout intensity based on sleep quality)

### 5.2 Data Write

- Write completed workouts to HealthKit as `HKWorkout`
- Include: workout type, duration, calories burned, heart rate samples
- Activity rings contribution

### 5.3 Apple Watch Companion (v2 — Future)

- Start/control workouts from watch
- Live heart rate during workout
- Haptic cues for set completion and rest timer
- Complication showing streak and next workout time

---

## 6. Exercise Library

### 6.1 Initial Library Size

Launch with **120–150 exercises** covering:

| Category | Count | Examples |
|----------|-------|---------|
| Bodyweight Upper | 25 | Push-up variations, dips, pike press, diamond push-ups |
| Bodyweight Lower | 25 | Squats, lunges, step-ups, glute bridges, calf raises |
| Bodyweight Core | 20 | Planks, dead bugs, hollow holds, bicycle crunches, mountain climbers |
| Dumbbell Upper | 20 | Shoulder press, rows, curls, lateral raises, chest press |
| Dumbbell Lower | 15 | Goblet squats, RDLs, split squats, sumo squats |
| Resistance Band | 15 | Band pull-aparts, banded squats, banded rows, face pulls |
| Cardio / HIIT | 15 | Jumping jacks, high knees, skaters, squat jumps, burpees |
| Warmup / Cooldown | 15 | Arm circles, leg swings, cat-cow, child's pose, hip circles |

### 6.2 Exercise Media

Each exercise requires:
- **Thumbnail:** 400×400 static image (for lists/preview)
- **Demo animation:** Lottie animation (preferred) or 5-10 second looping video
- **Form cue text:** 2-3 key points displayed during exercise

**Media production approach (MVP):**
- Phase 1: Use Lottie stick-figure animations (fast to produce, small file size)
- Phase 2: Record live-action demo videos with a trainer
- Phase 3: Add AI-generated form analysis overlay

---

## 7. Navigation Structure

```
Tab Bar (4 tabs)
├── 🏠 Home (Today's workout + quick start)
├── 📊 Progress (History, stats, charts, PRs)
├── 🏆 Challenges (Leaderboard, badges, challenges)
└── ⚙️ Profile (Settings, subscription, preferences)
```

---

## 8. Development Phases

### Phase 1: MVP (Weeks 1–8)

**Goal:** Core workout generation loop, streak system, basic analytics

- [ ] Project setup: SwiftUI app, navigation structure, tab bar
- [ ] Onboarding flow (8 screens)
- [ ] User authentication (Apple Sign In + email)
- [ ] Backend API: user CRUD, workout generation endpoint
- [ ] AI workout generation engine (LLM integration)
- [ ] Exercise database: 80 exercises with text descriptions
- [ ] Home screen: today's workout preview, time selector, quick start
- [ ] Active workout screen: exercise display, set tracking, rest timer, swap
- [ ] Post-workout screen: rating, difficulty, calorie display
- [ ] Workout history (basic list view)
- [ ] Weekly streak system
- [ ] Push notifications (daily reminder, streak at risk)
- [ ] CoreData local storage
- [ ] Basic Settings screen
- [ ] StoreKit 2 subscription integration
- [ ] HealthKit: write workouts

### Phase 2: Engagement (Weeks 9–14)

**Goal:** Retention mechanics, social features, polish

- [ ] XP and leveling system
- [ ] Badge system (15 badges)
- [ ] Shareable workout cards
- [ ] AI post-workout summary generation
- [ ] AI weekly progress report
- [ ] Next-day workout preview
- [ ] Progress charts (Swift Charts): calendar heat map, muscle radar
- [ ] Personal records tracking
- [ ] Streak freezes
- [ ] Streak saver micro-workouts
- [ ] Exercise demo animations (Lottie) for top 50 exercises
- [ ] Improved push notifications (personalized timing)
- [ ] HealthKit: read heart rate, weight, sleep
- [ ] App Store Optimization (screenshots, description, keywords)
- [ ] Paywall optimization

### Phase 3: Growth (Weeks 15–20)

**Goal:** Viral mechanics, community, retention optimization

- [ ] Friends system (add via contacts, share link)
- [ ] Weekly leaderboard (friends' XP ranking)
- [ ] Group challenges ("Team 1000 Minutes")
- [ ] Referral system (invite friends → both get 1 month free)
- [ ] Workout card customization (backgrounds, themes)
- [ ] iOS widget (streak count, next workout time)
- [ ] Dynamic Island integration (active workout timer)
- [ ] Lock screen Live Activity (workout progress)
- [ ] Exercise video demos (replace remaining Lottie with video)
- [ ] AI form tips (contextual, per-exercise)
- [ ] Mood-based workout adjustment
- [ ] A/B testing framework for onboarding and paywall
- [ ] Analytics: Mixpanel / Amplitude integration

### Phase 4: Advanced AI (Weeks 21+)

- [ ] AI voice coaching during workouts (text-to-speech with encouragement)
- [ ] Calendar integration (suggest workout windows based on schedule)
- [ ] Computer vision form checking (on-device, using Vision framework)
- [ ] Apple Watch companion app
- [ ] Predictive churn detection with proactive engagement
- [ ] Personalized workout music tempo matching
- [ ] Family plan (2 adults on one subscription)

---

## 9. Key Metrics & Success Criteria

### 9.1 North Star Metric

**Weekly Active Exercisers (WAE):** Users who complete at least 1 workout per week.

### 9.2 Primary Metrics

| Metric | Target (Month 3) | Target (Month 6) |
|--------|-------------------|-------------------|
| Day 1 Retention | 40% | 45% |
| Day 7 Retention | 20% | 25% |
| Day 30 Retention | 10% | 15% |
| Onboarding → 1st Workout | 60% | 70% |
| Weekly Active Exercisers | 35% of installs | 40% |
| Free → Paid Conversion | 5% | 8% |
| Average Workouts/Week (active) | 2.5 | 3.0 |
| Monthly Churn (paid) | 12% | 8% |
| App Store Rating | 4.5+ | 4.7+ |
| NPS | 40+ | 50+ |

### 9.3 AI Quality Metrics

| Metric | Target |
|--------|--------|
| Workout generation latency | < 3 seconds |
| Workout rating (user avg) | ≥ 3.8 / 5 |
| Difficulty rating "Just Right" | ≥ 65% |
| Exercise swap rate | < 15% |
| Workout completion rate (started → finished) | ≥ 80% |

---

## 10. Technical Constraints & Non-Functional Requirements

### 10.1 Performance

- App launch to home screen: < 2 seconds
- Workout generation: < 3 seconds (show loading animation)
- Exercise swap: < 2 seconds
- Offline support: last generated workout available offline
- App size: < 100 MB (defer video downloads)

### 10.2 Security & Privacy

- All API communication over HTTPS
- JWT tokens with 15-minute expiry, refresh tokens in Keychain
- User data encrypted at rest (CoreData + CloudKit)
- GDPR/CCPA compliant: data export + deletion endpoints
- No selling of user data, ever
- HealthKit data never leaves the device (used only for local calculations)
- Workout generation prompts do not contain PII beyond age/sex/weight

### 10.3 Accessibility

- Full VoiceOver support on all screens
- Dynamic Type support (all text scales)
- Minimum contrast ratio 4.5:1
- Haptic feedback as alternative to audio cues
- Large touch targets (≥ 44pt, prefer 60pt for workout screen)
- Reduce Motion support (disable animations)

### 10.4 Localization (v1 = English only)

- All user-facing strings in `.strings` files
- Date/time formatting via `DateFormatter` with locale
- Weight/height: imperial (US default) and metric
- Exercise names: English only at launch

---

## 11. Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| AI generates poor/unsafe workouts | High | Validate all AI output against exercise DB; never suggest exercises not in library; human review of edge cases |
| AI API downtime | High | Cache 3 pre-generated workouts locally; fallback to template-based generation |
| High API costs from LLM calls | Medium | Cache common workout patterns; use smaller models for simple generations; batch non-urgent AI tasks |
| Low Day 1 retention | High | Minimize onboarding friction; guarantee first workout completion in < 5 min |
| Users find workouts too easy/hard | Medium | Aggressive feedback loop (rating + difficulty); AI adjusts within 2-3 workouts |
| App Store rejection | Medium | Follow all HIG guidelines; avoid medical claims; clear subscription disclosures |
| Exercise injury liability | High | Clear disclaimers; never claim medical authority; link to professional guidance; avoid exercises with high injury risk for beginners |

---

## 12. Legal & Compliance

- **Terms of Service:** Required before account creation
- **Privacy Policy:** CCPA + GDPR compliant, accessible from Settings and App Store listing
- **Health Disclaimer:** "FitSnack is not a substitute for professional medical advice. Consult your doctor before starting any exercise program."
- **Subscription disclosures:** Apple-required language about auto-renewal, pricing, cancellation
- **Data deletion:** Users can delete all data from Settings (GDPR right to erasure)
- **Apple App Store guidelines:** Full compliance with sections 3.1.1 (payments), 3.1.2 (subscriptions), 5.1 (privacy), 5.3 (gaming/gambling — N/A)

---

## 13. File & Folder Structure (iOS Project)

```
FitSnack/
├── FitSnackApp.swift                  # App entry point
├── Info.plist
├── Assets.xcassets/
│
├── Models/
│   ├── User.swift
│   ├── Exercise.swift
│   ├── Workout.swift
│   ├── WorkoutBlock.swift
│   ├── WorkoutExercise.swift
│   ├── SetLog.swift
│   ├── Badge.swift
│   └── WorkoutHistory.swift
│
├── Views/
│   ├── Onboarding/
│   │   ├── OnboardingContainerView.swift
│   │   ├── WelcomeView.swift
│   │   ├── ProfileSetupView.swift
│   │   ├── FitnessLevelView.swift
│   │   ├── GoalSelectionView.swift
│   │   ├── EquipmentSelectionView.swift
│   │   ├── WeeklyCommitmentView.swift
│   │   ├── InjuriesView.swift
│   │   └── FirstWorkoutView.swift
│   │
│   ├── Home/
│   │   ├── HomeView.swift
│   │   ├── WorkoutPreviewCard.swift
│   │   ├── QuickStartGrid.swift
│   │   ├── WeeklyProgressDots.swift
│   │   └── AIInsightCard.swift
│   │
│   ├── Workout/
│   │   ├── ActiveWorkoutView.swift
│   │   ├── ExerciseDisplayView.swift
│   │   ├── SetTrackerView.swift
│   │   ├── RestTimerView.swift
│   │   ├── ExerciseSwapSheet.swift
│   │   ├── WorkoutCompleteView.swift
│   │   └── BodyHeatMapView.swift
│   │
│   ├── Progress/
│   │   ├── ProgressView.swift
│   │   ├── CalendarHeatMap.swift
│   │   ├── MuscleRadarChart.swift
│   │   ├── PersonalRecordsView.swift
│   │   ├── WorkoutHistoryList.swift
│   │   └── WeeklyReportView.swift
│   │
│   ├── Social/
│   │   ├── ChallengesView.swift
│   │   ├── LeaderboardView.swift
│   │   ├── BadgesGridView.swift
│   │   └── ShareWorkoutCardView.swift
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── ProfileEditView.swift
│   │   ├── EquipmentEditView.swift
│   │   ├── NotificationSettingsView.swift
│   │   └── SubscriptionView.swift
│   │
│   ├── Paywall/
│   │   └── PaywallView.swift
│   │
│   └── Components/
│       ├── PrimaryButton.swift
│       ├── TimeSlider.swift
│       ├── ExerciseRowView.swift
│       ├── StreakBadge.swift
│       ├── XPProgressBar.swift
│       └── LoadingWorkoutView.swift
│
├── ViewModels/
│   ├── OnboardingViewModel.swift
│   ├── HomeViewModel.swift
│   ├── WorkoutViewModel.swift
│   ├── ProgressViewModel.swift
│   ├── SocialViewModel.swift
│   ├── SettingsViewModel.swift
│   └── SubscriptionViewModel.swift
│
├── Services/
│   ├── APIService.swift               # Network layer
│   ├── AuthService.swift              # Apple Sign In + JWT
│   ├── WorkoutGenerationService.swift # AI workout generation
│   ├── HealthKitService.swift         # HealthKit read/write
│   ├── NotificationService.swift      # Push notification management
│   ├── SubscriptionService.swift      # StoreKit 2
│   ├── PersistenceService.swift       # CoreData
│   ├── AnalyticsService.swift         # Event tracking
│   └── ShareService.swift             # Workout card generation
│
├── Persistence/
│   ├── FitSnack.xcdatamodeld          # CoreData schema
│   ├── CoreDataManager.swift
│   └── CloudKitManager.swift
│
├── Utilities/
│   ├── CalorieCalculator.swift
│   ├── DateExtensions.swift
│   ├── ColorTheme.swift
│   ├── HapticManager.swift
│   └── Constants.swift
│
├── Resources/
│   ├── Exercises.json                 # Exercise database (bundled)
│   ├── Animations/                    # Lottie files
│   └── Fonts/
│
└── Tests/
    ├── WorkoutGenerationTests.swift
    ├── CalorieCalculatorTests.swift
    ├── StreakLogicTests.swift
    └── ExerciseFilterTests.swift
```

---

## 14. Design System

### 14.1 Color Palette

```swift
// Primary
static let brand = Color(hex: "#4F46E5")          // Indigo — trust, energy
static let brandLight = Color(hex: "#818CF8")
static let brandDark = Color(hex: "#3730A3")

// Accents
static let success = Color(hex: "#10B981")         // Green — completion
static let warning = Color(hex: "#F59E0B")         // Amber — attention
static let danger = Color(hex: "#EF4444")          // Red — streak risk
static let fire = Color(hex: "#F97316")            // Orange — streaks/calories

// Neutrals
static let textPrimary = Color(hex: "#111827")
static let textSecondary = Color(hex: "#6B7280")
static let background = Color(hex: "#F9FAFB")
static let cardBackground = Color(hex: "#FFFFFF")
static let divider = Color(hex: "#E5E7EB")

// Dark mode variants defined via asset catalog
```

### 14.2 Typography

```swift
// Using SF Pro (system font) for iOS native feel
static let largeTitle = Font.system(size: 34, weight: .bold)
static let title = Font.system(size: 24, weight: .bold)
static let title2 = Font.system(size: 20, weight: .semibold)
static let headline = Font.system(size: 17, weight: .semibold)
static let body = Font.system(size: 17, weight: .regular)
static let callout = Font.system(size: 16, weight: .regular)
static let subheadline = Font.system(size: 15, weight: .regular)
static let footnote = Font.system(size: 13, weight: .regular)
static let caption = Font.system(size: 12, weight: .regular)

// Monospaced for timers
static let timer = Font.system(size: 48, weight: .bold, design: .monospaced)
```

### 14.3 Component Spacing

```swift
static let spacingXS: CGFloat = 4
static let spacingSM: CGFloat = 8
static let spacingMD: CGFloat = 16
static let spacingLG: CGFloat = 24
static let spacingXL: CGFloat = 32
static let spacingXXL: CGFloat = 48

static let cornerRadius: CGFloat = 12
static let cornerRadiusLarge: CGFloat = 16
static let cornerRadiusFull: CGFloat = 9999  // Pill shape

static let buttonHeight: CGFloat = 56
static let cardPadding: CGFloat = 16
```

---

## 15. App Store Metadata

### 15.1 Name & Subtitle

**Name:** FitSnack — AI Micro Workouts
**Subtitle:** 5-30 min workouts for busy people

### 15.2 Keywords

`workout,fitness,ai,short workout,quick workout,home workout,busy mom,busy dad,exercise,micro workout,5 minute workout,bodyweight,no gym,streak,hiit,strength`

### 15.3 Description (First 3 Lines — Most Important)

"Too busy to work out? FitSnack builds a custom AI workout in seconds — just tell it how many minutes you have. Whether you've got 5 minutes between meetings or 30 minutes while the kids nap, FitSnack creates the perfect workout for you, every single day."

### 15.4 App Category

Primary: Health & Fitness
Secondary: Lifestyle

---

*End of PRD v1.0*
