# US-AC08 - Safety-filter routing (injury flag, never silent)

Rendered by `RepTodayTests/InjuryRoutingEvidenceTests` on every run.
Re-generate the committed PNGs with `REPTODAY_WRITE_EVIDENCE=1` (see `AGENTS.md`).

## What the images show

| File | Surface | What it evidences |
| --- | --- | --- |
| `01-coach-injury-offer.png` | `CoachInjuryOfferView` hosted directly | The offer names the area, asks rather than announces, and states plainly "I haven't changed anything about your workouts". Both affordances are present: **Open injury settings** (a navigation, not a setting) and **Not now**. |
| `02-coach-conversation-offer.png` | The production `CoachView` after "my knee hurts on squats" | The offer appears as its own card at the end of the turn, below the coach's ordinary answer. The coach still talks; nothing was written. |
| `03-injury-control-routed.png` | The production `InjuryFlagsView`, arrived at from the coach's route | Every protectable area is a switch (so a flag is reversible here), the routed area arrives switched on but **unsaved**, the pending change is named - "Will start working around: Knees." - directly above the live confirmation, and the screen states the change can be switched back off at any time. |

## What these images do *not* prove

- That declining or accepting writes nothing. That is behavioural and is proved in `CoachViewModelTests` (US-AC08 block) and `InjuryFlagsViewModelTests`.
- That the *model's* replies never claim a change was made. A model's free text cannot be pinned; what is pinned is the persona instruction that steers it, in `proxy/test/worker.test.js`. The coach proxy is not deployed, so no live reply has been observed.

## Captain-verifiable manual QA

- The sheet presentation of the injury control from the coach, and the navigation push from Settings, are standard SwiftUI transitions - the evidence asserts which surface renders, not the transition.
- Live on-device VoiceOver focus behaviour when the offer appears mid-conversation.
