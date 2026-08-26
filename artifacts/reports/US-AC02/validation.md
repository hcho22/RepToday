# US-AC02 - The talking coach (A): history-aware, science-grounded

FR-7 (the talking half). A premium AI coach chat surface where the user asks free-text questions and the coach answers, grounded in the user's real on-device history through the audited `CoachContextBundle` (US-AC01) and the stateless `CoachProxyClient` transport.
The coach only ever *talks* - it never generates, edits, or prescribes a workout (the deterministic on-device engine owns every session); that invariant is enforced in the proxy persona.

## What shipped

- **Chat surface** (`Views/Coach/CoachView.swift`) + **`@Observable` view model** (`ViewModels/CoachViewModel.swift`). The view model holds the on-device conversation transcript (the "memory" - the transport is stateless per request), assembles the `CoachContextBundle` via `CoachContextBundle.make(...)` from the app's already-computed services, calls `CoachProxyClient.reply(...)`, and maps thrown `CoachError`s to a non-blocking, retryable UI state.
- **Refined proxy persona** (`proxy/src/worker.js`, `COACH_SYSTEM_PROMPT`): covers the target intents ("why this workout?", "how do I do <movement>?", "is <movement> safe with <complaint>?" -> safe general guidance + suggest flagging in the app, "I'm bored" -> explain variety), the app's identity-framed voice, and the never-a-workout safety framing. US-AC01's minimal stub is replaced.
- **Endpoint configuration** follows the analytics precedent exactly: per-configuration `REPTODAY_COACH_ENDPOINT` / `REPTODAY_COACH_SECRET` build settings -> `Info.plist` (`RepTodayCoachEndpoint` / `RepTodayCoachSecret`) -> resolved once in `DI/ServiceContainer.live` via `CoachProxyClient.configured(...)`. Missing/empty/unusable -> the coach is inert (`coachClient == nil`), never fatal, never sent to a wrong destination.
- **Entry point:** a minimal, reachable, **ungated** `Coach` row on the Profile tab (`Views/RootView.swift`), trivially replaceable. US-AC03 owns premium gating + the upsell entry point (noted in a code comment there).

## Acceptance criteria

| # | Criterion | Evidence |
|---|-----------|----------|
| 1 | Chat surface; coach answers using the derived bundle + message via US-AC01's transport | `01-coach-answered-conversation.png`; `CoachViewModelTests.testSendCarriesTheDerivedContextBundleFromRealState` (outbound body is the real `CoachContextBundle`) |
| 2 | Answers the target intents | `proxy/test/worker.test.js` "sends a persona that forbids generating a workout and names the target intents and voice" (persona covers stalest-pattern why, form, injury-flag/never-diagnose, variety) |
| 3 | Never returns/implies a generated or edited workout | Enforced in `COACH_SYSTEM_PROMPT` (rule 1: "never generate, edit, prescribe... talking only"); asserted in the proxy persona test. The app owns no workout-generation path from the coach |
| 4 | Graceful failure; core loop unaffected, never waits | `02-coach-graceful-failure.png`; `CoachViewModelTests.testTransportFailureBecomesRetryableErrorAndNeverHangs`, `testBadStatusMapsToTheGenericNonBlockingError`, `testRetryAfterFailureSendsTheSameQuestionWithoutDuplicatingIt` |
| 5 | Identity-framed copy, app voice, never loss-framed/gamified | Persona rule 4; the surface's empty-state/failure/unavailable copy ("your workout isn't affected", "you're someone who shows up") |
| 6 | Accessibility + `Theme`; evidence path; `docs/test-coverage.md` row; suites pass | `CoachViewEvidenceTests` (live a11y tree: distinct "You said:"/"Coach said:" bubbles, labelled input/send, retry, unavailable state); all `Theme` tokens; test-coverage row added |

## Screens

- `01-coach-answered-conversation.png` - the user asks "Why did I get squats today?" and the coach answers with grounded, stalest-pattern reasoning; distinct user (accent, trailing) and coach (surface, leading) bubbles; input + send controls.
- `02-coach-graceful-failure.png` - a transport error renders a calm, retryable banner ("The coach couldn't answer just now. Your workout isn't affected - tap to try again." + "Try again"); the question is preserved.
- `03-coach-unavailable.png` - the unconfigured build (every shipped build today, since the proxy is deploy-ready but not deployed) shows a calm "Coach isn't available right now" state, not an error.

## Notes / scope

- **No coach proxy is deployed yet**, so both build configurations carry an empty coach origin and the coach is inert (`03-coach-unavailable.png`). Pointing it at a deployed `https://<worker>/coach` origin is a one-line `project.yml` change - the unit suite exercises the wired path through the injected transport seam. A real end-to-end Claude reply is captain-verifiable manual QA once the proxy ships.
- **Out of scope (separate stories):** premium gating + upsell (US-AC03), the "sent to Claude, not stored" disclosure (US-AC04), coach-sourced policy writes (US-AC05/06/07), the injury-flag routing UI (US-AC08 - here the coach gives copy-level safe guidance + "flag it in the app" only), premium analytics narration (US-AN01/02).

## How to regenerate

```
cd ios/RepToday
xcodebuild -project RepToday.xcodeproj -scheme RepToday \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  REPTODAY_WRITE_EVIDENCE=1 \
  -only-testing:RepTodayTests/CoachViewEvidenceTests test
```
