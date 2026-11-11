# Accounts: Clerk sign-in and local-first sync (M3)

Date: 2026-11-11.
Covers US-AU01 to US-AU05 of `.claude/agent/tasks/prd-ppl-rest-accounts-coach-agent_261110.md` and ADR-0016.
This is the public-safe record of what was built, how it was verified, what is still owed on a device, and the release steps.
It names no account, email address, token or key value.

## Accepted contract and impact

- **Intended behavior:** new users sign in with Clerk (Apple, Google, email code) at a required "Save your plan" step; users onboarded before accounts sign in once on their next launch and their on-device and iCloud history uploads automatically; Core Data stays the local store and syncs to Convex when online; CloudKit sync ends; account deletion removes the account's Convex data, the Clerk user and the data on the device.
- **Preserved behavior:** sessions generate, play and log fully offline; the Training Day engine, Rest Days, Focus Areas and Outside Activities behave as before; telemetry (`events`, `rateLimits`, `POST /logEvent`, `POST /webEvent`) is untouched; the Coach works as before; no data is lost or duplicated by the migration, and a device's `User.id` is never rekeyed.
- **Accepted change:** the optional Sign in with Apple step is gone and sign-in is required.
- **Impact:** onboarding, launch routing, persistence (model version 3), account deletion and Settings in the app; a new Convex schema and functions; a Clerk instance; the Privacy Policy source; the App Store privacy labels.
- **Risk:** high - persisted user data moves to a new server and sign-in gates the app.
- **Recovery:** before release, revert the PR. After a build ships, user iCloud data is never deleted by the migration, so a fixed build can re-run it; Convex data can be deleted per user. A broken sign-in gate is contained only by shipping a new build.

## How it was verified

| Check | Where | Result |
| --- | --- | --- |
| Ownership on every public function, idempotent upsert, newest wins, tombstones, ordered pull pagination, malformed changes refused before any write, deletion order and repeat-safety | `convex/sync.test.ts`, `convex/accounts.test.ts` (`npm test`, in process) | Pass |
| Dev deployment refuses an unauthenticated call (`unauthenticated`) and an unverifiable token (401); telemetry route unchanged | Live probe of `courteous-dogfish-560` | Pass |
| Outbox written in the same save as every record; coalescing; replays write nothing; edits during an upload are kept; pulls never echo; cursor moves only after a saved page; restore from an account | `LocalFirstSyncTests` | Pass |
| Offline generate, play and log, then sync | `LocalFirstSyncTests.testASessionGeneratesPlaysAndLogsOfflineThenSyncs` | Pass |
| Migration: stage resolution, interrupted upload, kill between queueing and advancing, re-run writes nothing new, newer account data kept, model-version-2 store opens and moves completely | `LegacyAccountMigrationTests` | Pass |
| Deletion: server first, offline changes nothing, repeat skips the finished server step, outbox and session cleared | `AccountDeletionAccountTests` | Pass |
| Wire shape and error mapping against the backend's validators | `ConvexSyncRemoteTests` | Pass |
| Sign-in panel, onboarding completion (create vs restore vs unreachable), Account screen copy | `AccountSignInTests`, `OnboardingViewModelTests` | Pass |
| "Save your plan", the existing-user sign-in and the Account screen in light, dark, the largest text size and 375x667, with VoiceOver labels | `AccountScreensEvidenceTests` | Pass |
| Fresh install: real email-code sign-up at "Save your plan", then "Everything is saved" | `AccountEndToEndUITests` A, development Clerk + dev backend | Pass (simulator) |
| Seeded existing user: an install onboarded and played by the pre-account build (main at `d5556bf`) upgraded in place, "Keep your history" first, history moved | `AccountEndToEndUITests` C, then the dev backend read with the Convex CLI | Pass (simulator): the profile, Focus Areas, policy and the played session reached the account |
| Offline session then sync: a session played with the backend cut off, "2 changes will save when you're online", then saved after relaunch online | `AccountEndToEndUITests` A | Pass (simulator) |
| Account deletion: back to onboarding, the account's rows purged, its account row removed after the grace period, the Clerk user unknown afterwards; another account untouched | `AccountEndToEndUITests` B, Convex CLI, Clerk Frontend API sign-in probe | Pass (simulator) |

The walks ran on 2026-11-11 on an iPhone 16 simulator (iOS 18.6, Xcode 26.5) against the development Clerk instance and dev deployment `courteous-dogfish-560`.
Simulator-only: they use Clerk's development test email addresses (fixed code 424242), which send no mail, and a Debug-only switch (`-RepTodaySyncOffline YES`) standing in for airplane mode, because the Simulator shares the Mac's network.
Real Apple and Google sign-in, real airplane mode, real iCloud data and VoiceOver itself were not exercised; they are the device checks below.
Findings from the walks, fixed: on a device with no iCloud account the move never got an import answer and stayed in `importingFromICloud` (it now asks CloudKit's account status and reads the mirror's "no iCloud account" error, and waits at most once per launch; the final walk C ended at `complete`); the Account screen wrapped a long email mid-word and misaligned its second line; and a sign-in session left in the Keychain by an earlier install is, correctly, offered back on "Save your plan" and "Keep your history", which the walks now handle. After a deletion, "Save your plan" no longer offers the deleted account.
The walks left two Clerk test accounts (test addresses only) and their rows on the development instance and dev deployment; every other walk account was deleted through the app.

## Owed on a device (exit criteria)

- Fresh install on an iPhone: sign in with Apple, then on another install with Google; both reach Today.
- An iPhone running the last pre-account TestFlight build with real history (ideally with a second iPhone or an iCloud-only record): install the M3 build, sign in once, confirm every session appears on the account and on a second device after signing in there.
- Airplane mode: play a session, see "will save when you're online" on Profile > Account, turn airplane mode off, see "Everything is saved".
- Delete the account; confirm onboarding returns, and signing in again with the same Apple ID starts a new, empty account.
- VoiceOver on "Save your plan" and "Keep your history".

## Release steps (each a separate, captain-approved step)

1. Create the production Clerk instance with Apple, Google and email-code sign-in (no password requirement), activate its Convex integration and register the native iOS app.
2. Set `CLERK_FRONTEND_API_URL` and `CLERK_SECRET_KEY` on the production Convex deployment, then deploy `convex/` there (the push is refused until the issuer is set). The schema change is additive; `events` and `rateLimits` are unchanged.
3. Set the Release `REPTODAY_CLERK_PUBLISHABLE_KEY` (`pk_live_...`) and `REPTODAY_CONVEX_URL` in `ios/RepToday/project.yml`; `tools/archive-release.sh` refuses an archive without both.
4. Publish `gtm/03-site/privacy.html` after legal review (`gtm/03-site/DEPLOY.md`).
5. Enter the App Store privacy labels below in App Store Connect before the build is submitted.
6. After every TestFlight user has moved, a later build removes the iCloud container entitlement and the `NSPersistentCloudKitContainer` class.

## App Store privacy labels (App Store Connect > App Privacy)

M3 adds data that leaves the device to Rep Today's servers, linked to the user's account.
None of it is used for tracking, and none is shared with data brokers or advertisers.
Declarations to add, each **Linked to the user**, **not used for tracking**, purpose **App Functionality**:

| Category | Data type | What it is |
| --- | --- | --- |
| Contact Info | Email Address | The account's sign-in email (or Apple's private relay address), held by Clerk |
| Contact Info | Name | The name entered in onboarding, stored with the profile |
| Identifiers | User ID | The Clerk user id that owns the account data |
| Health & Fitness | Fitness | Completed sessions, logged Outside Activities (some from Apple Health suggestions), the training program settings |
| Health & Fitness | Health | Injury areas the user flagged; height and weight |
| Other Data | Other Data Types | Age, sex, fitness level, focus areas, stated reason for training |

Unchanged declarations: the anonymous usage measurement (Usage Data > Product Interaction, **not linked**, Analytics) and the optional AI Coach (User Content > Other User Content, not linked, App Functionality).
Apple Health data stored on Rep Today's servers is disclosed in the Privacy Policy and never used for advertising (App Store Review Guideline 5.1.3).
These declarations are an engineering reading of how the app handles data; they need the captain's review before entry.
