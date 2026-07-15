# PRD: Rebrand FitSnack → Rep Today (pre-public)

_Created: 2026-07-14_

## Introduction

Rename the app from **FitSnack** to **Rep Today** across the entire codebase before the first App Store submission.
"Rep Today" is the brand and under-icon display name; the App Store *listing* name will be "Rep Today, Rest Tomorrow" (set in App Store Connect, not in this repo).

The app has never shipped: `DEVELOPMENT_TEAM` is empty, there is no App Store Connect record, and there are no real users or synced CloudKit data.
This is the **only free window** to change the fields that become permanent at first submission - the bundle identifier, the CloudKit container, and the StoreKit product ids.
After publish, changing those orphans user data or is outright impossible, so the rebrand must happen now.

This is a full rename (permanent identifiers + user-facing display/copy + internal module/target/folders + living docs + proxy + GitHub repo), not a cosmetic find-and-replace.

## Goals

- Change every permanent identifier to the `com.reptoday.app` reverse-DNS root while it is still free to change.
- Show "Rep Today" as the under-icon display name and remove every user-visible "FitSnack" string.
- Rename the internal Swift module/target/folders/scheme to `RepToday` so the codebase reads consistently.
- Keep the full test suite (655 tests) green and the app booting cleanly in the Simulator at every step.
- Leave dated historical PRD/task artifacts untouched as point-in-time records.

## User Stories

### US-001: Confirm `reptoday.com` is obtainable and lock the reverse-DNS root

**Description:** As the owner, I want to confirm `reptoday.com` is available/controllable before I bake `com.reptoday.app` into permanent fields, so I never lock a bundle id anchored to a domain I can't own.

**Acceptance Criteria:**

- [x] `reptoday.com` availability (or existing ownership) is verified via a registrar/WHOIS lookup
- [x] The `@reptoday` handle situation is noted (nice-to-have, not a blocker)
- [x] The final reverse-DNS root is recorded as `com.reptoday.app` (or an explicitly chosen fallback if the domain is unobtainable)
- [x] This story blocks US-004; no permanent identifier is changed until it passes

**Validation Test:**

- **Setup:** None.
- **Steps:**
  1. Run a WHOIS / registrar availability check on `reptoday.com`.
  2. Record whether it is available, already owned, or taken.
- **Expected Result:** A definitive yes/no on obtaining `reptoday.com`, and a confirmed reverse-DNS root string to use downstream.
- **Failure Indicator:** The domain is taken by an unrelated party and no fallback root is chosen, leaving US-004 unable to proceed safely.

**Findings & Decision (recorded 2026-07-14):**

- **`reptoday.com` — registered, not free.** Verisign registry WHOIS: created 2018-12-14, expires 2026-12-14, registrar TurnCommerce/NameBright. It resolves to a **HugeDomains** parking/sale page (domain investor, no active business) with a **buy-it-now of $3,895** (or ~$162.29/mo). So it is *obtainable* (purchasable) but not a free registration.
- **`@reptoday` handles:** GitHub `github.com/reptoday` → HTTP 404 (**appears available**). Instagram → HTTP 200 behind a login wall, which is returned for both taken and free handles, so **inconclusive**; X/TikTok/App Store dev name still need a manual logged-in check. Nice-to-have, not a blocker.
- **Bundle-root note:** Apple bundle identifiers use reverse-DNS *convention* only and do **not** verify domain ownership, so `com.reptoday.app` is a valid, permanent root whether or not `reptoday.com` is owned.
- **Decision (owner):** Lock the reverse-DNS root as **`com.reptoday.app`** and **defer** the `reptoday.com` purchase ($0 now); buy the domain (or use `reptoday.app`/a marketing domain) later if the app gains traction. Marketing domain: TBD.
- **US-004 is UNBLOCKED** — permanent identifiers may proceed against the `com.reptoday.app` root.

### US-002: Rename the internal module, target, scheme, and folders to `RepToday`

**Description:** As a developer, I want the Xcode target, Swift module, scheme, and folder tree renamed to `RepToday` so nothing internal reads "FitSnack".

**Acceptance Criteria:**

- [x] Folders renamed: `ios/FitSnack/` → `ios/RepToday/`, inner `FitSnack/` → `RepToday/`, `FitSnackTests/` → `RepTodayTests/`
- [x] `project.yml`: project `name`, target `FitSnack` → `RepToday`, test target `FitSnackTests` → `RepTodayTests`, and all source/scheme paths updated
- [x] `App/FitSnackApp.swift` → `App/RepTodayApp.swift`, and `struct FitSnackApp` → `struct RepTodayApp` (with `@main` intact)
- [x] All 47 test files: `@testable import FitSnack` → `@testable import RepToday`
- [x] Resource files renamed: `FitSnack.entitlements` → `RepToday.entitlements`, `FitSnack.storekit` → `RepToday.storekit`; `project.yml` `INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`, `excludes`, and `storeKitConfiguration` paths updated to match
- [x] `AppState.swift` UserDefaults suite `FitSnack.Preview` → `RepToday.Preview` (both lines)
- [x] `xcodegen generate` succeeds; app builds; full test suite passes (667/667 green under the `RepToday` module)

**Validation Test:**

- **Setup:** Clean working tree on a rebrand branch.
- **Steps:**
  1. `cd ios/RepToday && xcodegen generate`
  2. `xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
  3. `xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday -destination 'platform=iOS Simulator,name=iPhone 16' test`
- **Expected Result:** Project regenerates with the `RepToday` scheme, builds with no missing-file errors, and all 655 tests pass under the renamed module.
- **Failure Indicator:** `xcodegen` reports missing source paths, the build fails on an unresolved `import RepToday`, or any test target fails to compile.

### US-003: Rename the CoreData model to `RepToday`

**Description:** As a developer, I want the CoreData model and store files renamed to `RepToday`, since this is the one internal rename with persistence risk and it must be done while there are no users.

**Acceptance Criteria:**

- [x] `FitSnack.xcdatamodeld` (and inner `FitSnack.xcdatamodel`) → `RepToday.xcdatamodeld` / `RepToday.xcdatamodel`
- [x] `PersistenceController.swift`: `NSPersistentCloudKitContainer(name: "FitSnack")` → `"RepToday"`, the `forResource: "FitSnack"` momd lookup → `"RepToday"`, and store filenames `FitSnack.sqlite` / `FitSnack-Local.sqlite` → `RepToday.sqlite` / `RepToday-Local.sqlite`
- [x] CoreData **entity** names (`CDUser`, `CDWorkoutLog`, `CDSessionPolicy`, `CDActiveSession`) are left unchanged (not brand-named)
- [x] Persistence tests and the full suite pass; the in-memory `/dev/null` test path is unaffected

**Validation Test:**

- **Setup:** A Simulator with any prior FitSnack dev build deleted (old store files are disposable).
- **Steps:**
  1. `xcodegen generate` and run the full test suite.
  2. Launch the app in the Simulator; complete onboarding and finish one session.
  3. Inspect the app container's Application Support directory.
- **Expected Result:** All tests pass; `RepToday.sqlite` and `RepToday-Local.sqlite` materialize (no `FitSnack.sqlite`); the model loads without the `fatalError("Failed to locate the … CoreData model")` path firing.
- **Failure Indicator:** App traps on launch with a missing-model fatal error, or store files still carry the `FitSnack` name.

### US-004: Migrate the permanent identifiers to the `com.reptoday.app` root

**Description:** As the owner, I want the bundle id, CloudKit container, StoreKit product ids, and Keychain service key moved to the new root, because these are immutable after the first submission.

**Acceptance Criteria:**

- [x] `project.yml`: `bundleIdPrefix` `com.fitsnack` → `com.reptoday`; app `PRODUCT_BUNDLE_IDENTIFIER` → `com.reptoday.app`; test target → `com.reptoday.app.tests`
- [x] `RepToday.entitlements`: iCloud container `iCloud.com.fitsnack.app` → `iCloud.com.reptoday.app`
- [x] `PersistenceController.swift:31`: `cloudKitContainerIdentifier` → `iCloud.com.reptoday.app`
- [x] StoreKit ids `com.fitsnack.app.premium.{monthly,yearly}` → `com.reptoday.app.premium.*` in **both** `SubscriptionPlan.swift` (`ProductID.monthly`/`.yearly`) and `RepToday.storekit` (`productID` ×2, `_applicationInternalID`) - the two must stay identical
- [x] `AuthCredentialStore.swift:44`: Keychain service `com.fitsnack.app.auth` → `com.reptoday.app.auth`
- [x] `StoreKitSubscriptionServiceTests` / `PaywallViewModelTests` pass against the new ids; full suite green

**Validation Test:**

- **Setup:** US-001 confirmed the root; the `RepToday.storekit` config is attached to the scheme.
- **Steps:**
  1. `grep -rn "com.fitsnack" ios/RepToday` → expect no matches.
  2. Run the full test suite.
  3. Launch in the Simulator, open the paywall, and complete a sandbox purchase and a restore.
- **Expected Result:** No `com.fitsnack` strings remain; all tests pass; the paywall lists and purchases `com.reptoday.app.premium.monthly` / `.yearly`, and restore re-grants premium.
- **Failure Indicator:** A `com.fitsnack` id lingers in either StoreKit source, the purchase can't find its product, or CloudKit setup logs the old container.

### US-005: Set the display name and rebrand all user-facing copy

**Description:** As a user, I want the app to present itself as "Rep Today" everywhere I can see it, with no "FitSnack" text.

**Acceptance Criteria:**

- [x] `project.yml` adds `INFOPLIST_KEY_CFBundleDisplayName: "Rep Today"` (with the space) - currently unset, so it defaults to the target name
- [x] `Info.plist` `NSHealthUpdateUsageDescription` copy: "FitSnack writes…" → "Rep Today writes…"
- [x] `PaywallView.swift:176` placeholder privacy URL no longer contains "fitsnack" (real URL value tracked as an Open Question / pre-submission task)
- [x] Remaining "FitSnack" mentions in app `.swift` files (Theme, User, SubscriptionPlan, CoreDataUserService, HealthKitService, HealthKitWorkoutSample, ServiceProtocols, OnboardingView, etc.) → "Rep Today"
- [x] Verify in iOS Simulator: under-icon label and the Health permission prompt both read "Rep Today"

**Validation Test:**

- **Setup:** Build and install on a Simulator that has never granted Health access.
- **Steps:**
  1. Install the app; view the Home screen / app icon label.
  2. Complete onboarding and finish a session to trigger the HealthKit share prompt.
  3. `grep -rin "fitsnack" ios/RepToday/RepToday --include="*.swift" --include="*.plist"`.
- **Expected Result:** The under-icon name reads "Rep Today"; the Health prompt text starts "Rep Today writes…"; the grep returns nothing.
- **Failure Indicator:** The icon still says "FitSnack"/"RepToday" (no space), the Health string names FitSnack, or any user-facing string survives the grep.

### US-006: Rebrand the living docs (CLAUDE.md + README)

**Description:** As a contributor, I want `CLAUDE.md` and `README.md` to describe "Rep Today" with correct file paths, since the folder rename makes their old paths stale.

**Acceptance Criteria:**

- [x] `CLAUDE.md`: product name "FitSnack" → "Rep Today"; every `ios/FitSnack/FitSnack/...` path → `ios/RepToday/RepToday/...`; build/test commands updated to the `RepToday` scheme/project
- [x] `README.md`: rebranded consistently
- [x] Dated files under `.claude/agent/tasks/` are **not** modified (historical snapshots)

**Validation Test:**

- **Setup:** US-002/US-003 complete (folders already moved).
- **Steps:**
  1. `grep -rn "FitSnack\|ios/FitSnack" CLAUDE.md README.md` → expect no matches.
  2. Copy the Build & Run commands from `CLAUDE.md` and run them verbatim.
- **Expected Result:** No stale brand/paths in either doc; the copied commands generate, build, and test successfully against the `RepToday` project.
- **Failure Indicator:** A `CLAUDE.md` build command points at a non-existent `ios/FitSnack` path or the `FitSnack` scheme.

### US-007: Rebrand the proxy

**Description:** As a developer, I want the deferred Variety Language proxy renamed so it doesn't ship "FitSnack" branding when it is eventually deployed.

**Acceptance Criteria:**

- [x] `proxy/wrangler.toml`: worker `name` `fitsnack-variety-language-proxy` → `reptoday-variety-language-proxy`
- [x] `proxy/package.json`: `name` and `description` rebranded
- [x] `proxy/README.md` and `proxy/src/worker.js` header comment rebranded (including the `ios/FitSnack/...` path reference in the README → `ios/RepToday/...`)
- [x] No functional change to the single-Claude-call behavior

**Validation Test:**

- **Setup:** Node available in `proxy/`.
- **Steps:**
  1. `grep -rin "fitsnack" proxy` (excluding `node_modules`) → expect no matches.
  2. `cd proxy && npx wrangler deploy --dry-run` (or `wrangler dev` startup) to confirm config still parses.
- **Expected Result:** No "fitsnack" strings remain; the worker config validates with the new name.
- **Failure Indicator:** `wrangler` errors on the config, or a brand string survives the grep.

### US-008: Rename the GitHub repository

**Description:** As the owner, I want the GitHub repo renamed from `hcho/FitSnack` to `hcho/reptoday` so the remote matches the brand.

**Acceptance Criteria:**

- [x] Repo renamed `hcho22/FitSnack` → `hcho22/reptoday` (via `gh repo rename`)
- [x] The local git remote URL is updated to the new name
- [x] The old URL confirmed to auto-redirect (rename is reversible - `git ls-remote` over the old URL resolves to the renamed repo's HEAD; the unauthenticated web URL 404s only because the repo is private)

**Validation Test:**

- **Setup:** Push access to the repo; working tree committed.
- **Steps:**
  1. Rename the repo on GitHub.
  2. Update the local remote and run `git fetch`.
  3. Open the old `github.com/hcho/FitSnack` URL in a browser.
- **Expected Result:** `git fetch` succeeds against the new remote; the old URL redirects to `hcho/reptoday`.
- **Failure Indicator:** `git fetch` fails with a 404, or the old URL 404s instead of redirecting.

### US-009: Final rebrand verification (whole-repo guard)

**Description:** As the owner, I want a single guard proving no "FitSnack" token remains anywhere it shouldn't, so the rebrand is provably complete before going public.

**Acceptance Criteria:**

- [ ] `grep -rn "FitSnack\|com.fitsnack\|iCloud.com.fitsnack" ios proxy CLAUDE.md README.md` returns nothing (excluding `build/` artifacts and `.claude/agent/tasks/` historical files)
- [ ] `xcodegen generate` + full build + 655-test suite all pass
- [ ] App boots in the Simulator; under-icon name is "Rep Today"; CloudKit mirroring sets up (or falls back local-only) with `RepToday.sqlite` present
- [ ] A sandbox purchase/restore against `com.reptoday.app.premium.*` works

**Validation Test:**

- **Setup:** All prior stories merged.
- **Steps:**
  1. Run the guard grep above.
  2. `xcodegen generate`, build, and `test` on the `iPhone 16` Simulator.
  3. Launch, complete onboarding + a session, open the paywall and purchase/restore.
- **Expected Result:** Grep is empty; all tests pass; the app presents as "Rep Today" end-to-end; store files and product ids all carry `RepToday` / `com.reptoday.app`.
- **Failure Indicator:** Any lingering `FitSnack`/`com.fitsnack` token outside the allowed historical paths, a test failure, or a runtime reference to the old container/product ids.

## Functional Requirements

- FR-1: The bundle identifier must be `com.reptoday.app` and the test bundle id `com.reptoday.app.tests`.
- FR-2: The CloudKit container must be `iCloud.com.reptoday.app` in both the entitlements file and `PersistenceController.cloudKitContainerIdentifier`.
- FR-3: StoreKit product ids must be `com.reptoday.app.premium.monthly` / `.yearly`, identical in `SubscriptionPlan.swift` and the `.storekit` config.
- FR-4: The Keychain service key must be `com.reptoday.app.auth`.
- FR-5: `CFBundleDisplayName` must be explicitly set to `Rep Today` (with a space).
- FR-6: The Swift module/target/scheme/folders must be `RepToday`, and every `@testable import` must reference `RepToday`.
- FR-7: The CoreData model, container name, and store files must be `RepToday`; entity class names (`CD*`) must remain unchanged.
- FR-8: No user-facing string may contain "FitSnack".
- FR-9: `CLAUDE.md`, `README.md`, and `proxy/` must be rebranded, including file-path references.
- FR-10: The dated files under `.claude/agent/tasks/` must remain unchanged.

## Non-Goals (Out of Scope)

- Setting the App Store Connect *listing* name ("Rep Today, Rest Tomorrow") - that is App Store Connect metadata, not a repo change.
- Renaming or rewriting the dated PRD/task-brief files under `.claude/agent/tasks/` (historical snapshots).
- Renaming CoreData entity classes (`CDUser`, `CDWorkoutLog`, `CDSessionPolicy`, `CDActiveSession`).
- Creating the App Store Connect record or configuring signing (`DEVELOPMENT_TEAM` stays empty; provisioning is a separate pre-submission task).
- Authoring the real privacy-policy page/content (only the placeholder token is de-branded here).
- Any new product features or behavior changes - this is a rename only.

## Technical Considerations

- **Ordering / dependencies:** US-001 gates US-004. US-002 (structure) and US-003 (CoreData) should land before US-005/US-006 because the folder move invalidates old paths. US-004 can run once the structure exists.
- **CoreData is the riskiest step.** The model name, `NSPersistentCloudKitContainer(name:)`, the momd resource lookup, and the store filenames must all agree, or the app traps at launch. Safe only because there are no users; local/simulator stores reset.
- **`build/` is gitignored** - those `FitSnack.*` artifacts are regenerated by `xcodegen`/`xcodebuild` and need no manual edit.
- **Two identical StoreKit id lists** (`SubscriptionPlan.swift` + `.storekit`) must be edited together or purchases silently fail.
- No `CONTEXT.md`/ADR is warranted: a product rename is not a domain-glossary term, and the identifier choices are obvious given the brand.

## Success Metrics

- Whole-repo guard grep for "FitSnack"/"com.fitsnack" returns zero matches outside `build/` and `.claude/agent/tasks/`.
- 655/655 tests pass under the `RepToday` module.
- App boots and presents as "Rep Today" end-to-end (icon label, Health prompt, paywall) with `RepToday.sqlite` and `com.reptoday.app.premium.*` in use.
- Every permanent identifier is anchored to `com.reptoday.app` before the first submission.

## Open Questions

- ~~Is `reptoday.com` actually available/owned? If not, what is the fallback reverse-DNS root (blocks US-004)?~~ **Resolved (US-001, 2026-07-14):** registered and purchasable via HugeDomains ($3,895), purchase deferred; reverse-DNS root locked as `com.reptoday.app` regardless (Apple does not verify domain ownership). US-004 is unblocked.
- What is the real privacy-policy URL to replace the placeholder in `PaywallView.swift`?
- Confirm `CFBundleDisplayName` should be "Rep Today" (space) while the App Store listing name is the fuller "Rep Today, Rest Tomorrow".
