# ADR-0008: Static Trainer pose art replaces the Lottie demo, and the countdown ring leaves the exercise card

- Status: Accepted (decided 2026-10-02); **not yet implemented** - the captain has not yet authorized implementation.
- Date: 2026-10-02
- Deciders: captain, via the Trainer pose art design interview (2026-10-02)
- Spec: `.claude/agent/tasks/prd-trainer-pose-art_261002.md` (`US-TP##`)
- Supersedes / amends: the US-O01 Lottie exercise-demo seam; the US-CC11 work-window layout (illustration and compact ring together in the card); the US-O03 Hold Timer layout (a full-size ring in place of the illustration).
- Relates to: the domain term `CONTEXT.md` -> "Trainer"; [ADR-0002](0002-per-interval-pacer-clock.md) (the per-interval pacer clock, which this keeps visible).

## Context

The player's demo slot was built in US-O01 around a bundled Lottie clip per movement, with a per-pattern SF Symbol as the fallback.
No clip ever shipped, so every movement shows the generic glyph, and the Lottie package is the app's only third-party dependency while rendering nothing.
US-CC11 kept that seam on purpose ("dropping in per-movement clips lights them up at once").

The captain has now produced illustrated art for two Trainers, a male and a female demonstrator, with a static start pose and end pose for almost every movement.
Showing two poses side by side needs room the card does not have while it also holds a countdown ring: inside today's work window each pose would be about 60 pt wide, and a running hold hides the illustration entirely behind a 200 pt ring.

## Decision

**The demo is static Trainer pose art, and the card belongs to the poses.**

1. The exercise illustration resolves the user's Trainer start/end pose art from the asset catalog, else today's SF-Symbol fallback.
   The Lottie package, `Exercise.animationName` and `LottieDemoView` are removed.
   Old active-session snapshots keep decoding, because synthesized `Codable` ignores the removed key.
2. Start and end poses show side by side, static, filling the exercise card at its current height (about 150 pt per pose), in every player state.
3. The countdown ring for the rep work window and the running hold leaves the card and becomes a compact ring beside the exercise name.
   The hold no longer replaces the art with a full-size ring.
4. Any future motion (video or animation) is designed on its own when it arrives, rather than kept alive as an empty seam.

## Considered options

- **Keep Lottie as the seam and add the art beside it** - rejected: it keeps a dependency that renders nothing and two illustration paths to maintain, for motion nobody has planned.
- **Keep the ring in the card and shrink the poses** - rejected: about 60 pt per pose cannot be read from the floor, and the state tones (US-CC10) already mark each transition, so the ring does not need the card.
- **Grow the card** - rejected: it pushes the name, target and controls down and breaks today's fit on small phones.

## Consequences

- The app has no third-party Swift package.
- Missing art degrades per movement and per Trainer: a full pair, a single centered pose, or the SF-Symbol glyph; a build-time report lists every served movement lacking a full pair, so gaps stay visible.
- The app binary grows by roughly 15-20 MB of bundled PNGs (about 16.7 MB raw for the served movements; art for movements withheld until version 2 is added by file drop when they return), accepted because the core loop is on-device and offline with no download path.
- The rest overlay also shows the upcoming movement's poses, so on small phones its ring and poses shrink until everything fits with both controls visible.
- The card keeps the app's card color; a dedicated card color is added only if a pose reads poorly on it.
- Reintroducing motion later is a fresh design, not a data drop into an existing seam.
- Evidence suites that asserted the ring inside the card (US-CC11) are updated to the new layout; the ring's accessibility contract (US-CC14) is unchanged.
