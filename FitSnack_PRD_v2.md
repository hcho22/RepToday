# Product Requirements Document: FitSnack — Micro-Workout App for Busy People

**Version:** 2.0
**Last Updated:** April 8, 2026
**Platform:** iOS (SwiftUI, iOS 17+)
**Status:** Pre-Development

**What changed in v2.0:**
- Restructured development phases: Phase 1 (MVP) uses a deterministic rule-based workout engine — no LLM required
- LLM/AI features introduced in Phase 2 (post-workout summaries, weekly reports) and Phase 3+ (form tips, voice coaching)
- Exercise library replaced with 142 calisthenics-focused exercises drawn from Chris Heria, Dr. Mike Israetel, and Strength Side
- Added rule-based workout generation algorithm specification
- Updated equipment types to reflect calisthenics focus (pull-up bar, parallettes, rings, resistance bands)
- Added 12 progression chains for systematic exercise advancement
- Added workout structure templates for 5/10/15/20/30-minute sessions

---

## 1. Executive Summary

FitSnack is an iOS-first workout app designed for busy working parents and professionals who have between 5 and 30 minutes per day to exercise. The app generates personalized daily workouts using a deterministic rule-based engine (Phase 1) that adapts to the user's available time, equipment, fitness history, goals, and recovery state — eliminating decision fatigue entirely. AI/LLM features are layered on in Phase 2+ for coaching insights, summaries, and advanced personalization.

The core promise: **Open the app, tell it how many minutes you have, press play.** No browsing. No choosing. No thinking.

### 1.1 Core Value Proposition

- **Zero-decision workouts:** The engine generates a complete, personalized workout the moment you tell it how much time you have
- **Time-flexible by design:** Every workout is 5–30 minutes, generated dynamically — not pre-recorded videos cut to length
- **Calisthenics-first:** 142 exercises drawn from Chris Heria, Dr. Mike Israetel, and Strength Side — mostly bodyweight, minimal equipment
- **Progressive and intelligent:** Tracks history, manages fatigue across muscle groups, and ensures progressive overload even in short sessions
- **Built for consistency, not intensity:** Rewards showing up, even for 5 minutes, over grinding through hour-long sessions

### 1.2 Target Users

**Primary:** Working parents aged 28–45 with children under 12, household income $75K+, who previously exercised regularly but lost their routine after having kids.

**Secondary:** Busy professionals aged 25–40 without children who travel frequently or work unpredictable hours and cannot commit to a fixed gym schedule.

**Psychographic profile:** These users don't lack motivation — they lack time and mental bandwidth. They feel guilty about not exercising. They've tried and abandoned 2–3 fitness apps. They want to feel like they're "doing something" even on their worst days.

---

## 2. Technical Architecture

### 2.1 Tech Stack

```
Phase 1 (MVP) — No external AI services required:

┌─────────────────────────────────────────────────────┐
│                    iOS Client                        │
│  SwiftUI · iOS 17+ · Swift 5.9+                     │
│  HealthKit · CoreData · CloudKit · StoreKit 2        │
│  Lottie (animations) · Charts (Swift Charts)         │
│                                                      │
│  Rule-Based Workout Engine (on-device)               │
│  Exercise Database (bundled JSON)                    │
│  Calorie Calculator (MET formula)                    │
│  Progression Tracker (CoreData)                      │
└──────────────────────┬──────────────────────────────┘
                       │ REST (auth, sync, subscriptions)
┌──────────────────────▼──────────────────────────────┐
│                   Backend API                        │
│  Node.js (Fastify) or Python (FastAPI)               │
│  PostgreSQL · Redis · S3                             │
│  Hosted on: Railway / Fly.io                         │
└─────────────────────────────────────────────────────┘

Phase 2+ adds:

┌─────────────────────────────────────────────────────┐
│               AI / LLM Services                      │
│  Claude API — post-workout summaries                 │
│  Claude API — weekly progress reports                │
│  Claude API — contextual form tips                   │
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
    injuries: string[];                // Free text tags: "lower_back", "left_knee", etc.
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
    preferredNotificationTimes: string[];
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
  id: string;                          // e.g., "push_001"
  name: string;                        // e.g., "standard_push_ups"
  displayName: string;                 // e.g., "Standard Push-Ups"
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
  movementPattern: 'push_horizontal' | 'push_vertical' | 'pull_vertical' | 'pull_horizontal' | 'squat' | 'hinge' | 'core_anti_extension' | 'core_flexion' | 'core_rotation' | 'core_compression' | 'cardio' | 'mobility' | 'primal';
  category: 'strength' | 'cardio' | 'flexibility' | 'warmup' | 'cooldown' | 'skill';
  difficulty: 1 | 2 | 3 | 4 | 5;
  equipment: Equipment[];              // Empty array = bodyweight only
  isUnilateral: boolean;
  athleteSource: string[];             // e.g., ["heria", "israetel", "strength_side"]

  // Timing
  defaultReps?: number;
  defaultDurationSeconds?: number;     // For timed exercises (planks, holds)
  defaultSets: number;
  restBetweenSetsSeconds: number;
  estimatedTimePerSetSeconds: number;  // Including reps + transitions

  // Progression chains
  progressionChainId: string;          // e.g., "chain_horizontal_push"
  progressionOrder: number;            // Position in chain (1 = easiest)
  regressions: string[];               // Exercise IDs for easier versions
  progressions: string[];              // Exercise IDs for harder versions
  advancementCriteria: string;         // e.g., "3×15 clean reps"

  // Metadata
  metValue: number;                    // Metabolic Equivalent for calorie calc
  tags: string[];
  apartmentFriendly: boolean;          // No jumping/impact
}

type MuscleGroup =
  | 'chest' | 'upper_back' | 'lower_back' | 'shoulders' | 'biceps' | 'triceps'
  | 'forearms' | 'core' | 'obliques' | 'quads' | 'hamstrings' | 'glutes'
  | 'calves' | 'hip_flexors' | 'adductors' | 'abductors'
  | 'wrists' | 'rotator_cuff' | 'traps' | 'erectors';

type Equipment =
  | 'none' | 'pull_up_bar' | 'resistance_bands' | 'parallettes'
  | 'rings' | 'dip_bars' | 'elevated_surface' | 'wall'
  | 'bench_or_chair' | 'sliders_or_towel' | 'anchor_point'
  | 'band_or_stick' | 'step_or_stairs' | 'box_or_platform';
```

#### Workout

```typescript
interface Workout {
  id: string;
  userId: string;
  createdAt: Date;

  // Generation context
  requestedDurationMinutes: number;
  actualDurationMinutes?: number;
  generationMethod: 'rule_engine' | 'llm';  // Track which system generated it

  // Structure
  warmup: WorkoutBlock;
  mainBlocks: WorkoutBlock[];          // 2-4 blocks
  cooldown: WorkoutBlock;

  // Status
  status: 'generated' | 'in_progress' | 'completed' | 'skipped' | 'partial';
  startedAt?: Date;
  completedAt?: Date;

  // Post-workout
  userRating?: 1 | 2 | 3 | 4 | 5;
  perceivedDifficulty?: 'too_easy' | 'just_right' | 'too_hard';
  caloriesBurned?: number;
  heartRateData?: HeartRateDataPoint[];

  // Insights (Phase 2: AI-generated; Phase 1: template-based)
  summary?: string;
  muscleGroupsWorked: Record<MuscleGroup, 'primary' | 'secondary'>;
  focusAreas: string[];
}

interface WorkoutBlock {
  id: string;
  name: string;                        // "Upper Body Push", "Core Finisher"
  type: 'warmup' | 'strength' | 'circuit' | 'hiit' | 'emom' | 'amrap' | 'cooldown';
  exercises: WorkoutExercise[];
  restBetweenExercisesSeconds: number;
  rounds?: number;
  timeLimitSeconds?: number;
}

interface WorkoutExercise {
  exerciseId: string;
  exercise: Exercise;
  sets: number;
  reps?: number;
  durationSeconds?: number;
  restAfterSeconds: number;
  notes?: string;                      // Form cues (static in Phase 1, AI in Phase 2+)

  // Tracking
  completedSets: SetLog[];
  skipped: boolean;
  substitutedWith?: string;
}

interface SetLog {
  setNumber: number;
  reps?: number;
  durationSeconds?: number;
  completedAt: Date;
  rpe?: number;                        // Rate of Perceived Exertion 1-10
}
```

#### WorkoutHistory

```typescript
interface WorkoutHistory {
  userId: string;

  last7Days: {
    workoutsCompleted: number;
    totalMinutes: number;
    muscleGroupFrequency: Record<MuscleGroup, number>;
    movementPatternFrequency: Record<string, number>;
    averageDifficulty: number;
    averageRating: number;
  };

  last30Days: {
    workoutsCompleted: number;
    totalMinutes: number;
    muscleGroupFrequency: Record<MuscleGroup, number>;
    exerciseFrequency: Record<string, number>;
    progressionData: ProgressionEntry[];
    averageDifficulty: number;
    averageRating: number;
    averageDurationMinutes: number;
    preferredTimeOfDay: string;
  };

  personalRecords: Record<string, {
    exerciseId: string;
    maxReps?: number;
    maxDuration?: number;
    achievedAt: Date;
  }>;

  // Learning signals
  exercisesRatedPoorly: string[];
  exercisesSkipped: string[];
  preferredExercises: string[];
}
```

### 2.3 API Endpoints

```
AUTH
  POST   /api/auth/register           — Create account (Apple Sign In + email)
  POST   /api/auth/login
  POST   /api/auth/refresh
  DELETE /api/auth/account             — Delete account + all data

USER
  GET    /api/user/profile
  PUT    /api/user/profile
  PUT    /api/user/preferences
  GET    /api/user/stats               — Gamification stats
  POST   /api/user/equipment           — Update available equipment

WORKOUTS
  POST   /api/workouts/generate        — Generate workout (rule-engine, runs on-device in Phase 1)
  GET    /api/workouts/:id
  PUT    /api/workouts/:id/start
  PUT    /api/workouts/:id/complete
  POST   /api/workouts/:id/swap        — Swap exercise (rule-engine substitution)
  GET    /api/workouts/history

EXERCISES
  GET    /api/exercises                — Full library with filters
  GET    /api/exercises/:id
  GET    /api/exercises/search

AI (Phase 2+ only — not in MVP)
  POST   /api/ai/summary              — Generate post-workout AI summary
  POST   /api/ai/weekly-report        — Generate weekly progress report
  POST   /api/ai/form-tips            — AI form tips for specific exercise
  GET    /api/ai/next-workout-preview  — AI reasoning for tomorrow's workout

SOCIAL (Phase 3+)
  GET    /api/social/leaderboard
  POST   /api/social/share
  POST   /api/social/invite
  GET    /api/social/challenges
  POST   /api/social/challenges/:id/join

SUBSCRIPTIONS
  POST   /api/subscriptions/verify
  GET    /api/subscriptions/status
```

### 2.4 Workout Generation: Rule-Based Engine (Phase 1 — No LLM)

The MVP workout generation engine is entirely deterministic — pure code logic operating on the exercise database and user history. No LLM calls, no API costs for generation, instant results.

#### Generation Algorithm

```
Input: {
  durationMinutes: number,         // 5, 10, 15, 20, 25, or 30
  userProfile: UserProfile,
  last7DaysHistory: WorkoutHistory,
  availableEquipment: Equipment[],
  injuries: string[]
}

Step 1 — Select workout template based on duration:
  5 min  → DENSITY: 1 movement pattern, 5 rounds × (40s work / 20s rest)
  10 min → CIRCUIT: 7-8 exercises, 45s/15s, 1 round (Heria format)
  15 min → FOCUSED: 2 movement patterns, 3-4 exercises, 3 sets each
  20 min → STRUCTURED: 2-3 movement patterns, 4-5 exercises, 3 sets + cooldown
  25 min → SUPERSET: 3 movement patterns, supersets with 90s rest
  30 min → FULL: 3-4 supersets of opposing movements, 3 sets each

Step 2 — Determine today's movement pattern focus:
  a. Query last 7 days of muscle group frequency
  b. Rank muscle groups by staleness (days since last worked)
  c. Apply weekly balance rules:
     - Push + Core (Day A)
     - Pull + Hinge (Day B)
     - Squat + Primal Movement (Day C)
     - Full Body Circuit (Day D)
  d. Select the pattern combo with the highest staleness score
  e. Never repeat yesterday's primary pattern unless user requests it

Step 3 — Filter exercise pool:
  a. Start with all 142 exercises
  b. REMOVE exercises requiring equipment the user doesn't have
  c. REMOVE exercises flagged for user's injuries
  d. REMOVE exercises above user's difficulty level:
     - Beginner: difficulty 1-2 only
     - Intermediate: difficulty 1-3
     - Advanced: difficulty 1-5
  e. REMOVE exercises the user frequently skips (>3 skips)
  f. BOOST exercises the user rates highly (4-5 stars)
  g. If apartmentFriendly preference set, REMOVE exercises where apartmentFriendly = false

Step 4 — Select exercises for each block:
  a. From filtered pool, pick exercises matching today's movement patterns
  b. Prioritize variety: don't repeat exercises used in last 3 workouts
  c. For each movement pattern, select from appropriate progression chain:
     - Find user's current level in the chain (based on logged performance)
     - Select the exercise at that level
     - If user has achieved advancementCriteria (e.g., 3×15), auto-suggest next in chain
  d. For warmup: always pick 2-3 from mobility exercises (items 129-136)
  e. For cooldown (>10 min workouts): pick 1-2 from mobility exercises

Step 5 — Assemble workout structure:
  a. Warmup block: 2-3 mobility exercises, 30-45s each
  b. Main blocks: exercises arranged per template (Step 1)
  c. Calculate timing:
     totalTime = Σ(sets × estimatedTimePerSetSeconds) + Σ(restPeriods) + transitions(10s each)
  d. If totalTime > requestedDuration: remove last exercise or reduce sets
  e. If totalTime < requestedDuration - 2min: add exercise from same pattern
  f. Cooldown block: 1-2 stretches, 30s each

Step 6 — Calculate estimates:
  a. Calories: Σ(MET × weightKg × durationHours) per exercise
  b. Muscle groups worked map
  c. Generate static summary template:
     "{focusArea} · {exerciseCount} exercises · ~{calories} cal"

Output: Workout object ready for display
```

#### Workout Template Structures (per Duration)

```
5-MINUTE DENSITY BLOCK:
  Warmup: 1 mobility move (30s)
  Main: 5 rounds of single movement pattern
    Format: 40s work / 20s rest
    Exercises: 3 exercises from same pattern, rotating
  No cooldown
  Sets accumulated: 3-5 per muscle group

10-MINUTE CIRCUIT (Heria format):
  Warmup: 2 mobility moves (60s total)
  Main: 7-8 exercises × 45s work / 15s rest
    Pull from multiple patterns for full-body stimulus
  No cooldown
  Sets accumulated: 1-2 per muscle group

15-MINUTE FOCUSED BLOCK:
  Warmup: 2 mobility moves (60s)
  Block A: 2 exercises, 3 sets each, 60s rest (Pattern 1)
  Block B: 2 exercises, 3 sets each, 60s rest (Pattern 2)
  Cooldown: 1 stretch (30s)
  Sets accumulated: 6 for primary, 6 for secondary

20-MINUTE STRUCTURED SESSION:
  Warmup: 3 mobility moves (90s)
  Block A: 2-3 exercises, 3 sets, 60-90s rest
  Block B: 2 exercises, 3 sets, 60-90s rest
  Cooldown: 2 stretches (60s)
  Sets accumulated: 9-12 across 2-3 patterns

30-MINUTE FULL SESSION (Israetel superset format):
  Warmup: 3 mobility moves (90s)
  Superset 1: Push + Pull, 3 sets, 5-10s between, 90s between rounds
  Superset 2: Squat + Hinge, 3 sets
  Finisher: Core circuit, 2-3 exercises, 2 sets
  Cooldown: 2-3 stretches (90s)
  Sets accumulated: 12-18 covering full body
```

#### Exercise Swap Algorithm (No LLM)

```
When user taps "Swap":
  1. Record swap reason: 'too_hard' | 'no_equipment' | 'hurts' | 'dont_like'
  2. Find replacement from same:
     - movementPattern
     - progressionChainId (if possible)
     - Similar difficulty (±1 level)
  3. If reason = 'too_hard': pick regression (easier in chain)
  4. If reason = 'hurts': exclude all exercises sharing same primary muscle group
  5. If reason = 'dont_like': pick different exercise, same pattern, log to exercisesSkipped
  6. Ensure replacement hasn't been used in this workout
  7. Recalculate timing and calories
```

### 2.5 AI Integration Plan (Phase 2+)

AI/LLM features are NOT part of MVP. They are layered on after the core workout loop is validated.

#### Phase 2: LLM for Text Generation (Weeks 9-14)

**Post-workout AI summary** — After workout completion, send workout data to Claude API:
```
Input: completed workout data (exercises, sets, reps, duration, rating, difficulty)
       + user history (last 30 days trends)
Output: 2-3 sentence personalized summary
Example: "Strong session! You increased your push-up reps by 2 since last week.
         Your shoulder press is ready to progress — try elevated pike push-ups next time."
```

**Weekly AI progress report** — Monday morning, batch-generate:
```
Input: all workouts from past 7 days + 30-day trends
Output: ~150 word narrative with insights and encouragement
```

**Cost estimate:** ~$0.01-0.03 per summary (Claude Haiku), ~$0.05-0.10 per weekly report (Claude Sonnet). At 1,000 active users doing 3 workouts/week = ~$120-360/month.

#### Phase 3: LLM for Contextual Intelligence (Weeks 15-20)

- AI form tips personalized to user's logged mistakes and progression level
- Mood-based workout adjustment (interpret free-text mood input)
- AI reasoning for workout preview ("Tomorrow I'm focusing on pull + hinge because you haven't worked back in 4 days and your legs are fresh")

#### Phase 4: Advanced AI (Weeks 21+)

- AI voice coaching during workouts (TTS with contextual encouragement)
- Computer vision form checking (on-device, Vision framework)
- Predictive churn detection
- Calendar-aware scheduling

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
  "What do you have access to? (Select all that apply)"
  [Nothing — just me and the floor!]
  [Pull-up Bar]
  [Resistance Bands]
  [Parallettes or Push-up Bars]
  [Gymnastic Rings]
  [Dip Bars]
  [A Chair or Bench]

Screen 6: Weekly Commitment
  "How many workouts per week feels realistic?"
  Slider: 2 — 3 — 4 — 5 — 6 — 7
  Default position: 3
  Helper text: "Most FitSnack users start with 3. You can always adjust."

Screen 7: Injuries / Limitations (optional, skip-able)
  "Anything we should know about?"
  Multi-select tags: [Lower Back] [Knees] [Shoulders] [Wrists] [Neck] [Ankles]
  Free-text field: "Anything else? E.g., recovering from surgery..."
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
- Onboarding completion event triggers first workout generation (on-device, instant)
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
│  │  💪 Upper Body Push + Core    │ │
│  │  🕐 15 min · 🔥 ~120 cal      │ │
│  │                               │ │
│  │  Preview:                     │ │
│  │  • Diamond Push-Ups    3×12   │ │
│  │  • Pike Push-Ups       3×10   │ │
│  │  • Plank Shoulder Taps 3×10   │ │
│  │  • Bicycle Crunches    3×15   │ │
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
│  Insight 💡                       │
│  "You've hit upper body twice     │
│   this week — tomorrow will       │
│   focus on legs to stay balanced" │
│                                   │
└──────────────────────────────────┘
```

**Behavior:**
- On app open, if no workout generated today, auto-generate one using `typicalAvailableMinutes` (instant, on-device)
- "Change time" opens the duration slider and regenerates (instant)
- "Regenerate" creates a completely new workout for the same duration (instant)
- Quick Start buttons generate and immediately start a workout
- Workout preview shows 3-4 main exercises (not warmup/cooldown)
- Insight is template-based in Phase 1 (e.g., muscle balance tips from history data)
- Weekly dots show completion status at a glance

### 3.3 Active Workout Screen

The workout screen must be usable with sweaty hands, at arm's length, with minimal cognitive load.

```
┌──────────────────────────────────┐
│  Push + Core           12:34     │
│  ████████████░░░░  Exercise 3/6  │
│                                   │
│  ┌──────────────────────────────┐ │
│  │                               │ │
│  │    [Exercise Animation/Demo]  │ │
│  │    (looping Lottie or video)  │ │
│  │                               │ │
│  └──────────────────────────────┘ │
│                                   │
│  DIAMOND PUSH-UPS                 │
│  Set 2 of 3 · 12 reps            │
│                                   │
│  Form tip: "Hands together under  │
│  chest, elbows close to body"     │
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

**Workout screen features:**
- Large, tappable buttons (minimum 60pt touch targets)
- Exercise demo plays automatically (looping animation or short video)
- Haptic feedback on set completion
- Audio countdown beeps for timed exercises (last 3 seconds)
- Rest timer with haptic pulse when done
- "Swap Exercise" uses rule-based swap algorithm (instant, no API call)
- Progress bar shows overall workout progress
- Elapsed time always visible
- If user leaves app mid-workout, save state locally and resume on return
- Lock screen / Dynamic Island integration showing current exercise + timer

**Swap Exercise flow:**
1. User taps "Swap"
2. Bottom sheet shows reason: "Too hard" / "No equipment" / "Hurts" / "Don't like it"
3. Rule engine returns substitute matching same muscle group and time budget (instant)
4. New exercise slides in with animation
5. Swap reason stored for future generation learning

### 3.4 Post-Workout Screen

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
│  Summary:                         │
│  "Push + Core focus today.        │
│  You completed 9 sets across      │
│  4 muscle groups in 15 minutes."  │
│  (Phase 1: template-based)        │
│  (Phase 2: AI-generated insight)  │
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
│  │  6-axis: push, pull, legs,    │ │
│  │  core, hinge, mobility        │ │
│  └──────────────────────────────┘ │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  Progression Chains 📈        │ │
│  │  Push: Standard → Diamond ✓   │ │
│  │  Pull: Neg. Pull-Up → Pull-Up │ │
│  │  Squat: BW Squat → Lunge      │ │
│  │  Core: Plank → Hollow Hold    │ │
│  └──────────────────────────────┘ │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  Personal Records 🏆          │ │
│  │  Push-ups: 20 reps (Mar 20)   │ │
│  │  Plank: 1:45 (Mar 18)         │ │
│  │  L-Sit: 15s (Mar 22)          │ │
│  └──────────────────────────────┘ │
│                                   │
│  Recent Workouts                  │
│  [List of past workout cards]     │
│                                   │
└──────────────────────────────────┘
```

### 3.6 Streak & Gamification System

*(Unchanged from v1 — see full details in v1 PRD. Key points:)*

- **Weekly Streak:** 3 workouts/week default (Mon–Sun window)
- **Streak Saver:** 2-3 minute micro-workout offered Sunday evening if 1 short
- **XP:** duration_minutes × 3 per workout, bonuses for streaks and PRs
- **Levels:** Couch Explorer (L1) → Living Legend (L50)
- **Badges:** 10 achievements (First Rep, Early Bird, Century, etc.)

### 3.7 Notification Strategy

*(Unchanged from v1)*

### 3.8 Shareable Workout Card

*(Unchanged from v1)*

### 3.9 Settings & Profile

```
Profile & Settings
├── Account
│   ├── Name, Email, Avatar
│   ├── Apple Health Connection
│   ├── Subscription Status
│   └── Delete Account
├── Workout Preferences
│   ├── Available Equipment (multi-select: pull-up bar, bands, parallettes, rings, etc.)
│   ├── Injuries & Limitations (tag selector + free text)
│   ├── Weekly Workout Goal (slider)
│   ├── Preferred Workout Duration (default)
│   ├── Fitness Level
│   ├── Primary Goal
│   └── Apartment-Friendly Mode (no jumping/impact)
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

- 3 workouts per week (rule-engine generated)
- Basic workout history (last 7 days)
- Weekly streak tracking
- 1 streak freeze per month
- Full exercise library access
- Post-workout rating

### 4.2 Premium Tier ($7.99/month or $59.99/year)

Everything in Free, plus:
- Unlimited workouts
- Full workout history with analytics
- Muscle balance radar chart
- Progression chain tracking with advancement suggestions
- Personal records tracking
- AI post-workout summaries and insights (Phase 2+)
- AI weekly progress reports (Phase 2+)
- Unlimited streak freezes
- Shareable workout cards (premium designs)
- Apartment-friendly mode

### 4.3 Trial & Paywall

*(Unchanged from v1 — 14-day free trial, annual plan prominent)*

---

## 5. HealthKit Integration

*(Unchanged from v1)*

---

## 6. Exercise Library: 142 Calisthenics Exercises

### 6.1 Design Philosophy

The exercise library draws from three complementary coaching systems:

- **Chris Heria (THENX):** Circuit-and-progression framework. 45s work / 15s rest format. Prioritizes fundamentals before skills. Hybrid weighted calisthenics at 15+ rep mastery. 4.1M YouTube subscribers.
- **Dr. Mike Israetel (Renaissance Periodization):** Evidence-based volume science. Stimulus-to-fatigue ratio (SFR) drives exercise selection. Volume landmarks (MEV/MAV/MRV) set weekly targets. 5-30 reps to failure, 10-20 optimal.
- **Strength Side (Josh Hash):** Functional movement + mobility. Primal/animal movement patterns. Targets adults 35-60+ returning to fitness. Deep squat holds, bear crawls, ground transitions. 2.06M YouTube subscribers.

### 6.2 Equipment Categories

| Equipment | Required For | Exercise Count |
|-----------|-------------|---------------|
| None (bodyweight only) | Core library | ~85 exercises |
| Pull-up bar | Pull variations, hanging core | ~25 exercises |
| Resistance bands | Assisted movements, isolation | ~6 exercises |
| Elevated surface (chair/bench/box) | Incline/decline, Bulgarian splits | ~10 exercises |
| Parallettes or push-up bars | Deficit push-ups, L-sits | ~6 exercises |
| Rings | Ring push-ups, rows, dips, muscle-ups | ~8 exercises |
| Wall | Handstands, wall sits | ~4 exercises |
| Dip bars | Parallel bar dips | ~2 exercises |
| Sliders/towel | Sliding leg curls | ~1 exercise |
| Anchor point | Nordic curls | ~2 exercises |

### 6.3 Complete Exercise Database

#### PUSH — Horizontal (17 exercises)

| # | Exercise | Diff | Equipment | Primary Muscles | Secondary | Source | Progression Notes |
|---|----------|------|-----------|----------------|-----------|--------|-------------------|
| 1 | Wall Push-Ups | 1 | None | Chest, triceps | Front delts | CC | Entry point; build to 3×50 |
| 2 | Incline Push-Ups | 1 | Elevated surface | Chest, triceps | Front delts | Heria, SS | Adjustable by surface height |
| 3 | Knee Push-Ups | 1 | None | Chest, triceps | Front delts | Heria | Bridge to full push-ups |
| 4 | Standard Push-Ups | 2 | None | Chest, triceps | Front delts, core | All | Foundation; goal: 3×15 |
| 5 | Wide Push-Ups | 2 | None | Outer chest, shoulders | Triceps | Heria | Chest emphasis |
| 6 | Diamond Push-Ups | 2 | None | Triceps, inner chest | Shoulders | Heria, SS | Triceps emphasis |
| 7 | Decline Push-Ups | 2 | Elevated surface | Upper chest, shoulders | Triceps | Heria | Feet elevated 12–24" |
| 8 | Pseudo Planche Push-Ups | 3 | None | Shoulders, chest | Biceps, core | Heria | Hands by hips, lean forward |
| 9 | Deficit Push-Ups | 3 | Parallettes | Chest (deep stretch) | Triceps, shoulders | Israetel | Israetel: "amazing" for chest |
| 10 | Spiderman Push-Ups | 2 | None | Chest, obliques | Hip flexors, core | Heria | Warmup + core hybrid |
| 11 | Archer Push-Ups | 3 | None | Chest, triceps (uni) | Core, shoulders | Heria, SS | Step toward one-arm |
| 12 | Typewriter Push-Ups | 4 | None | Chest, triceps | Shoulders | Heria | Lateral shifting archer |
| 13 | Explosive/Clapping Push-Ups | 3 | None | Chest, triceps (power) | Shoulders | Heria | Plyometric; not apartment-friendly |
| 14 | Ring Push-Ups | 3 | Rings | Chest, triceps | Stabilizers, core | Israetel, Heria | Excellent SFR per Israetel |
| 15 | One-Arm Push-Ups | 4 | None | Chest, triceps, core | Obliques | Heria, CC | Master push exercise |
| 16 | Weighted Push-Ups | 3 | Vest/backpack | Chest, triceps | Shoulders | Heria | When 3×15 BW is easy |
| 17 | Pelican Push-Ups | 4 | Rings | Chest, biceps | Shoulders | Heria | Advanced ring variation |

#### PUSH — Vertical (10 exercises)

| # | Exercise | Diff | Equipment | Primary Muscles | Secondary | Source | Progression Notes |
|---|----------|------|-----------|----------------|-----------|--------|-------------------|
| 18 | Pike Push-Ups | 2 | None | Shoulders, triceps | Upper chest | Heria, SS | HSPU prep; build to 3×12 |
| 19 | Elevated Pike Push-Ups | 3 | Elevated surface | Shoulders, triceps | Traps | Heria | Feet on box/chair |
| 20 | Wall Walks | 2 | Wall | Shoulders, core | Traps | Heria | Handstand prep |
| 21 | Wall Handstand Hold | 2 | Wall | Shoulders, core, traps | Forearms | Heria, SS | Goal: 60 seconds |
| 22 | Freestanding Handstand | 3 | None | Shoulders, core, traps | Wrists | SS | Key skill |
| 23 | Handstand Push-Ups (wall) | 4 | Wall | Shoulders, triceps | Traps, core | Heria, SS | Build to 3×8 |
| 24 | 90-Degree HSPU | 5 | Parallettes + wall | Full upper body | Core | Heria | Elite pressing |
| 25 | Bench Dips | 1 | Bench/chair | Triceps | Chest, shoulders | Heria | Dip entry point |
| 26 | Parallel Bar Dips | 2 | Dip bars | Triceps, chest | Shoulders | All | Build to 3×15 |
| 27 | Ring Dips | 4 | Rings | Triceps, chest | Stabilizers | Heria, Israetel | Added instability |

#### PULL — Vertical and Horizontal (25 exercises)

| # | Exercise | Diff | Equipment | Primary Muscles | Secondary | Source | Progression Notes |
|---|----------|------|-----------|----------------|-----------|--------|-------------------|
| 28 | Dead Hang (passive) | 1 | Pull-up bar | Grip, forearms | Shoulder decompression | SS | Foundation; 30–60s holds |
| 29 | Active Hang | 1 | Pull-up bar | Scapular stabilizers, lats | Grip | SS | Scapular depression |
| 30 | Scapula Pull-Ups | 1 | Pull-up bar | Scapular muscles, lats | Grip | Heria | Front lever prep |
| 31 | Australian/Inverted Rows | 1 | Low bar/rings | Upper back, lats, biceps | Rear delts | All | Angle adjustable |
| 32 | Ring Rows | 1 | Rings | Upper back, biceps | Core, rear delts | SS, Israetel | Adjustable difficulty |
| 33 | Jumping Pull-Ups | 1 | Pull-up bar | Lats, biceps | Grip | Heria | Assisted concentric |
| 34 | Negative Pull-Ups | 2 | Pull-up bar | Lats, biceps (eccentric) | Grip, core | Heria | 5–7s lowering |
| 35 | Chin-Ups | 2 | Pull-up bar | Biceps, lats | Forearms | All | Supinated; higher bicep EMG |
| 36 | Pull-Ups (standard) | 2 | Pull-up bar | Lats, biceps | Rear delts, core | All | 117–130% MVIC lat activation |
| 37 | Wide-Grip Pull-Ups | 3 | Pull-up bar | Outer lats, teres major | Biceps | Heria | Lat width emphasis |
| 38 | Close-Grip Pull-Ups | 3 | Pull-up bar | Lats, biceps | Forearms | Heria | Bicep-heavy |
| 39 | Commando Pull-Ups | 3 | Pull-up bar | Lats, biceps, forearms | Core | Heria | Neutral grip, alternating |
| 40 | High Pull-Ups / Explosive | 3 | Pull-up bar | Lats, biceps (power) | Core | Heria, SS | Muscle-up prep |
| 41 | Sternum Pull-Ups | 3 | Pull-up bar | Lats, rhomboids | Biceps | Heria | Pull to sternum |
| 42 | L-Sit Pull-Ups | 4 | Pull-up bar | Lats, core | Biceps, hip flexors | OG | Pull-up + core |
| 43 | Archer Pull-Ups | 4 | Pull-up bar | Lats (unilateral) | Biceps, core | General | Step toward one-arm |
| 44 | Weighted Pull-Ups | 3 | Pull-up bar + vest | Lats, biceps | Full back | Heria, Israetel | When 3×15 BW easy |
| 45 | One-Arm Pull-Ups | 5 | Pull-up bar | Lats, biceps, grip | Core | Heria, CC | Master pull exercise |
| 46 | Band-Assisted Muscle-Ups | 3 | Bar + band | Lats, chest, triceps | Core | Heria | Muscle-up progression |
| 47 | Muscle-Ups | 4 | Pull-up bar | Lats, chest, triceps | Core, shoulders | Heria, SS | Prereq: 10–15 strict pull-ups |
| 48 | Ring Muscle-Ups | 4 | Rings | Lats, chest, triceps | Stabilizers | SS | Advanced ring skill |
| 49 | Skin the Cat | 3 | Rings/bar | Shoulders, lats | Core | SS | Shoulder mobility + strength |
| 50 | Ring Curls | 2 | Rings | Biceps | Forearms | Israetel | Adjustable by body angle |
| 51 | Bodyweight Skull Crushers | 2 | Low bar | Triceps | Chest | Israetel | Bar at waist height |
| 52 | Brachiation (monkey bars) | 3 | Monkey bars | Lats, biceps, grip | Core, shoulders | SS | 1–2 cycles × 5 sets |

#### SQUAT — Lower Body (22 exercises)

| # | Exercise | Diff | Equipment | Primary Muscles | Secondary | Source | Progression Notes |
|---|----------|------|-----------|----------------|-----------|--------|-------------------|
| 53 | Deep Squat Hold | 1 | None | Quads, glutes | Hip mobility, ankles | SS | Central to SS; hold 60s |
| 54 | Bodyweight Squats | 1 | None | Quads, glutes | Hamstrings, core | All | Foundation; build to 3×20 |
| 55 | Heel-Elevated Squats | 2 | Book/wedge | Quads (emphasized) | Glutes | Israetel | Go 2/3 up for constant tension |
| 56 | Sumo Squats | 2 | None | Quads, inner thighs | Glutes | Heria | Wide-stance variation |
| 57 | Cossack Squats | 3 | None | Adductors, quads | Hip mobility, glutes | SS | Mobility + strength hybrid |
| 58 | Alternating Lunges | 2 | None | Quads, glutes | Hamstrings, balance | Heria | Functional carryover |
| 59 | Reverse Lunges | 2 | None | Quads, glutes | Balance | SS, Israetel | Knee-friendly variant |
| 60 | Bulgarian Split Squats | 3 | Elevated surface | Quads, glutes | Hamstrings, balance | Israetel | High SFR; Israetel endorses |
| 61 | Sissy Squats | 3 | None/support | Quads (extreme) | Core | Israetel | Excellent quad SFR |
| 62 | Step-Ups | 2 | Box/chair | Quads, glutes | Balance | SS, Heria | >100% MVIC GMax per EMG |
| 63 | Jump Squats | 2 | None | Quads, glutes (power) | Calves | Heria | Not apartment-friendly |
| 64 | Switching Lunges | 3 | None | Quads, glutes (explosive) | Balance | Heria | Plyometric lunge |
| 65 | Horse Stance | 2 | None | Quads, adductors | Glutes | SS | Isometric wide stance hold |
| 66 | Assisted Pistol Squats | 3 | Support surface | Quads, glutes | Balance, ankles | Heria | Doorframe or band assist |
| 67 | Pistol Squats | 4 | None | Quads, glutes, balance | Core, ankles | All | Master single-leg squat |
| 68 | Duck Walk | 2 | None | Quads, glutes | Ankle mobility | SS | Deep squat walking |
| 69 | Single-Leg Calf Raises | 1 | Step/stairs | Calves | Balance | Israetel | Full ROM with deep stretch |
| 70 | Double-Leg Calf Raises | 1 | Step/stairs | Calves | — | Heria | Build to 3×20 |
| 71 | Wall Sit | 2 | Wall | Quads (isometric) | Glutes | Heria | 45–60s holds |
| 72 | Box Jumps | 3 | Box/platform | Quads, glutes (power) | Calves | Heria | Explosive lower body |
| 73 | Frog Hops | 2 | None | Quads, glutes | Shoulders | SS | Deep squat + explosive jump |
| 74 | Side-to-Side Squats | 2 | None | Quads, adductors | Glutes | Heria | Lateral movement |

#### HINGE — Posterior Chain (10 exercises)

| # | Exercise | Diff | Equipment | Primary Muscles | Secondary | Source | Progression Notes |
|---|----------|------|-----------|----------------|-----------|--------|-------------------|
| 75 | Glute Bridges | 1 | None | Glutes, hamstrings | Core | Israetel | Build to 3×20 |
| 76 | Single-Leg Glute Bridges | 2 | None | Glutes (unilateral) | Hamstrings, core | Israetel | Doubles load per leg |
| 77 | Single-Leg Hip Thrusts | 3 | Bench/chair | Glutes, hamstrings | Core | Israetel | Shoulders elevated |
| 78 | Single-Leg Romanian DL | 2 | None | Hamstrings, glutes | Balance, core | Israetel, SS | 59% MVIC GMax per EMG |
| 79 | Good Mornings (BW) | 2 | None | Hamstrings, erectors | Glutes | Israetel | Hands behind head |
| 80 | Sliding Leg Curls | 3 | Sliders/towel | Hamstrings | Glutes | Israetel | Smooth floor required |
| 81 | Nordic Curl (eccentric) | 3 | Anchor point | Hamstrings (eccentric) | Glutes | Israetel | High SFR; lower slowly |
| 82 | Full Nordic Curls | 4 | Anchor point | Hamstrings | Glutes, core | Israetel | Concentric + eccentric |
| 83 | Short Bridges | 1 | None | Glutes, lower back | Hamstrings | CC | Entry hinge movement |
| 84 | Full Bridges | 3 | None | Posterior chain, shoulders | Wrists, hip flexors | CC, SS | Spinal mobility + strength |

#### CORE — 34 exercises (Anti-Extension, Flexion, Rotation, Compression, Skills)

| # | Exercise | Diff | Equipment | Primary Muscles | Secondary | Source | Progression Notes |
|---|----------|------|-----------|----------------|-----------|--------|-------------------|
| 85 | Forearm Plank | 1 | None | Deep core, transverse abs | Shoulders | All | Build to 60s |
| 86 | High Plank | 1 | None | Core, shoulders | Triceps | Heria | Straight-arm variant |
| 87 | Plank Shoulder Taps | 2 | None | Core, anti-rotation | Shoulders | Heria | Anti-rotation + anti-extension |
| 88 | Plank to Low Plank | 2 | None | Core, triceps | Shoulders | Heria | Dynamic variation |
| 89 | Body Saw (plank) | 3 | None | Core (anti-extension) | Shoulders | General | Rock forward/back |
| 90 | Hollow Body Hold | 2 | None | Rectus abs, hip flexors | Transverse abs | SS, OG | Fundamental gymnastic position |
| 91 | Arch/Superman Hold | 1 | None | Erectors, glutes | Rear delts | SS | Complement to hollow body |
| 92 | Dead Bug | 1 | None | Deep core, hip flexors | Transverse abs | General | Anti-extension with limbs |
| 93 | Crunches | 1 | None | Rectus abdominis | — | Israetel | No-equipment core |
| 94 | Bicycle Crunches | 2 | None | Rectus abs, obliques | Hip flexors | Heria | 248% crunch activation (ACE) |
| 95 | Seated In-and-Outs | 2 | None | Full abs | Hip flexors | Heria | Signature THENX exercise |
| 96 | Lying Leg Raises | 2 | None | Lower abs | Hip flexors | Heria | Build to 3×15 |
| 97 | Lying Hip Raises | 2 | None | Lower abs (deep) | Core | Heria | Hips lift off floor |
| 98 | Flutter Kicks | 2 | None | Lower abs | Hip flexors | Heria | Alternating leg raises |
| 99 | V-Ups / Reach-Ups | 2 | None | Upper abs | Hip flexors | Heria | Full-body crunch |
| 100 | Hanging Knee Raises | 2 | Pull-up bar | Lower abs, hip flexors | Grip | Heria, SS | Build to 3×15 |
| 101 | Hanging Leg Raises | 3 | Pull-up bar | Full abs, hip flexors | Grip | Heria, SS | 212% crunch activation (ACE) |
| 102 | Toes-to-Bar | 4 | Pull-up bar | Full abs, hip flexors | Lats, grip | Heria | Advanced hanging core |
| 103 | Russian Twists | 2 | None | Obliques | Rectus abs | Heria | Seated rotation |
| 104 | Side Plank | 2 | None | Obliques | Hip stabilizers | All | Build to 45s each side |
| 105 | Side Plank Reach-Throughs | 3 | None | Obliques, core | Shoulders | Heria | Dynamic side plank |
| 106 | Mountain Climbers | 2 | None | Core, hip flexors | Shoulders (cardio) | Heria | Core + cardio hybrid |
| 107 | Plank Knees-to-Elbows | 2 | None | Core, obliques | Hip flexors | Heria | Cross-body mountain climber |
| 108 | Bolt Hold (tucked L-sit) | 2 | None/parallettes | Core, hip flexors | Triceps | Heria | L-sit entry; 45s goal |
| 109 | L-Sit (floor) | 3 | None/parallettes | Core, hip flexors, quads | Triceps | All | Key calisthenics hold |
| 110 | L-Sit (parallettes) | 3 | Parallettes | Core, hip flexors | Triceps, shoulders | Heria, OG | Elevated for easier compression |
| 111 | V-Sit | 5 | None/parallettes | Core, hip flexors | Shoulders | OG | Advanced compression hold |
| 112 | Tuck Front Lever | 3 | Pull-up bar | Lats, core | Shoulders | Heria | Entry front lever |
| 113 | Advanced Tuck Front Lever | 4 | Pull-up bar | Lats, core | Glutes | Heria | Extended hips |
| 114 | Full Front Lever | 5 | Pull-up bar | Lats, core, shoulders | Glutes | Heria | Elite static hold |
| 115 | Tuck Planche | 4 | Parallettes/floor | Shoulders, chest, core | Biceps (tendon) | Heria | Entry planche |
| 116 | Crow Stand | 2 | None | Shoulders, wrists | Core | Heria, CC | Balance and wrist conditioning |
| 117 | Dragon Flag (eccentric) | 4 | Bench | Full core | Hip flexors | General | Eccentric-only initially |
| 118 | Back Lever | 4 | Rings/bar | Shoulders, back, core | Biceps | Heria, SS | Shoulder flexibility required |

#### CARDIO, MOBILITY, and PRIMAL MOVEMENT (24 exercises)

| # | Exercise | Diff | Equipment | Primary Focus | Secondary | Source | Notes |
|---|----------|------|-----------|--------------|-----------|--------|-------|
| 119 | Jumping Jacks | 1 | None | Cardio, shoulders | Calves | Heria | Low-impact option available |
| 120 | High Knees | 1 | None | Cardio, hip flexors | Core | Heria | Standing-in-place |
| 121 | Burpees (no push-up) | 2 | None | Full body cardio | Core, legs | Heria | Step-back for apartment |
| 122 | Burpee Push-Ups | 3 | None | Full body + push | Chest, legs | Heria | Full burpee |
| 123 | Bear Crawl | 2 | None | Shoulders, core, quads | Coordination | SS | Fundamental animal movement |
| 124 | Lateral Bear Crawl | 2 | None | Shoulders, obliques | Hips | SS | Side-to-side |
| 125 | Crab Walk | 2 | None | Triceps, glutes, shoulders | Core | SS | Posterior + mobility |
| 126 | Side Kick-Through | 3 | None | Core, shoulders | Hip flexors | SS | Rotation from quadruped |
| 127 | Monkey Crawl | 3 | None | Shoulders, core, hips | Coordination | SS | Lateral locomotion |
| 128 | Ground-to-Standing | 2 | None | Full body, hip mobility | Balance | SS | Functional daily movement |
| 129 | Wrist Circles/Extensions | 1 | None | Wrist flexors/extensors | — | SS | Essential before ground work |
| 130 | Arm Circles | 1 | None | Shoulder mobility | Rotator cuff | Heria | Pre-workout activation |
| 131 | Cat-Cow | 1 | None | Thoracic spine | Core | SS | Spinal mobility prep |
| 132 | Deep Squat Mobility Hold | 1 | None | Hips, ankles | Lower back | SS | 60–90s passive hold |
| 133 | 90/90 Hip Stretch | 1 | None | Hip rotators | Glutes | SS | Internal/external rotation |
| 134 | Thoracic Spine Rotations | 1 | None | T-spine mobility | Lats | SS | Key mobility drill |
| 135 | World's Greatest Stretch | 2 | None | Hips, T-spine, hamstrings | Shoulders | General | Dynamic multi-joint |
| 136 | Shoulder Dislocates | 1 | Band/stick | Shoulder mobility | Chest, lats | SS | Warm-up essential |
| 137 | Band-Assisted Pull-Ups | 2 | Bar + band | Lats, biceps | Grip | Heria | Pull-up progression |
| 138 | Band Pull-Aparts | 1 | Band | Rear delts, rhomboids | Mid-traps | Israetel | High-frequency accessory |
| 139 | Band Face Pulls | 1 | Band | Rear delts, rotator cuff | Mid-traps | Israetel, SS | Shoulder health essential |
| 140 | Band Lateral Raises | 1 | Band | Side delts | Traps | Israetel | Side delt isolation |
| 141 | Band-Resisted Push-Ups | 2 | Band | Chest, triceps | Shoulders | General | Progressive resistance |
| 142 | Band Good Mornings | 1 | Band | Hamstrings, glutes | Erectors | General | Light hinge patterning |

### 6.4 Twelve Progression Chains

Each chain represents a skill path. Mastery of one level (3 sets × 8-15 reps or 30-60s holds) signals readiness for the next.

**Chain 1 — Horizontal Push:** Wall push-ups → Incline → Knee → Standard → Diamond → Decline → Pseudo planche → Archer → One-arm. *Side branch:* Deficit → Ring push-ups → Pelican push-ups.

**Chain 2 — Vertical Push:** Pike push-ups → Elevated pike → Wall handstand holds → Wall HSPU → Freestanding handstand → 90° HSPU. *Dip branch:* Bench dips → Parallel bar dips → Ring dips.

**Chain 3 — Vertical Pull:** Dead hang → Active hang → Scapula pull-ups → Negative pull-ups → Chin-ups/Pull-ups → Wide/close grip → High pull-ups → Sternum pull-ups → Weighted → Archer → One-arm. *Skill branch:* Band-assisted muscle-ups → Muscle-ups → Ring muscle-ups.

**Chain 4 — Horizontal Pull:** Inverted rows (vertical angle) → Inverted rows (incline) → Horizontal inverted rows → Ring rows → Wide rows → Archer rows.

**Chain 5 — Squat:** Deep squat holds → Bodyweight squats → Heel-elevated → Lunges → Bulgarian split squats → Sissy squats → Assisted pistols → Pistol squats. *Side:* Sumo → Cossack squats.

**Chain 6 — Hinge:** Glute bridges → Single-leg bridges → Good mornings → Single-leg RDL → Sliding leg curls → Nordic eccentric → Full Nordic. *Bridge branch:* Short bridges → Full bridges.

**Chain 7 — Core Anti-Extension:** Dead bug → Forearm plank → Body saw → Hollow body hold → Dragon flag eccentric → Full dragon flags.

**Chain 8 — Core Dynamic:** Crunches → Bicycle crunches → Lying leg raises → Seated in-and-outs → Hanging knee raises → Hanging leg raises → Toes-to-bar.

**Chain 9 — Core Compression:** Bolt hold → L-sit kicks → Floor L-sit → Parallette L-sit → V-sit.

**Chain 10 — Front Lever:** Scapula pull-ups → Tuck front lever → Advanced tuck → Single-leg → Full front lever.

**Chain 11 — Planche:** Pseudo planche hold → Pseudo planche push-ups → Crow stand → Tuck planche → Advanced tuck → Full planche.

**Chain 12 — Primal Movement:** Deep squat hold → Bear crawl → Lateral bear crawl → Crab walk → Side kick-throughs → Monkey crawl → Primal flow sequences.

### 6.5 Exercise Media (MVP)

- **Thumbnail:** 400×400 static illustration per exercise
- **Demo animation:** Lottie stick-figure animations (Phase 1), live-action video (Phase 2+)
- **Form cue text:** 2-3 key points displayed during exercise (static text, stored in Exercises.json)

---

## 7. Navigation Structure

```
Tab Bar (4 tabs)
├── 🏠 Home (Today's workout + quick start)
├── 📊 Progress (History, stats, charts, progression chains)
├── 🏆 Challenges (Leaderboard, badges, challenges)
└── ⚙️ Profile (Settings, subscription, preferences)
```

---

## 8. Development Phases (Restructured)

### Phase 1: MVP — Rule-Based Engine, No AI (Weeks 1–8)

**Goal:** Core workout loop powered by deterministic algorithm. Validate that the "open → time → play" experience works without any LLM dependency.

**What ships:**
- [ ] Project setup: SwiftUI app, navigation structure, tab bar
- [ ] Onboarding flow (8 screens)
- [ ] User authentication (Apple Sign In + email)
- [ ] Backend API: user CRUD, sync, subscriptions
- [ ] **Rule-based workout generation engine (on-device, instant)**
- [ ] **Exercise database: 142 exercises as bundled JSON (Exercises.json)**
- [ ] **12 progression chains with auto-advancement logic**
- [ ] **Workout templates for 5/10/15/20/25/30-minute sessions**
- [ ] **Rule-based exercise swap (instant, no API)**
- [ ] Home screen: today's workout preview, time selector, quick start
- [ ] Active workout screen: exercise display, set tracking, rest timer, swap
- [ ] Post-workout screen: rating, difficulty, calorie display (MET formula)
- [ ] **Template-based post-workout summary** (no AI — e.g., "Push + Core · 6 exercises · 127 cal")
- [ ] Workout history (basic list view)
- [ ] Weekly streak system
- [ ] Push notifications (daily reminder, streak at risk)
- [ ] CoreData local storage
- [ ] Basic Settings screen (equipment, injuries, fitness level)
- [ ] StoreKit 2 subscription integration
- [ ] HealthKit: write workouts

**What does NOT ship in Phase 1:**
- ❌ No LLM API calls of any kind
- ❌ No AI-generated summaries or insights
- ❌ No AI form tips
- ❌ No social features
- ❌ No XP/leveling system (add in Phase 2)

**Cost in Phase 1:** $0 for AI. Only costs are backend hosting (~$10-50/month) and Apple Developer account ($99/year).

### Phase 2: AI Intelligence Layer + Engagement (Weeks 9–16)

**Goal:** Layer LLM-powered text generation on top of the validated workout loop. Add retention mechanics.

**AI features (first LLM integration):**
- [ ] **AI post-workout summaries** — Claude Haiku generates 2-3 sentence personalized insight after each workout
- [ ] **AI weekly progress reports** — Claude Sonnet generates ~150 word narrative every Monday
- [ ] **AI next-workout preview with reasoning** — "Tomorrow: Pull + Hinge because you haven't worked back in 4 days"
- [ ] API endpoint: `/api/ai/summary`, `/api/ai/weekly-report`

**Engagement features (no AI required):**
- [ ] XP and leveling system
- [ ] Badge system (10 badges)
- [ ] Shareable workout cards
- [ ] Progression chain visualization (which level you're at per chain)
- [ ] Progress charts (Swift Charts): calendar heat map, muscle radar
- [ ] Personal records tracking
- [ ] Streak freezes + streak saver micro-workouts
- [ ] Exercise demo animations (Lottie) for top 50 exercises
- [ ] Improved push notifications (personalized timing based on actual usage)
- [ ] HealthKit: read heart rate, weight
- [ ] Paywall optimization

**Estimated AI cost:** ~$120-360/month at 1,000 active users (Claude Haiku for summaries, Sonnet for weekly reports).

### Phase 3: Growth + Advanced AI (Weeks 17–22)

**Goal:** Viral mechanics, community features, and deeper AI personalization.

**AI features:**
- [ ] **AI contextual form tips** — personalized to user's progression level and common mistakes
- [ ] **Mood-based workout adjustment** — interpret free-text mood to adjust workout type/intensity
- [ ] **AI-enhanced workout generation** — LLM can override/enhance rule-engine output for edge cases

**Growth features:**
- [ ] Friends system (contacts, share link)
- [ ] Weekly leaderboard (friends' XP)
- [ ] Group challenges ("Team 1000 Minutes")
- [ ] Referral system (invite → both get 1 month free)
- [ ] Workout card customization
- [ ] iOS widget (streak count, next workout time)
- [ ] Dynamic Island integration (active workout timer)
- [ ] Lock screen Live Activity
- [ ] A/B testing framework
- [ ] Analytics: Mixpanel / Amplitude

### Phase 4: AI-First Features (Weeks 23+)

- [ ] AI voice coaching during workouts (TTS with contextual encouragement)
- [ ] Calendar integration (suggest workout windows based on schedule)
- [ ] Computer vision form checking (on-device, Vision framework)
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

### 9.3 Workout Quality Metrics

| Metric | Target |
|--------|--------|
| Workout generation latency (Phase 1) | < 100ms (on-device) |
| Workout generation latency (Phase 2+ AI) | < 3 seconds |
| Workout rating (user avg) | ≥ 3.8 / 5 |
| Difficulty rating "Just Right" | ≥ 65% |
| Exercise swap rate | < 15% |
| Workout completion rate (started → finished) | ≥ 80% |

---

## 10. Technical Constraints & Non-Functional Requirements

### 10.1 Performance

- App launch to home screen: < 2 seconds
- Workout generation (Phase 1, on-device): < 100ms
- Workout generation (Phase 2+, AI-enhanced): < 3 seconds
- Exercise swap: instant (on-device rule engine)
- Offline support: workout generation works fully offline (rule engine + bundled exercise DB)
- App size: < 80 MB (Lottie animations are lightweight)

### 10.2 Security & Privacy

- All API communication over HTTPS
- JWT tokens with 15-minute expiry, refresh tokens in Keychain
- User data encrypted at rest (CoreData + CloudKit)
- GDPR/CCPA compliant: data export + deletion endpoints
- No selling of user data
- HealthKit data never leaves the device
- Phase 2+ AI prompts do not contain PII beyond age/sex/weight

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
| Rule engine generates repetitive workouts | Medium | 142-exercise library + variety scoring + "don't repeat last 3 workouts" logic |
| Rule engine generates unsafe exercise for user's level | High | Strict difficulty filtering by fitness level; injury tag exclusions; progression chain gating |
| Users outgrow rule engine's intelligence | Medium | Phase 2 AI layer enhances generation; user feedback loop continuously improves |
| Low Day 1 retention | High | Minimize onboarding; first workout in < 5 min; instant generation (no loading) |
| Users find workouts too easy/hard | Medium | Post-workout rating + difficulty feedback adjusts next workout within 1 session |
| App Store rejection | Medium | Follow HIG; avoid medical claims; clear subscription disclosures |
| Exercise injury liability | High | Health disclaimer; never claim medical authority; progression chain prevents over-reaching |
| Phase 2 AI costs spiral | Medium | Use Haiku for summaries ($0.01 each); rate-limit free tier; cache common patterns |

---

## 12. Legal & Compliance

*(Unchanged from v1)*

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
│   ├── WorkoutHistory.swift
│   └── ProgressionChain.swift         # NEW: chain definitions
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
│   │   └── InsightCard.swift           # Template-based in P1, AI in P2
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
│   │   ├── ProgressionChainView.swift  # NEW: visual chain progress
│   │   ├── PersonalRecordsView.swift
│   │   ├── WorkoutHistoryList.swift
│   │   └── WeeklyReportView.swift
│   │
│   ├── Social/                         # Phase 3
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
├── Engine/                             # NEW: Rule-based workout engine
│   ├── WorkoutGenerator.swift          # Core generation algorithm
│   ├── ExerciseFilter.swift            # Equipment/injury/level filtering
│   ├── ExerciseSelector.swift          # Variety, staleness, preference scoring
│   ├── WorkoutAssembler.swift          # Template assembly + timing calc
│   ├── ProgressionManager.swift        # Chain advancement logic
│   ├── SwapEngine.swift                # Exercise substitution logic
│   └── CalorieCalculator.swift         # MET-based calculation
│
├── Services/
│   ├── APIService.swift               # Network layer
│   ├── AuthService.swift              # Apple Sign In + JWT
│   ├── HealthKitService.swift         # HealthKit read/write
│   ├── NotificationService.swift      # Push notification management
│   ├── SubscriptionService.swift      # StoreKit 2
│   ├── PersistenceService.swift       # CoreData
│   ├── AnalyticsService.swift         # Event tracking
│   ├── ShareService.swift             # Workout card generation
│   └── AIService.swift                # Phase 2+: Claude API integration
│
├── Persistence/
│   ├── FitSnack.xcdatamodeld          # CoreData schema
│   ├── CoreDataManager.swift
│   └── CloudKitManager.swift
│
├── Utilities/
│   ├── DateExtensions.swift
│   ├── ColorTheme.swift
│   ├── HapticManager.swift
│   └── Constants.swift
│
├── Resources/
│   ├── Exercises.json                 # 142-exercise database (bundled)
│   ├── ProgressionChains.json         # 12 chain definitions (bundled)
│   ├── WorkoutTemplates.json          # Duration-based templates (bundled)
│   ├── Animations/                    # Lottie files
│   └── Fonts/
│
└── Tests/
    ├── WorkoutGeneratorTests.swift     # Core engine tests
    ├── ExerciseFilterTests.swift
    ├── ProgressionManagerTests.swift
    ├── CalorieCalculatorTests.swift
    ├── StreakLogicTests.swift
    └── SwapEngineTests.swift
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
static let largeTitle = Font.system(size: 34, weight: .bold)
static let title = Font.system(size: 24, weight: .bold)
static let title2 = Font.system(size: 20, weight: .semibold)
static let headline = Font.system(size: 17, weight: .semibold)
static let body = Font.system(size: 17, weight: .regular)
static let callout = Font.system(size: 16, weight: .regular)
static let subheadline = Font.system(size: 15, weight: .regular)
static let footnote = Font.system(size: 13, weight: .regular)
static let caption = Font.system(size: 12, weight: .regular)
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
static let cornerRadiusFull: CGFloat = 9999

static let buttonHeight: CGFloat = 56
static let cardPadding: CGFloat = 16
```

---

## 15. App Store Metadata

### 15.1 Name & Subtitle

**Name:** FitSnack — Micro Workouts
**Subtitle:** 5-30 min calisthenics for busy people

### 15.2 Keywords

`workout,fitness,calisthenics,short workout,quick workout,home workout,busy mom,busy dad,exercise,micro workout,5 minute workout,bodyweight,no gym,streak,hiit,strength,pull ups,push ups`

### 15.3 Description (First 3 Lines)

"Too busy to work out? FitSnack creates a custom workout in seconds — just tell it how many minutes you have. Whether you've got 5 minutes between meetings or 30 minutes while the kids nap, FitSnack builds the perfect calisthenics workout for you, every single day."

### 15.4 App Category

Primary: Health & Fitness
Secondary: Lifestyle

---

*End of PRD v2.0*
