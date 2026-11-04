# Offline session building ("Airplane mode on. The session still builds.")

The claim: with no network at all, a cold open of the app shows a complete session on the Ready Screen, with no error, spinner or degraded state.
This record holds the three things that back it: the engine is the on-device one by name, every network touch on the cold-open path was audited, and an automated test plus a real-iPhone check guard the result.

## The engine

The only `WorkoutEngineProtocol` conformer was named `MockWorkoutEngine` and lived in `Services/Mock/MockServices.swift`, although it always ran the real deterministic pipeline.
It is now `OnDeviceWorkoutEngine` in `ios/RepToday/RepToday/Services/Engine/OnDeviceWorkoutEngine.swift`, wired by both `ServiceContainer.live(...)` and `ServiceContainer.mock()`.
Generation is `SessionAssembly.assemble` and a swap is `ExerciseSwap.swap`, both pure Swift over the bundled, load-validated `Resources/Exercises.json`.
No other change to the engine: session contents and determinism are untouched.

## Network touches on the cold-open path

The path traced: `RepTodayApp.init()` builds `AppState` and `ServiceContainer.live(...)`; `RootView.prepareAppOpen()` runs the app-open phase reconciliation behind a brief `ProgressView`; then `ReadyView`'s `.task` runs `ReadyViewModel.load()`, which reads the user, the resumable session, recent logs and the policy from CoreData, generates the session on-device, then computes the Variety Language line and Consistency Score.
Paths are relative to `ios/RepToday/RepToday/`.

| Touch | Does the Ready Screen await it? | Offline behavior | Where |
| --- | --- | --- | --- |
| Telemetry `POST /logEvent`: app-entry events | No | Fire-and-forget. `record(_:)` is synchronous and only hands the event to a bounded queue; delivery runs on its own task, fails, and keeps the event in the outbox for a later connection. | `App/RepTodayApp.swift:94`, `Services/Analytics/LiveAnalyticsService.swift:211` |
| Telemetry recovery on launch and foreground | No | Fire-and-forget `Task`; an offline send fails and stays queued. | `App/RepTodayApp.swift:76`, `App/RepTodayApp.swift:118` |
| Telemetry `ready_screen_shown` | No | Recorded after the session is generated; same synchronous hand-off as above. | `ViewModels/ReadyViewModel.swift:215` |
| Telemetry during onboarding (`onboarding_started`, `onboarding_completed`) | No | Same synchronous hand-off; `finish()` saves the user and seeds the policy locally first. | `ViewModels/OnboardingViewModel.swift:168`, `ViewModels/OnboardingViewModel.swift:268` |
| Variety Language upgrade `POST /variety-language` | Not wired | The Ready Screen's resolver has no provider and treats the network as offline, so the line is always the on-device template. Even if a provider were wired, the session is shown before the line is computed, and any failure returns the template. | `ViewModels/ReadyViewModel.swift:151`, `Services/Language/VarietyLanguageResolver.swift:39`, `Services/Language/VarietyLanguageResolver.swift:60`, `ViewModels/ReadyViewModel.swift:490` |
| Coach `POST /coach` | No | Not on this path: `ReadyViewModel` takes no coach seam. Building the client at launch makes no request. | `DI/ServiceContainer.swift:318` |
| CloudKit mirroring | No | `loadPersistentStores` loads the local stores; mirroring runs in the background and falls back to local-only when it cannot set up. | `Persistence/PersistenceController.swift:63` |
| StoreKit transaction listener | No | Background `Task` started at launch; the Ready Screen reads no entitlement. | `App/RepTodayApp.swift:65` |
| HealthKit share request | No | Local system prompt in a non-blocking `.task` on the tabs; not a network call. | `Views/RootView.swift:163` |
| Sign in with Apple | No | Optional in onboarding and skipped offline; `finish()` reads only the local Keychain and otherwise uses a local id. | `ViewModels/OnboardingViewModel.swift:288` |
| App-open phase reconciliation | Yes (local only) | CoreData reads and an on-device evaluator; no network. | `Views/RootView.swift:100` |

No touch blocks or degrades session building, so no production code changed for the audit.

## Automated guard

`ios/RepToday/RepTodayTests/OfflineSessionGenerationTests.swift` runs in the default `RepToday` test scheme, so CI runs it on every pull request.
It builds the production container (`ServiceContainer.live(...)`), runs the app-open reconciliation and `ReadyViewModel.load()` the way `RootView` and `ReadyView` do, and asserts a complete session (training block present, every block filled, within the ±60 s fit) with no error and no loading state.

- Every telemetry request goes through the real `LiveAnalyticsService` over a `URLSession` that fails it with `URLError(.notConnectedToInternet)`; the test checks requests really reached it and stayed queued.
- One test holds a telemetry request open forever and shows the Ready Screen still becomes ready while it is outstanding, so nothing on the path awaits the network.
- One test wires the real Variety Language provider over an offline session behind a resolver told the network is up, and still gets the template line and a ready session.
- A protocol registered globally for each test must see no request on `URLSession.shared`; adding one to the cold-open path fails the suite (checked by adding one and watching two tests fail).
- Covers a fresh install through onboarding and a cold open of an install with saved history.

What it cannot cover: the in-memory test store has no CloudKit, and the Simulator is not a phone in airplane mode.
The device check below is that half.

## Device check

Run on a real iPhone by hand, on a Debug build of the branch that carries this record.
"Complete session" means the Ready Screen shows the session's movements and an enabled Start, with no "We couldn't load today's session." message, no spinner after the first moment, and no empty or placeholder state.

| # | Check | Steps | Result | Build commit | Device | iOS | Date |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Cold open offline, existing install | Onboarded install with at least one completed session. Turn Airplane Mode on and confirm Wi-Fi is off in Control Center. Force-quit the app from the app switcher. Open the app. | Pass. The captain reported "cold open pass". Installed over the existing onboarded app. This Debug build's telemetry sink was the inert no-op (no dev telemetry secret in the build), so the live telemetry transport offline was covered by `OfflineSessionGenerationTests`, not by the phone. | c02badf (Debug) | iPhone 13 Pro | 26.6.2 | 2026-11-04 |
| 2 | Fresh install offline, through onboarding | Delete the app, then install the build. Turn Airplane Mode on and Wi-Fi off before the first open. Open the app, skip Sign in with Apple, finish onboarding. | Not run on a device. The captain accepted the automated fresh-install test (`OfflineSessionGenerationTests.testFreshInstallOfflineOnboardsAndBuildsACompleteSession`) as the evidence for this path, because a device fresh install would erase the on-device history. | | | | |
