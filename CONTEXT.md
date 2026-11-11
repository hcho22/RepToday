# CONTEXT - Rep Today domain glossary

The resolved vocabulary of the Rep Today domain: the small set of terms whose meaning is load-bearing across the product, the engine, and the docs.
This is a glossary of settled terms, not a spec - each entry points to the authoritative code or doc rather than duplicating its detail.
`AGENTS.md` is the working guide for contributors; the dated PRDs under `.claude/agent/tasks/` are the strategic source of truth; decisions that changed a term's meaning are recorded as ADRs under `docs/adr/`.

## Pillar

The training families a session draws from - `strength`, `mobility`, `primal` (`Models/Enums.swift`, `Pillar`).

**Strength is the primary pillar of every session.**
Single-focus, blend, cold-start, and Return sessions all lead with strength; mobility is **supporting** - the structural warm-up and the cooldown bookends only, never a training block and never the lead.
This is the strength-primary decision that superseded the earlier co-primary framing (see [ADR-0001](docs/adr/0001-strength-primary-sessions.md)); it is captain-accepted, and the term "co-primary" is retired for describing current behavior.
Since **US-M01** the strength lead is *structural*, and since M1 every session is a **Training Day**: Warm-Up -> one strength circuit for one group -> Cooldown, with no strength-vs-mobility split machinery. Since **US-M03** the `sitsLong` (desk-worker signal) *biases* bookend selection toward posture/hip openers - never a sizing lever, so it can never reintroduce a mobility middle block (`SessionAssembly.postureHipLean`; see AGENTS.md section 2).
Since **US-M02** the bookends are *pattern-matched*: each mobility movement carries a `complements: [MovementPattern]` tag (`Exercises.json`), and the warm-up and cooldown **lead** with a stretch complementing the day's lead strength pattern, then fill with the existing staleness / no-repeat ordering - a preference, never a filter (`SessionAssembly.leadingComplement`); the general pool is the fallback so a bookend is never starved.

`primal` is **retired** as a training family ([ADR-0014](docs/adr/0014-retire-primal-pillar.md), M1): crawls need floor space a home or hotel room does not have.
Every locomotion movement carries `audience: retired` and stays in the catalog only so old logs and paused sessions still resolve; Bear Hold stays on the core ladder.
The engine mechanics live in `Services/Engine/SessionAssembly.swift` (the Training Day slot plan).

## Movement Practice (retired)

The mobility **training** block that once sat between the warm-up and cooldown - a real block of mobility work (deep squat holds, hip work, thoracic rotations), distinct from the structural warm-up.
**Retired by US-M01** (2026-08-13): it is no longer emitted at any length, its split machinery (`PillarBalance`/`PillarWeights`) is removed, and the training minutes it held were reallocated to strength.
Mobility now survives only as the warm-up and cooldown bookends. The term is kept here only so a future contributor recognizes it as a removed concept, not a live block (see [ADR-0001](docs/adr/0001-strength-primary-sessions.md) and the "Movement Practice removal" follow-on in `.claude/agent/tasks/prd-strength-primary-sessions_260812.md`).

## Continuous Circuit

The active-session model: a hands-free, follow-along session that auto-advances on a per-interval countdown - the strength block runs as circuit rounds ("Round N of M"), each work window counts down and auto-flows into rest, and holds auto-start and flow linearly.
**Once a session starts it needs no tap for the length the user chose** ([ADR-0010](docs/adr/0010-short-rests-stretched-work-windows.md)): every timed hold - warm-up, cooldown, strength or primal - auto-starts after its get-ready beat, a per-side hold flows side 1, "Switch sides", side 2, and a rep-based warm-up or cooldown move runs on the same auto-advancing window as a training set.
The one-time "how this works" card shows before the first session starts and its button starts the session, so it never pauses a running one; the one-time Trainer choice likewise shows before the start whenever the Trainer is unresolved.
It **supersedes** the manual tap-to-advance player (the US-K01/US-K02/US-O03 model where every set needs a **Complete set** tap and every stretch a **Start hold** tap), and is never user-selectable alongside it; Pause, Done, Skip, Swap, Stop hold and **+ More time** are optional extras no session requires.
The spec is the Continuous-Circuit Sessions PRD (`.claude/agent/tasks/prd-continuous-circuit-sessions_260814.md`, `US-CC##`); the decisions behind it are [ADR-0002](docs/adr/0002-per-interval-pacer-clock.md) (the per-interval **pacer clock**, which partially reverses US-O03's hidden-clock stance), [ADR-0003](docs/adr/0003-even-round-circuit-timing.md) (**even-round** timing: a uniform set count per training block) and [ADR-0010](docs/adr/0010-short-rests-stretched-work-windows.md) (**short rests**, with the **stretched work window** as the fit lever that replaced ADR-0003's round rest).
Reps stay the currency (no timed-interval conversion), counted in **round numbers** ([ADR-0011](docs/adr/0011-round-numbers-and-the-climb.md)).
Self-pacing is preserved by in-flow escape hatches (chiefly **+ More time**), never a parallel manual mode.
**Story-by-story (PRD complete, US-CC01...US-CC14):** US-CC01 shipped the first player slice - a rep-based **strength/primal** training set now counts down on an auto-advancing **work window** (`ActiveSessionViewModel.workWindow`, `ActiveSessionView.WorkWindowCountdownView`) that records the set at zero and flows into the *existing* US-K02 rest with no tap, plus a prominent **Done** to advance early; the window reads the engine's already-planned per-set seconds (`SessionAssembly.workSecondsPerSet`). **US-CC03/US-CC04 have landed** (engine-only, ADR-0003): `SessionAssembly` now sizes a training block as a circuit of a **uniform round count** (every station's `sets` equal) and lands the ±1 min target by tuning a **bounded between-round rest** (30-75s) as the primary fit lever, with a fixed ~15s between-station transition as the distinct second gap - the per-exercise set-adjust lever is retired (`SessionAssembly.blockSeconds`/`setRoundsAndRest`). **US-CC02 has landed** (player-only): the strength / dedicated-primal training block is played as a **circuit of rounds** - the player rotates one set of each station per round (A, B, C, A, B, C, ...) via `ActiveSessionViewModel.nextPosition(fromIndex:set:)` and surfaces **"Round N of M"** (`currentRound`/`circuitRoundCount`), warm-up/cooldown bookends stay linear (no round), and aggregate logging is unchanged. **US-CC05 has landed** (player-only): a warm-up/cooldown bookend **hold auto-starts hands-free** (never a Start-hold tap) and a per-side bookend flows side 1 -> a brief **"Switch sides"** beat -> side 2 with no tap (`ActiveSessionViewModel.autoStartHoldIfNeeded`/`currentStepIsBookendHold`), while a timed strength/primal *training* hold keeps the US-O03 manual Start-hold path. **US-CC06 has landed** (player-only): the quiet in-flow escape hatches with **no separate manual mode** - the new one is an explicit user **Pause** (`ActiveSessionViewModel.pause(asOf:)`/`resume(asOf:)`, a Pause/Resume toggle in the shared `ActiveSessionView.SessionTopBar`) that freezes whichever countdown is live - work window, hold, or rest - and its audio-cue timing, then resumes from the exact remainder, **without backgrounding** (a foreground state kept distinct from the scene-phase background pause via `pauseForBackground`/`resumeFromForeground`); the other hatches (Done, Skip, Swap, round-rest +/skip) are surfaced as-is, and `NoManualModeGuardTests` fails the build if a `manualMode`/`ManualMode` identifier ever appears in the player sources. **US-CC07 has landed** (player-only, a hardening/lock-in story with no engine change): a mid-circuit **skip** or **swap** holds for **all remaining rounds** and the block stays structurally even - both were already structural once US-CC02/US-CC03 landed (the player keeps one `Step` per station, so skip passes over the station in every round and a swap replacing the slot carries the substitute through all later rounds while `ExerciseSwap` keeps the block's uniform round count M), and the settled product decision is **Option A, honest late-entrant**: a swap's substitute joining in round *r* logs only the `M-r+1` rounds it actually played rather than fabricating a pre-swap set. **US-CC08 has landed** (engine-only): `SessionAssembly.workSecondsPerSet` is no longer a planning-only proxy but a **generous runtime pace** - one documented constant `SessionAssembly.workPaceGenerosityFactor = 1.25` applied *inside* that function, so the same inflated number feeds both the planning wall-clock and the on-screen work window and the window can never be roomier than what the fit planned. It scales the **rep branch only** (a hold's per-second cost is definitional, not estimated, so holds pass through at 1.0) and never touches Step 6's per-set target. Two accepted, measured consequences: a session fits **fewer rounds** - and at 45 min one fewer **station** (8 rounds x 4 instead of 7 x 5, so the longest strength block trains 4 distinct movements) - with a fast user finishing early and tapping **Done**; and the US-M03 `sitsLong` bookend bias now genuinely **binds** on the shipped catalog, so its byte-identical-training-middle guard was rescoped to the real invariant (same movements at the same per-set targets, blocks still internally even, equal bookend seconds still producing identical round counts). **US-CC09 has landed** (hardening/lock-in, no production change - the invariant was already structural from US-CC01/US-CC02/US-CC07): an auto-advanced set and a **Done** early-advance both record prescribed = performed (`completeSet()`/`recordSet`, identical to the pre-US-CC01 tapped path), only an explicit **Skip** (`skipExercise`) logs an exercise not-done, and `CompletedSet` carries only `reps`/`durationSeconds` - no per-set "did they really do it" field - so the end-of-session `rate` (US-L02) stays the sole Ramp signal; locked by `ActiveSessionViewModelTests.testWholeSessionHandsFreeWithOneSkipLogsCompletedExceptTheSkip` and the reflection guard `NoPerSetCompletionTrackingGuardTests`. **US-CC10 has landed** (player-only): the single US-K02 feedback seam becomes a per-state **non-verbal cue vocabulary** - `Utilities/SessionCuePlayer.swift` replaces `RestTimerFeedback` with a `SessionCue` enum (`.go`/`.halfway`/`.transition`/`.roundRest`/`.done`) and `SessionCuePlayer.play(_:suppressAudio:)`, so the hands-free flow is tellable apart by ear with no spoken callouts; the five states route onto the player's existing transition points, the real `SystemSessionCuePlayer` **ducks** the user's own audio (`AVAudioSession` `.playback` + `.duckOthers`, never stopping it), and VoiceOver coordination withholds the *tone* (reading `UIAccessibility.isVoiceOverRunning` at fire time, injected `voiceOverActive`) while still firing the *haptic* so a cue never talks over speech. **US-CC11 has landed** (player-only, presentation): the rep-based work window is **visual-primary** - the movement illustration and a compact `CountdownRing` show together, so a text-and-ring-only window is rejected as too bare; since ADR-0008 the illustration is the Trainer's start/end poses filling the exercise card (the shared `ExerciseIllustration`, else the SF-Symbol glyph, held **static** while a countdown runs) and the compact ring sits beside the exercise name rather than in the card. The between-station **transition beat** (US-CC04) earns a prominent "Next: <exercise>" cue in `RestView.nextUp` (movement name in largeTitle/accent, spoken "Next: <exercise>") - told apart from a between-round rest via a retained-cue seam (`ActiveSessionViewModel.restCue`/`isTransitionBeat`, in-memory only, cleared in `endRest`) - while the shared rest overlay header stays "Rest". No engine/model/persistence/advance/timing/cue-vocabulary change. **US-CC12 has landed** (hardening/lock-in, test + docs only, no production change): an old paused session written by the pre-CC manual player resumes in the new player from its saved position (step index, set, completed sets, skips, clock origin), and the migration was found **already structural** once US-CC02 kept `currentStepIndex`/`currentSet` unchanged (a station's r-th set *is* round r), so `init(state:)` copies `completedSets`/`skippedStepIDs` verbatim, an **uneven** pre-US-CC03 block resolves deterministically via `blockSpan`'s max-set-count round count and `hasSet`'s per-station gating (no work lost or double-counted), only the per-side `hold.side` restores idle (never a running leg, US-O03), and forward safety is inherent (no snapshot-schema change). **US-CC13 has landed** (player-only, presentation + one-shot flag; no engine/model/persistence/advance/timing/cue change): a single dismissible **first-run explainer** (`Views/ActiveSession/ContinuousCircuitExplainerView.swift`) shown at most once on first arrival at the player states the four points - the session auto-advances, **+ More time** never rushes you, **Done** jumps ahead, and tones mark state changes - in identity-framed, non-loss-framed copy; the persisted one-shot flag lives on `AppState` (`hasSeenContinuousCircuitExplainer`, read via `shouldShowContinuousCircuitExplainer`, flipped via `markContinuousCircuitExplainerSeen()`), and `ActiveSessionView` presents it as an **overlay layer** (not a `.sheet`, so the entrance/exit transition can be stilled under Reduce Motion), holds the already-started session on a US-CC06 user **pause** while it is up (freezing the first window/hold/rest and its cue timing, resumed on "Got it"), and never gates the start. **US-CC14 has landed** (player/presentation-only; no engine/timing/persistence/advance/completion-logging/cue-vocabulary change), and with it **the continuous-circuit PRD is complete**: **+ More time** is now a first-class, always-available hatch on both auto-advancing countdowns (`ActiveSessionViewModel.extendActiveCountdown(by:)` gated by `canExtendActiveCountdown = isRunningWorkWindow || isHolding`, surfaced in the player's secondary row via the shared `secondaryAction` whenever a work window or hold leg is running - the rest keeps its own "+15s"), adding the **same +15s** the rest's `extendRest` uses; it is a **pure display/timer affordance** that logs no value (US-CC09 stands, the set still records prescribed = performed) and writes no snapshot (neither window nor hold leg is persisted). The auto-advancing countdown ring is now accessible: the shared `ActiveSessionView.CountdownRing` carries `.accessibilityAddTraits(.updatesFrequently)` so VoiceOver polls the remaining time on demand rather than announcing every tick or stealing focus, its sweep animates only when Reduce Motion is off, and the movement name / round-set label / target / primary controls wrap under Dynamic Type while the ring clock shrinks to fit; AC5 (an auto-advance never cutting off speech) is inherited from US-CC10's tone-withholding. The story-by-story record above describes each story at landing; where it says a training hold keeps a manual Start-hold, the between-round rest is a 30-75s fit lever, the explainer pauses a started session, or Adaptive Overload's percentage ramp is unchanged, ADR-0010 and ADR-0011 now govern.

## Rest

A countdown between efforts that the user recovers through: the **between-station transition** inside a round (the "Next: <exercise>" beat), the **between-round rest**, the transition between blocks, and a warm-up or cooldown move's between-set rest.
Both gaps start at 15 seconds ([ADR-0010](docs/adr/0010-short-rests-stretched-work-windows.md)) and grow only when reps alone cannot fill a session ([ADR-0013](docs/adr/0013-fixed-four-sets-five-step-reps.md)): the rest after a round up to 60 seconds on a session of 30 minutes or less, and on a 45 or 60 minute session the pause between movements up to 60 seconds and the rest after a round up to the level cap (beginner 2:00, intermediate 1:30, advanced 1:00).
The per-side "Switch sides" beat is 5 seconds, and **+15s** stays an optional way to ask for more.
The owning code is `SessionAssembly.fit`, `SessionAssembly.roundRestCap` and `WorkoutBlock.transitionSeconds`; the player clamps every rest it opens to `SessionAssembly.maxRestSeconds`.

## Stretched work window (retired)

A rep-based set's countdown lengthened past the pace its reps need so a session landed on its length ([ADR-0010](docs/adr/0010-short-rests-stretched-work-windows.md)).
Retired by [ADR-0013](docs/adr/0013-fixed-four-sets-five-step-reps.md): **Padding** and then rest fill a session instead.
`PrescribedExercise.stretchSeconds` stays decodable so a session saved before M1 still plays its windows.

## Round numbers

Every rep and hold number is a multiple of five ([ADR-0011](docs/adr/0011-round-numbers-and-the-climb.md)); a per-side move follows the rule per side.
Since M1 the numbers live in **Earned Reps** ranges (reps 15-30, advanced 15-50; per side 5-15; holds 20-60 seconds, advanced 90), and a short session may serve down to 10 reps (5 per side) - the one owner is `Services/Engine/RepGrammar.swift`.
**The climb** ([ADR-0013](docs/adr/0013-fixed-four-sets-five-step-reps.md)'s reconciliation, replacing ADR-0011's three-session climb): Earned Reps climb 5 after each session not rated too hard whose prescription reached them, "too easy" adds 5 at once, and "too hard" or a skip takes 5 off - or, already at the bottom of the range, steps the move one rung down its progression chain.
After "too hard" the completion screen lists the session's strength and primal moves for the user to tap any they **couldn't finish**: only those step back and that session never counts toward their advancement, the untapped ones hold, and with none tapped every move steps back and the session counts toward no move's advancement.
A number logged before the grid is read rounded down onto it, and logs are never rewritten.
The owning code is `Services/Engine/AdaptiveOverload.swift`.

## Wide Circuit (retired)

How a long session used to be filled: by going wider, promoting further-chain accessories once every station sat at a 2-4 round cap ([ADR-0004](docs/adr/0004-round-cap-wide-circuit.md)).
Retired by [ADR-0013](docs/adr/0013-fixed-four-sets-five-step-reps.md): a Training Day serves a fixed number of movements for its length, every station runs 4 rounds, and **Padding** and rest fill the time.

## Different workout

The Ready Screen's button that rebuilds today's session at the same length with other moves, pressed as often as the user likes before they start.
Each press ranks the moves the earlier presses of the same sequence already showed behind their alternatives; it never filters, so movement access, injury flags, earned tiers and the timing fit still decide every pick.
When nothing new is left the default session comes back and the presses start over, so the same history and the same number of presses always give the same workout.
A length change starts over, a paused session waiting to be resumed is untouched, and nothing is logged until the session is started, so a press never counts toward variety, progression or the Consistency Score.
Starting a session, fresh or resumed, ends the sequence, so the next Ready Screen shows the default session for the history that session leaves.
It is unrelated to the in-session **Swap**, which replaces one move while a session runs.
The owning code is `Models/SessionVariation.swift`, `SessionAssembly.assemble(variation:)` and `ReadyViewModel.showDifferentWorkout()`.

## Staple movement

A movement most people already know by name - a push-up, a squat, a plank, a glute bridge - and the only kind a beginner or intermediate user is offered while they are in the **Discipline Phase**.
Every catalog movement says who it is a staple for: beginners and up, intermediates and up, or advanced users only.
An advanced user keeps the full variety; earning the **Strength Phase** lifts the restriction for everyone, so every movement opens at once.
A few movements are withdrawn until version 2 and are offered to nobody.
The gate is the self-reported fitness level picked at onboarding, there is no setting to change it, and it is decided in one place for every session, swap, progression map and Coach surface.
A user partway up a progression on a movement they no longer get is served the closest movement they do get on the same progression; their logged history is never rewritten.
It supersedes the **Effective Difficulty Cap** (US-SP01), which gated the pool by a difficulty band from the same fitness level; that term is retired.
Pull is the one exception to "familiar only": it keeps its current equipment-free movements.
The decision is recorded as [ADR-0007](docs/adr/0007-staple-movements-for-beginner-and-intermediate.md).

**The one exception ([ADR-0015](docs/adr/0015-practice-movement-bypasses-staple-gate.md)):** a **Practice Movement** may sit above the user's staple level; injury exclusions, Strength-Phase locks and withdrawals still apply.

## Foundation

What the user clears to earn the Strength Phase.
There are exactly four foundations, always listed in this order: **Push, Pull, Legs, Core**.
A foundation is not a movement pattern.
Movement patterns are the engine's staleness and variety buckets: squat and hinge stay separate patterns in session assembly, and pull stays an ordinary strength pattern.
A foundation is what the *user* is asked to clear, and it is made of one or more **lines**, each a movement pattern plus the progression chains whose entry rung counts.
**Legs** groups two lines, a **Squat side** and a **Hinge side**, and is cleared only when both are.
Push, Pull and Core have one line each.
A line is cleared when a logged, non-skipped performance of the entry rung (lowest progression order) of any one of its counting chains meets that rung's advancement criteria.
Each foundation's counting ladder:

- **Push** - either push chain (horizontal or vertical).
- **Pull** - the **horizontal chain only** (Wall Scapular Pull, Supine Floor Row, Single-Arm Supine Floor Row).
  The postural chain (Superman Hold, Reverse Snow Angel) stays in sessions as accessory and prehab work but never counts toward clearing Pull.
- **Legs** - Squat side: either squat-family chain (squat or lunge).
  Hinge side: either hinge-family chain (bridge or hip).
- **Core** - any core chain.

The Strength Phase is earned when all four foundations are cleared and the Consistency Score has been sustained above 80 for about eight weeks; an earned Strength Phase is never revoked, so a change to the foundations can only change what a Discipline user still has to clear.
Pull's ladder ends at Single-Arm Supine Floor Row with no locked Strength-Phase rung, because a Pull top rung needs equipment and the zero-equipment rule stands until the planned Phase 2 equipment work.
The rationale, presentation, Coach behavior and existing-user recalculation are recorded in [ADR-0006](docs/adr/0006-foundations-push-pull-legs-core.md).

Since M1 a line is cleared by four clean sets at the top of the user's range on the entry rung, at earned reps, in a session not rated too hard ([ADR-0013](docs/adr/0013-fixed-four-sets-five-step-reps.md), `RepGrammar.isAdvancementMet`), so a Discipline user may need to re-clear a foundation after the update.

## Back injury area

The single protectable **Back** area covers both upper and lower back complaints and excludes Pull and Hinge work.
**Shoulders** is distinct and excludes Push and Pull work.

## Trainer

The illustrated person who demonstrates movements during a session: a male Trainer and a female Trainer, each drawn in a start pose and an end pose for a movement.
The Trainer only demonstrates; it never talks, advises, or changes a session, and it is distinct from the **Coach**, the premium AI chat.
A user's Trainer defaults from their onboarding answer, a user who answered "other" chooses once, and anyone can switch in Settings.
The owning code is `Models/Trainer.swift` (the enum, `Trainer.effective(for:)` and the one write `saveTrainerChoice`), `Services/Trainer/TrainerPoseResolver.swift` (which poses exist, read off the asset catalog by exercise id) and `Views/ActiveSession/ExerciseIllustration.swift`; the spec is `.claude/agent/tasks/prd-trainer-pose-art_261002.md` (`US-TP##`) and the decision is [ADR-0008](docs/adr/0008-static-trainer-pose-art-replaces-lottie-demo.md).

## Waitlist

The pre-launch sign-up on `reptoday.app`: a visitor gives an email address, answers one **Fit** question, and may ask for a beta invitation.
A visit's **Source** is where the visitor came from, taken only from the link they arrived by (`reptoday.app/tiktok`, `/youtube`, `/reddit`, `/network`; any other arrival is `unknown`) and never asked as a question; it is unrelated to the "Source" column of the asset-attribution ledger.
**Fit** (capital F) is the visitor's answer to "Which sounds most like you?" (`lost-the-routine`, `exercises-regularly`, `never-had-a-routine`); it is unrelated to the engine's timing fit (Step 7).
The **anonymous view** is the one address-free file (entry identifier, Source, Fit, beta opt-in, sign-up date) that RepToday keeps on the founder's Mac for gr0wthlab's launcher to read; an **entry identifier** is the random, never address-derived name of one sign-up in it.
The producer's **ledger** (beside the view, Kit subscriber id to entry identifier) is the only place an entry identifier is trusted; Kit's API cannot delete a subscriber, so removal and retention **erase** one: unsubscribe it, overwrite its address with a placeholder that is not an address, and blank every stored answer.
The founder then deletes the erased record in Kit's web app, which also removes the approximate location Kit keeps and its API cannot clear; the tooling names the Kit subscriber ids to delete and checks afterwards that each no longer answers.
A **removal request** is an unsubscribe, a spam complaint about a waitlist email (Kit state `complained`), or a message to the policy's contact address; a bounce is not one.
Addresses are resolved only on the founder's side, at send time, and no email-service credential or address export is ever placed in the gr0wthlab, Mandu or RepToday checkouts.
Live since 2026-10-21: the spec, which tracks what has landed, is `.claude/agent/tasks/prd-waitlist_261019.md` (`US-WL##`), the approved strings and tags are in `tools/waitlist/contract.json`, and the boundary decision is [ADR-0009](docs/adr/0009-waitlist-anonymous-view-and-address-boundary.md).

## Two-Writer Policy Safety

`SessionPolicy` has two writers - the deterministic Programmer (`DeterministicSessionPolicyService`, which owns the safety moves: plateau de-load, Re-entry Ramp, cold-start) and the premium AI coach (`Services/Coach/CoachSessionPolicyService`, US-AC07, which may only nudge the three **preference** levers).
**Safety > preference, structurally:** a coach write is a *safety-sovereign overlay* - it re-reads the freshest in-force policy from the shared `SessionPolicyStore` and overlays only its own levers (`SessionPolicy.applyingCoachProposal`), and every coach-touchable lever is either **disjoint** from the safety moves (`patternEmphasis`) or **only-downward** (`progressionRate` eased down only; `varietyWindow` narrowed only), so a coach write can never clobber a de-load / Re-entry / cold-start.
The change is a closed `CoachPolicyProposal` (no safety field is expressible), clamped to the engine's rails before it is accepted, tagged `updatedBy == .llm`, noted honestly (`PolicyNote.coachTemplated`), applied on the next open, and reversible.
The decision is recorded as [ADR-0005](docs/adr/0005-two-writer-policy-safety.md); the owning code is `SessionPolicy`, `CoachSessionPolicyService`, `CoachPolicyProposal`, and the closed proposal producers `CoachIntentMapper` (free-text tuning, US-AC07) and `CoachAnalyticsInsight` (a strength-journey stall offer, US-AN02).

**Planned note ([ADR-0017](docs/adr/0017-coach-agent-on-convex.md), 2026-11-10):** a Coach **Custom Workout** is a separate, user-accepted artifact, not a policy write, so this structure is unchanged by it.

## discipline-first

The product's positioning: the promise is **daily consistency** - showing up - independent of whether a given day's work is strength or mobility.
Discipline-first is a framing about the user's behavior and identity ("you're someone who moves"), not a claim about the session's pillar mix.
It coexists with the strength-primary engine: the engine leads with strength while the positioning stays discipline-first, and every user starts in the **Discipline Phase** and earns the **Strength Phase** through sustained consistency plus demonstrated competence (`Services/Consistency/`, `PhaseEvaluator`; `AGENTS.md` "Consistency & Phase").
No gamification (no XP, levels, badges, or a streak to break); a miss dents but never zeroes the Consistency Score.

## Training Day

A session dedicated to one group: a **Push Day** (push), a **Pull Day** (pull), or a **Legs Day** (squat and hinge).
A Training Day never mixes groups; its only extras are the **Core Sprinkle** and the warm-up and cooldown bookends.
Its main slots by length are 1 (5-20 min), 2 (30), 3 (45) and 4 (60); a Push or Pull Day has two ladders, so its third and fourth slots are **Practice Movements**, and a Legs Day uses the squat, lunge, bridge and hip ladders.
Every main and core station runs 4 rounds.
Decided in [ADR-0012](docs/adr/0012-push-pull-legs-rotation-with-rest-day.md) and [ADR-0013](docs/adr/0013-fixed-four-sets-five-step-reps.md); the owning code is `Services/Engine/SessionAssembly.swift` and `Models/TrainingDay.swift`.

## Rotation / Cycle

Training Days always run Push -> Pull -> Legs and advance only when a session is completed, so a missed day never skips a group.
One pass through the three is a **Cycle**.
A log's Training Day is read off its stations' roles (`WorkoutLog.trainingDay`), so logs written before M1 carry none and existing users start at Push.
The owning code is `Services/Engine/TrainingRotation.swift`.

## Rest Day

The planned day off after every completed Cycle.
Any day without a session after Legs counts as the rest; a user may "train anyway", which forfeits it.
Today shows a Rest Day card with an optional mobility-only **Recovery** flow, which neither advances the Rotation nor counts as a session (`WorkoutLog.isRecovery`).
Anonymous telemetry still counts a Recovery flow like any session (`session_started`, `session_completed`, `week_active`), by the captain's decision of 2026-11-10.
A Rest Day never lowers the Consistency Score.

## Core Sprinkle

The one core movement added to every Training Day (two when Abs is a **Focus Area**), rotating across core ladders from Cycle to Cycle.

## Practice Movement

The next harder rung of a ladder, prescribed at low reps beside the current rung on longer sessions.
It runs at 4 x 10 (per side 4 x 5, holds 15 seconds), previews progression but never advances it (`LoggedExercise.countsForProgression`), and may sit above the user's staple level ([ADR-0015](docs/adr/0015-practice-movement-bypasses-staple-gate.md)).
With no harder rung the slot takes the rung below at volume reps; with neither, the session has one fewer movement.

## Variation (planned)

A same-difficulty alternative to a rung (Standard -> Wide or One-legged push-up) that joins longer sessions as an extra movement once its Trainer art exists.
It unlocks with its parent rung and never advances the ladder.

## Earned Reps / Rep Ramp

The per-movement rep count the user has earned through rated sessions, always a multiple of 5, recorded on every prescription and log (`earnedReps`, `earnedDurationSeconds`) so Padding and a short session's cut never move it.
Moving up a rung requires four clean sets at the top of the level's range at earned reps ([ADR-0013](docs/adr/0013-fixed-four-sets-five-step-reps.md)).

## Padding

Reps prescribed above Earned Reps only to fill a longer session.
Padded reps count as done but never move the Rep Ramp or a rung.

## Outside Activity

A workout done outside Rep Today (a run, a swim), logged by hand from Today or added from an Apple Health suggestion ("Add it / Ignore", never applied without a tap).
Run, bike and hike work Legs; swim, row and climb work Pull; anything else works no group.
The group it worked gets at least a day off: it swaps behind the next group, or, when it is the last group left in the Cycle, the Rest Day comes early: the next day, if that day has no activity of its own.
Any other day it keeps without a Training Day is a Day Off, not the Cycle's Rest Day (`RestReason`).
It counts as showing up for the Consistency Score, though not toward earning the Strength Phase, and never completes a group.
The owning code is `Models/OutsideActivity.swift` (stored on-device as `CDOutsideActivity`, model version 2, never synced to iCloud), `Services/Engine/TrainingRotation.swift` and `Services/Health/HealthWorkoutSuggestions.swift`, which never suggests Rep Today's own workouts back.

## Custom Workout (planned)

A workout written by the **Coach** that the user reviews, edits and accepts before playing.
It counts like an Outside Activity and never advances progression ([ADR-0017](docs/adr/0017-coach-agent-on-convex.md)).

## Focus Area

A body part the user wants to improve: Chest, Shoulders, Arms, Back, Abs, Legs, or Glutes - multi-select and optional, asked in onboarding and editable in Settings.
It replaced the never-read goal list (`primaryGoal`, whose key profiles still carry so older builds can read them).
It changes emphasis within Training Days, never the Rotation: a movement it covers is ordered first among its kind of station, padded first (and cut last) by the fit, and given the Practice slot first; Abs adds a second Core Sprinkle.
Chest covers the horizontal push ladder, Shoulders the vertical push ladder, Arms the diamond push-up, dips and rows, Back both pull ladders, Abs core, Legs the squat and lunge ladders, Glutes the bridge and hip-hinge ladders.
The owning code is `Models/FocusArea.swift` and `Services/Engine/SessionAssembly.swift`.

## Welcome Page

The tap-through page shown on every cold launch after onboarding, before Today, and never on a resume from the background: a greeting with the user's name, today's Training Day or Rest Day, the Cycle strip, and "Let's go".
It replaces the launch spinner; the app-open reconciliation and Today's load run behind it.
The owning code is `Views/Welcome/WelcomePageView.swift` and `AppState.isWelcomePending`.

## Account (planned)

The user's required sign-in identity; their data lives on the device first and syncs to Rep Today's server ([ADR-0016](docs/adr/0016-clerk-accounts-convex-local-first.md)).

## Coach

The premium AI conversation partner, distinct from the **Trainer**.
Today it is a stateless chat that may only nudge preference levers (see Two-Writer Policy Safety).
**Planned change ([ADR-0017](docs/adr/0017-coach-agent-on-convex.md), 2026-11-10, not yet implemented):** the Coach becomes an agent with its own tab that remembers the user, acts through confirmed tools, writes **Custom Workouts**, gives general diet guidance to adults only, and sets reminders.
