# K8 Wedge-Comprehension Coding Rubric (pre-registered)

The instrument for K8, the qualitative kill signal defined in `investment-thesis.md` (§5, lines 206-210): *the wedge fails to be perceived.*
This document is the written coding rubric that thesis line 207 requires "drafted and frozen before the first TestFlight session," and thesis §6 step 1 (line 253) requires frozen *first*, before any moderated cohort is recorded.
It operationalizes the thesis's pre-registered thresholds into concrete, observable coding criteria against RepToday's actual first-run UI.
It does not set, move, or reinterpret any threshold: every number below is copied in meaning from the thesis and cited to its line, and the thesis remains the source of truth if the two ever disagree.

## Pre-registration header

**What K8 measures:** whether a first-time user perceives the wedge - "Open the app. The workout is already there." (`gtm/03-site/index.html`, `gtm/02-brand/positioning.md`) - *without explanation*: they see the ready session, understand nothing is being asked of them, and start it, and when asked to describe the app unprompted they reach for some version of "it's already ready when you open it."
The kill signal is the inverse: first-time users hunt for a workout list, scroll for a browse screen, or ask where to pick a workout, and/or their unprompted descriptions do not mention the ready-on-open behavior.

**Why pre-registration is load-bearing here:** a rubric written or adjusted after the data arrives can be tuned to produce whichever verdict is wanted, so the thresholds and coding rules must be fixed before the first observed run exists (thesis line 209: "the point of pre-registering them is that they are fixed before any data arrives").
Freezing this document is therefore a precondition for running the moderated cohort, not a deliverable of it.

```
Frozen on:        [DATE - fill at freeze time, before the first TestFlight session]
Pre-registered by: [CAPTAIN sign-off]
Coder:            [CAPTAIN TO FILL - a named person who is not the founder]
```

The `Coder` line mirrors the thesis's own `[FOUNDER TO FILL: name of the non-founder coder]` placeholder on line 207 and must be filled with the same named non-founder before coding begins.
This rubric is authored to be locked; once `Frozen on` carries a date, no criterion, definition, decision rule, or threshold in it may change for the cohort it governs.

## Unit of analysis

**One observed first run** = one first-time user's first session with the app, from the moment the app is installed/opened through either their first `Start` press or their disengagement from the first-run flow, whichever comes first, plus (when available) their single unprompted one-sentence description of the app.
A "first run" is the user's genuine first exposure: a re-recording of someone who has already seen the app is not a first run and is not coded.
The two thesis thresholds read from two overlapping-but-distinct pools drawn from these runs - the behavioral pool (every coded first run) and the description pool (every run that also yields an unprompted one-sentence description) - and are aggregated separately (see "Pre-registered aggregate thresholds").

## The actual first-run flow being coded

The coded behaviors are defined against RepToday's real UI, not a hypothetical one - read `ios/RepToday/RepToday/Views/RootView.swift` and `ios/RepToday/RepToday/Views/Ready/ReadyView.swift` for the ground truth.

1. **Onboarding** (`Views/Onboarding/OnboardingView.swift`): six steps - Welcome, Basics, Fitness level, Why, Lifestyle, Duration - ending in a primary button labeled **"Start moving."**
   Completing it saves the user, seeds the cold-start policy, and flips the router into the main tabs.
   Onboarding is *setup*, not the wedge; it is coded only for context (see edge cases), not as list-hunting.
2. **The Ready Screen** (`ReadyView`, the "Today" tab, opened automatically on `house.fill`): the wedge surface.
   It renders, top to bottom: a greeting ("Ready when you are[, name]."), **"Today: X min"**, a one-line variety subtitle, an optional Resume card / Consistency card / policy note, a horizontal row of **duration chips** (5 / 10 / 15 / 20 / 30 / 45 / 60 min), the session itself as **block cards** (warm-up / training / cooldown, each listing its prescribed exercises and targets), and a pinned, dominant **"Start"** button at the bottom that is always present and enabled.
3. **The three tabs**: Today (the Ready Screen), Progress (`chart.line.uptrend.xyaxis`), Profile (`person.crop.circle.fill`, a placeholder plus a Settings row).

**Crucial UI fact that defines "hunting":** RepToday has **no workout list, no catalog, no browse screen, and no workout picker anywhere.**
The duration chips resize *time* and regenerate the one session in place; they are not a menu of workouts.
So "hunting for a workout list" cannot mean opening a list that exists - it can only be coded as the *searching behaviors a user performs when they expect a list this app does not have.*
Those concrete behaviors are enumerated in the coding criteria below.

## Per-run coding criteria

The coder marks each observable behavior below for each run.
Each behavior has a definition and a decision rule written so two coders watching the same run reach the same mark.
Behaviors B1-B4 are the **hunting behaviors** the thesis kill threshold counts (line 209); B5 is the comprehension behavior; B6 is time; B7 is the unprompted description.

### B1 - Hunting for a workout list

**Definition:** the user acts as though a list or catalog of selectable workouts should exist and looks for it.
**Coded present when any of these concrete acts occurs** on the Ready Screen (or via the tabs) *before the user's first `Start` press*:
- **pull-to-refresh** (or repeated downward tug at the top of the Today scroll) apparently expecting a different or additional session to load;
- **scrolling past the last block card** and continuing to scan/flick, apparently expecting more sessions or a list to appear below the single session (distinguish from reading: a read scrolls through the blocks once and stops; hunting keeps going past the end looking for more);
- **tapping an exercise row** expecting it to open a library, catalog, or "choose a different exercise" screen (the rows are inert previews on the Ready Screen);
- **switching to the Progress or Profile tab, or opening Settings, in search of where to choose/browse a workout** (not for that tab's own purpose - see decision rule).

**Decision rule:** mark B1 present if at least one of the above occurs and the user's evident goal is *finding a workout to select* (shown by the act itself and any accompanying verbalization).
A tab switch is B1 only when it is a search for workout selection; a tab switch to genuinely look at Progress or Settings for their own sake is **not** B1.
When intent is unclear from action alone and the user says nothing, apply the silent-run rule under "Coding decision rules."

### B2 - Scrolling/searching for a browse screen

**Definition:** the user searches the app's navigation for a "browse workouts" surface - a narrower, navigation-specific case of the same expectation as B1, called out separately because the thesis names it separately (line 209).
**Coded present when:** the user methodically visits tabs/menus/back-and-forth navigation apparently mapping the app for a browse/discovery area, or hunts for a search field or filter.
**Decision rule:** B2 is about *navigational search* for a browse area; B1 is about expecting a *list* on or below the current screen.
A single run can be marked for both if both patterns appear; for the kill numerator they are not double-counted (see "Coding scheme").

### B3 - Asking where to pick a workout

**Definition:** the user verbally asks (to the moderator, aloud to themselves in a think-aloud, or in a recorded comment) where to choose, pick, browse, or set up a workout.
**Coded present when:** an utterance of the form "where do I pick a workout?", "how do I choose the exercises?", "is there a list of workouts?", "where's the menu of sessions?", "do I build my own?" occurs *before* the first `Start` press.
**Decision rule:** the question must express an expectation of *selecting* a workout.
A question about *how to begin the shown session* ("do I just tap Start?", "is this it?") is **not** B3 - it is evidence of comprehension, not hunting (see B5 and the "is this it?" edge case).
Moderator-introduced framing does not count - see the contamination rule.

### B4 - Using the duration chips as a workout picker (ambiguous-intent hunting)

**Definition:** the user treats the duration chips as though they were a menu of *different workouts to pick from* rather than a *time* control.
**Coded present when:** the user cycles the chips while verbalizing a search for other/different *workouts* (not other durations), e.g. "let me see the other workouts" while tapping chips.
**Decision rule - default to not-hunting:** simply tapping one or more chips to change the session length is **normal engagement with the ready model and is NOT hunting** (it is B5-consistent).
B4 is marked *only* when chip use is explicitly a search for a workout catalog, shown by verbalization or by a clearly list-seeking pattern (rapidly cycling all chips scanning for something other than a time change, then continuing to hunt).
This behavior exists solely to prevent an ambiguous chip interaction from being silently miscoded either way; when in doubt, B4 is absent and the chip tap is comprehension-neutral.

### B5 - Recognizing and starting the already-ready session (comprehension)

**Definition:** the user engages the session that is already on screen without searching for a list/browse/picker.
**Coded present when:** the user reads or glances over the session (greeting, "Today: X min", blocks) and presses **`Start`** on the presented session - optionally after resizing time with a duration chip - without exhibiting B1-B4.
An explicit verbal recognition of ready-on-open ("oh, it already made one", "it's just ready", "I don't have to pick anything") strengthens B5 but is not required for it.
**Decision rule:** B5 present requires a `Start` press on the ready session with no preceding hunting behavior (B1-B4) in the same run.
If the user pressed `Start` *after* hunting (B1-B4 occurred earlier in the run), B5 is **absent** and the run is a hunting run (see the "eventually found Start" rule) - the wedge is about immediate perception, so an eventual Start does not erase earlier hunting.

### B6 - Time to first Start (or first meaningful engagement)

**Definition:** elapsed time from the Ready Screen first appearing to the user's first `Start` press.
**Coded as:** whole seconds, measured from the frame the Ready Screen first renders to the frame `Start` is pressed.
If the user never presses `Start`, record `no-Start` and note the terminal behavior (quit, kept hunting, handed device back).
**First meaningful engagement fallback:** for a run that never reaches `Start`, also record the time to the first deliberate act *on the ready session itself* (a duration-chip resize, or a clear read-and-consider) if one occurred, so a never-started run still carries a datum; this is descriptive context and does not enter either kill threshold.
B6 is a reported descriptive measure (faster is better-perceived) and, per the thesis, carries **no pre-registered threshold** - it is not a kill input, only color for the review.

### B7 - Unprompted one-sentence description mentions ready-on-open (yes/no)

**Definition:** when the user (or an early reviewer) describes the app *unprompted* in one sentence, does that description mention the ready-on-open behavior?
**Coded YES when** the description conveys that the workout is *already there / already made / ready when you open it / requires no choosing or setup* - any phrasing of the "it's ready when you open it" property, in the user's own words.
**Coded NO when** the description omits that property, even if accurate about other things: "quick bodyweight workouts", "a no-equipment fitness app", "five-minute exercises", "an offline workout app" are all **NO** unless they also convey the already-ready/no-choosing property.
**Coded N/A (not in the description pool) when** no unprompted description was produced, or the description was prompted/led by the moderator naming the behavior first (contamination - see rule).
**Decision rule:** "unprompted" is strict - the description must be volunteered, or given in response to a neutral "how would you describe this app?" that does not itself mention readiness, instantness, or picking.
A description the moderator steered toward the answer is N/A, not YES.

## Coding scheme (marks -> outcome categories)

Each coded first run resolves to exactly **one primary outcome category**, applied in this fixed priority order so two coders reach the same category:

| Priority | Primary category | Rule |
| --- | --- | --- |
| 1 | **Hunted for a list** | B1 present. |
| 2 | **Scrolled for a browse screen** | B2 present (and B1 absent). |
| 3 | **Asked where to pick** | B3 present (and B1, B2 absent). |
| 4 | **Comprehended** | B5 present and none of B1-B4 present. |
| 5 | **Inconclusive / no-engagement** | none of B1-B5 resolvable (e.g. a silent run with no Start and no hunting act) - see decision rules. |

B4 (chip-as-picker) when present is folded into "Hunted for a list" at priority 1, since it is a hunting behavior; when absent it has no effect.
A run can exhibit more than one hunting behavior; the priority order assigns it a single label for reporting, but for the **kill numerator a run counts once if it exhibits *any* of B1-B4** (it is a hunting run), never multiple times.

**The kill numerator** (the "hunting/scrolling/asking" set the thesis counts) = every run whose primary category is *Hunted for a list*, *Scrolled for a browse screen*, or *Asked where to pick* (equivalently: every run with at least one of B1-B4 present).
**Comprehended** and **Inconclusive / no-engagement** runs are **not** in the kill numerator.

**Tie-break for ambiguous or partial comprehension:**
- A run showing **any** B1-B4 hunting behavior is a hunting run for the numerator **even if the user eventually pressed `Start`** ("eventually found Start" - the earlier hunting is what K8 measures).
- A run where the user taps duration chips and presses `Start` with no list/browse/picker-seeking is **Comprehended**, not hunting - resizing time is not hunting (B4 default).
- A run where intent is genuinely unreadable and the user neither hunts (no B1-B4) nor starts (no B5) is **Inconclusive / no-engagement**, which per the literal thesis wording is *not* a hunting run and therefore *not* in the kill numerator (see the documented consequence under "Coding decision rules"); it still counts as one coded first run toward the ≥25 sample.

## Pre-registered aggregate thresholds (copied from the thesis - do not add or move any number)

These are the thesis's numbers, cited to their lines; this rubric operationalizes them and must not change them.

- **Behavioral kill:** K8 fires if **more than 50%** of rubric-coded first runs are hunting runs (show users hunting for a workout list, scrolling for a browse screen, or asking where to pick a workout).
  Source: `investment-thesis.md` line 209 ("more than 50% of rubric-coded first runs show users hunting for a workout list, scrolling for a browse screen, or asking where to pick a workout").
  Numerator = coded first runs in the kill numerator set (any of B1-B4); denominator = all rubric-coded first runs.

- **Description kill:** K8 fires if **fewer than 30%** of unprompted descriptions mention the ready-on-open behavior.
  Source: `investment-thesis.md` line 209 ("or fewer than 30% of unprompted descriptions mention the ready-on-open behavior").
  Numerator = descriptions coded B7 = YES; denominator = descriptions in the description pool (B7 = YES or NO; N/A excluded).

- **Either threshold firing fires K8** (the thesis joins them with "or" on line 209).
  Both thresholds are pre-registered founder priors with no external benchmark, fixed before any data arrives (line 209, `[ASSUMPTION]`).

- **Under-sampling:** if **25 observed first runs cannot be reached by the 90-day review, K8 is reported as under-sampled, not passed.**
  Source: `investment-thesis.md` line 210.
  "Under-sampled" is a named state distinct from pass and from fire; a sample below 25 runs is never reported as a pass, and the description-pool count is reported alongside it.

- **Severity context (not a threshold this rubric sets):** K8 is one of the two criteria whose firing is on its own a walk-away signal - "K1/K8 firing at all" is the walk-away line (`investment-thesis.md` line 237). This rubric does not adjudicate that; it only produces the coded inputs.

No number in this section may be edited without editing the thesis first; the thesis is authoritative.

## Protocol

- **Sample:** at least **25 observed first runs**, pooled across moderated TestFlight sessions and consented early post-launch recordings (`investment-thesis.md` lines 207, 253).
- **Coder:** a **named person who is not the founder**, recorded on the `Coder:` line above, matching the thesis's `[FOUNDER TO FILL: name of the non-founder coder]` (line 207). This rubric does not name the coder - `[CAPTAIN TO FILL - a named person who is not the founder]`.
- **Freeze timing:** this rubric is frozen **before the first TestFlight session / first cohort** (`investment-thesis.md` lines 207, 253); the `Frozen on` and `Pre-registered by` lines are completed at freeze time and not after.
- **Descriptions:** unprompted one-sentence descriptions are collected from beta users and early reviews (line 207) and coded per B7; they form the description pool, which may be larger or smaller than the behavioral pool.
- **Review point:** the counts are read at the 90-day review that governs the whole K1-K8 set; if the 25-run floor is unmet at that review, report under-sampled (line 210).

## Per-run coding sheet template

The coder fills one of these for each observed first run.

```
Run ID:              ____________________            Date observed: __________
Source:              [ ] moderated TestFlight   [ ] consented post-launch recording
Genuine first run?   [ ] yes  [ ] no (if no -> do not code)

Behavioral marks (mark present / absent for each):
  B1  Hunted for a list ................................ [ ] present  [ ] absent
        which act(s): [ ] pull-to-refresh  [ ] scrolled past last block
                      [ ] tapped exercise row for a catalog  [ ] tab/Settings for selection
  B2  Scrolled/searched for a browse screen ............ [ ] present  [ ] absent
  B3  Asked where to pick a workout .................... [ ] present  [ ] absent
        utterance: ______________________________________________________
  B4  Used duration chips as a workout picker .......... [ ] present  [ ] absent
  B5  Recognized & started the ready session .......... [ ] present  [ ] absent
        verbal recognition of ready-on-open? [ ] yes  [ ] no

Primary outcome (exactly one, by priority order):
  [ ] Hunted for a list   [ ] Scrolled for a browse screen   [ ] Asked where to pick
  [ ] Comprehended        [ ] Inconclusive / no-engagement

In kill numerator (any of B1-B4 present)?  [ ] yes  [ ] no

B6  Time to first Start: ______ s     [ ] no Start (terminal behavior: ____________)
      first meaningful engagement (if no Start): ______ s / [ ] none

B7  Unprompted one-sentence description:
      verbatim: ________________________________________________________________
      mentions ready-on-open?  [ ] YES  [ ] NO  [ ] N/A (none produced / prompted)

Coder notes / ambiguity flags: ____________________________________________________
```

## Coding decision rules / edge cases

- **Silent runs (no verbalization):** code from action alone.
  A user who reads the blocks and presses `Start` with no hunting act is **Comprehended** (B5) even without saying anything.
  A user who exhibits a clear hunting act (B1/B2) without speaking is still a **hunting run**.
  A user who neither hunts nor starts and says nothing is **Inconclusive / no-engagement** - do not guess intent to force it into a hunting or comprehended bucket.

- **Documented consequence of the literal threshold wording:** the thesis kill numerator (line 209) counts runs that *show hunting/scrolling/asking*, so an Inconclusive / no-engagement run is in the denominator but **not** the numerator - it lowers the failing ratio rather than raising it.
  This is the faithful reading of the pre-registered wording, not a choice this rubric makes; it is surfaced here so the captain can override it at freeze time if desired.
  Absent such an override before freeze, code it as written.

- **"Eventually found Start after searching":** a run with any B1-B4 hunting behavior is a hunting run even if the user later presses `Start`; the eventual Start is recorded in B6 but does not move the run out of the kill numerator.

- **"Is this it?" / confirmation questions:** a user asking whether the shown session is the whole thing, or whether they simply tap Start, is expressing *comprehension of a single ready session* (they see one session and are confirming there is nothing to pick) - this is **not** B3.
  B3 requires expecting to *select* a workout.

- **Duration chips:** tapping chips to change time is never hunting on its own (B4 default absent); it is comprehension-consistent engagement with the ready model.

- **Moderator-prompt contamination:** if the moderator introduces the words "ready", "already there", "instant", "no choosing", or names the wedge before the user does, then:
  the user's subsequent description is **N/A** for B7 (it was led), and any subsequent recognition is discounted for B5.
  If the moderator instead asks the user to *find a workout to pick* (leading them toward hunting), any hunting that follows that prompt is **discounted** and flagged - do not code moderator-induced hunting as B1-B3.
  Moderators should follow the pre-registered neutral script and avoid both leads; flag any contaminated run in the notes and, where it invalidates the primary outcome, mark the run contaminated and exclude it from the pool (recording why), so a contaminated run neither passes nor fails the wedge.

- **Onboarding is not hunting:** navigating the six onboarding steps (including going Back) is setup, not list-hunting; B1-B4 apply to the Ready Screen and the main tabs, not to the onboarding questionnaire.

- **Partial / ambiguous comprehension:** resolve by the priority order in the coding scheme and the B4/B5 default-to-comprehension rules; when a run remains genuinely unresolvable after those rules, code it **Inconclusive / no-engagement** and flag it, rather than inventing a partial-credit category (there is none - the thesis thresholds are counts of whole runs).

- **Inter-coder reliability (optional, if a second non-founder coder is available):** have both code an overlapping subset (e.g. the first 8-10 runs) independently, compare primary-outcome agreement and kill-numerator agreement, and reconcile disagreements against these written rules *before* coding the remainder.
  Report the agreement rate alongside the K8 result as a reliability check; it does not change any threshold.
  This is a recommended safeguard, not a pre-registered requirement, and its absence does not invalidate a single-coder result.

## Provenance and non-authority

This rubric is subordinate to `investment-thesis.md`.
It restates the K8 thresholds only to operationalize them and cites each to its thesis line; if any number here is ever read as differing from the thesis, the thesis governs and this document is corrected to match.
Nothing in this document changes K0-K9, the expected bands, or any other kill criterion.
