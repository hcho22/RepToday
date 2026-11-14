# Sign Out (Part C)

Date: 2026-11-13.
Covers US-SO01 and US-SO02 of `.claude/agent/tasks/prd-health-coach-sizing-signout_261112.md` (decisions 13 to 16, FR-7, FR-8).
This is the public-safe record of what was built, how it was verified and what is still owed.
It names no account, email address, token, key or provider log.

## Accepted contract and impact

- **Contract:** `CONTEXT.md` ("Account"); `docs/implementation-log.md` ("Sign Out"). No new ADR; ADR-0016 carries a one-line note that an existing account can now sign in from Welcome.
- **Intended behavior:** a signed-in user signs out from Settings in two taps; pending changes upload first, and anything that cannot upload is lost only after an explicit warning; the phone then holds nothing of the account and returns to Welcome, whose "Already have an account? Sign in" link signs back in; the same account restores its history and Premium with no onboarding, and a new account onboards.
- **Preserved:** Delete Account's flow, server step and confirmation; the different-account erase; sync, sign-in and onboarding for a new account; every account's server copy; install-level state (the anonymous telemetry identity, rotated as the erase always did, the telemetry choice, one-time product notes, the owed legacy iCloud deletion).
- **Accepted change:** a user-initiated sign-out erases the phone's copy of the account.
- **Delete Account corrections** (the shared teardown now clears account data it already should have): the Strength-Phase celebration, so a later account gets its own graduation moment; the legacy move's import-attempt count; and every notification Rep Today has pending or delivered, including one no saved reminder names.
- **Impact:** iOS only - Settings, onboarding's Welcome step and its sign-in completion, the account and sync services, both Core Data stores, today's choices, Coach reminders and notifications. No server, Convex or schema change.
- **Risk:** medium. A local, user-initiated wipe on the existing erase seam; a missed outbox check would lose workouts, and a missed store would leak one account's data to the next person on the phone. The human-judgment areas are the warning wording and the upload bound, bounded by decisions 13 and 14.
- **Upload bound:** 15 seconds for one sync cycle (`AccountSignOutService.defaultUploadTimeout`); an offline phone answers at once. A cycle still running at the bound keeps going in the background, and the erase waits for it to end.
- **Recovery:** revert the PR in a new build; the server keeps every uploaded record, so a signed-out user restores by signing in. Changes a user discarded with Sign Out Anyway, or any a defect lost before upload, cannot be recovered. A revert is verified by the Settings row being gone and the existing erase tests passing.
- **Release:** deferred to the owed M3/M4 release steps.

## How it was verified

| Check | Where | Result |
| --- | --- | --- |
| Upload first over the real Core Data stores, the real teardown and the fake account server: online saves and reports all saved; offline, a refused push and an upload past the bound report unsaved and change nothing; no backend, or a pre-account move still importing, counts as unsaved | `AccountSignOutServiceTests` | Pass |
| After sign-out (online, and Sign Out Anyway offline): no workout, Outside Activity, paused session, profile, policy, Custom Workout, today's choice, reminder, scheduled notification, outbox entry, sync cursor or session; Coach acknowledgement, Strength celebration and Apple Health choice reset; the server's rows unchanged and no account deleted; a second sign-out is a no-op; another account links with no erase offer | `AccountSignOutServiceTests` | Pass |
| Each Delete Account correction, through Delete Account and the different-account erase; every persisted key in the app's sources decided as the account's or the install's, each account key proved back to a new install's value | `AccountDeviceLeftoverTests` | Pass; sabotage-checked (dropping the celebration reset fails six tests) |
| Confirmation, warning only for unsaved changes, Cancel a no-op, Sign Out Anyway, no second run while busy, a failed erase retried | `AccountSignOutViewModelTests` | Pass |
| Welcome's sign-in: straight to the sign-in and Back to Welcome; a saved plan restores; no plan continues into the questions and finishes from the last one; the questions-first path unchanged | `OnboardingViewModelTests` | Pass |
| The Settings row above Delete Account, Cancel on both dialogs, Sign Out Anyway to Welcome, the Welcome link through the questions to Today, pressed in the running app | `SignOutUITests` (iPhone 16 and iPhone SE, light) | Pass |
| Delete Account still routes to onboarding, and cancelling still leaves the user signed in | `AccountDeletionUITests` | Pass |
| The full unit suite | `xcodebuild -scheme RepToday test` (iPhone 16, iOS 26.5) | 1853 tests, 0 failures, 2 opt-in skips |

### Simulator walk against the dev deployment

`AccountEndToEndUITests` D1 to D4 (opt-in, `REPTODAY_E2E_ACCOUNTS=1`), on one erased iPhone 16 Simulator (iOS 26.5), development Clerk and the dev deployment `courteous-dogfish-560`, with Clerk test addresses.
Before D2 the walk account was given Premium on the dev deployment with `npx convex run entitlements:linkVerified` and an `Xcode`-environment transaction, standing in for a sandbox purchase, as the M4 walks did.

| Step | What it showed | Result |
| --- | --- | --- |
| D1 | A new account onboards, plays a session that saves to the account, and Today moves from Push Day to Pull Day | Pass |
| D2 | Signed in with Premium; Sign Out with nothing waiting asks once and lands on Welcome with no warning; "Already have an account? Sign in" restores straight to Today on the same Training Day, with no questions, and the Premium Coach is there with no Restore Purchases | Pass |
| D3 | With the backend offline (`-RepTodaySyncOffline`), a played session waits; Sign Out shows "Recent workouts aren't saved"; Cancel keeps the user signed in and the session in place; Sign Out Anyway lands on Welcome; signing back in online finds the account as it was before that session | Pass |
| D4 | After sign-out, a second account signed in from Welcome answers the questions, opens on Push Day with none of the first account's history, and sees the free Coach preview | Pass |

The first D3 run stopped on a test navigation step (the Profile tab kept Settings open after Cancel); the walk was fixed and D2 to D4 were rerun on the final code.

### Look and accessibility

On a 375x667 iPhone SE Simulator (iOS 26.5), light at the default size and dark at the largest accessibility size: the Welcome link (Theme accent on secondary text, a 44pt target, below the fold and reached by scrolling at the largest size), the last question's Finish, the Settings Account section, the confirmation and the warning (system alerts, whose message scrolls at the largest size).
The accessibility tree gives the link "Already have an account? Sign in" as one button, the row "Sign Out" as a button with its hint, and both alerts their titles, messages and buttons.
The walk found the onboarding progress bar counting the skipped "Save your plan" step on the signed-in path; it now counts only the steps walked.

## Untested, with the reason

- Live VoiceOver speech and focus: the Simulator has no VoiceOver; labels, traits and hints were read from the accessibility tree.
- Apple and Google sign-in, real airplane mode and a real App Store purchase: device checks, as for M3 and M4; the walk used email-code sign-in, the offline launch switch and a development entitlement grant.
- The system's removal of pending and delivered notifications: unit-tested through the scheduler seam; not observed in Notification Center.
- `SignOutUITests` at the largest text size: the shared reset helper's ten swipes cannot reach Delete Account on a 375x667 screen at that size, so the suite stops before signing out; the look walk above covered those screens instead.
