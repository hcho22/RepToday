# ADR-0016: Clerk accounts with Convex as the local-first source of truth

- Status: Accepted (decided 2026-11-10); not yet implemented (M3, `US-AU01`...`US-AU05`).
- Date: 2026-11-10
- Deciders: captain, via the Push/Pull/Legs design grill (2026-11-09 to 2026-11-10)
- Spec: `.claude/agent/tasks/prd-ppl-rest-accounts-coach-agent_261110.md`
- Reverses: the Coach PRD non-goal "No Rep Today server-side per-user memory, accounts, or persisted coach content" (`.claude/agent/tasks/prd-phase-2-strength-coach-analytics_260825.md`).
- Replaces: CloudKit private-database sync and the optional Sign in with Apple step.
- Relates to: `CONTEXT.md` -> "Account"; ADR-0017.

## Context

Rep Today has no server accounts: data lives in Core Data synced through the user's private iCloud database, and Convex holds only anonymous telemetry.
A Coach agent that remembers users and reads their workout and injury history, cross-device continuity, and future non-iOS clients all need a real identity and server-side data.

## Decision

**Sign-in is required through Clerk (Apple, Google, email) at the end of onboarding, and Convex becomes the server source of truth, with the phone local-first.**

- New users sign in at "Save your plan" after answering onboarding; existing users sign in once on their next launch and their on-device and iCloud history uploads automatically, idempotently and resumably.
- Core Data stays the on-device store; sessions generate, play and log offline, and changes sync to Convex when online. CloudKit is removed.
- Every Convex function checks that the caller owns the data. Account deletion removes Convex data, the Clerk user and local data.

## Considered Options

- Identity only, data stays in iCloud - rejected: the Coach would still need history shipped from the phone each turn, and no cross-platform path.
- Online-only Convex - rejected: hotel and travel users need offline sessions.

## Consequences

- New privacy policy and App Store privacy labels; data now leaves the device to Rep Today's servers.
- A sync layer and migration become load-bearing code.
