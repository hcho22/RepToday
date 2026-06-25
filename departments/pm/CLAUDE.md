# PM Context — FitSnack

For project-wide context (architecture, tech stack), see root `CLAUDE.md`.

## Product Context

**Target users:** Busy, desk-bound adults wanting 5-30 minute workouts.

**Value proposition:** A deterministic, on-device engine hands the user a complete zero-equipment session for the time they have - no browsing, no choosing, no thinking. The promise is the discipline of showing up; strength is earned over time, never sold up front.

**Phase 1 MVP:** Apple-native and offline-first - mock services + CoreData (`NSPersistentCloudKitContainer`) persistence, Sign in with Apple, CloudKit sync. No custom backend.

**Post-MVP:** Real service implementations swap in with zero UI changes via the protocol pattern. AI/LLM features are deferred to Phase 2 and do language only (summaries, weekly narratives) - they never generate or adapt a workout.

**App structure:** Onboarding → the main app (Home, Active session, Post-session, Progress), routed by `AppState`.

## Feature Areas

- **Session generation:** ~38 bundled bodyweight exercises (Zero-Equipment Floor), deterministic engine - session shape, pillar/pattern staleness, phase/injury/difficulty filtering, progression chains, Adaptive Overload, warmup/cooldown timing fit, in-session swap
- **Consistency & phase (no gamification):** no XP/levels/badges. A forgiving **Consistency Score** measures showing up (a single miss dents but never zeroes; a 5-min session counts as a full show-up); `longestChain` is surfaced as pride, never a threat. The deterministic `PhaseEvaluator` promotes Discipline → Strength on sustained consistency + competence; all MVP users resolve to Discipline
- **Progress tracking:** Consistency Score, longest chain, progression-chain position, personal records
- **Profile:** Onboarding captures fitness level, goals, injuries, sitting hours, weekly goal
- **Deferred (Phase 2):** LLM language summaries/narratives, full Strength-Phase catalog, expanded HealthKit/notifications/premium depth

## PRD Workflow

1. New feature request: generate a PRD using `.claude/skills/prd/PRD_SKILL.md`
2. Save PRDs to `.claude/agent/tasks/prd-[feature-name].md`
3. Source of truth: strategic plan `.claude/agent/tasks/FitSnack-PRD-v5.md`; implementation PRD / live progress tracker `.claude/agent/tasks/prd-fitsnack-mvp_0626.md` (30 stories US-A01 … US-J04, checkboxes flipped to `[x]` as each completes)
4. Every user story must include **Acceptance Criteria** and a **Validation Test** (setup, steps, expected result, failure indicator)
5. After Engineering delivers: produce a Learning Summary for the Founder

## Founder Communication

- The Founder is learning to code — explain everything in plain English
- Use analogies and real-world comparisons
- Define technical terms when first used
- Include "What You Should Know" section in every report
- Keep reports to 1 page maximum

## Artifact Locations

| Artifact | Path |
|----------|------|
| PRDs / task briefs | `.claude/agent/tasks/` |
| Learning summaries | `artifacts/learning-logs/YYYY-MM-DD-[feature-name].md` |
| Specs / briefs | `artifacts/specs/` |
| Engineering reports | `artifacts/reports/` |
| QA test results | `artifacts/reports/test-results/` |
