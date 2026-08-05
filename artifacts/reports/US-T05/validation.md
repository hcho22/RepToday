# US-T05 Validation - anonymous per-install identity

**Story:** US-T05 of `.claude/agent/tasks/prd-funnel-instrumentation_260803.md` - a random per-install identifier plus `firstLaunchAt` / `lastActiveAt` on `AppState`.
**Date:** 2026-08-04
**Verdict:** PASS. The PRD's whole Validation Test was run against the real Debug app installed on a Simulator, plus three probes it does not ask for.

> **Read this first.** This is a point-in-time transcript and **nothing re-runs it.** Every step below was driven by hand against a Simulator; this repository has no CI and no automated check of any kind runs against a pull request, so nothing revalidates any of it on a later change. The one gate that does re-run, and only when someone runs it, is `xcodebuild ... -scheme RepToday test`, whose `AppStateTests` model a reinstall as a wiped `UserDefaults` suite rather than as an actual uninstall - so none of the three probes below is re-checked by anything, ever. Reading this file as a standing guarantee would be reading it wrong: it says what was true at commit `3e8bc8b`, and nothing more. That is the same status as `artifacts/reports/US-T03/validation.md`, for the same reason. `Utilities/AppState.swift` has not been touched since `69c858f`, two commits before the run, and the only source change after it is a doc comment - so the run does cover the implementation as it stands, which is a fact about this branch today rather than a property that holds itself.

---

## How the values were read

| | |
|---|---|
| Device | iPhone 16 Simulator, `27C7F91C-0186-4F8A-9F8E-DE9F0A69FFAA` |
| Bundle | `com.reptoday.app`, Debug build, installed and launched |
| Source of every value below | the app container's own `Library/Preferences/com.reptoday.app.plist` |

Nothing in this file is a unit-test assertion.
These are the values the installed app actually wrote to disk, read back out of its own container after each launch.
The run's raw transcript is not committed; the blocks quoted below are verbatim from it, dropping only the launch PID lines and eliding each container path's `/Users/…/CoreSimulator/Devices/<UDID>/data` prefix.
Every key the plist held at each stage is shown, so the absences below - no `firstLaunchAt` on the upgrade path, no `firstLaunchUnknown` on a genuine first launch - are absences in the file rather than omissions here.

---

## 1. The PRD's Validation Test - install, relaunch, delete and reinstall

| Stage | `AppState.installId` | `AppState.firstLaunchAt` | `AppState.lastActiveAt` |
|---|---|---|---|
| 1. fresh install, first launch | `902676E9-2278-4CFE-871C-EEB9BC508A55` | 2026-08-04 23:41:27Z | 2026-08-04 23:41:27Z |
| 2. force-quit + relaunch | same | same | 2026-08-04 23:41:**34**Z (moved) |
| 3. delete app + reinstall | `94705D88-344E-4C51-BCD4-88201436C0B4` (**new**) | 2026-08-04 23:41:**42**Z (**new**) | 2026-08-04 23:41:42Z |

```
### STAGE: 1 - FIRST LAUNCH (fresh install)
# data container: .../Containers/Data/Application/C1A225B4-7A8E-4D6F-B76F-9C081474BE9A
  "AppState.firstLaunchAt" => 2026-08-04 23:41:27 +0000
  "AppState.installId" => "902676E9-2278-4CFE-871C-EEB9BC508A55"
  "AppState.lastActiveAt" => 2026-08-04 23:41:27 +0000

### STAGE: 2 - RELAUNCH (same install)
# data container: .../Containers/Data/Application/C1A225B4-7A8E-4D6F-B76F-9C081474BE9A
  "AppState.firstLaunchAt" => 2026-08-04 23:41:27 +0000
  "AppState.installId" => "902676E9-2278-4CFE-871C-EEB9BC508A55"
  "AppState.lastActiveAt" => 2026-08-04 23:41:34 +0000

### STAGE: 3 - REINSTALL (deleted, installed again)
# data container: .../Containers/Data/Application/B2B6FC81-CB2C-4A07-AB73-B14944D4BFD7
  "AppState.firstLaunchAt" => 2026-08-04 23:41:42 +0000
  "AppState.installId" => "94705D88-344E-4C51-BCD4-88201436C0B4"
  "AppState.lastActiveAt" => 2026-08-04 23:41:42 +0000
```

That is the PRD's Expected Result on each of its three launch claims: the first launch sets all three values, the relaunch preserves the id and the origin and moves only `lastActiveAt`, and the reinstall produces both a new id and a new origin.
Its fourth claim, about `install_week`, is qualified below rather than claimed here.
The data container's own UUID is unchanged between stages 1 and 2 and different in stage 3 (`C1A225B4-…` -> `B2B6FC81-…`), which is iOS having allocated a fresh container for a fresh install - so stage 3 is a real uninstall rather than a cleared key.
No `AppState.firstLaunchUnknown` key is written on a genuine first launch - the marker is absent from all three stages, which is what distinguishes them from the upgrade path in section 4.

**One part of the Expected Result was not read off disk, and is not claimed to have been.**
`installWeek` is a computed property, so it is nowhere in the plist; the PRD's "`install_week` matches `ConsistencyScore.startOfWeek(firstLaunchAt)`" is asserted in `AppStateTests` against the helper directly, not here.
What this run does establish about the cohort is one consequence of the observed origin: 2026-08-04 23:41:42Z is Tue 2026-08-04 16:41 Pacific, whose Sunday-start Pacific week begins 2026-08-02 00:00 - strictly behind the launch, so no precise install time is recoverable from the week the install cohorts into.

---

## 2. Nothing survived the uninstall - and a control hit proving the search worked

After the app was deleted in stage 3, the **entire** simulated device was searched binary-safe - every app container, `Library/Keychains/keychain-2-debug.db` and its write-ahead log, caches, the lot - for both identifiers:

```
-- install #1 id 902676E9-2278-4CFE-871C-EEB9BC508A55 (its app was deleted):
   NO FILE ON THE DEVICE STILL CONTAINS IT
-- install #2 id 94705D88-344E-4C51-BCD4-88201436C0B4 (current install, control):
   .../Containers/Data/Application/B2B6FC81-.../Library/Preferences/com.reptoday.app.plist
```

The control hit is the load-bearing half of this probe and is recorded deliberately: the same search, over the same device, with the same method, **did** find the live install's identifier, and found it in exactly one file - the app's own preferences, and no keychain.
So the absence of install #1 is a search that would have caught a survivor and did not, rather than a search that failed to look properly.

**What this proves, stated exactly.**
Nothing survived that uninstall, on that simulated device, at that moment.
It is **not** a general guarantee about every path an identifier could outlive an uninstall by, and in particular it does **not** disprove the backup caveat this branch's docs carry: `UserDefaults` lives in `Library/Preferences`, which **is** included in iCloud and iTunes backups and in device-to-device transfer, so an id can outlive an uninstall-then-restore and one id can end up live on two devices after a migration.
Those are different claims about different paths.
This probe covers the plain delete-and-reinstall path only; no restore was exercised here at all.
The honest guarantee remains "dies with the app **absent a backup restore**", as `docs/implementation-log.md`, `docs/test-coverage.md`, and the US-T05 criterion annotation all state.
The reason `UserDefaults` is still the right storage is unchanged by either claim: the Keychain survives a plain uninstall with **no restore involved**, and that is the gap this probe measures.

---

## 3. A resume is not a cold launch

`lastActiveAt` is documented as moving on a cold launch only, because `init` is its only writer and `AppState` is constructed once per process.
Backgrounding Rep Today (by launching Settings) and resuming it left the value untouched:

```
### A1 - app in the foreground
  "AppState.firstLaunchAt" => 2026-08-04 23:41:42 +0000
  "AppState.installId" => "94705D88-344E-4C51-BCD4-88201436C0B4"
  "AppState.lastActiveAt" => 2026-08-04 23:45:13 +0000

### A2 - after backgrounding and resuming (lastActiveAt must NOT move)
  "AppState.firstLaunchAt" => 2026-08-04 23:41:42 +0000
  "AppState.installId" => "94705D88-344E-4C51-BCD4-88201436C0B4"
  "AppState.lastActiveAt" => 2026-08-04 23:45:13 +0000
```

That is the install stage 3 left behind, still carrying its own id and origin, and neither of those moved either.
The next *cold* launch did move `lastActiveAt`.
That is the behaviour the third review round (`69c858f`) corrected the comments and docs to describe, observed here rather than reasoned about.

---

## 4. The upgraded install, on a real install rather than a wiped suite

The state that matters most at launch is an install that already existed when this build shipped: onboarded, but with no `AppState.installId` and no `AppState.firstLaunchAt` on disk.
It was reproduced by shutting the simulator down first - so `cfprefsd` had flushed and could not serve a cached copy back to the app - rewriting this app's preferences into that pre-US-T05 shape, then booting and launching the real app.

Every key on disk at each stage, verbatim:

```
### B1 - AFTER the rewrite: what an older build leaves behind (onboarded, no identity)
  "AppState.isOnboarded" => true
  "AppState.lastActiveAt" => 2026-08-04 23:46:00 +0000

### B2 - FIRST LAUNCH ON THE NEW BUILD (mints an id; refuses to fabricate an origin)
  "AppState.firstLaunchUnknown" => true
  "AppState.installId" => "E2912DAC-20FA-4958-908E-55EBED2B8BBC"
  "AppState.isOnboarded" => true
  "AppState.lastActiveAt" => 2026-08-04 23:46:51 +0000

### B3 - RELAUNCH (the id must NOT be re-minted, and the unknown origin must NOT be backfilled)
  "AppState.firstLaunchUnknown" => true
  "AppState.installId" => "E2912DAC-20FA-4958-908E-55EBED2B8BBC"
  "AppState.isOnboarded" => true
  "AppState.lastActiveAt" => 2026-08-04 23:47:02 +0000

installId minted on the upgrade launch : E2912DAC-20FA-4958-908E-55EBED2B8BBC
installId after the next cold launch   : E2912DAC-20FA-4958-908E-55EBED2B8BBC
STABLE - one identity across launches
```

`firstLaunchAt` is absent from B2 and B3, which is the point: no origin was invented from the upgrade date.
`lastActiveAt` moving between B2 and B3 is the same cold-launch write section 3 covers, and is what makes B3 a second launch rather than a re-read of the first.

So an upgraded install mints an identity without fabricating an origin out of the upgrade date, and - because the unknown is persisted as its own marker rather than inferred from the missing pair - it does not re-mint that identity on every launch.
This is the behaviour the review rounds added - `d9091b1` distinguishing an upgraded install from a first launch and persisting the unknown as its own marker, `2c53ef9` narrowing the rule so a usable stored origin is kept - verified here against a real installed binary instead of the wiped `UserDefaults` suite the unit tests model it with.

`04-upgraded-install.png` shows that install presenting the Health Access permission prompt rather than the onboarding welcome screen the three launch screenshots show: an existing user was not sent back through onboarding.
That is the user-visible half of this launch state - `isOnboarded == true` with no stored id is the discriminator that makes `isFirstLaunch == false`, and this is what it looks like from the user's side.
Its status bar reads 4:47, which is 16:47 Pacific and places it at the B3 relaunch (23:47:02Z) rather than the B2 upgrade launch (23:46:51Z).

---

## 5. Screenshots - and why only one is committed

`01-first-launch.png`, `02-relaunch.png` and `03-reinstall.png` are **byte-identical**: all three are 164,033 bytes with md5 `ddd4ab10ea5517ed39e3d9a6c8c6cd1b`, all three showing the same onboarding welcome screen.
None of them is committed, because three copies of one image are three copies of one image.
That identity is the honest result rather than a failed capture: this story adds no user-visible surface at all, so minting, reading and re-minting the identity being invisible is exactly what a correct implementation looks like from the outside.
Only `04-upgraded-install.png` is committed, because it is the one frame where the screen actually differs and the difference means something.
Unlike the images the evidence suites write under `artifacts/reports/<story>/`, all four were captured by hand off the running Simulator: no test renders them, so no `REPTODAY_WRITE_EVIDENCE=1` run regenerates the committed one and it cannot drift into a diff on its own.

---

## The unit suite alongside it

The full `RepTodayTests` suite was run green on an iPhone 16 Simulator via `xcodebuild ... -scheme RepToday test` in the same pass: the run reported **848 tests, 0 failures**.
That count is recorded here because this file is a transcript of one run and a transcript may say what the run said.
It is deliberately **not** carried into the PRD's acceptance annotation, which states its own reason: a tally in prose goes stale the next time a test is added and then misreports what was run.

---

## What this record does not establish

- **Any restore path.** Only a plain delete-and-reinstall was exercised. See the cross-reference in section 2.
- **A real device, or a real App Store install.** Everything above is a Simulator with a Debug build. Entitlement-gated paths behave differently on hardware, though nothing in this story touches one.
- **Anything on a wire.** `installId` reaches no request body until US-T04, and nothing in production reads `isFirstLaunch` or `installWeek` until US-T07. This file is about what gets written to disk and what does not survive an uninstall, and about nothing else.
- **Any future commit.** Point-in-time, nothing re-runs it, no CI. See the note at the top.
