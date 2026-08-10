# Rep Today - App Store privacy nutrition labels (App Privacy data-type declarations)

**Status: engineering specification, evidence-grounded, captain decisions resolved. Not a legal review.**

This document specifies, for each Apple "App Privacy" data type, whether Rep Today collects it and how it is classified, so the captain can transcribe it directly into App Store Connect -> App Privacy.
The two classification calls that were product/compliance judgments have been decided by the captain (see [Decisions](#decisions-resolved-by-the-captain)); this document states that single chosen path as definitive.
Every classification is grounded in the app's actual behavior (code and the event schema), cited with `file:line` or a doc reference, not in assumptions.
It exists because the pre-publication red-team checklist (`gtm/08-redteam/pre-publication-checklist.md:11-12`) requires the App Store privacy label to be aligned with the app's real data story and to tell **one story** consistent with the privacy policy (`gtm/03-site/privacy.html`) and the landing FAQ.

It does **not** attempt the legal review of the privacy policy - that is a separate counsel step - and it changes no product code, policy, or site copy.

---

## TL;DR

- Rep Today's core loop is **fully on-device, offline, and account-free**.
- The only thing an emitting build sends to a Rep Today-controlled endpoint is **anonymous product-usage telemetry** carrying a **random per-install UUID** and non-identifying event properties - **no name, no email, no advertising identifier**.
- **No ATT prompt. No IDFA. No IDFV. No advertising SDKs. No third-party analytics/tracking SDKs. No cross-app tracking.** (Confirmed by code search - see [No ATT / IDFA](#no-att--idfa--advertising).)
- On-device workout history and profile, optional **user-owned private iCloud** sync (CloudKit private DB), **write-only** Apple Health, and the **Keychain-stored Sign in with Apple identifier** are, per Apple's rules, **not developer data collection** and therefore carry **no label entry**.
- The label is therefore small: **Usage Data (Product Interaction)** and **Identifiers (Device ID)**, both marked **not linked to identity** and **not used for tracking**, purpose **Analytics** - matching the funnel PRD's FR-12 and the checklist.
- **This label presumes telemetry is enabled at submission time.** See [Prerequisites before submission](#prerequisites-before-submission).

---

## Decisions (resolved by the captain)

Two classifications were product/compliance judgment calls rather than facts readable from the code.
The captain has decided both; this document states the chosen path as definitive.
The alternative that was **not** chosen is preserved only as [Appendix A](#appendix-a---the-alternative-not-chosen) for the record.

### Decision A - the per-install UUID -> CHOSEN: declare as Identifiers -> Device ID

The random per-install UUID (minted on first launch, kept only in `UserDefaults`, sent with every telemetry event; explicitly **not** IDFA/`identifierForVendor`/Sign in with Apple identifier/email - `ios/RepToday/RepToday/Utilities/AppState.swift:22-27`, `:74-78`) is declared under **Identifiers -> Device ID**, marked **not linked to identity** and **not used for tracking**, purpose **Analytics**.

### Decision B - what the submitted build collects -> CHOSEN: wire it on, declare it

The label reflects the **intended shipped behavior with telemetry enabled** (the production endpoint configured at submission time), **not** the current empty-endpoint no-op state.
So the submitted build declares **Usage Data (Product Interaction)** collected for **Analytics**, marked **not linked to identity** and **not used for tracking**, with **no ATT prompt and no IDFA / advertising identifier**.

Today a **Release** build's telemetry endpoint (`REPTODAY_ANALYTICS_ENDPOINT`) is empty, so `ServiceContainer.live` resolves `NoOpAnalyticsService` and sends zero bytes (`ios/RepToday/RepToday/Services/Analytics/LiveAnalyticsService.swift:113-141`, doc `:22-29`).
The captain's decision is to close that gap before submission rather than ship a non-collecting build - see [Prerequisites before submission](#prerequisites-before-submission).

**The tables below are the definitive label for the submitted (telemetry-enabled) build.**

## Prerequisites before submission

This label presumes telemetry is enabled at submit time.
The following are **separate tasks tracked by firstmate**, not part of this document, but they must be true before a build carrying this label is submitted:

- **Wire the production telemetry endpoint:** choose and configure the production Convex deployment so the Release `REPTODAY_ANALYTICS_ENDPOINT` is non-empty and `ServiceContainer.live` resolves `LiveAnalyticsService` rather than `NoOpAnalyticsService` (`LiveAnalyticsService.swift:113-118`). Until then, a distributed build collects nothing and this label would overstate the current behavior.
- **Reconcile the site to the collecting story:** update the landing FAQ / event schema so the FAQ, the privacy policy, and this label tell one story once collection is live - notably the FAQ's missing opt-out mention flagged in [One-story alignment](#one-story-alignment-cross-check). This is A/B-sensitive copy work owned elsewhere.

---

## The verified data story (each claim -> evidence)

| Data path | What actually happens | Leaves device to a Rep Today server? | Evidence |
|---|---|---|---|
| Workout generation + history + profile | Generated and stored **on-device** (CoreData). Profile = name, age, sex, height, weight, goals, injuries. | **No** - there is no Rep Today server behind the core loop. | `OnboardingViewModel.swift:304-330`; core-loop offline per `AGENTS.md` |
| Optional iCloud sync | `CDUser` / `CDWorkoutLog` / `CDSessionPolicy` mirror to the user's **own private CloudKit database** via `NSPersistentCloudKitContainer` (default = private DB). Additive, optional, falls back to local-only. | **No** - it is the user's personal iCloud; the developer cannot read it. | `Persistence/PersistenceController.swift:124-135`; datamodel `Cloud` config members `RepToday.xcdatamodel/contents:35-42` |
| Apple Health | **Write-only.** The app *shares* (writes) workouts + active-energy samples and requests `read: []`; it never reads Health data back. | **No** - stays in Apple Health on device. | `Services/Health/HealthKitService.swift:48` (`toShare: shareTypes, read: []`); class doc `:4-11` |
| Sign in with Apple | Optional. Stores only Apple's stable **user identifier** in the **Keychain**, on-device. Name/email scopes are requested but the returned name/email are **discarded** (only `credential.user` is used). | **No** - "never leaves the device." | `Services/Auth/AppleAuthService.swift:31` (`save(result.userIdentifier)`), `:51`; `ViewModels/OnboardingViewModel.swift:199-205` (only `credential.user`); `AppleSignInAuthorizing.swift:9-10` |
| Anonymous usage telemetry | One fire-and-forget POST per event to the Convex sink. Body = `{name, installId, clientTs, props}` - the per-install UUID + event name + timestamp + a non-identifying property bag. Opt-out. | **Yes (emitting build only)** - to Rep Today's own endpoint; **no** email/name/advertising id. | `Services/Analytics/AnalyticsWireBody.swift` (body shape); `LiveAnalyticsService.swift:205-237`; opt-out `AppState.swift:170-172` |
| Pre-launch waitlist email | Collected by the **website** (Kit), not the app. | N/A to the app label - this is a website practice, out of scope for the app's App Privacy label. | `gtm/03-site/privacy.html` section 9 |

Telemetry properties are non-identifying by construction - `requested_minutes`, `completed_minutes`, `elapsed_seconds`, `generation_ms`, `was_return`, `perceived_difficulty`, `abandon_point`, `entry_point`, `plan`, `install_week` - none carry name, body metrics, free text, or location (`gtm/06-channels/event-metric-schema.md:11-27`).

---

## The label - master declaration (submitted, telemetry-enabled build)

| Apple category -> type | Collected? | Linked to identity? | Used for tracking? | Purpose(s) | Evidence / reason |
|---|---|---|---|---|---|
| **Usage Data -> Product Interaction** | **Yes** | **No** | **No** | Analytics | The 13 funnel events (installs, onboarding, session lifecycle, weekly rollup, paywall/subscribe). `event-metric-schema.md:11-27`; `LiveAnalyticsService.swift:205-237`. Not linked: no name/email/account tied to the id. Not tracking: never shared with data brokers, never joined to other apps' data. |
| **Identifiers -> Device ID** | **Yes** | **No** | **No** | Analytics | The random per-install UUID sent with each event. `AnalyticsWireBody.swift`; `AppState.swift:74-78`. Not IDFA/IDFV/Apple-ID/email (`AppState.swift:22-27`). |
| Everything else (all categories below) | **No** | - | - | - | See [full checklist](#full-apple-data-type-checklist) and [reasoning notes](#per-integration-reasoning-notes). |

Both collected types are **Not linked to the user's identity** and **Not used for tracking**, so **no ATT prompt is required**.

---

## Full Apple data-type checklist

Every Apple App Privacy data type, with a Collected Y/N and the reason.
Scan for "Yes"; there are exactly two.

| Category | Type | Collected? | Reason |
|---|---|---|---|
| Contact Info | Name | No | Profile display name is on-device / user's own private iCloud only; never sent to a developer server (`OnboardingViewModel.swift:304-330`). Sign in with Apple name is discarded (`OnboardingViewModel.swift:199-205`). |
| Contact Info | Email Address | No | The app never asks for email. Sign in with Apple email is discarded. The waitlist email is a **website** practice, not the app. |
| Contact Info | Phone Number / Physical Address / Other | No | Not requested anywhere. |
| Health & Fitness | Health | No | HealthKit is **write-only** (`HealthKitService.swift:48`); the app reads no health data. |
| Health & Fitness | Fitness | No | Workout history + fitness profile stay on-device / user's own private iCloud; not sent to a developer server. Telemetry carries only non-identifying counters, not fitness records. |
| Financial Info | Payment / Credit / Other | No | Purchases run through StoreKit 2 / Apple; the app collects no payment or financial info and runs no billing server. |
| Location | Precise / Coarse | No | No location APIs used; no location property in any event. |
| Sensitive Info | Sensitive Info | No | None collected. |
| Contacts | Contacts | No | No Contacts access. |
| User Content | Emails/Messages, Photos/Videos, Audio, Gameplay, Customer Support, Other | No | No such content collected off device. The onboarding "why" free text and profile stay on-device / private iCloud and are never sent in telemetry. |
| Browsing History | Browsing History | No | Not applicable. |
| Search History | Search History | No | No search feature. |
| **Identifiers** | **Device ID** | **Yes** | Per-install random UUID sent with telemetry. See master table. |
| Identifiers | User ID | No | No account/user id is sent off device. The Sign in with Apple identifier stays in the Keychain and is never transmitted (`AppleAuthService.swift:31,51`). |
| Purchases | Purchase History | No (see [note](#reviewer-judgment-note-monetization-events)) | Monetization events are classified as Product Interaction; `plan` is a StoreKit product id on an interaction event, not a financial/billing record. |
| **Usage Data** | **Product Interaction** | **Yes** | The funnel events. See master table. |
| Usage Data | Advertising Data | No | No ads, no advertising SDKs. |
| Usage Data | Other Usage Data | No | Only the pre-registered product events above. |
| Diagnostics | Crash Data | No | No crash-reporting SDK. |
| Diagnostics | Performance Data | No (see [note](#reviewer-judgment-note-generation_ms)) | `generation_ms` rides on a Product Interaction event, not a separate diagnostics stream; no MetricKit/crash SDK. |
| Diagnostics | Other Diagnostic Data | No | None. |
| Other Data | Other Data | No | None. |

---

## Per-integration reasoning notes

### Apple Health -> no label entry
The service requests share access only and passes `read: []` (`HealthKitService.swift:48`); its own header documents it as write-only and it never issues a read query for health samples.
Under Apple's rules, data written to Apple Health that stays on the device / in HealthKit and is not read back by the developer is **not developer data collection**, so it earns no Health or Fitness entry.
If a future story ever *reads* health data off the device, this must be revisited.

### Optional iCloud (CloudKit private DB) -> no label entry
The `Cloud` configuration mirrors to the user's own private CloudKit database (`PersistenceController.swift:133-135`; `NSPersistentCloudKitContainerOptions` defaults to the private database scope; no public/shared scope is configured).
Apple's guidance treats data a user stores in their own iCloud (CloudKit private database) as **not** collected by the developer - the developer operates no server that holds it and cannot read it.
This is confirmed to be the user's private DB and not a developer-controlled backend (there is no such backend behind the core loop).

### Sign in with Apple -> no label entry
Optional, and used only to associate optional iCloud sync with the Apple account.
The app stores Apple's stable user identifier in the **Keychain** on-device (`AppleAuthService.swift:31`, doc `:51` "never leaves the device"), and although `.fullName`/`.email` scopes are requested (`AppleSignInAuthorizing.swift:75`, `OnboardingView.swift:239`), the completion handler keeps only `credential.user` and **discards name/email** (`OnboardingViewModel.swift:199-205`); the programmatic path likewise saves only the identifier.
Nothing from this flow is transmitted to a developer server, so no Contact Info or Identifier entry arises from it.

### Anonymous telemetry -> the one collection
This is the only path that sends data to a Rep Today-controlled endpoint (on an emitting build).
The wire body is exactly `{name, installId, clientTs, props}` (`AnalyticsWireBody.swift`); there is no field for name, email, or an advertising id, by construction.
Collection is **opt-out with disclosure**: on by default, disclosed on the first onboarding screen and in Settings -> Privacy, and turned off via `AppState.analyticsEnabled` effective on the next event (`AppState.swift:170-172`; opt-out story US-T06).
Both the Usage Data and the Device ID are therefore declared **not linked to identity** (no identity is ever attached) and **not used for tracking** (never shared with data brokers, never combined with other companies' data for cross-app tracking).

### Reviewer-judgment note: monetization events
`paywall_shown` / `trial_started` / `subscribe` are recorded as product-funnel events, with `subscribe` carrying `plan` (the StoreKit product id) (`event-metric-schema.md:25-27`).
A conservative reviewer could argue the `subscribe` event touches **Purchases -> Purchase History**.
**Recommendation:** classify these as **Usage Data -> Product Interaction** (they record interaction with the paywall/subscription flow plus a plan identifier for funnel analytics, not a financial ledger), and declare **no Financial Info** (StoreKit/Apple handle the transaction; the app collects no payment data).
This matches the schema's own treatment of them as product events and the FR-12 two-type label.
If counsel prefers maximum caution, adding Purchases -> Purchase History (Not linked, Not tracking, Analytics) is the safe over-declaration; it does not change the not-linked / not-tracking / no-ATT posture.

### Reviewer-judgment note: `generation_ms`
`generation_ms` (engine latency) rides on the `ready_screen_shown` Product Interaction event, not a separate diagnostics pipeline, and there is no crash/performance SDK.
It is declared as a property of Usage Data rather than as Diagnostics -> Performance Data; over-declaring Performance Data (Analytics) would be harmless if a reviewer insists, but is not warranted by a single latency counter on a product event.

---

## No ATT / IDFA / advertising

- **No App Tracking Transparency prompt** and **no IDFA**: a repo-wide search for `AppTrackingTransparency` / `ATTracking` / `ASIdentifierManager` / `advertisingIdentifier` / `requestTrackingAuthorization` returns **no usage in app code** - the only `IDFA` hit is a comment in `AppState.swift:24` stating the per-install id is deliberately *not* derived from it.
- The app **does not track** users across other companies' apps or websites and shares **no identifiers** with third parties, so it is not required to present the ATT prompt (`event-metric-schema.md:53`).
- No advertising SDKs, no third-party analytics/tracking SDKs; the only third-party Swift package in the app is Lottie (`LiveAnalyticsService.swift:6-9`).

---

## One-story alignment cross-check

The label, the privacy policy, and the landing FAQ must tell one story (checklist `:11-12`, `redteam-lawyer-v2.md:33`).

| Claim | This label | Privacy policy (`privacy.html`) | Landing FAQ (`index.html` / `index-b.html`) | Aligned? |
|---|---|---|---|---|
| History on-device, no server behind the core loop | Not collected | Section 1-2 | "Is my data sold?" 1034 / 1037 | Yes |
| Optional sync = user's own private iCloud | Not collected | Section 3 | "Is my data sold?" 1034 / 1037 | Yes |
| Apple Health write-only | Not collected | Section 5 | "Is my data sold?" 1034 / 1037 | Yes |
| Sign in with Apple identifier stays in Keychain; no name/email collected | Not collected | Section 4 | "Sign in with Apple" 923 / 1013 | Yes |
| Anonymous usage w/ per-install UUID; no email/IDFA | Usage Data + Device ID, not linked, not tracking | Section 6 | "Is my data sold?" 1034 / 1037 | Yes |
| Opt-out of usage measurement | Reflected (not linked / not tracking; disclosed) | Section 6 "You can turn it off" | **FAQ omits the off switch** | **Flag** |
| No ATT prompt, no IDFA, no ad SDKs, not sold | No ATT / IDFA; no tracking | Section 7 | "Is my data sold?" 1034 / 1037 | Yes |

**Inconsistency to flag (do not fix here):** the landing FAQ's "Is my data sold?" answer describes the anonymous measurement but **does not mention the opt-out**, while the policy and the app's first onboarding screen do.
The checklist already tracks this (`pre-publication-checklist.md:12`) and deliberately leaves the A/B-tested FAQ copy untouched until a distributed emitting build ships or the test concludes.
Per that item and the task's scope, this document only **flags** the gap; it does not edit the site copy (that is separate, A/B-sensitive work).

---

## Maintenance

Re-verify this specification whenever any of the cited paths change:
the telemetry wire body (`AnalyticsWireBody.swift`), the endpoint configuration or no-op fallback (`LiveAnalyticsService.swift`), the event schema (`gtm/06-channels/event-metric-schema.md`), HealthKit read/write posture (`HealthKitService.swift`), the CloudKit database scope (`PersistenceController.swift`), or the Sign in with Apple handling (`Services/Auth/`).
A new event property or a new integration can add a data type; keep this label, the privacy policy, and the FAQ telling one story.

---

## Appendix A - the alternative not chosen

For the record only. The captain chose the **wire-on-and-declare** path (Decision B above); this appendix documents the option that was **not** taken, so a future reader understands why the label declares collection on a build whose Release endpoint is currently empty.

**Not chosen: ship a non-collecting build and declare "Data Not Collected."**
A Release build submitted with the empty `REPTODAY_ANALYTICS_ENDPOINT` sends zero bytes (`LiveAnalyticsService.swift:113-141`), so that specific build could honestly declare **Data Not Collected**.
The label would then have to be updated to the Usage Data + Device ID set - and a new build submitted, since the endpoint is a per-configuration build setting - before any telemetry-enabled build is distributed.
The captain chose instead to enable telemetry at submission and declare it up front (see [Prerequisites before submission](#prerequisites-before-submission)), so measurement is available from day one and the label is not immediately stale.
