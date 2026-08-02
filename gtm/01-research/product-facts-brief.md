# Product Facts Brief (internal - source of truth for all GTM agents)

Derived from `prd-fitsnack-mvp-v6_0702.md` and `prd-rebrand-fitsnack-to-rep-today_071426.md`. Contradicting these is a hard failure.

## What the product is

**Rep Today** (formerly FitSnack; App Store listing name: plain "Rep Today", subtitle "Opens to a ready workout" - the v1 "Rest Tomorrow" suffix was killed by D-106, see `02-brand/naming-decision.md`) - a discipline-first micro-workout iOS app for busy, desk-bound adults.

- **Zero-equipment, bodyweight only.** Every movement works with a floor and a wall ("hotel room test"). 57-movement library (42 at US-B01, grown to 57 by US-O02).
- **Opens to a ready session.** The app opens to a complete, pre-generated session at the user's learned Default Duration with one dominant Start button. It never asks "how long do you have?" before Start. Duration is a one-tap non-blocking chip (5/10/15/20/30/45/60 min) that regenerates the session in under 100ms.
- **Sessions 5-60 minutes**, generated **on-device, deterministically, offline, in under 100ms**.
- **The AI never generates a workout.** An AI Programmer asynchronously tunes a per-user Session Policy (progression rate, pillar weighting, variety window); the deterministic engine assembles every session. The AI is never on the path between opening the app and starting. At MVP the Programmer is deterministic on-device heuristics (option C) with exactly one optional LLM call (the "Variety Language" line), always backed by an offline template.
- **Three pillars:** bodyweight strength, mobility, primal/animal movement. Mobility is co-primary (same-day relief), never a warm-up. Primal is first-class.
- **Discipline over optimization.** Consistency Score is forgiving and rolling - NOT a streak. A 5-minute session counts as a full show-up. A single miss dents the score, never zeroes it. A Return after a gap is served easy and winnable and is celebrated, never penalized; readjustment happens over a gentle Re-entry Ramp afterward.
- **Adaptive difficulty:** Asymmetric Ramp - backs off immediately when a session was too hard, climbs gradually when too easy. New users get a capped, gentle cold start with deliberate first-week variety across all three pillars.
- **In-session swap:** a movement can be swapped mid-session; the deterministic swap engine substitutes a same-pillar, same-pattern peer within the difficulty band and time budget, and shows a clear "no safe alternative" state when none exists (PRD US-C08/US-K03, implemented and tested).
- **No XP, no levels, no badges, no leaderboards. Anywhere.** Including ad copy.
- **Pricing:** free tier = unlimited workouts forever. Premium ~$7.99/mo or ~$59.99/yr with 14-day trial unlocks depth (deeper analytics, Strength Phase, later AI reports). The paywall never gates the core loop.
- **Apple-native:** iOS 17+, SwiftUI, Sign in with Apple, CloudKit private sync, HealthKit writes, StoreKit 2. Works fully offline and without an account.
- **Two-phase journey:** everyone starts in the Discipline Phase (consistency is the only goal); the Strength Phase is earned by sustained consistency plus cleared movement tiers, never self-selected.

## Status (be honest about this everywhere)

- Pre-launch. iOS-first. **Zero users. Zero downloads. Zero revenue. Zero testimonials.**
- Not yet submitted to the App Store; `DEVELOPMENT_TEAM` unset; no App Store Connect record.
- 667/667 tests pass; app boots in the iPhone 16 Simulator; the MVP core loop (Epics A-N) is implemented.
- `reptoday.com` is registered by a domain investor (HugeDomains, buy-it-now $3,895 as of 2026-07-14); purchase deferred by the founder. Bundle root `com.reptoday.app` locked (Apple does not verify domain ownership).

## What it is NOT (say so when honesty demands)

- Not a strength program, not coaching, not a replacement for a gym.
- No Android, no Watch/widgets at MVP. No social features or challenges.
- No health/medical claims permitted: no calorie/weight-loss/pain-cure/body-composition promises, no before/afters.

## Voice rules (every founder-voiced or product-adjacent line must pass)

- Identity-framed, never loss-framed: "You're someone who moves," never "Don't break your streak."
- Plain, declarative, short. No hype stacking, no three-adjective runs, no "revolutionary / game-changing / unlock your potential."
- No bro-fitness register: no grind, no beast mode, no "no excuses," no shame. Discipline means showing up, and showing up is made easy.
- Never mock the user's current state. The audience is a tired parent at 9pm, not a gym rat.
- No emojis in product-adjacent copy (sparing use in social drafts only where the channel demands it, noted).
- Specific over aspirational: "a 7-minute session is already on screen when you open the app" beats "your fitness journey, reimagined."
- No em dashes in copy; use plain dashes.
