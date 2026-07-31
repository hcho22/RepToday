# Product Requirements Document: FitSnack — Discipline-First Movement App

**Version:** 6.0
**Last Updated:** July 2, 2026
**Platform:** iOS (SwiftUI, iOS 17+)
**Status:** Pre-Development

**What changed in v6.0 (reconciles the document to ADRs 0014–0019):**

v6.0 reworks the product around a new wedge: **daily-adaptive AI programming that builds discipline**. The AI does not generate workouts directly — it tunes the parameters the deterministic engine runs on. This inverts v5.0's stance that AI is language-only, and introduces a minimal backend earlier than v5.0 assumed. Specifically:

- **AI shapes policy; the engine still generates every session (ADR-0014).** An asynchronous, off-device **AI Programmer** reviews logged history and writes a per-user **Session Policy** (progression rate, pillar weighting, variety windows). The on-device **Deterministic Engine** still assembles every session offline in <100ms from that policy. This **supersedes v5.0's ADR-0007** (AI as language-only): AI now influences workouts, but indirectly, never by direct generation.
- **Discipline overrides optimization (ADR-0015).** When the AI Programmer's optimization logic and the discipline goal conflict, discipline wins by design. The sharp case — a **Return** after a gap — is resolved by sequencing: the Return session is easy, winnable, and celebrated regardless of detraining; readjustment for lost time happens across the following **Re-entry Ramp**, never in the Return itself.
- **The app opens to a ready session, never a question (ADR-0016).** Sessions support a **5–60 min** range (superseding v5.0's 5–30 and the informal 5–10 "single-focus" framing), but the app never gates entry on "how long do you have?" It opens to a **Ready Screen** — a complete session pre-generated at the user's **Default Duration**, one tap to start, with duration a non-blocking one-tap adjustment.
- **Backend is a client-triggered stateless proxy; no scheduler, no data mirror (ADR-0017).** Re-programming is triggered by the client on app open when due — never by a server clock. The MVP **starts at option (C)** (deterministic re-weighting, zero LLM calls) and migrates to **(B)** (LLM through a thin key-holding proxy). This **supersedes v5.0's "no backend / $0 AI" MVP claim.**
- **Cold-start difficulty: capped self-report + asymmetric ramp (ADR-0018).** Day-one difficulty is seeded from self-reported `fitnessLevel` but served at the gentle end of a capped band; real performance then corrects via an **Asymmetric Ramp** — eager to back off, patient to push.
- **Cold-start variety: derived week one + a day-one LLM slice (ADR-0019).** Week one is derived from onboarding inputs but governed by a mandatory **First-Week Contrast** rule so the wedge is vivid immediately. The contrast is named in language from session one via a **fallback-guarded LLM slice** — the one LLM call pulled into the MVP, always backed by a deterministic template.

**Carried forward unchanged from v5.0 (ADRs 0001–0013):** discipline-first positioning; the two-phase Discipline→Strength journey; Movement Practice as co-primary pillar; ~30–40 movement launch library; forgiving rolling Consistency Score; Zero-Equipment Floor; Apple-native client stack; free-unlimited-workouts monetization with paywall on depth.

**Open decisions flagged in this document:** the single-focus-vs-blend session model at the new 5–60 range (§2.4); whether `primaryGoal` survives alongside the new `why` (§2.3); the cold-start-to-normal-loop handoff threshold (§2.8). Each is marked `[NEEDS DECISION]` inline.

---

## 1. Executive Summary

FitSnack is an iOS-first movement app for busy, desk-bound adults who can give exercise a few minutes a day. It exists to build one thing: the **discipline** of showing up. Open the app and a complete zero-equipment session is already waiting — a blend of bodyweight strength, mobility, and primal movement, assembled by a deterministic on-device engine. No browsing, no choosing, no thinking, and no question to answer before you start. Sessions run anywhere from 5 to 60 minutes; the app arrives pre-set to the length you actually complete, adjustable in one tap if today is different.

The wedge is **daily-adaptive AI that builds discipline**. Behind the scenes, an **AI Programmer** learns each user — their history, their stated *why*, the durations they truly finish, the signs they're stalling or drifting away — and tunes the parameters the engine runs on. It never generates a workout directly and is never on the path between opening the app and starting; it shapes the *program* the daily sessions emerge from. The felt result is an app that quietly gets to know you and keeps the work fresh, varied, and winnable — so the habit sticks.

The product is built on a two-phase journey. New users live in the **Discipline Phase**, where the only goal is consistency and sessions stay short and simple. As a user earns it — by sustaining the habit *and* progressing their movements — the app matures into the **Strength Phase**, where training shifts toward real strength and capability. Strength is the destination, not the entry promise.

### 1.1 Core Value Proposition

- **Build the discipline to move well and feel better — in minutes.** The honest promise at this dose.
- **An AI that learns you and builds the habit.** The AI Programmer reads your history, your *why*, and your real patterns to keep sessions fresh, varied, and winnable — and to catch you drifting before you quit. It tunes the program; it never makes you wait or think.
- **Nothing to decide, ever.** Open the app and today's session is already there — no browsing, no picker to clear, not even a "how long do you have?" to answer. Instant, offline, free.
- **Never the same week twice.** Sessions are non-repetitive by design, deliberately spreading across strength, mobility, and primal movement so different parts of the body get worked day to day — and the app tells you what today is and how it differs, so the variety is felt from session one.
- **Mobility is co-primary, not a warm-up.** Movement Practice (deep squat holds, hip work, thoracic rotations, primal movement) targets the stiffness a desk worker feels *today* and delivers same-day relief — the differentiator no strength-led competitor leads with.
- **Zero equipment, permanently.** Every session works with a floor and a wall. Optional minimal equipment arrives only in the Strength Phase, and is never required.
- **Earned strength.** Consistent showing-up plus built-in progression produces real strength over time; the app turns up the dial as you prove the habit.
- **Forgiving by design.** A rolling Consistency Score rewards showing up and survives a missed day. Come back after a gap and the app celebrates the return with an easy win — it never makes you feel behind.

### 1.2 Target Users

**Primary:** Working parents aged 28–45 who sit 6+ hours/day, feel stiff and guilty about not exercising, and have abandoned 2–3 fitness apps. Their felt pain is stiffness and aches *now*, not a lack of muscle.

**Secondary:** Busy professionals aged 25–40 who travel or work unpredictable hours and cannot commit to a gym schedule.

**Psychographic:** Time- and bandwidth-poor, not motivation-poor. They want to feel they are "doing something" even on their worst day — and to not be made to feel like failures when they miss.

---

## 2. Technical Architecture

### 2.1 Tech Stack (MVP — Apple-native client + thin stateless proxy)

```
┌─────────────────────────────────────────────────────────┐
│                       iOS Client                         │
│  SwiftUI · iOS 17+ · Swift 5.9+                           │
│  HealthKit · CoreData · CloudKit · StoreKit 2             │
│  Sign in with Apple · Lottie · Swift Charts              │
│                                                          │
│  Deterministic Engine (on-device) — generates every     │
│    session offline, <100ms, from the Session Policy      │
│  Session Policy (CoreData/CloudKit) — always valid,      │
│    even offline and before the AI Programmer first runs  │
│  Exercise Library (bundled JSON, ~30–40 movements)       │
│  Consistency Score + Phase Evaluator (CoreData)          │
│  Adaptive Overload (logged-performance driven)           │
│  Re-program trigger (on app open, when due)              │
└──────────────────────────┬───────────────────────────────┘
                           │  single LLM call, only when a
                           │  Re-program is due (never on the
                           │  path to starting a session)
                           ▼
┌─────────────────────────────────────────────────────────┐
│         Thin Stateless Proxy (the only backend)          │
│  Holds the model API key; proxies one Claude call per    │
│  Re-program. No user logs at rest — history is sent       │
│  transiently from the device and not stored server-side. │
│  No scheduler. No database mirror. Nearly free at rest.   │
└─────────────────────────────────────────────────────────┘
```

**The AI Programmer** runs behind this proxy: given a user's recent logs, it diagnoses plateaus (Physical Stall / Disengagement) and rewrites the **Session Policy** — progression rate, pillar weighting, variety windows. It **never generates or delivers a session** and is **never on the critical path** of starting one. The Deterministic Engine reads the policy and assembles every session on-device.

**MVP migration (ADR-0017):** the MVP *starts at option (C)* — the re-weighting runs as deterministic heuristics on-device with **zero LLM calls** — and migrates to *(B)*, where the LLM (via the proxy) makes the diagnosis and the weekly note richer. One LLM slice is pulled forward into the MVP regardless: the day-one **Variety Language** (ADR-0019), always backed by a deterministic template so the app never depends on the network, even on day one.

**CloudKit** handles sync + backup, **StoreKit 2** subscriptions, **Sign in with Apple** identity, **HealthKit** stays on-device. The proxy is the same minimal key-holder v5.0 always anticipated for language features — introduced sooner, not a new class of infrastructure (ADR-0014, ADR-0017).

### 2.2 Core Domain Concepts

These are the canonical terms (full definitions in `CONTEXT.md`):

Carried from v5.0:
- **Micro-Workout** — a complete session generated to fit the user's available time (now 5–60 min).
- **Discipline Phase / Strength Phase** — the two stages of a user's journey.
- **Earned Progression** — advancing between phases by demonstrated consistency, not self-selection.
- **Adaptive Overload** — week-to-week variation and increasing demand keyed to logged performance.
- **Movement Practice** — the co-primary mobility/longevity pillar.
- **Warm-up** — the brief preparatory mobility that opens every session (distinct from Movement Practice).
- **Single-Focus Session** — a short session that does one pillar well rather than blending. `[NEEDS DECISION: thresholds at the new 5–60 range — see §2.4]`
- **Zero-Equipment Floor** — the permanent guarantee that every workout needs only a floor and a wall.
- **Consistency Score** — the forgiving, rolling measure of showing up.

New in v6.0 (the AI Programmer model):
- **Deterministic Engine** — the on-device logic that assembles every session offline and instantly; it selects and sequences movements but does not learn.
- **AI Programmer** — the asynchronous, off-device process that reviews history and writes the Session Policy; its scoped job is plateau diagnosis + cross-signal weekly re-weighting, surfaced as a natural-language note. Never generates a session; never on the critical path.
- **Session Policy** — the per-user parameters the engine consumes (progression rate, pillar weighting, variety windows). The AI Programmer writes it; the engine reads it. Always valid, including offline and before the AI Programmer has ever run.
- **Program (user-facing)** — the *felt* experience of a personalised plan; an emergent result of policy + daily generation, never a pre-authored multi-week artifact.
- **Return** — a user's first session after a gap; governed by discipline (easy, winnable, celebrated; Consistency Score protected), not optimization.
- **Re-entry Ramp** — the few sessions after a Return over which difficulty walks back up to account for lost time. Readjustment lives here, never in the Return itself.
- **Why** — the user's underlying reason for training; primarily a *language* input, with exactly one programming effect (a mobility/strength/primal opening bias). Never invoked in language for a session that doesn't actually reflect it.
- **Ready Screen** — the state the app opens to: a complete session pre-generated at the Default Duration, one tap to start; adjustments are non-blocking, never a gate.
- **Default Duration** — the pre-selected session length; seeded by onboarding, then set to the duration the user actually *completes* (not what they pick).
- **Re-program** — one pass of the AI Programmer; triggered on app open when due (Weekly Boundary, Return, Physical Stall, Disengagement), never by a server clock. Renders from the old policy immediately; new policy applies next open.
- **Weekly Boundary** — the re-program cadence tied to the user's Consistency Score week.
- **Physical Stall** — trigger: cleared to advance but hasn't (an optimization concern → *more* challenge).
- **Disengagement** — trigger: fading commitment, shrinking/skipped sessions (a discipline concern → *less* friction).
- **Trigger Precedence** — when both fire, Disengagement wins; never add challenge to a user showing signs of leaving (ADR-0015 applied at trigger level).
- **Starting Difficulty** — day-one difficulty, seeded from a *capped* self-reported band, served at its gentle end.
- **Asymmetric Ramp** — difficulty moves down eagerly (on "too hard"/skips) and up gradually (on "too easy").
- **First-Week Contrast** — the rule forcing week one to spread vividly across pillars, overriding the theme-sameness that onboarding inputs would otherwise produce.
- **Variety Language** — the day-one naming of each session's contrast; the one LLM slice in the MVP, always backed by a deterministic template.

### 2.3 Data Models (MVP-relevant)

```typescript
type Pillar = 'strength' | 'mobility' | 'primal';

type Phase = 'discipline' | 'strength';

interface User {
  id: string;
  displayName: string;
  createdAt: Date;

  profile: {
    age: number;
    sex: 'male' | 'female' | 'other';
    heightCm: number;
    weightKg: number;
    fitnessLevel: 'beginner' | 'intermediate' | 'advanced';  // seeds Starting Difficulty (capped) + ramp speed
    // [NEEDS DECISION] primaryGoal vs why: `why` (below) now carries motivation.
    // Does the coarse enum survive alongside it, or fold into `why`? Kept for now, un-reconciled.
    primaryGoal: 'stay_active' | 'build_strength' | 'increase_energy' | 'reduce_stress' | 'lose_weight';
    why: {                             // ADR-0019 / CONTEXT: language-primary, one programming effect
      statement: string;               // free text, e.g. "get on the floor with my grandkids"
      openingBias?: Pillar;            // the SINGLE programming effect the why is allowed to have
    };
    sitsLong: boolean;                 // "sit 6+ hours most days?" — biases toward Movement Practice
    injuries: string[];                // tags: "lower_back", "knees", ...
  };

  phase: Phase;                        // computed by PhaseEvaluator; never user-selected

  duration: {                          // ADR-0016 / ADR-0018
    defaultMinutes: number;            // shown on Ready Screen; set to COMPLETED duration, not picked
    onboardingSeedMinutes: number;     // the single onboarding answer that seeds day one
    completedDurationEWMA?: number;    // learned signal the AI Programmer reads to set defaultMinutes
  };

  coldStart: {                         // ADR-0018 / ADR-0019; retired after handoff (see §2.8)
    sessionsLogged: number;
    active: boolean;                   // true until enough history drives the engine unassisted
  };

  subscription: {
    tier: 'free' | 'premium';          // free = unlimited workouts; premium = depth layer
    provider: 'apple';
    expiresAt?: Date;
    trialEndsAt?: Date;
  };

  consistency: {
    weeklyGoal: number;                // default 3
    score: number;                     // rolling 0–100, forgiving (see ConsistencyScore)
    workoutsThisWeek: number;
    longestChain: number;              // surfaced as earned celebration, never as threat
    totalWorkoutsCompleted: number;
    totalMinutesExercised: number;
  };
}

interface Exercise {
  id: string;                          // e.g. "push_standard"
  displayName: string;
  pillar: Pillar;
  movementPattern: MovementPattern;
  category: 'strength' | 'mobility' | 'warmup' | 'cooldown' | 'primal';
  difficulty: 1 | 2 | 3 | 4 | 5;
  phase: Phase;                        // discipline-available vs strength-only (e.g. L-sit)
  equipment: Equipment[];              // MVP: always [] (bodyweight) — Zero-Equipment Floor
  isHold: boolean;                     // holds are timed; reps otherwise
  defaultReps?: number;
  defaultDurationSeconds?: number;
  estimatedTimePerSetSeconds: number;
  metValue: number;
  progressionChainId: string;
  progressionOrder: number;
  regressionId?: string;
  progressionId?: string;
  advancementCriteria: string;         // e.g. "3x15 clean reps"
  apartmentFriendly: boolean;
}

interface WorkoutLog {                 // the signal BOTH Adaptive Overload and the AI Programmer read
  workoutId: string;
  completedAt: Date;
  requestedMinutes: number;            // what the Ready Screen offered / the user set
  durationMinutes: number;             // what they ACTUALLY completed (feeds Default Duration)
  shape: 'single_focus' | 'blend';     // [NEEDS DECISION] thresholds at 5–60 — see §2.4
  focusPillar?: Pillar;                // for single-focus sessions
  perceivedDifficulty?: 'too_easy' | 'just_right' | 'too_hard';  // drives Asymmetric Ramp
  wasReturn: boolean;                  // true if this was a Return session (ADR-0015)
  exercises: {
    exerciseId: string;
    pillar: Pillar;
    movementPattern: MovementPattern;
    completedSets: { reps?: number; durationSeconds?: number }[];
    skipped: boolean;
  }[];
}

// The central v6 object: written by the AI Programmer, read by the Deterministic Engine.
// ALWAYS valid — a fresh user has a sensible default policy before the Programmer ever runs.
interface SessionPolicy {              // ADR-0014 / ADR-0017
  version: number;                     // increments each Re-program; engine reads the latest
  updatedAt: Date;
  updatedBy: 'default' | 'deterministic' | 'llm';  // (C) writes 'deterministic'; (B) writes 'llm'

  progressionRate: number;             // how fast Adaptive Overload advances (per-user)
  pillarWeighting: Record<Pillar, number>;         // relative time/emphasis across pillars
  varietyWindow: number;               // "no repeats within N sessions" — tunable per user

  coldStartContract?: {                // present only while coldStart.active (ADR-0019)
    forceContrastSpread: boolean;      // First-Week Contrast override on derived week one
    cappedMaxDifficulty: 1|2|3|4|5;    // the Starting Difficulty cap
  };

  reentry?: {                          // present only during a Re-entry Ramp (ADR-0015)
    rampSessionsRemaining: number;
  };

  note?: {                             // the user-visible surface (language)
    text: string;                      // weekly narrative / "what I changed and why"
    source: 'template' | 'llm';        // MUST fall back to 'template' if the LLM call fails
  };
}

// Why the AI Programmer re-programmed — drives which policy levers move.
interface ReprogramTrigger {           // ADR-0017 / CONTEXT
  kind: 'weekly_boundary' | 'return' | 'physical_stall' | 'disengagement';
  detectedAt: Date;
  // When 'physical_stall' AND 'disengagement' both apply, Disengagement wins (Trigger Precedence).
}
```

### 2.4 The Deterministic Engine

The engine is pure code — instant, offline, deterministic. It runs the same whether or not the AI Programmer has ever executed, because it reads a **Session Policy** that is always valid (a sensible default exists from day one). The AI Programmer changes the *policy*, never this pipeline, and is never on this path. Full pipeline:

```
Input: { requestedMinutes, userProfile, recentLogs, phase, sessionPolicy }

Step 0 — Cold-start override (ADR-0019), only while coldStart.active:
  If sessionPolicy.coldStartContract.forceContrastSpread:
    derive today's pillar/pattern from onboarding inputs BUT force a vivid
    day-to-day spread across pillars (First-Week Contrast), overriding the
    theme-sameness that `why`/sitsLong alone would produce.
  Cap difficulty at coldStartContract.cappedMaxDifficulty (Starting Difficulty).

Step 1 — Session shape:
  [NEEDS DECISION] The v5 thresholds below were pinned to the old 5–10/15/20–30
  framing. The range is now 5–60 (ADR-0016) and primal is a full pillar. The
  single-focus-vs-blend model must be re-decided for the new range — e.g. does a
  60-min session blend all THREE pillars? Placeholder mapping, NOT yet locked:
    5–10 min  → SINGLE_FOCUS: pick ONE pillar (the stalest, see Step 2)
    15 min    → BLEND (light): warm-up + one real block + a small second block
    20–45 min → BLEND (full): warm-up + strength block + mobility block + cooldown
    60 min    → BLEND (extended): all three pillars + warm-up + cooldown  (UNVERIFIED)

Step 2 — Pillar balance (staleness × policy):
  a. From recentLogs, compute days-since-worked per pillar (strength, mobility, primal)
  b. Scale staleness by sessionPolicy.pillarWeighting (the AI Programmer's lever)
     and by profile.why.openingBias (the single allowed programming effect of `why`)
  c. For SINGLE_FOCUS: choose the stalest weighted pillar (mobility bias retained if
     profile.sitsLong AND short session AND not strongly stale on strength)
  d. For BLEND: include multiple; weight time by relative weighted staleness
  e. RETURN OVERRIDE (ADR-0015): if this is a Return, discipline wins — serve an easy,
     winnable session regardless of staleness/optimization; readjustment waits for the
     Re-entry Ramp (Step 6).

Step 3 — Movement-pattern focus within a pillar:
  a. Rank patterns by staleness (push / squat / hinge / core / mobility groups)
  b. Never repeat yesterday's primary pattern unless requested

Step 4 — Filter exercise pool:
  a. Start from the ~30–40 library
  b. REMOVE exercises whose phase == 'strength' if user.phase == 'discipline'
  c. REMOVE exercises flagged for the user's injuries
  d. REMOVE difficulty above level (beginner 1–2, intermediate 1–3, advanced 1–5)
  e. REMOVE exercises frequently skipped (>3)
  f. MVP: all exercises are bodyweight (equipment == []) by the Zero-Equipment Floor

Step 5 — Select per pattern via progression chain:
  a. Find the user's current chain position from logged performance
  b. Select that exercise; if advancementCriteria met, offer the next in chain
  c. Avoid exercises used in the last 3 sessions (variety / anti-boredom)

Step 6 — Adaptive Overload (rep/set targets):
  a. Pull the user's logged capacity for the selected exercise
  b. Prescribe reps/sets at or just above demonstrated capacity (progressive),
     scaled by sessionPolicy.progressionRate
  c. Apply the Asymmetric Ramp (ADR-0018): a recent 'too_hard'/skip pulls difficulty
     DOWN immediately; 'too_easy' nudges UP only gradually
  d. If in a Re-entry Ramp (ADR-0015): hold difficulty below normal and walk it back
     up over reentry.rampSessionsRemaining sessions
  e. NEVER a fixed heroic number (e.g. "100 squats"); always capacity-relative

Step 7 — Assemble + fit timing:
  a. Always open with a Warm-up (in a short mobility-led session the opening
     flow doubles as warm-up + training)
  b. Build blocks per Step 1's shape
  c. totalTime = Σ(sets x estTimePerSet) + rests + transitions
  d. Trim or extend to fit requestedMinutes (± ~1 min)
  e. Cooldown stretch for sessions > 10 min

Output: Workout ready to play. Latency target < 100ms.
```

### 2.5 Phase Evaluation (Earned Progression)

A `PhaseEvaluator` (deterministic) decides the user's phase. A user is in the **Strength Phase** only when **both** hold:

1. **Consistency:** Consistency Score sustained above a threshold over a rolling window (e.g. ≥80% over ~8 recent weeks).
2. **Competence:** the user has advanced through the foundational progression chains (e.g. cleared the entry tiers of push, squat, hinge, core).

Because consistent attendance plus Adaptive Overload produces the competence, the two converge naturally over ~6–12 months. The transition is a gradual ramp (difficulty and available exercises expand), not a one-time event. A perfectly consistent user who never advances her movements stays in the Discipline Phase, with the engine actively nudging her up the chains — honest stewardship, never framed as failure (ADR-0006).

### 2.6 Consistency Score (Forgiving)

```
weeklyAdherence(week) = min(1, workoutsCompleted(week) / weeklyGoal)
score = weightedRollingAverage(weeklyAdherence, recentWeeks) * 100
        // recent weeks weighted more; a single miss dents, never zeroes

- A 5-minute session counts as a full "show up."
- A Return after a gap protects the Score and is celebrated, never penalized (ADR-0015).
- longestChain is tracked and surfaced as an earned badge of pride.
- A broken chain reduces the chain counter but only dents the score.
- Copy is identity-framed ("you're someone who moves"), never loss-framed.
```

### 2.7 The AI Programmer (ADR-0014, ADR-0015, ADR-0017)

The AI Programmer is the wedge. It is an asynchronous, off-device process that reviews a user's logged history and rewrites the **Session Policy** the Deterministic Engine runs on. It **never generates or delivers a session** and is **never on the critical path** of starting one.

**What it decides.** Its scoped job is (1) **plateau diagnosis** — distinguishing a **Physical Stall** (cleared to advance but hasn't → *more* challenge) from **Disengagement** (fading commitment → *less* friction), and (2) **cross-signal re-weighting** of the policy in response. When both triggers fire, **Disengagement wins** (Trigger Precedence): the app never adds challenge to someone showing signs of leaving. This is discipline-overrides-optimization (ADR-0015) applied at the trigger level.

**When it runs (Re-program).** Triggered by the client on app open when one is due — by **Weekly Boundary** (aligned to the Consistency Score week), **Return**, **Physical Stall**, or **Disengagement**. **Never** by a server-side clock. The user never waits: the app renders immediately from the existing policy, and a freshly computed policy applies on the *next* open (new programming lands one session later).

**Its user-visible surface.** A natural-language **note** — "what I changed and why." This is the honest bridge to v5.0's "AI does language" instinct: the language is real because it describes real policy changes the engine will actually execute. Language may never invoke a `why` or claim a change the sessions don't reflect (no hollow callbacks).

**MVP posture (ADR-0017).** The MVP *starts at (C)*: the re-weighting runs as **deterministic heuristics on-device, zero LLM calls**, and the note is templated. It migrates to *(B)*: the LLM (via the thin proxy) makes the diagnosis and the note richer. The single LLM call pulled into the MVP is the day-one **Variety Language** (§2.8), always deterministically backed. **This supersedes v5.0's ADR-0007** (AI as language-only, never touching workouts): AI now shapes workouts — indirectly, through policy, never by generation.

### 2.8 Cold Start (ADR-0018, ADR-0019)

Every adaptive mechanism above assumes history; a new user has none. Cold start governs roughly the first several sessions until the engine can drive itself.

**Difficulty (ADR-0018).** Seeded from self-reported `fitnessLevel`, but served at the **gentle end of a capped band** — a mis-report can't produce a badly over-hard first session. Real performance then corrects via the **Asymmetric Ramp** (down eagerly, up gradually). Rationale: too-easy self-corrects because the user returns; too-hard doesn't, because they don't.

**Variety (ADR-0019).** Week one is **derived** from onboarding inputs (`why`, `fitnessLevel`, `sitsLong`) but governed by a mandatory **First-Week Contrast** rule that forces a vivid day-to-day spread across pillars — because those inputs alone bias toward a single theme (a desk-worker → all mobility), which would read as repetitive and undercut the wedge. The contrast is named in language from session one via the **Variety Language** LLM slice, always backed by a deterministic template so the app never depends on the network — even on day one.

**Handoff.** `[NEEDS DECISION]` Cold-start rules (First-Week Contrast, difficulty cap) retire once there's enough logged history to drive staleness rotation and Adaptive Overload unassisted — provisionally the first **5–7 sessions**, exact number to be tuned in testing. Until locked, `coldStart.active` flips on this provisional threshold.

---

## 3. Feature Specifications (MVP)

### 3.1 Onboarding (detailed flow deferred to Phase 2)

MVP onboarding is intentionally minimal: name + basic profile, fitness level (seeds capped Starting Difficulty), the user's **why** (free-text reason — the emotional core the AI Programmer's language draws on), "do you sit 6+ hours most days?", optional injuries, and **one** duration question that seeds the Default Duration ("how long do you usually have?"). After onboarding the app opens straight to a **Ready Screen** with the first session already generated — no picker to clear. **Recommendation carried into Phase 2 design:** make the very first session a short Movement Practice reset, so a stiff user feels relief in minute one. Goal: first workout within 5 minutes of opening the app. `[NEEDS DECISION: primaryGoal vs why — see §2.3]`

### 3.2 Ready Screen (ADR-0016)

The app opens to a **complete session already generated** at the user's Default Duration — one tap to start, never a question to answer first. On open it also checks whether a **Re-program** is due and, if so, triggers it in the background (rendering from the existing policy meanwhile; the new policy applies next open). Surfaces: today's session preview with its **Variety Language** ("Today's a mobility day — yesterday was strength"); the duration shown as a **non-blocking, one-tap-adjustable chip** (5/10/15/20/30/45/60), loud enough to override but never a gate; the Consistency Score (forgiving, identity-framed); and the AI Programmer's note when present. No XP in the MVP.

The distinction that defines the wedge: the screen shows **"Today: 15 min — Start"**, never **"How long do you have today?"** with Start disabled until answered.

### 3.3 Active Session Screen

Large touch targets, auto-playing exercise demo (Lottie), set tracking, rest timer with haptics, swap (deterministic substitution within pillar/pattern/time budget). Resumes if the app is backgrounded. The running session clock is deliberately **not** shown while the session runs (revised by US-O03; a total ticking up in the corner turns a five-minute session into something to get through) - the total is revealed once, on the post-session screen. What a timed (hold) exercise gets instead is its own manual-start countdown that fires the haptic/audio cue and records the set at zero, counted one side at a time; rep-based exercises stay timer-free.

### 3.4 Post-Session Screen

Completion celebration, session summary (template-based in MVP), muscle/mobility coverage, rating + perceived difficulty (feeds Adaptive Overload), Consistency Score update. Difficulty feedback adjusts the next session within one cycle.

### 3.5 Progress Tab

Calendar of sessions, Consistency Score over time, pillar-balance view (strength vs mobility), progression-chain position, and personal bests. Deeper analytics sit behind the paywall.

---

## 4. Monetization

### 4.1 Free Tier

- **Unlimited workouts, forever** — the core loop is never gated.
- Full ~30–40 movement library.
- Consistency Score + weekly goal.
- Basic session history.

### 4.2 Premium (~$7.99/month or ~$59.99/year, 14-day trial)

The **depth** layer:
- Full analytics and progress intelligence (trends, pillar-balance detail, charts).
- The **Strength Phase** and advanced programming.
- Optional equipment variants (kettlebell / dumbbell), when introduced.
- AI coaching, summaries, and weekly reports (later phase).

**Principle:** charge the user who's hooked and wants more *out of* the habit; never charge the user still building it (ADR-0013).

---

## 5. Exercise Library (~30–40 Movements)

### 5.1 Structure

Sized to carry both co-primary pillars while staying shippable solo. Roughly:

- **Strength — push (horizontal & vertical):** wall / incline / knee / standard / wide / diamond push-ups; pike push-up; floor dips. (~8)
- **Strength — squat:** bodyweight squat, sumo squat, reverse lunge, split squat, wall sit. (~5)
- **Strength — hinge:** glute bridge, single-leg bridge, good morning, single-leg RDL. (~4)
- **Strength — core:** forearm plank, dead bug, bird dog, bicycle crunch, lying leg raise, side plank, hollow hold. (~7)
- **Strength — pull (no equipment, postural):** prone Y-T-W, superman hold, reverse snow angel. (~3)
- **Movement Practice (mobility):** deep squat hold, 90/90 hip stretch, cat-cow, thoracic rotations, world's greatest stretch, pigeon, frog, down dog, kneeling hip-flexor stretch, wall chest opener, forward fold, child's pose. (~12)
- **Primal:** bear crawl, crab walk, ground-to-standing. (~3)

Each movement carries a regression and a progression so Adaptive Overload has room. Strength-Phase-only skills (e.g. L-sit, pistol squat, one-arm push-up) are tagged `phase: 'strength'` and stay hidden in the Discipline Phase.

### 5.2 Animations

Lottie demos for the launch movements only (mobility holds are mostly static — cheap to animate). **Sourcing approach deferred to Phase 2.**

---

## 6. Development Phases

### Phase 1 — MVP (the discipline loop)

Ships: deterministic on-device engine reading a **Session Policy**; **AI Programmer at option (C)** (deterministic on-device re-weighting — plateau/disengagement diagnosis, pillar/duration tuning — zero LLM calls); the **day-one Variety Language LLM slice** through the thin stateless proxy, always deterministically backed; ~30–40 movement library + animations; session model (warm-up always; single-focus/blend `[NEEDS DECISION]`); Adaptive Overload with Asymmetric Ramp; cold-start seeding + First-Week Contrast; Return / Re-entry Ramp; PhaseEvaluator (Discipline-Phase only at launch); forgiving Consistency Score; **Ready Screen** / active / post-session / progress screens; swap; CoreData + CloudKit; StoreKit 2 (free unlimited core, premium depth); Sign in with Apple; HealthKit write; the **thin stateless proxy** (key holder for the one LLM slice).

Explicitly **not** in MVP: the full **(B)** LLM Programmer (richer diagnosis + narrative notes — MVP ships (C) + the single Variety slice); server-side scheduler or user-data mirror; XP/levels/badges; social features; the full Strength-Phase catalog; equipment variants.

Cost: near-$0 AI at launch (one short LLM call per new-user session for Variety Language; deterministic elsewhere); the proxy is nearly free at rest; Apple Developer account ($99/yr). Minimal hosting for the proxy only.

### Phase 2 — Depth, Earned Strength, and the Deferred Details

The deferred items land here, plus the AI Programmer's full (B) layer:
- Detailed onboarding flow (mobility-reset first session).
- Animation sourcing and full demo set.
- XP / levels / badges (kept off the core loop; optional polish, no loss-aversion).
- The full Strength-Phase catalog + optional equipment variants.
- **Expand the AI Programmer from (C) to (B)** — LLM-driven plateau diagnosis and richer narrative notes (summaries, weekly reports) through the proxy that *already exists* from Phase 1. Not a new backend, an expanded use of it.
- Premium analytics depth.

### Phase 3+ — Growth

Android, social/leaderboards/challenges, widgets, Live Activities, advanced AI, Apple Watch. All deferred and gated on the core loop proving retention first.

---

## 7. Key Metrics

**North Star: Weekly Active Exercisers** — users completing ≥1 session/week. (This is "discipline," measured.)

| Metric | Month 3 | Month 6 |
|--------|---------|---------|
| Onboarding → 1st session | 60% | 70% |
| Day 7 retention | 20% | 25% |
| Day 30 retention | 10% | 15% |
| Weekly Active Exercisers | 35% of installs | 40% |
| Free → Paid | 4% | 7% |
| Session completion (started → finished) | ≥80% | ≥80% |
| Generation latency (on-device) | <100ms | <100ms |

---

## 8. Non-Functional Requirements

- **Performance:** launch → home < 2s; generation < 100ms; fully offline core loop; app size < 50MB.
- **Privacy:** HealthKit stays on-device; data export + deletion; no data sale.
- **Accessibility:** VoiceOver, Dynamic Type, ≥44pt (prefer 60pt) targets, Reduce Motion, haptics as audio alternative.
- **Safety:** strict difficulty gating by phase/level; injury exclusions; progression-chain gating prevents over-reaching; health disclaimer; no medical claims.

---

## 9. Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Repetitive sessions | Variety scoring + "no repeats in last 3" + ~30–40 movements recombined + Adaptive Overload |
| Unsafe prescription | Phase/level difficulty gating; injury exclusion; capacity-relative reps (never fixed heroic numbers) |
| Guilt-driven churn | Forgiving Consistency Score; tiny minimum win; identity framing; no reset-to-zero streak |
| Solo over-scope | ~30–40 library (not 100); backend limited to a stateless proxy (no scheduler/DB); MVP AI is deterministic (C) with one LLM slice; details deferred to Phase 2 |
| Weak differentiation | Mobility as co-primary, same-day-relief hook — an open lane vs strength-led competitors |
| App Store rejection | Follow HIG; clear subscription disclosure; no medical claims |
| LLM fails on day one (new dependency) | Variety Language always backed by a deterministic template; app never blocks on the call; render from existing/default policy (ADR-0017/0019) |
| Hollow callback (language promises what sessions don't deliver) | Language may only name a `why` or contrast the engine actually produced; `why` carries exactly one real programming effect (ADR-0019) |
| AI adds challenge to someone quitting | Trigger Precedence: Disengagement suppresses Physical Stall; discipline overrides optimization (ADR-0015) |
| User feels "behind" after a gap | Return served easy/winnable, Score protected; readjustment deferred to Re-entry Ramp (ADR-0015) |
| "Novelty vs progression" tension | Variety varies the *experience*; progression chains + Adaptive Overload repeat the *stimulus* enough to drive real gains |
| Scope creep back into a real backend | Stateless proxy only; no scheduler/data mirror; re-program is client-triggered on open (ADR-0017) |

---

*End of PRD v6.0 — reconciled to ADRs 0001–0019. Three decisions remain open and are marked `[NEEDS DECISION]` inline: the single-focus/blend model at the 5–60 range (§2.4), primaryGoal vs why (§2.3), and the cold-start handoff threshold (§2.8).*
