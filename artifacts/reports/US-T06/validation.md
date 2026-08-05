# US-T06 Validation Test - opt-out consent flag, Settings toggle, onboarding disclosure

**Story:** `.claude/agent/tasks/prd-funnel-instrumentation_260803.md`, `### US-T06`.
**Date:** 2026-08-05.
**Setup:** Debug build of the real app, iPhone 16 Simulator (`32039CCE-BE1D-4233-A4D4-19CA9428DBF3`, iOS 18.6), deleted and reinstalled first so `UserDefaults` was clean.
The build's `RepTodayAnalyticsEndpoint` was read out of the installed bundle rather than assumed: `https://courteous-dogfish-560.convex.site`, the dev deployment.
The `events` table was read with `npx convex data events` against that same deployment, which is the dashboard's contents rather than a screenshot of it.

**Outcome: run, PASS - and re-framed, the same way US-T04 re-framed its own.**

## Why the test as written cannot be run, and what stood in for it

Steps 2 and 4 say "start a session and confirm events land in Convex".
That cannot be done against the shipped build, and this story did not make it possible: **nothing in the app calls `record(_:)`**, and adding an emission site would be US-T07 through US-T12's scope landing here.
So the legs that needed a real emission were driven by the committed Debug harness (`TelemetryUITestHarness`, `-RepTodayTelemetryProbe YES`), which emits one `app_install` from `RepTodayApp.init()` - the exact name and the exact place US-T07's first real emission will use - plus, for the live legs only, a **temporary one-line edit** that let the probe reach the real deployment instead of the harness's in-process interceptor.
That edit was reverted before the commit, along with two throwaway XCUITest drivers used to walk the app; `git status` was checked clean of them afterwards.

**What the live legs therefore prove:** that the opt-out flag decides whether a real POST reaches a real Convex deployment.
**What they do not prove:** that the shipped build emits anything. It does not, by design, until US-T07.

## Steps and observations

### 1. The disclosure appears in onboarding, with a privacy-policy link

Fresh install, plain launch. The first onboarding screen carries, below the Sign in with Apple block:

> Rep Today collects anonymous usage data to see whether it's working - you can turn that off anytime in Profile, under Settings.

and a `Privacy Policy` link beneath it.
Render: `01-onboarding-disclosure.png`.

It sits on the **first** screen rather than the last on purpose: the first event the app will emit hangs off app entry (US-T07's `app_install`), so a disclosure at the end of onboarding would arrive after the thing it discloses.

Onboarding *completing* was not re-walked by hand here - `OnboardingImperialUITests.testImperialAnswersCarryThroughOnboardingToAReadySession` walks the whole flow to a ready session in the real app and passes on this branch, which is a stronger check than a manual pass would have been.
That is stated rather than glossed: this leg confirms the disclosure is on the screen where it lands, not that a human completed the flow around it.

The app's own preferences plist after that first launch:

```
"AppState.firstLaunchAt" => 2026-08-05 14:13:37 +0000
"AppState.installId"     => "21F29912-CD04-495A-B18F-A4B45B280F1F"
```

`AppState.analyticsEnabled` is **absent**, which is the point of the read: the flag is not written until the user answers, and absence resolves to opted *in*.
A naive `bool(forKey:)` would have read that same absence as opted out and shipped every install silent.

### 2. With telemetry on (the default), an event reaches Convex

Rows in `events` carrying this install's id, before: **0**.

Launch with `-RepTodayTelemetryProbe YES` and no consent argument (so the shipped default applies). After ~8s:

```
clientTs      | installId                              | name         | props
1785939250436 | "21F29912-CD04-495A-B18F-A4B45B280F1F" | "app_install"| { "install_week": "probe" }
```

One row, carrying the installed app's own `installId` read out of its own plist - not a test double.

### 3. With telemetry off, nothing lands

Same launch plus `-AppState.analyticsEnabled NO`. After 12s, rows for this install: still **1**. No new row.

That is the launch-argument path, which is the one an out-of-process test can reach: `UserDefaults` reads the argument domain ahead of the persisted one, so the argument closes the same gate the Settings toggle writes.

### 4. Toggling off and back on in Settings, with no restart

Driven through the real UI - Profile tab -> Settings row -> the switch - against the live deployment, in one launch, with no relaunch anywhere in the sequence:

| step | telemetry | new row in Convex |
|---|---|---|
| app entry | on (default) | yes - `clientTs 1785939342314` |
| tap "Emit probe" | on | yes - `clientTs 1785939353561` |
| toggle **off** in Settings, tap "Emit probe" | off | **no** |
| toggle back **on**, tap "Emit probe" | on | yes - `clientTs 1785939375843` |

Three rows for four emission attempts, and the missing one is the attempt made while the toggle was off.
The ~22s gap between the second and third rows is the toggle-off, the swallowed attempt, and the toggle-on.

Renders of the surface this was driven through: `02-profile-settings-row.png`, `03-settings-privacy-toggle-off.png` (launched opted out - the toggle shows the real stored state, not a default-on), `04-settings-privacy-toggle-on.png`.

Those last two Settings renders were **refreshed at the branch tip**, under the same launches, after the consent copy moved from a row inside the card to the section footer, so they show what ships rather than the layout the original run photographed; the observation they illustrate is unchanged.

### 5. Cleanup

All four probe rows were deleted from the dev deployment afterwards, by a scratch `internalMutation` deployed, run, deleted, and redeployed away - the same treatment US-T03 and US-T04 gave their own junk rows.
`npx convex data events` reports 0 rows for this install id, and `git status convex/` is clean.

## Expected Result vs. what happened

| Expected | Observed |
|---|---|
| The disclosure appears in onboarding | Yes, on the first screen, with the privacy-policy link |
| With the toggle on, events land | Yes - one row per emission, carrying the app's own `installId` |
| With the toggle off, **no** new rows appear for that install | Yes - zero new rows, by launch argument and by the in-app toggle |
| The app behaves identically | Yes - no error, no delay; the gate returns before any task, encode, or request is created |
| Toggling back on resumes emission without a restart | Yes - all four legs in step 4 happened in one app launch |

**Failure Indicator, checked:** no event landed while the toggle was off; the toggle is reachable (Profile -> Settings, asserted hittable) and labelled ("Share anonymous usage data"); the disclosure is present; nothing needed a restart.

## What re-runs, and what does not

This transcript is a point-in-time record. This repo has **no CI**, so nothing here re-runs by itself.

What *is* re-runnable is `RepTodayUITests/TelemetryOptOutUITests`, which asserts the same gate out of process without touching the network (the harness's interceptor is in place there, so FR-13 holds).
Its honesty was checked twice, by breaking each thing it protects and confirming it fails.

**Sabotage 1 - the gate.** With `isEnabled: analyticsGate` replaced by `isEnabled: { true }` in `ServiceContainer.live(...)`, three of the suite's tests fail:

```
testTelemetryOffMeansTheAppDispatchesNothing: ("1") is not equal to ("0") -
  the app tried to send telemetry while the user was opted out
testTogglingTelemetryOffAndOnIsHonouredWithoutARestart: ("3") is not equal to ("2") -
  an event was sent after the user turned telemetry off
testRendersTheConsentSurfacesAndTheGateChangingTheCount: ("3") is not equal to ("2") -
  an event was sent after the user turned telemetry off
```

and all three pass again once the gate is restored.
That is the answer to "would this test pass for reasons that have nothing to do with the flag": it would not.

**Sabotage 2 - the launch guard, and this one failed the first time.** Every launch in the suite must carry one of two guards: consent pinned off, or the probe harness armed (which intercepts the transport in process). The guard was first written as a single `tearDown` assertion over the app's final `launchArguments`. Re-injecting the original defect - the render leg opening with a raw, unguarded `app.launchArguments = ["-AppState.isOnboarded", "NO"]` - **passed**, because that test launches twice and the second, guarded launch overwrites the arguments the first one set, so teardown finds a guarded array and reports nothing. The net could not see the very bug shape it was written for.
It is now checked on **entry to every launch** as well as at teardown, against a record of what the helper itself last wrote, so a raw launch before, between, or after a helper launch is all caught. Re-injecting the same defect now fails:

```
testRendersTheConsentSurfacesAndTheGateChangingTheCount: XCTAssertTrue failed -
  a launch in this suite bypassed `launch(_:onboarded:)` and carried neither telemetry
  guard: ["-AppState.isOnboarded", "NO"]
```

That first failure is recorded rather than quietly fixed, because it is the whole argument for running the check: a safety assertion nobody breaks on purpose is indistinguishable from one that cannot fail.

**Sabotage 3 - the launch guard's empty-arguments hole, and this one also corrected the check before it caught anything.** A review round pointed out that the guard above only inspects a *non-empty* `launchArguments`, so the simplest bypass of all was invisible: a bare `app.launch()` with no arguments set at all leaves the array empty, and neither the entry check nor the teardown check fires - yet that launch builds the real transport against the dev deployment with the gate at its shipped default (on). The check now treats "arguments empty **and** the app is running **and** the helper wrote nothing" as a bypass, and its doc comment writes down the complete space of observable launch states as an enumeration, so a new bypass shape can be tested against it rather than re-derived.

Adding that condition alone made **all five** tests in the suite fail immediately, before any launch, on entirely unmodified test bodies:

```
testTelemetryOffMeansTheAppDispatchesNothing (failed in 0.099s): XCTAssertTrue failed -
  a launch in this suite bypassed `launch(_:onboarded:)` and set no launch arguments at
  all, so it carried neither telemetry guard.
```

The condition was wrong, not the tests: `XCUIApplication` is rebuilt per test case but the **app process is not**, so a leftover from the previous test made `app.state` report running before this test had launched anything. `setUp` now terminates any such leftover, which is what makes "the app is running" mean "something in *this* test started it" - the precondition the enumeration rests on, found by observing the failure rather than by reasoning about `app.state`.

With that precondition established, injecting a bare `app.launch()` at the top of `testTelemetryOffMeansTheAppDispatchesNothing` fails as intended:

```
TelemetryOptOutUITests.swift:114: error: XCTAssertTrue failed - a launch in this suite
  bypassed `launch(_:onboarded:)` and set no launch arguments at all, so it carried
  neither telemetry guard. Every launch must either pin consent off
  (-AppState.analyticsEnabled NO) or arm the probe harness (-RepTodayTelemetryProbe YES),
  which intercepts the transport in process. [...] Launch through `launch(_:onboarded:)`
  and name a `TelemetryPosture`.
Executed 1 test, with 1 failure (0 unexpected) in 5.483 seconds
```

Removing the injected line returns the suite to 10/0.
**What this guard still does not do:** it *detects* a bypass rather than *preventing* one - a raw launch written into a future test still compiles. The structural answer is a wrapper making a raw `XCUIApplication` unreachable from tests; it is deferred with a named trigger on US-T07's criteria, which is where this guard starts protecting real emissions rather than a hypothetical.

**What that re-runnable suite does not prove:** it counts at the `URLProtocol` boundary inside the app, so an attempt means the transport built and dispatched a request, not that bytes reached Convex - that half is what the live legs above are for, and they do not re-run.
It also says nothing about a Release build, which compiles none of the harness and today has no configured endpoint at all.

## Documentation sweep

Every prose-bearing artefact this branch touches, plus every file in the repo naming US-T06 or the seams this story changed, was swept for two things: prose gone stale, and prose claiming a stronger guarantee than the code delivers.

**32 checked, 22 touched (15 edited, 7 written new), 10 verified accurate and left alone.**

Edited because they described US-T06 as not-yet-landed, or over-claimed: the PRD's status header and its US-T04 / US-T07 cross-references, `AGENTS.md`'s telemetry paragraph and two of its pointers, `docs/implementation-log.md` (the US-T04 stub-then-connect sentence and the out-of-process one), `docs/test-coverage.md`'s `CoreDataServicesTests` and `LiveAnalyticsServiceTests` rows, `ServiceContainer.live`'s doc, `LiveAnalyticsService`'s `isEnabled` doc and the gate comment in `record(_:)`, `PaywallView`'s legal-links doc, and the doc comments in `AnalyticsServiceTests` and `LiveAnalyticsServiceTests` that spoke of US-T06 in the future tense.

Left alone after checking: `CoreDataServicesTests`' header (already accurate), `ServiceProtocols.swift`, `NoOpAnalyticsService`, `AnalyticsWireBody`, `AnalyticsEvent`, `project.yml`, `convex/README.md` (all still true - "nothing calls `record(_:)`" remains the case), and the US-T03/T04/T05 validation transcripts, which are point-in-time records this repo deliberately does not rewrite.

## Test runs on this branch

Local runs only - this repo has no CI, so no PR check gates any of it.

- `xcodebuild -scheme RepToday test` (iPhone 16, 18.6): **879 tests, 0 failures** (863 before this story).
- `xcodebuild -scheme RepTodayUITests test` (same device): **10 tests, 0 failures** (5 before this story).

Those counts are from the branch tip after the review rounds, not from the original commit; the live legs above were run against the original commit, which is why they are reported separately.
