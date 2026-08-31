# PRD: Phase 2 - Strength Phase, AI Coach & Analytics (2026-08-25)

## Introduction / Overview

Phase 2 turns Rep Today from a discipline-building daily habit into an app that also **rewards** that habit, **coaches** it, and **shows** its progress - without breaking the founding promise ("no browsing, no choosing, no thinking") or the deterministic, on-device, offline engine.

Three surfaces, one tier structure:

- **Strength Phase (free, retention).** The earned graduation from the Discipline Phase becomes real: earning it lifts the user's difficulty cap and opens a smooth ladder of harder skill movements, made visible from day one through a phase-progress surface and a progression map. Today the phase is fully evaluated but unlocks almost nothing, and only for already-"advanced" users.
- **AI Coach (premium, monetization).** A history-aware, science-grounded coach that (A) **talks** - answers "why this?", "how do I do a pistol squat?", "I'm bored" - and (B) **tunes** the user's program by adjusting the deterministic engine's existing policy knobs. The engine still generates every session; the LLM never generates one.
- **Analytics (premium, integrated).** Not a chart tab - the evidence the coach reads and acts on, anchored on the strength journey.

This PRD is the durable record of the Phase 2 design settled with the captain on 2026-08-25. Stories are ordered **retention-first**; the AI Coach's *tuning* half sits **below an explicit cut line** and is deferred if the ~Nov 3 PMF decision date tightens.

## Background: what already exists (do not rebuild)

- **Strength Phase machinery is complete but empty.** `PhaseEvaluator` (`Services/Consistency/PhaseEvaluator.swift`) earns `.strength` on sustained consistency (score >= 80 over ~8 weeks) AND cleared entry tiers of push/squat/hinge/core. `ExercisePoolFilter.isPhaseAllowed` gates `phase == .strength` exercises behind it. But only **3** gated skills exist (`push_one_arm`, `squat_pistol`, `core_l_sit`), all difficulty 5, no hinge skill.
- **The double-gate trap.** A phase-gated skill must pass `isPhaseAllowed` AND `isWithinDifficultyCap` (`difficultyCap`: beginner 1-2, intermediate 1-3, advanced 1-5). All 3 skills are difficulty 5, so today only an "advanced" user who earns the phase sees anything. Beginners/intermediates earn it and see nothing.
- **The policy seam for the coach already exists.** `SessionPolicy` (`Models/SessionPolicy.swift`) is the single seam between the programmer and the engine; `SessionPolicy.UpdatedBy` already has a reserved `.llm` case. Live levers: `progressionRate` (clamped), `varietyWindow`. `pillarWeighting` is **inert** since US-M01. There is **no** pattern-emphasis lever today.
- **The LLM transport is deploy-ready but not deployed.** `proxy/` is a Cloudflare Worker with route-specific provider keys: Variety Language remains on Anthropic, while the premium Coach uses OpenAI `gpt-5.6-luna`; the Worker stores no request or response content. The iOS Coach call path is wired but inert while its endpoint configuration is empty. `Services/Language/` separately composes an optional LLM slice over a deterministic template (`VarietyLanguageResolver`, provider `nil` in MVP).
- **Analytics split exists.** `Services/Progress/ProgressAnalytics.swift` renders free layers (pillar balance, chain positions, personal bests) for everyone and gates `DeepAnalytics` (per-pattern balance, weekly volume, difficulty mix) behind premium at the render boundary.
- **Monetization plumbing exists.** StoreKit 2, `SubscriptionTier { free, premium }` ("premium unlocks the depth layer (full analytics, later Strength Phase / AI)"), paywall + funnel telemetry (US-T12).

## Goals

- Make the Strength Phase a real, visible, motivating reward that every user who earns it experiences - not just advanced-level users. (Retention.)
- Give the free user a day-one view of the climb toward the Strength Phase, so motivation exists long before the ~8-week summit. (Retention, readable within the PMF window.)
- Ship a premium AI coach that is worth paying for because it knows *your* history and applies exercise science to *your* situation. (Monetization.)
- Let the coach retune programming from soft signals (the user's words) without ever generating a workout, making a session harder unbidden, or removing a movement silently. (Safety-preserving personalization.)
- Preserve Rep Today's core guarantees intact: deterministic on-device engine, offline core loop, <100ms generation, on-device privacy posture. (No regressions to the founding thesis.)
- Make premium analytics change behavior by feeding the coach, not by adding charts users ignore. (Monetization quality.)

## Architectural decisions (ADR-worthy - land as ADRs alongside this PRD)

1. **The LLM may advise bounded policy, never generate a workout.** Reframes the prior "LLM is language-only" wall. The coach writes a validated, clamped `SessionPolicy` tagged `.llm`; the deterministic engine still generates every session and owns all safety. (Supersedes the strict "language only" framing; option "C - LLM generates/adapts workouts" is rejected.)
2. **The coach stays stateless and device-anchored.** No server-side per-user memory, no accounts, still pseudonymous. Each turn sends a minimal *derived* context bundle, the user's message, and a separate random Coach safety identifier used for provider abuse prevention; the proxy calls OpenAI `gpt-5.6-luna` with `store: false` and stores no content itself. The safety identifier is never `installId` or a Rep Today account value, stays stable across launches, and rotates on account deletion. Under standard OpenAI retention, prompt and response content may remain in abuse-monitoring logs for up to 30 days; deployment does not require Zero Data Retention or Modified Abuse Monitoring. Chosen over richer Rep Today server memory while disclosing the provider boundary honestly.
3. **The Strength Phase is earned, free, and lifts the difficulty cap.** Demonstrated competence (8 weeks + cleared foundations) overrides the conservative onboarding fitness-level estimate. Never paywalled - honors `PhaseEvaluator`'s "never a reward withheld" principle.

## Cut line and sequencing (retention-first)

- **Slice 1 (build first): Strength Phase.** US-SP01 .. US-SP06. No LLM, no privacy work. Cheapest, fastest, readable retention evidence.
- **Slice 2: AI Coach - talking half (A).** US-AC01 .. US-AC04. The monetization test.
- **Slice 3: Analytics + coach tuning half (B).** US-AN01 .. US-AN02 and US-AC05 .. US-AC08.
- **CUT LINE:** everything in US-AC05 .. US-AC08 (the *tuning* coach and its engine/merge-safety work) is deferred if the clock tightens. A talking coach + a visible climb already tests both PMF questions (do they stay, do they pay).

---

## User Stories

### Epic A - Strength Phase (free, retention, Slice 1)

### US-SP01: Earning the Strength Phase lifts the difficulty cap

**Description:** As a user who has earned the Strength Phase, I want harder work to become available so that graduating actually changes my sessions, even if my onboarding fitness level was conservative.

**Acceptance Criteria:**

- [x] The effective difficulty cap used by `ExercisePoolFilter` is raised for a user whose earned phase is `.strength` (demonstrated competence overrides the self-reported `FitnessLevel` estimate).
- [x] The cap change is centralized (one function, e.g. `effectiveDifficultyCap(for:phase:)`), not scattered across call sites.
- [x] A phase-gated skill of difficulty 5 becomes reachable for a Strength-Phase user regardless of their onboarding `FitnessLevel`.
- [x] Cold-start / Start Seed banding and the injury/skip/zero-equipment filters are unchanged.
- [x] Unit tests cover: discipline user cap unchanged; strength user cap lifted; boundary at exactly the phase transition. Adds a row to `docs/test-coverage.md`.
- [x] Typecheck/build and the `RepToday` unit suite pass.

**Validation Test:**

- **Setup:** A synthetic user with `FitnessLevel.intermediate` and a log history that earns `.strength` (sustained 80+ over 8 active weeks, all four foundations cleared). Library includes `push_one_arm` (difficulty 5).
- **Steps:**
  1. Evaluate the user's phase (`.strength` expected).
  2. Assemble a session and inspect the eligible pool for push.
- **Expected Result:** `push_one_arm` is eligible; the same user forced to `.discipline` never sees it.
- **Failure Indicator:** An intermediate Strength-Phase user still cannot reach any difficulty-5 skill (the double-gate still binds).

### US-SP02: Fill the cliff - author mid-tier phase-gated skills

**Description:** As a user newly in the Strength Phase, I want a smooth ladder of new skills rather than a single jump to difficulty 5, so that progression feels earned and reachable.

**Acceptance Criteria:**

- [x] Add mid-tier (`difficulty` 3-4) `phase == .strength` skill movements to `Resources/Exercises.json` for push, squat, and core, slotting between the discipline frontier and the existing difficulty-5 skills, each on the correct `progressionChainId` at the correct `progressionOrder` with valid `advancementCriteria`.
- [x] Every new movement is zero-equipment (`equipment == []`) and passes load-time validation.
- [x] Each new movement has a `docs/asset-attribution.md` row if it ships any bundled asset (else none owed). *(None owed - no bundled asset ships; all three are `animationName`-less like their neighbours.)*
- [x] Progression-chain continuity: no gap or duplicate `progressionOrder` in any touched chain; `ProgressionChainSelection` still resolves frontier tiers correctly.
- [x] Tests assert catalog validity and that a Strength-Phase user advancing a chain now steps through the new mid-tier rung before the difficulty-5 skill. Adds a `docs/test-coverage.md` row.
- [x] Build and unit suite pass.

**Validation Test:**

- **Setup:** Load the catalog; a Strength-Phase advanced user with history at the discipline frontier of push.
- **Steps:**
  1. Validate `Exercises.json` loads.
  2. Advance the push chain step by step from the discipline frontier.
- **Expected Result:** The chain surfaces a difficulty-3/4 skill before `push_one_arm`, not a direct jump from difficulty 4 to 5.
- **Failure Indicator:** Catalog fails to load, or the ladder still jumps straight to difficulty 5.

### US-SP03: Add the missing hinge skill

**Description:** As a Strength-Phase user, I want a hinge skill to exist so that all four foundations have an earned skill, not just push/squat/core.

**Acceptance Criteria:**

- [x] Add at least one `phase == .strength` hinge skill (e.g. a single-leg / advanced hinge progression) to `Resources/Exercises.json` on a valid hinge `progressionChainId`, zero-equipment, load-validated, with mid-tier and top-tier rungs consistent with US-SP02.
- [x] `PhaseEvaluator.foundationalPatterns` still resolves hinge competence correctly (no change needed, but assert it).
- [x] Test asserts a hinge skill is reachable by a Strength-Phase user. `docs/test-coverage.md` row added.
- [x] Build and unit suite pass.

**Validation Test:**

- **Setup:** Strength-Phase user; catalog loaded.
- **Steps:** Assemble sessions until a hinge lead appears; inspect eligible hinge pool.
- **Expected Result:** At least one hinge skill is eligible for the Strength-Phase user and none for a discipline user.
- **Failure Indicator:** No hinge skill exists or it is never reachable.

### US-SP04: Phase-progress surface (the visible climb)

**Description:** As a Discipline-Phase user, I want to see how close I am to earning the Strength Phase so that I stay motivated long before I reach it.

**Acceptance Criteria:**

- [x] A read-only surface computes and shows, from real logs, the two earn signals: consistency progress (e.g. "sustained 80+ for 5 of 8 weeks") and competence progress ("2 of 4 foundations cleared: push [x], squat [x], hinge [ ], core [ ]").
- [x] Values come from the exact same logic `PhaseEvaluator` uses (no re-derivation that could disagree with the actual gate).
- [x] Copy is identity-framed, never loss-framed; no gamification (no XP/badges/streak-to-break).
- [x] Surface is free (not premium-gated).
- [x] Accessibility: VoiceOver labels, Dynamic Type, Reduce Motion respected; uses `Theme` tokens.
- [x] Verify on device/simulator with the evidence-capture path (hosted-surface test or XCUITest screenshot). `docs/test-coverage.md` row added.
- [x] Build and unit suite pass.

**Validation Test:**

- **Setup:** A user with 5 sustained weeks and push+squat cleared (hinge/core not).
- **Steps:** Open the phase-progress surface.
- **Expected Result:** Shows "5 of 8 weeks" (or equivalent) and exactly 2 of 4 foundations cleared, matching what `PhaseEvaluator` would gate on.
- **Failure Indicator:** Numbers disagree with `PhaseEvaluator`, or a user who has NOT earned the phase is shown as earned (or vice versa).

### US-SP05: Progression map (the ladder), tied to the Strength Phase

**Description:** As a user, I want to see the ladder of movements I am climbing and preview what I will earn, so that the strength journey is visible - without letting me choose my workout.

**Acceptance Criteria:**

- [x] A visual per-pattern ladder (push/squat/hinge/core) shows the chain from entry tier through the Strength-Phase skill, marking the user's current frontier and what is still locked.
- [x] Locked Strength-Phase rungs are shown as "earn the Strength Phase to unlock," previewable but not selectable.
- [x] The map never lets the user pick or start a specific movement (thesis preserved: no browsing/choosing the workout).
- [x] Current position is derived from real logs via existing chain-position logic (reuse `ProgressAnalytics` chain positions; do not re-derive).
- [x] Accessibility + `Theme` tokens; verify visually on device/simulator via the evidence path. `docs/test-coverage.md` row added.
- [x] Build and unit suite pass.

**Validation Test:**

- **Setup:** User at the full-push-up tier, Discipline phase.
- **Steps:** Open the progression map, view the push ladder.
- **Expected Result:** Current position marked at full push-up; archer/one-arm shown ahead, the phase-gated skill marked locked with an "earn the Strength Phase" affordance; no start/select control on any rung.
- **Failure Indicator:** Map lets the user start a movement, misplaces current position, or shows locked skills as available.

### US-SP06: The graduation moment

**Description:** As a user who just earned the Strength Phase, I want an honest, identity-framed reveal so that the milestone lands as stewardship of a habit I built, not a gamified reward.

**Acceptance Criteria:**

- [x] On the first app open after `PhaseEvaluator` transitions the user to `.strength`, a one-time reveal is shown (persisted one-shot flag on `AppState`, in the style of `hasSeenContinuousCircuitExplainer`).
- [x] Copy is identity-framed ("you're someone who moves - here's what you've earned"), never loss-framed, no "you unlocked a reward" gamification.
- [x] The reveal explains what changes (harder work is now available; new skills on the ladder) and points to the progression map.
- [x] It never gates the session and never re-fires after being seen (survives relaunch).
- [x] Accessibility + `Theme`; overlay-layer presentation (not `.sheet`) so transitions still under Reduce Motion. Verify via evidence path. `docs/test-coverage.md` row added.
- [x] Build and unit suite pass.

**Validation Test:**

- **Setup:** A user whose logs just crossed the earn threshold; one-shot flag unset.
- **Steps:** Launch the app; dismiss the reveal; relaunch.
- **Expected Result:** Reveal shows once with identity-framed copy, points to the map, never re-appears after dismissal or relaunch.
- **Failure Indicator:** Reveal re-fires, uses loss-framing, blocks the session, or never shows.

### Epic B - AI Coach (premium, monetization)

### US-AC01: Stateless coach data boundary (Slice 2)

**Description:** As a privacy-conscious user, I want Rep Today not to persist my coach content or send my Rep Today identity, while using a disclosed pseudonym for provider abuse prevention, so that I can understand the coach's deliberate break from the on-device privacy posture.

**Acceptance Criteria:**

- [x] Define a **derived context bundle**: a small, non-identifying summary (current chain positions, recent movement patterns, consistency trend, current phase, requested minutes) - NOT raw `WorkoutLog` history, NOT the Keychain/IDFA/Apple ID.
- [x] Expand `proxy/` to accept a coach request (context bundle + user message + constrained safety pseudonym), call OpenAI `gpt-5.6-luna` through the Responses API with `store: false` and `safety_identifier`, return the response, and **store nothing in the Rep Today proxy** (no logging of request/response bodies); enforce a bounded timeout and body size cap as the existing proxy does. Standard OpenAI abuse-monitoring retention of up to 30 days remains and must be disclosed.
- [x] No accounts introduced; requests remain pseudonymous. The safety identifier is a separately generated random `coach-<UUIDv4>`, never raw `installId` or an identity/account field, persists across launches, and rotates when the user deletes their account.
- [x] Conversation memory (if any) lives on-device only; the server is stateless per request.
- [x] Proxy tests cover: valid request returns a response; oversized/invalid request rejected; nothing is persisted. Typecheck (`npm run typecheck`) and `npm test` pass for the sink/proxy toolchain.
- [x] iOS-side client for the coach transport is fire-and-forget-safe and bounded; the core loop never waits on it.

**Validation Test:**

- **Setup:** Local/dev proxy deployment; a crafted context bundle + message.
- **Steps:**
  1. Send a coach request.
  2. Inspect the proxy for any stored request/response.
  3. Send an oversized body.
- **Expected Result:** An OpenAI `gpt-5.6-luna` answer returns with the dedicated pseudonym carried as `safety_identifier`; the Rep Today proxy stores no request/response content; standard OpenAI retention is disclosed; the oversized body is rejected before processing.
- **Failure Indicator:** Any Rep Today proxy persistence of user content, an undisclosed provider-retention promise, an unbounded call, a raw installation/account identity on the wire, or a safety identifier that does not rotate on account deletion.

### US-AC02: The talking coach (A) - history-aware, science-grounded

**Description:** As a premium user, I want to ask the coach questions and get answers grounded in my real history and exercise science, so that I understand and stay motivated.

**Acceptance Criteria:**

- [x] A chat surface where the user can ask free-text questions; the coach answers using the derived context bundle + the message via US-AC01's transport.
- [x] The coach answers the target intents: "why this workout?", "how do I do <movement>?", "is <movement> safe with <complaint>?" (guidance + route to injury flag, see US-AC08), "I'm bored" (explain variety + offer, see US-AC07 when built).
- [x] The coach **never** returns or implies a generated/edited workout in this story (talking only). It may explain the engine's deterministic choices.
- [x] Graceful failure: on timeout/offline/error the surface degrades to a clear non-blocking state; the core loop is unaffected.
- [x] Copy respects identity-framing and the app's voice.
- [x] Accessibility + `Theme`; verify on device/simulator. `docs/test-coverage.md` row added. Build and suites pass.

**Validation Test:**

- **Setup:** Premium user with real history; coach transport live.
- **Steps:** Ask "why did I get squats today?" and "how do I do a pistol squat?"
- **Expected Result:** Answers reference the user's actual context (e.g. stalest-pattern reasoning) and give correct, safe form guidance; no workout is generated or altered.
- **Failure Indicator:** Generic non-personalized answers, a fabricated workout, or the surface blocking the core loop on failure.

### US-AC03: Premium gating for the coach

**Description:** As the business, I want the coach gated behind premium so that it drives subscriptions, while the free core loop is never gated.

**Acceptance Criteria:**

- [x] The coach surface is reachable only for `SubscriptionTier.premium`; free users see an upsell entry point (reuse the paywall + `paywall_shown` entry-point pattern from US-T12).
- [x] The free core loop (generate, play, log, consistency, phase, phase-progress, progression map) is unchanged and never gated.
- [x] Entitlement checks reuse existing StoreKit 2 plumbing; no new billing path.
- [x] Tests cover: free user blocked with upsell; premium user allowed. `docs/test-coverage.md` row.
- [x] Build and suites pass.

**Validation Test:**

- **Setup:** One free user, one premium user.
- **Steps:** Each opens the coach entry point.
- **Expected Result:** Free user sees the paywall/upsell; premium user reaches the coach.
- **Failure Indicator:** Free user reaches the coach, or a core-loop screen becomes gated.

### US-AC04: Consent and disclosure for coach data

**Description:** As a user, I want a plain, upfront disclosure that my coach content and a separate abuse-prevention pseudonym are sent to OpenAI, that Rep Today's proxy stores none of the content, and that OpenAI may retain prompts and replies in abuse-monitoring logs for up to 30 days, so that I can consent knowingly.

**Acceptance Criteria:**

- [x] Before first use of the coach, a plain-language disclosure states that messages + a summary of training context are sent to OpenAI to answer, the Rep Today proxy stores no content, OpenAI may retain prompt and response content in abuse-monitoring logs for up to 30 days under standard retention, and a random abuse-prevention Coach code is sent instead of any installation/account identity and rotates on account deletion.
- [x] The disclosure is honest about the one break in the on-device posture (content leaves the device in the moment of the call) and is not buried in fine print.
- [x] A Settings entry documents the same, consistent with the existing Privacy section pattern (`SettingsView`).
- [x] The disclosure is separate from, and does not weaken, the existing anonymous product-telemetry opt-out.
- [x] Accessibility + `Theme`; verify on device/simulator. `docs/test-coverage.md` row.
- [x] Build and suites pass.

**Validation Test:**

- **Setup:** Premium user opening the coach for the first time.
- **Steps:** Open the coach; read the disclosure; check Settings.
- **Expected Result:** Clear disclosure shown before first use; Settings mirrors it; declining does not send anything.
- **Failure Indicator:** No disclosure, misleading wording, or a message sent before consent.

---

#### === CUT LINE: US-AC05 .. US-AC08 (and Analytics US-AN02 narration) defer if the PMF clock tightens ===

---

### US-AC05: New pattern-emphasis policy lever (engine)

**Description:** As a developer, I need a bounded pattern-emphasis lever on `SessionPolicy` so the coach can bias toward/away from a movement pattern without breaking session structure.

**Acceptance Criteria:**

- [x] Add a `patternEmphasis` lever to `SessionPolicy` (per-`MovementPattern` bias), decoding to neutral for existing persisted policies (round-trip safe, like the Start Seed additive fields).
- [x] The lever is a **preference** that reorders/weights pattern selection in the engine (Step 3 stalest-first ordering), **never a filter**: it can never starve a pool, remove a movement, change a block's structure/uniform round count, or reintroduce a mobility middle block. Shaped like the existing `sitsLong` bias.
- [x] Neutral value reproduces current behavior exactly.
- [x] Deterministic + `asOf`-pure; clamped to a bounded range.
- [x] Tests: neutral is a no-op; emphasis reorders but never starves/filters; structure invariants hold across all lengths/levels. `docs/test-coverage.md` row.
- [x] Build and suites pass.

**Validation Test:**

- **Setup:** A user policy with push emphasis set high, squat low; another neutral.
- **Steps:** Assemble many sessions under each policy across lengths.
- **Expected Result:** Emphasized policy leads with push more often; no session is ever starved, made structurally uneven, or given a mobility middle block; neutral matches pre-change output byte-for-byte.
- **Failure Indicator:** A starved pool, an uneven block, a filtered-out pattern, or neutral drifting from baseline.

### US-AC06: Asymmetric pace easing (coach can ease down, only the engine advances)

**Description:** As a tired user, I want the coach to be able to ease my pace, but never to crank difficulty up on request, so that advancement stays earned and safe.

**Acceptance Criteria:**

- [x] The coach may lower `progressionRate` (within the existing clamp) as a protective move; it may **not** raise it above the engine-earned value.
- [x] Upward pace remains owned solely by the deterministic engine (Adaptive Overload / Asymmetric Ramp).
- [x] The constraint is enforced structurally (a coach-sourced policy write cannot increase pace), not by convention.
- [x] Tests: coach ease-down applies; coach attempt to raise pace is rejected/clamped to no-increase. `docs/test-coverage.md` row.
- [x] Build and suites pass.

**Validation Test:**

- **Setup:** A policy at a given `progressionRate`.
- **Steps:** Apply a coach ease-down; then apply a coach attempt to increase pace.
- **Expected Result:** Ease-down takes effect; the increase attempt does not raise pace beyond the engine-earned value.
- **Failure Indicator:** A coach write increases difficulty pace.

### US-AC07: Coach tunes programming (B) - bounded policy write with two-writer safety

**Description:** As a premium user, I want to tell the coach "focus my push" or "I'm bored of squats" and have my program adjust, so that finetuning is real - without the coach ever overriding a safety back-off.

**Acceptance Criteria:**

- [x] The coach converts eligible requests into a bounded `SessionPolicy` write tagged `updatedBy: .llm`, touching **only** preference levers: `varietyWindow`, `patternEmphasis` (US-AC05), and downward `progressionRate` (US-AC06). It never touches safety filters (injuries, difficulty cap, phase gate, zero-equipment).
- [x] Every coach-written policy is validated and clamped to the engine's rails before it is accepted; an out-of-range proposal is clamped or rejected, never applied raw.
- [x] **Two-writer safety:** the deterministic Programmer's safety moves (plateau de-load, Re-entry Ramp, cold-start) remain sovereign. Because the coach touches disjoint or only-downward levers, a safety move is never clobbered by a newer coach write; define and test the merge/precedence rule explicitly (safety > preference).
- [x] Changes are surfaced honestly in the `SessionPolicy.Note` ("you asked to focus push - more push this week"), reusing the "note may only name a real change" contract, and are reversible.
- [x] The change applies on the next session open, never mid-session.
- [x] Tests: preference write applies + is noted; safety de-load is never overridden by a later coach write; clamp holds on an out-of-range proposal. `docs/test-coverage.md` row.
- [x] Build and suites pass.

**Validation Test:**

- **Setup:** A user; coach available; a plateau condition primed for the deterministic Programmer.
- **Steps:**
  1. Coach: "focus my push for a while." Observe next sessions + note.
  2. Trigger a deterministic plateau de-load, then issue another coach preference write.
- **Expected Result:** Push emphasis increases and is named in the note; the de-load is preserved (coach write does not un-do it); no out-of-range value is ever applied.
- **Failure Indicator:** A coach write overrides a safety de-load, removes a movement, makes a session harder, or applies an unclamped value.

### US-AC08: Safety-filter routing (injury flag - never silent)

**Description:** As a user who tells the coach "my knee's cranky," I want to be routed to explicitly set an injury flag rather than have the coach silently change what I'm shown, so that safety filters stay under my explicit control.

**Acceptance Criteria:**

- [x] On a health/injury signal, the coach proposes and **routes** the user to the real injury control ("sounds like your knee's bothering you - want to flag it?"); it never sets an injury/safety filter itself. *(`CoachInjurySignalMapper` returns a `CoachInjuryRoutingProposal` that names an `InjuryOption` and carries nothing that could write; `CoachViewModel` surfaces it as an offer with accept/decline and hands back only a destination.)*
- [x] Setting the injury flag happens through an explicit, confirmed, reversible user action (the existing injuries seam on `User`), surfaced clearly. *(New `InjuryFlagsView`/`InjuryFlagsViewModel`, reachable from Settings and from the coach's route; toggles stage, the named change is confirmed by an explicit control, and every flag switches back off from the same screen. Because it is a *safety* filter rather than a preference lever, a confirmed change also reaches the already-generated Ready-screen session without a relaunch, from both entry points: `AppState.injuryFlagsRevision` keys the Ready tab's load, and `ReadyViewModel.generate(user:)` is handed a freshly-read profile by each caller so a duration-chip tap cannot rebuild against stale injuries.)*
- [x] The coach's language never implies it has already removed movements. *(On-device: `CoachInjuryOfferCopy` says plainly that nothing has changed, pinned by `InjuryRoutingEvidenceTests`. Model-side: the proxy persona forbids claiming it flagged/removed/changed anything, pinned by `proxy/test/worker.test.js`.)*
- [x] Tests: an injury message yields a routing proposal, not a silent filter change; confirming sets the flag; declining changes nothing. `docs/test-coverage.md` row.
- [x] Build and suites pass.

**Validation Test:**

- **Setup:** Premium user; coach available.
- **Steps:** Tell the coach "my knee hurts on squats"; decline the flag; then accept it.
- **Expected Result:** Coach offers to flag it; on decline nothing changes; on accept the injury filter is set via the explicit control and is reversible.
- **Failure Indicator:** The coach silently removes squats, or sets an injury flag without explicit confirmation.

### Epic C - Analytics (premium, integrated, Slice 3)

### US-AN01: Strength-journey analytics

**Description:** As a premium user, I want analytics anchored on my strength journey so that I can see progress over time, not just this week's numbers.

**Acceptance Criteria:**

- [x] Extend `DeepAnalytics` (or an adjacent premium analytics unit) with strength-journey views: per-chain progression over time, tier-advancement timeline (e.g. "knee push-up -> full push-up in 6 weeks"), and phase-earning progress (reusing US-SP04's signals). (A new `StrengthJourney`/`ChainJourney`/`TierMilestone` field on `DeepAnalytics`, built by `ProgressAnalytics.makeStrengthJourney`; each `ChainJourney` is the dated climb through a pattern's active chain - `milestones` entry-first with `firstReachedAt`, `hasAdvanced`/`weeksClimbed` for the "in N weeks" line. Phase-earning progress reuses `viewModel.phaseProgress` (US-SP04's `PhaseProgress`), threaded into `DeepAnalyticsSection` and rendered by the new `StrengthJourneyCard`/`ChainJourneyView`/`MilestoneRow`/`PhaseEarningSummary` in `ProgressTabView`, not recomputed.)
- [x] All values are computed from real `WorkoutLog` history; no fabricated data. Locked/unreached tiers are never reported as achieved (respect the existing "never report against a locked Strength tier" rule). (`makeStrengthJourney` reads `firstReachedAt` as the earliest logged `completedAt` of a tier over the same worked-instance atom as the free layers; only **reachable** tiers - the same `phase == .discipline || phase == .strength` rule the chain-position/progression-map surfaces use - can be milestones, so a locked Strength tier is never a milestone. Pinned by `ProgressAnalyticsTests.testStrengthJourneyNeverReportsLockedTierAsReached`, `testStrengthJourneyUsesEarliestReachedDate`, `testStrengthJourneyExcludesSkippedAndSetless`.)
- [x] Premium-gated at the render boundary, consistent with today's `DeepAnalytics` split; free layers unchanged. (The journey is a `DeepAnalytics` field, so `ProgressTabView` renders it only inside `if viewModel.isPremium { DeepAnalyticsSection }` - the identical gate the other deep layers use; free users get the `PremiumUpsellCard`. Proved by `StrengthJourneyEvidenceTests.testFreeUserSeesNoStrengthJourney`.)
- [x] Accessibility + `Theme`; charts follow the app's visual system. Verify on device/simulator via the evidence path. `docs/test-coverage.md` row. (`StrengthJourneyCard`/`ChainJourneyView`/`MilestoneRow` use only `Theme` tokens and the same connector-rail marker ladder as `ProgressionMapCard`; each milestone is one combined a11y element naming the movement, its reached date, and "you're here" for the frontier. `StrengthJourneyEvidenceTests` hosts the production `ProgressTabView` and renders PNGs to `artifacts/reports/US-AN01/` with `validation.md`; `docs/test-coverage.md` row added.)
- [x] Build and suites pass. (`xcodebuild ... -scheme RepToday test` green; `ProgressAnalyticsTests` +7 strength-journey cases and `StrengthJourneyEvidenceTests` both pass.)

**Validation Test:**

- **Setup:** Premium user with multi-week history advancing at least one chain a tier.
- **Steps:** Open premium analytics; view the strength journey.
- **Expected Result:** Shows the tier advancement with correct dates/durations and current phase-earning progress; a free user sees the free layers only.
- **Failure Indicator:** Fabricated/mis-dated advancement, a locked tier reported as reached, or the deep layer visible to a free user.

### US-AN02: Coach narrates the analytics (integration) [below cut line with US-AC07]

**Description:** As a premium user, I want the coach to interpret my analytics and offer to act, so that the data changes my behavior instead of being a chart I ignore.

**Acceptance Criteria:**

- [x] The coach can read the strength-journey analytics (US-AN01) as part of its derived context and narrate a concrete insight ("your push is climbing, your hinge has been flat 3 weeks").
- [x] When the insight maps to a preference change, the coach offers an action that routes through US-AC07 (bounded policy write), never a direct workout edit.
- [x] No new data leaves the device beyond the derived context bundle defined in US-AC01 (still stateless, still no raw history).
- [x] Tests: given a flat-hinge history, the coach surfaces the hinge insight and offers the US-AC07 emphasis action. `docs/test-coverage.md` row.
- [x] Build and suites pass.

**Validation Test:**

- **Setup:** Premium user whose hinge has been flat while push climbed.
- **Steps:** Ask the coach "how am I doing?"
- **Expected Result:** Coach names the push gain and the hinge stall and offers to bias toward hinge (via US-AC07); accepting applies a bounded, noted policy change.
- **Failure Indicator:** Generic summary with no personalized insight, or an offered action that bypasses the bounded policy path.

---

## Functional Requirements

- **FR-1:** The effective difficulty cap MUST be lifted for `.strength`-phase users via one centralized function; `.discipline` users are unaffected. (US-SP01)
- **FR-2:** `Resources/Exercises.json` MUST gain mid-tier (difficulty 3-4) phase-gated skills for push/squat/core and at least one hinge skill (mid + top tier), all zero-equipment and load-validated. (US-SP02, US-SP03)
- **FR-3:** A free phase-progress surface MUST show consistency and competence progress computed by the same logic as `PhaseEvaluator`. (US-SP04)
- **FR-4:** A progression map MUST visualize each pattern's ladder, mark current position and locked Strength-Phase rungs, and MUST NOT allow selecting/starting a movement. (US-SP05)
- **FR-5:** A one-time, identity-framed graduation reveal MUST fire once on transition to `.strength`, persisted and non-repeating. (US-SP06)
- **FR-6:** `proxy/` MUST support a stateless coach request (derived context bundle + message + separate safety pseudonym -> OpenAI `gpt-5.6-luna` -> response), with `store: false`, `safety_identifier`, no Rep Today proxy persistence, bounded and size-capped, no installation/account identity fields, and no accounts. The pseudonym MUST be stable across launches and rotate on account deletion. Standard OpenAI abuse-monitoring retention remains permitted and disclosed. (US-AC01)
- **FR-7:** A premium-gated chat coach MUST answer history-aware, science-grounded questions and MUST NOT generate or edit a workout in the talking story. (US-AC02, US-AC03)
- **FR-8:** A plain, pre-use disclosure MUST state that coach content and a separate random abuse-prevention code are sent to OpenAI, the Rep Today proxy stores no content, OpenAI may retain prompt and response content in abuse-monitoring logs for up to 30 days under standard retention, and the code is not an installation/account identity and rotates on account deletion; it remains separate from the telemetry opt-out. (US-AC04)
- **FR-9:** `SessionPolicy` MUST gain a bounded, neutral-by-default `patternEmphasis` preference lever that reorders but never filters or restructures. (US-AC05)
- **FR-10:** A coach-sourced policy write MUST be able to lower `progressionRate` but MUST NOT raise it above the engine-earned value. (US-AC06)
- **FR-11:** The coach MUST write only preference levers, tagged `.llm`, validated and clamped; the deterministic Programmer's safety moves MUST remain sovereign under an explicit merge/precedence rule; changes MUST be noted honestly and apply next-session. (US-AC07)
- **FR-12:** On an injury/health signal the coach MUST route the user to set an explicit, reversible injury flag and MUST NEVER set a safety filter itself. (US-AC08)
- **FR-13:** Premium analytics MUST add strength-journey views computed from real history, gated at the render boundary, never reporting locked tiers as reached. (US-AN01)
- **FR-14:** The coach MUST be able to narrate the strength-journey analytics and offer only bounded-policy actions (via FR-11). (US-AN02)

## Non-Goals (Out of Scope)

- **No LLM-generated or LLM-edited workouts (option C).** The deterministic engine remains the sole generator; the LLM only talks and writes bounded policy.
- **No Rep Today server-side per-user memory, accounts, or persisted coach content.** The stateless proxy stores no content; standard OpenAI abuse-monitoring retention is allowed and disclosed.
- **No content/discovery library** (no exercise encyclopedia, no articles). Only the progression map, tied to the Strength Phase.
- **No paywalling of the Strength Phase or the core loop.** Strength Phase is earned and free; the core loop is free forever.
- **No coach control over safety filters** (injuries, difficulty cap, phase gate, zero-equipment) beyond routing.
- **No upward difficulty pushed on user request.** Advancement stays engine-earned.
- **No new gamification** (XP, levels, badges, streak-to-break).
- **No equipment.** Zero-Equipment Floor stays.
- **No change to the deterministic engine's <100ms, offline, on-device guarantees for the core loop.**
- **No Android/watch/widgets/Live Activities.**

## Design Considerations

- Reuse `Theme.Colors`/`Typography`/`Spacing`; 60pt touch targets on active screens; overlay-layer presentation for the graduation reveal (Reduce-Motion safe), following the `ContinuousCircuitExplainerView` pattern.
- Phase-progress and progression map should feel like *stewardship of a habit*, not a game board. Identity-framed copy only.
- Coach chat should degrade gracefully and never block the core loop; mirror the `VarietyLanguageResolver` "best-effort upgrade, never a dependency" stance.
- Progression map current-position and analytics should reuse `ProgressAnalytics` chain-position logic rather than re-deriving.

## Technical Considerations

- **Engine safety:** all new levers must be `asOf`-pure, clamped, neutral-by-default, and round-trip-safe for persisted `SessionPolicy` (follow the Start Seed additive-field precedent). The `.llm` `UpdatedBy` case already exists.
- **Two writers, one policy:** `SessionPolicy` is versioned last-writer-wins today; US-AC07 must add an explicit safety-sovereign merge rule so a coach write cannot clobber a deterministic de-load/re-entry.
- **Privacy:** the derived context bundle must be specified precisely and reviewed to ensure it is non-identifying; the proxy must not log bodies; no `installId`/IDFA/Apple ID/account value on the coach wire. The only correlation value is the separate constrained Coach safety pseudonym, rotated on account deletion.
- **Provider:** OpenAI Responses API, source-pinned to exact model `gpt-5.6-luna`, with `store: false`, `safety_identifier`, bounded timeout, output ceiling, and body cap. Deployment does not require Zero Data Retention or Modified Abuse Monitoring; standard OpenAI abuse-monitoring retention of up to 30 days is the disclosed baseline. Variety Language remains independently configured on Anthropic.
- **Testing seams:** reuse `HostedSurface`/`AccessibilityTree`/`EvidenceOutput` for new UI evidence; add `docs/test-coverage.md` rows per story; keep the `RepToday` unit suite green as the gate; convex/proxy toolchain via `npm run typecheck` + `npm test`.
- **Catalog:** new skills must keep progression chains gap-free and pass load-time validation; asset-attribution rows for any bundled asset.

## Success Metrics

- **Retention (readable pre-PMF):** measurable lift in day-7/day-30 return and week-active rate after the phase-progress surface + progression map ship (existing funnel events `day7_return`, `day30_return`, `week_active`).
- **Motivation proxy:** users engage with the phase-progress/map surfaces (add a lightweight, anonymous event if needed within the existing schema discipline).
- **Monetization:** premium conversion lift attributable to the coach entry point (`paywall_shown` -> `trial_started`/`subscribe`), and coach usage among premium users.
- **Safety (must hold):** zero instances of a coach-sourced change making a session harder unbidden, removing a movement, or overriding a safety back-off (enforced structurally + by tests, not just measured).
- **No regressions:** <100ms generation, offline core, and unit-suite green all preserved.

## Open Questions

- Exact composition of the derived context bundle (US-AC01) - which summarized fields are both useful and safely non-identifying?
- Precise bounds/clamp range for `patternEmphasis` (US-AC05) and how strongly it should bias stalest-first ordering before it risks feeling like "the user chose."
- The exact merge/precedence data model for two-writer `SessionPolicy` (US-AC07) - disjoint fields vs. a safety-sovereign overlay.
- Which specific mid-tier skills and hinge skill to author (US-SP02/03) - needs an exercise-science pass on progressions and `advancementCriteria`.
- Whether the graduation reveal (US-SP06) should also nudge a paywall view for the coach, or stay purely celebratory to protect the "never a reward withheld" feel.
- Whether any new anonymous telemetry is warranted for the phase-progress/map surfaces, kept within the existing 13-event schema discipline.
