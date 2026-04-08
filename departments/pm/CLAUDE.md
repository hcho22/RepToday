# PM Context — FitSnack

For project-wide context (architecture, tech stack), see root `CLAUDE.md`.

## Product Context

**Target users:** Busy parents and professionals wanting 5-30 minute workouts.

**Value proposition:** AI-powered workout generation that fits available time, adapts to equipment, avoids injuries, and gamifies progress.

**Phase 1 MVP:** Fully local — mock services + SwiftData persistence. No backend, no accounts.

**Post-MVP:** Convex backend integration with zero UI changes (swap mock services for Convex implementations via protocol pattern).

**App structure:** 8-screen onboarding → 4 tabs (Home, Progress, Challenges, Profile).

## Feature Areas

- **Workout generation:** 30 bundled exercises, smart filtering (equipment/difficulty/injuries), muscle group balancing, time-fitted warmup/main/cooldown blocks
- **Gamification:** XP (3/min + rating bonus), 11 levels (0-5500 XP), 10 badges (first_rep, week_one, early_bird, speed_demon, endurance_king, streak_starter, iron_will, centurion, variety_pack, full_body), weekly streaks
- **Progress tracking:** Calendar heat map, workout history list, calorie tracking
- **Profile:** Onboarding captures fitness level, goals, equipment, injuries, weekly commitment
- **Deferred (post-MVP):** HealthKit sync, push notifications, subscriptions/paywall, social/leaderboard

## PRD Workflow

1. New feature request → generate PRD using `.claude/skills/prd/PRD_SKILL.md`
2. Save PRDs to `.claude/agent/tasks/prd-[feature-name].md`
3. Existing Phase 1 PRD: `.claude/agent/tasks/prd-fitsnack-phase1-mvp.md`
4. Every user story must include **Acceptance Criteria** and a **Validation Test** (setup, steps, expected result, failure indicator)
5. After Engineering delivers → produce Learning Summary for the Founder

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
