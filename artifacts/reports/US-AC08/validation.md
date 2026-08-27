# US-AC08 - Safety-filter routing (injury flag, never silent)

Rendered by `RepTodayTests/InjuryRoutingEvidenceTests` on every run.
Re-generate the committed PNGs with `REPTODAY_WRITE_EVIDENCE=1` (see `AGENTS.md`).

## What the images show

| File | Surface | What it evidences |
| --- | --- | --- |
| `01-coach-injury-offer.png` | `CoachInjuryOfferView` hosted directly | The offer names the area, asks rather than announces, and states plainly "I haven't changed anything about your workouts". Both affordances are present: **Open Areas to protect** (a navigation naming the destination screen, not a setting) and **Not now**. |
| `02-coach-conversation-offer.png` | The production `CoachView` after "my knee hurts on squats" | The offer appears as its own card at the end of the turn, below the coach's ordinary answer. The coach still talks; nothing was written. |
| `03-injury-control-routed.png` | The production `InjuryFlagsView`, arrived at from the coach's route | Every protectable area is a switch (so a flag is reversible here), the routed area arrives switched on but **unsaved**, the pending change is named - "Will start working around: Knees." - directly above the live confirmation, and the screen states the change can be switched back off at any time. **Cancel** is the explicit way back out of the routed sheet, so "I changed my mind after accepting the route" is a labelled control rather than only a swipe-down. |

## What these images do *not* prove

- That declining or accepting writes nothing, or that **Cancel** discards the staged edit without writing. Those are behavioural and are proved in `CoachViewModelTests` (US-AC08 block) and `InjuryFlagsViewModelTests`.
- What a confirmation actually writes. That is one rule - the screen may only ever *add or keep* areas that arrived from elsewhere, and only an area it rendered and the user switched off is removed - pinned by `InjuryFlagsViewModelTests.testOnlyAnAreaRenderedThenSwitchedOffIsEverRemoved`, with its deliberately accepted cost (an area can stay flagged though it read as switched off at save time, and is reversible on this same screen without reopening it, because the save reads its own result back) named beside it.
- That a confirmed change reaches the Ready screen without a relaunch. That is behavioural: the injury save bumps `AppState.injuryFlagsRevision` (pinned in `AppStateTests`), the Ready tab re-loads on it, and `ReadyViewModelTests.testSelectDurationRegeneratesAgainstTheCurrentProfile` pins that a regeneration reads the *current* profile rather than the snapshot the screen loaded with.
- Which messages the detector reads as a health signal. `02-coach-conversation-offer.png` shows one that does ("my knee hurts on squats"); the boundary - including the deliberately accepted miss on "I injured my knee" - is pinned by name in `CoachInjuryRoutingTests`, not by any image.
- That the *model's* replies never claim a change was made. A model's free text cannot be pinned; what is pinned is the persona instruction that steers it, in `proxy/test/worker.test.js`. The coach proxy is not deployed, so no live reply has been observed.

## Captain-verifiable manual QA

- The sheet presentation of the injury control from the coach, and the navigation push from Settings, are standard SwiftUI transitions - the evidence asserts which surface renders, not the transition.
- Live on-device VoiceOver focus behaviour when the offer appears mid-conversation.
