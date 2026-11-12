# Coach Agent on Convex (M4)

Date: 2026-11-11.
Covers US-CA01 to US-CA08 of `.claude/agent/tasks/prd-ppl-rest-accounts-coach-agent_261110.md` and ADR-0017.
This is the public-safe record of what was built, how it was verified, what is still owed on a device, and the release steps.
It names no account, email address, token, key or prompt with user data in it.

## Accepted contract and impact

- **Contract:** ADR-0017 and its "Implementation decisions (M4, 2026-11-11)" section; `CONTEXT.md` ("Coach", "Custom Workout", "Rest Day", "Outside Activity"); `convex/README.md` ("The Coach agent and the Premium entitlement").
- **Impact:** a new Coach tab replaces the Profile Coach row; the Coach's backend moves from the Cloudflare Worker to Convex actions; a server-side Premium entitlement fed by App Store Server Notifications; a Custom Workout store (Core Data model version 4, Local configuration) synced through M3's outbox; on-device reminders with a Settings screen; the Coach data disclosure, the Privacy Policy source and the App Store privacy labels.
- **Retired:** the app's use of the Cloudflare Coach route and its App Attest/StoreKit runtime authentication, the synthetic and proof QA lanes and their schemes, and the Coach's keyword `SessionPolicy` tuning (US-AC07) and strength-journey offer (US-AN02) (captain's choice, 2026-11-11).
  The Worker itself and its Coach route are untouched and not deployed.
- **Risk:** medium - a paid surface and user training data now reach an LLM provider through a new server path.
  The core loop does not depend on any of it.
- **Recovery:** before release, revert the PR.
  After release, the Coach can be switched off server-side by unsetting `OPENAI_API_KEY` on the deployment, without a new build: every turn then answers `coach_unavailable`, which the app shows as "The coach couldn't answer just now. Your workout isn't affected".

## How it was verified

| Check | Where | Result |
| --- | --- | --- |
| Apple JWS verification: three-certificate chain to the pinned Apple roots, marker extensions, validity at the signed date, ES256, every malformed or forged shape refused | `convex/appStoreJws.test.ts` | Pass |
| Entitlement: notifications applied idempotently and in signed order, refunds and expiry end Premium, a subscription linked to one live account, restore never moves it from a live account, a link signed before the newest update never undoes a refund or grace period, account tokens, the `POST /appStore/notifications` answers | `convex/entitlements.test.ts` | Pass |
| Coach turn: Premium checked on every turn, ownership, daily limits, retries answered from memory without a second model call, tool calls clamped into proposals and unknown tools dropped, outcomes recorded, the under-18 diet decline before any model call and after the reply | `convex/coach.test.ts`, `convex/coachPrompt.test.ts` | Pass |
| Custom Workout sync and account deletion of every Coach table | `convex/sync.test.ts`, `convex/accounts.test.ts` | Pass |
| All Convex suites | `npm test` | 218 tests pass |
| Proposal application through the app's own paths, confirm-first then Undo, decline writes nothing, an outcome the server has not stored is resent and shown over a reloaded history while one it refuses for good is dropped, the closed action set with no safety-owned move, Custom Workouts never saved or played before acceptance, a played one recorded as an Outside Activity that logs no session, the FR-8 group rule | `CoachViewModelTests` (35 cases) | Pass |
| Today's choices shared by Today and the Coach; the Coach sees today's session with its swaps applied | `TodayChoicesTests` | Pass |
| Custom Workout model, Core Data store (Local only), sync both ways, deletion | `CustomWorkoutTests` | Pass |
| Reminders: permission at the first schedule, edit, disable, delete, identity-framed copy | `CoachRemindersTests` | Pass |
| Wire shapes and refusals for `coach:*` and `entitlements:*` | `ConvexCoachServiceTests` | Pass |
| A purchase carries the account token and is linked; Restore links; a link failure never blocks the on-device unlock | `PaywallAccountLinkTests` | Pass |
| Coach tab, free preview, disclosure, Reminders screen in light, dark, the largest text size and 375x667, with what VoiceOver says | `CoachViewEvidenceTests`, `CoachDataDisclosureEvidenceTests`, `RemindersEvidenceTests` | Pass |
| A Release build carries no Coach configuration and no retired Coach client code | `tools/test-release-build-inspection.py` (CI), `tools/inspect-release-build.py` (archive) | Pass |
| Model choice (Open Question 3) | `convex/coachEval.ts` on the dev deployment | `gpt-5.6-luna` chosen; see ADR-0017 |

### Simulator walks against the development deployment

`CoachEndToEndUITests` (opt-in, `REPTODAY_E2E_COACH=1`) drove the real app on an iPhone 16 simulator (iOS 18.6, Xcode 26.5) against the development Clerk instance, the dev deployment `courteous-dogfish-560` and the real model, signing up with Clerk test addresses.
Before the Premium steps, the walk account was given Premium on the dev deployment with `npx convex run entitlements:linkVerified` and an `Xcode`-environment transaction, standing in for a sandbox purchase (the M4 row of `docs/test-coverage.md` has the command shape).

| Step | What it proved | Result |
| --- | --- | --- |
| A | A free account sees the Coach preview with no message field; "See Premium plans" opens the paywall | Pass (simulator) |
| B1 | Each tool proposed by the model and applied by the app after Confirm, each card then offering Undo: log a run, make today 10 minutes, swap a movement, set Focus Areas, rest today (Today shows the chosen Rest Day), then train anyway | Pass (simulator) |
| B3 | An adult gets general diet guidance; a reminder set two minutes ahead through the Coach asked for notification permission at its first save and was delivered as a notification on the Home Screen | Pass (simulator) |
| B2 | A Custom Workout proposed for a hotel room, no Play before acceptance, a step's sets changed in the editor, accepted and played to the end in the hands-free player, still playable after, and recorded on Today as a Custom Workout under Outside activity | Pass (simulator) |
| C1, C2 | The account deleted through Settings (every Coach row on the deployment removed, the Clerk user gone), a 16-year-old onboarded (age 16 synced to the account), and a diet question answered with the server's fixed decline while a training question is answered | Pass (simulator) |
| B4 | A reminder set through the Coach is listed in Settings > Reminders and deleted there | Pass (simulator) |

Findings from the walks, fixed:

- The conversation hung the main thread when the keyboard opened on a conversation with history: a lazy stack scrolled to its end while the keyboard resized it re-placed its rows without end.
  The conversation is now a plain stack (the server returns at most 200 messages), which also keeps every turn in VoiceOver's reach.
- After a reply the view scrolled to the Coach's bubble, leaving the proposal card and its Confirm below the fold; nothing re-pinned the newest turn when the keyboard opened or when the tab opened on a conversation.
  All three now scroll to the end, and Send puts the keyboard away.
- The Coach was told about today's session with a swapped-out movement removed but its substitute missing, so it could not tell which movement came first.
  The phone now sends the session as Today shows it, through one shared swap function.
- The model's reply to an adult's diet question named the age rule ("Since you're an adult...") and used an em dash.
  The instructions now forbid both, and the server normalizes a stray em dash to the app's spaced hyphen.
- The paywall the Coach opens listed only the Progress analytics; it now leads with the Coach.
- Custom Workout step thumbnails drew both Trainer poses in a 44-point box; they now show the start pose, larger.
- Every Reminders switch was labelled "Reminder on"; each now names its reminder.
  At the accessibility text sizes the composer's prompt is shortened so it fits.

The walk accounts used Clerk test addresses only; the adult walk account was deleted through the app, and the minor and earlier attempt accounts remain on the development instance.
The App Store Server Notifications Sandbox URL for the dev deployment is set in App Store Connect, but no notification had arrived on the dev deployment when the walks ran (its `appStoreNotifications` table is empty), so live delivery is a device check.
Layer captures of hosted screens do not draw the navigation bar's blur, so in the evidence renders scrolled content shows through the Coach's bar; the simulator walk screenshots show the real, frosted bar.

## Simulator-only, and owed on a device (exit criteria)

Everything above ran in the Simulator; the Premium state came from a seeded `Xcode`-environment entitlement, not a purchase.
Owed on a real iPhone with a Debug build and a Sandbox Apple ID:

- Buy Premium with the Sandbox tester from the Coach's paywall; the Coach opens; the entitlement row on the dev deployment shows `Sandbox`.
- A renewal arrives as a `DID_RENEW` notification and moves the entitlement's expiry; a test notification sent from App Store Connect arrives.
- A refund or lapse ends Premium on the next turn.
- Reinstall and sign in to the same account: Restore links the subscription; a different account on the same Apple ID is told the subscription belongs to another account.
- A reminder is delivered with the phone locked; deleting it in Settings stops it.
- VoiceOver on the disclosure, a proposal card (Confirm, Not now, Done, Undo) and the Custom Workout editor.
- A visual pass on a small phone at the largest text size, light and dark.

## Release steps (each a separate, captain-approved step)

1. On the production Convex deployment: set `OPENAI_API_KEY`, and `APPSTORE_ENVIRONMENTS` to `Production,Sandbox` (App Review and TestFlight purchase in Sandbox); never set `APPSTORE_ALLOW_XCODE` there.
   Deploy `convex/` (with or after the M3 release steps); the schema change is additive and `events`/`rateLimits` are unchanged.
2. In App Store Connect, set the Production Server URL (Version 2) to the production deployment's `/appStore/notifications`, decide where the Sandbox URL points for TestFlight, and send a test notification.
3. Update the subscription products' descriptions in App Store Connect to include the Coach, as the paywall and the local StoreKit configuration now do.
4. Publish `gtm/03-site/privacy.html` after legal review (`gtm/03-site/DEPLOY.md`).
5. Enter the App Store privacy label changes below before the build is submitted.
6. Retire the Cloudflare Worker's Coach route and its OpenAI secret.
   No shipped build ever had the route configured, so this can follow any time; it is a separate Worker deploy.

The Worker's other route, `POST /variety-language`, is unaffected: it receives only two pillar labels, calls Anthropic, and never used the Coach's App Attest/StoreKit authentication.
It stays as is.

## App Store privacy labels (App Store Connect > App Privacy)

Changes from the M3 declarations (`artifacts/reports/accounts-m3/validation.md`), each **not used for tracking**, purpose **App Functionality**:

| Category | Data type | Change |
| --- | --- | --- |
| User Content | Other User Content | The Coach conversation and accepted Custom Workouts are now stored with the account: change from **not linked** to **Linked to the user** |
| Purchases | Purchase History | New: the Premium subscription's product, period end and original transaction id, kept with the account so the Coach can check Premium; **Linked to the user** |
| Health & Fitness | Fitness, Health | Unchanged declarations; the Privacy Policy now also says the Coach sends the user's sessions, Outside Activities, Custom Workouts and flagged injury areas to OpenAI to write a reply |

OpenAI processes Coach messages on Rep Today's behalf to provide the feature; it is disclosed in the Coach data disclosure (shown and acknowledged before the first message, App Store Review Guideline 5.1.2(i)) and the Privacy Policy, and is not tracking.
Reminders stay on the device and collect nothing.
These declarations are an engineering reading of how the app handles data; they need the captain's review before entry.
