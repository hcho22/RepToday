# Product Requirements Document: FitSnack — Discipline-First Movement App

**Version:** 5.0
**Last Updated:** June 25, 2026
**Platform:** iOS (SwiftUI, iOS 17+)
**Status:** Pre-Development

**What changed in v5.0 (reconciles the document to ADRs 0001–0013):**
- Repositioned from "build muscle + move better" to **discipline-first**: the product builds the habit of moving; strength is *earned* over time, never the launch headline (ADR-0003).
- Introduced the two-phase user journey — **Discipline Phase → Strength Phase** — crossed by *earned* consistency-plus-competence, per user, not a product roadmap (ADR-0004, ADR-0006).
- Elevated **Movement Practice (mobility)** from "third pillar" to a **co-primary pillar** and the core differentiator (ADR-0008).
- Cut the launch library from 100 to **~30–40 movements** (ADR-0008); resolved the prior 100-vs-142 exercise-count contradiction by deletion.
- Defined the **session model**: every session warms up; short sessions (5–10 min) are **single-focus**, 15+ min sessions **blend** both pillars (ADR-0010, ADR-0011).
- Locked the engine as **deterministic and on-device**; LLM/AI is reserved for *language only* in a later phase and never generates workouts (ADR-0007).
- Replaced the fragile streak with a **forgiving rolling Consistency Score**; the unbroken chain is earned celebration, never a threat (ADR-0012).
- Established the **Zero-Equipment Floor**: every workout completable with a floor and a wall, permanently; optional equipment is Strength-Phase-only and deferred (ADR-0005).
- Removed the custom backend from the MVP — **Apple-native stack only** (CloudKit, StoreKit 2, Sign in with Apple, HealthKit); server deferred to the LLM phase (ADR-0009).
- Changed monetization: **free unlimited workouts**, paywall on *depth*, not on the core loop (ADR-0013).
- Deferred to Phase 2: detailed onboarding flow, animation sourcing, XP/levels/badges, the full Strength-Phase catalog and equipment variants, and Android/social/go-to-market.

---

## 1. Executive Summary

FitSnack is an iOS-first movement app for busy, desk-bound adults who can give exercise 5–30 minutes a day. It exists to build one thing: the **discipline** of showing up. Open the app, say how many minutes you have, and it generates a complete zero-equipment session — blending bodyweight strength and mobility — using a deterministic on-device engine. No browsing, no choosing, no thinking.

The product is built on a two-phase journey. New users live in the **Discipline Phase**, where the only goal is consistency and sessions stay short and simple. As a user earns it — by sustaining the habit *and* progressing their movements — the app matures into the **Strength Phase**, where training shifts toward real strength and capability. Strength is the destination, not the entry promise.

### 1.1 Core Value Proposition

- **Build the discipline to move well and feel better — in minutes.** The honest promise at this dose.
- **Mobility is co-primary, not a warm-up.** Movement Practice (deep squat holds, hip work, thoracic rotations, primal movement) targets the stiffness a desk worker feels *today* and delivers same-day relief — the differentiator no strength-led competitor leads with.
- **Zero-decision sessions.** The engine builds a complete, personalized session the moment you give it your minutes — instant, offline, free.
- **Zero equipment, permanently.** Every session works with a floor and a wall. Optional minimal equipment arrives only in the Strength Phase, and is never required.
- **Earned strength.** Consistent showing-up plus built-in progression produces real strength over time; the app turns up the dial as you prove the habit.
- **Forgiving by design.** A rolling Consistency Score rewards showing up and survives a missed day, instead of punishing one slip with a reset to zero.

### 1.2 Target Users

**Primary:** Working parents aged 28–45 who sit 6+ hours/day, feel stiff and guilty about not exercising, and have abandoned 2–3 fitness apps. Their felt pain is stiffness and aches *now*, not a lack of muscle.

**Secondary:** Busy professionals aged 25–40 who travel or work unpredictable hours and cannot commit to a gym schedule.

**Psychographic:** Time- and bandwidth-poor, not motivation-poor. They want to feel they are "doing something" even on their worst day — and to not be made to feel like failures when they miss.

---

## 2. Technical Architecture

### 2.1 Tech Stack (MVP — Apple-native, no custom backend)

```
┌─────────────────────────────────────────────────────┐
│                    iOS Client                        │
│  SwiftUI · iOS 17+ · Swift 5.9+                       │
│  HealthKit · CoreData · CloudKit · StoreKit 2         │
│  Sign in with Apple · Lottie · Swift Charts           │
│                                                       │
│  Deterministic Workout Engine (on-device)             │
│  Exercise Library (bundled JSON, ~30–40 movements)    │
│  Consistency Score + Phase Evaluator (CoreData)       │
│  Adaptive Overload (logged-performance driven)        │
└───────────────────────────────────────────────────────┘

No custom server in the MVP. CloudKit handles sync + backup,
StoreKit 2 handles subscriptions, Sign in with Apple handles
identity, HealthKit stays on-device.

Later phase (when LLM features arrive):
┌─────────────────────────────────────────────────────┐
│  Minimal backend to hold the model API key and proxy  │
│  Claude calls for summaries / weekly narratives only. │
│  AI never generates or adapts a workout.              │
└───────────────────────────────────────────────────────┘
```

**Rationale:** the engine is deterministic and runs on-device, so there is nothing to compute server-side at MVP. A backend is deferred to the first genuine need for one — holding an API key for the language features (ADR-0007, ADR-0009).

### 2.2 Core Domain Concepts

These are the canonical terms (full definitions in `CONTEXT.md`):

- **Micro-Workout** — a complete 5–30 min session generated to fit the user's available time.
- **Discipline Phase / Strength Phase** — the two stages of a user's journey.
- **Earned Progression** — advancing between phases by demonstrated consistency, not self-selection.
- **Adaptive Overload** — week-to-week variation and increasing demand keyed to logged performance.
- **Movement Practice** — the co-primary mobility/longevity pillar.
- **Warm-up** — the brief preparatory mobility that opens every session (distinct from Movement Practice).
- **Single-Focus Session** — a short session that does one pillar well rather than blending.
- **Zero-Equipment Floor** — the permanent guarantee that every workout needs only a floor and a wall.
- **Consistency Score** — the forgiving, rolling measure of showing up.

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
    fitnessLevel: 'beginner' | 'intermediate' | 'advanced';
    primaryGoal: 'stay_active' | 'build_strength' | 'increase_energy' | 'reduce_stress' | 'lose_weight';
    sitsLong: boolean;                 // "sit 6+ hours most days?" — biases toward Movement Practice
    injuries: string[];                // tags: "lower_back", "knees", ...
    typicalAvailableMinutes: number;
  };

  phase: Phase;                        // computed by PhaseEvaluator; never user-selected

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

interface WorkoutLog {                 // the signal Adaptive Overload reads
  workoutId: string;
  completedAt: Date;
  durationMinutes: number;
  shape: 'single_focus' | 'blend';
  focusPillar?: Pillar;                // for single-focus sessions
  perceivedDifficulty?: 'too_easy' | 'just_right' | 'too_hard';
  exercises: {
    exerciseId: string;
    pillar: Pillar;
    movementPattern: MovementPattern;
    completedSets: { reps?: number; durationSeconds?: number }[];
    skipped: boolean;
  }[];
}
```

### 2.4 The Deterministic Engine

The MVP engine is pure code — no LLM, no network, instant, offline. Full pipeline:

```
Input: { requestedMinutes, userProfile, recentLogs, phase }

Step 1 — Session shape (ADR-0011):
  5–10 min  → SINGLE_FOCUS: pick ONE pillar (the stalest, see Step 2)
  15 min    → BLEND (light): warm-up + one real block + a small second block
  20–30 min → BLEND (full): warm-up + strength block + mobility block + cooldown

Step 2 — Pillar balance (staleness):
  a. From recentLogs, compute days-since-worked per pillar (strength, mobility)
  b. For SINGLE_FOCUS: choose the stalest pillar (biased toward mobility if
     profile.sitsLong AND requestedMinutes <= 10 AND not strongly stale on strength)
  c. For BLEND: include both; weight time by relative staleness

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
  b. Prescribe reps/sets at or just above demonstrated capacity (progressive)
  c. NEVER a fixed heroic number (e.g. "100 squats"); always capacity-relative

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
- longestChain is tracked and surfaced as an earned badge of pride.
- A broken chain reduces the chain counter but only dents the score.
- Copy is identity-framed ("you're someone who moves"), never loss-framed.
```

### 2.7 AI / LLM (deferred — later phase only)

When introduced, the LLM (Claude API) does **language only**: post-workout summaries, weekly narrative reports. It is never on the critical path of generating or adapting a workout. This is the first thing that requires the minimal backend (to hold the API key). Not in MVP.

---

## 3. Feature Specifications (MVP)

### 3.1 Onboarding (detailed flow deferred to Phase 2)

MVP onboarding is intentionally minimal: name + basic profile, fitness level, primary goal, "do you sit 6+ hours most days?", optional injuries, and a time selector for the first session. **Recommendation carried into Phase 2 design:** make the very first session a short Movement Practice reset, so a stiff user feels relief in minute one. Goal: first workout within 5 minutes of opening the app.

### 3.2 Home Screen

One clear action: start today's session. On open, if none generated today, auto-generate using `typicalAvailableMinutes`. Surfaces: today's session preview, a duration selector, quick-start buttons (5/10/15/20/30), the Consistency Score (forgiving, identity-framed), and a template-based insight (e.g. pillar-balance nudge). No XP in the MVP.

### 3.3 Active Session Screen

Large touch targets, auto-playing exercise demo (Lottie), set tracking, rest timer with haptics, swap (deterministic substitution within pillar/pattern/time budget). Resumes if the app is backgrounded. Elapsed time always visible.

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

Ships: deterministic on-device engine; ~30–40 movement library + animations; two-pillar session model (single-focus short / blend long, warm-up always); Adaptive Overload; PhaseEvaluator (Discipline-Phase experience only at launch, since no user has earned Strength Phase yet); forgiving Consistency Score; home / active / post-session / progress screens; swap; CoreData + CloudKit; StoreKit 2 (free unlimited core, premium depth); Sign in with Apple; HealthKit write.

Explicitly **not** in MVP: any LLM calls; custom backend; XP/levels/badges; social features; the full Strength-Phase catalog; equipment variants.

Cost: $0 for AI; Apple Developer account ($99/yr). No hosting.

### Phase 2 — Depth, Earned Strength, and the Deferred Details

The five deferred items land here, plus the first AI layer:
- Detailed onboarding flow (mobility-reset first session).
- Animation sourcing and full demo set.
- XP / levels / badges (kept off the core loop; optional polish, no loss-aversion).
- The full Strength-Phase catalog + optional equipment variants.
- LLM language features (summaries, weekly reports) + the minimal backend to support them.
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
| Solo over-scope | ~30–40 library (not 100); no backend; deterministic engine; details deferred to Phase 2 |
| Weak differentiation | Mobility as co-primary, same-day-relief hook — an open lane vs strength-led competitors |
| App Store rejection | Follow HIG; clear subscription disclosure; no medical claims |

---

*End of PRD v5.0 — reconciled to ADRs 0001–0013.*
