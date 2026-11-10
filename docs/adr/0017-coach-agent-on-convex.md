# ADR-0017: The Coach is a Convex-hosted agent that writes user-accepted Custom Workouts

- Status: Accepted (decided 2026-11-10); not yet implemented (M4, `US-CA01`...`US-CA08`).
- Date: 2026-11-10
- Deciders: captain, via the Push/Pull/Legs design grill (2026-11-09 to 2026-11-10)
- Spec: `.claude/agent/tasks/prd-ppl-rest-accounts-coach-agent_261110.md`
- Supersedes: the Cloudflare Worker Coach route with per-request App Attest and StoreKit-receipt authentication (`docs/coach-runtime-authentication.md`).
- Relates to: [ADR-0005](0005-two-writer-policy-safety.md) (safety-owned engine moves stay out of the Coach's reach); ADR-0016; `CONTEXT.md` -> "Coach", "Custom Workout".

## Context

Today the Coach is a stateless chat: each turn sends only the current message and a de-identified context bundle to OpenAI through a Cloudflare Worker, and the model itself takes no actions.
The captain wants a premium Coach that remembers the user, acts on their behalf, writes workouts from their history, gives diet guidance and sets reminders.

## Decision

**The Coach runs as Convex actions authenticated by Clerk, with persistent memory, tools, and free-form Custom Workouts the user must accept.**

- Premium is a per-user entitlement in Convex kept current by App Store Server Notifications and checked every turn.
- Tools: log an Outside Activity, rest today or train anyway, change today's length, swap a movement, set Focus Areas, schedule an on-device reminder. Each action is confirmed with Undo. De-load, Re-entry and cold start stay engine-owned.
- A Custom Workout is written freely by the model from the user's workout history, status and injury history. It is a proposal: the user reviews, edits and accepts it before it plays. Any movement is allowed; catalog movements show Trainer art, others are text-only and untracked. A played Custom Workout counts like an Outside Activity and never advances progression.
- Diet guidance is general (protein, hydration, low carb, low sugar, vegetables), for adults only, and never medical.
- The Coach becomes the fourth tab.

## Considered Options

- Coach steers the deterministic engine through closed tools only - rejected by the captain in favor of free-form writing with user review as the safety rail.
- Keeping the Cloudflare proxy and shipping history in each request - rejected once user data lives in Convex.

## Consequences

- Workout and injury history now reach the LLM provider; the Coach data disclosure and privacy policy must say so.
- Custom Workouts are a separate artifact, not a `SessionPolicy` write, so ADR-0005's safety-over-preference structure is unchanged.
