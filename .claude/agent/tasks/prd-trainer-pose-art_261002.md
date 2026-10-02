# PRD: Trainer Pose Art in the Active Session

- Status: **Planned - not yet authorized for implementation.**
  Every decision in the table below was settled with the captain in a design interview on 2026-10-02, and the seven follow-up questions this PRD raised were settled the same day ("go with your recommendations").
  The product choices the interview did not settle are listed under Open Questions, each with a marked recommendation.
  The captain asked to discuss before implementing, so no story may start until the captain confirms the go.
- Story prefix: `US-TP##` (Trainer Pose).
- Related decisions: [ADR-0008](../../../docs/adr/0008-static-trainer-pose-art-replaces-lottie-demo.md) (static Trainer pose art replaces the Lottie demo seam, and the countdown ring leaves the exercise card).
  Domain term: `CONTEXT.md` -> "Trainer".
- Supersedes, on landing: the US-O01 Lottie exercise-demo seam (`Exercise.animationName`, `LottieDemoView`, the Lottie package).
- Amends, on landing: the US-CC11 visual-primary work window layout (illustration and compact ring together in the card) and the US-O03 Hold Timer layout (full-size ring in place of the illustration).
- Source art: the captain's local trainer-art workspace, outside this repository, in six family folders (push, back, leg, core, primal, mobility).
  Implementation reads it; nothing in this PRD modifies it.

## Introduction / Overview

During a session, Rep Today currently shows a generic SF Symbol per movement pattern (one glyph for every push movement, one for every squat, and so on).
The user is on the floor, often glancing at the phone from a distance, and the glyph cannot tell them what a Pike Push-Up or a Cossack Squat actually looks like.
The bundled-animation path built for this in US-O01 (Lottie) never received a single clip, so the app ships with a third-party dependency that renders nothing.

The captain has produced illustrated **Trainer** art for the current catalog: a male and a female Trainer, each drawn in a **start** and an **end** pose for every movement.
This feature shows those two poses side by side on the exercise card throughout the active session and on the rest overlay's "next" preview, picks the Trainer from the user's onboarding answer (with a choice for users who answered "other" and a Settings switch for everyone), and retires the unused Lottie path.

It is a **player and presentation change**.
The deterministic engine, session timing, completion logging, cue vocabulary, persistence of sessions, and telemetry are unchanged.

## Goals

- Show the selected Trainer's start and end poses, static and side by side, on the exercise card in every player state, and under the rest overlay's "next" preview.
- Default the Trainer from the onboarding sex answer, ask a user who answered "other" once, and let any user switch at any time in Settings.
- Ship with the art that exists today: full pairs where they exist, a single centered pose where only one exists, and today's SF-Symbol glyph where none is usable, with every gap listed at build time.
- Keep today's on-screen fit: the exercise card keeps its current height, nothing else moves down, and small phones keep fitting.
- Remove the Lottie package (the app's only third-party dependency) and its dead code without breaking any persisted active-session snapshot.
- Record the art's provenance in `docs/asset-attribution.md` before any art ships.

## Interview decisions and where this PRD carries them

Each numbered decision is the captain's answer from the 2026-10-02 interview.
Decisions 11-17 are the captain's answers to the follow-up questions the first draft of this PRD raised (captain, 2026-10-02: "go with your recommendations").
This PRD invents no further product decisions.
Any product choice the interview did not settle is listed under Open Questions with a marked recommendation, and every acceptance criterion that depends on one says "per Open Question N".

| # | Decision (captain's answer) | Carried by |
| --- | --- | --- |
| 1 | **Trainer selection (A):** default follows the onboarding sex answer (male -> male Trainer, female -> female Trainer); an "other" answer makes a one-time choice the first time Trainer art appears; a new Settings row switches at any time; existing users follow the same rule from their stored answer. Term: **Trainer**, distinct from **Coach**. | US-TP03, US-TP10, US-TP11; FR-5 to FR-9; `CONTEXT.md` |
| 2 | **Pose display (C):** start and end side by side, both visible, static (no flipbook, no rep-synced animation). | US-TP06; FR-10, FR-11 |
| 3 | **Layout (B):** the two poses get the whole exercise card at its current size (`ExerciseDemoView.height`, about 150 pt per pose); the countdown ring leaves the card and becomes a compact ring beside the exercise name; timed holds use the same layout instead of today's full-card ring. | US-TP07; FR-14 to FR-17; ADR-0008 |
| 4 | **Surfaces (B):** exercise card in every state (rep work window, timed hold, stretch, pre-hold) and the rest overlay (`RestView.nextUp`) for the between-station transition beat and the between-round rest; swap needs no surface of its own; Ready-screen preview and Progress-tab ladder out of scope. | US-TP06, US-TP07, US-TP08; FR-12, FR-13, FR-18; Non-Goals |
| 5 | **Per-side movements (B):** art shown as drawn, no mirroring for side 2; the "Switch sides" beat and "Side 2 of 2" text carry the side change. | FR-11; Non-Goals |
| 6 | **Incomplete art (A):** pair side by side, single pose centered, no usable art keeps the SF-Symbol fallback (currently Prone Y-T-W Raises); missing art later is a file drop with no code change; a build-time check lists every served movement lacking a full pair for either Trainer. | US-TP04, US-TP05, US-TP06; FR-3, FR-4, FR-20 to FR-22 |
| 7 | **Animation support (B):** retire Lottie (package, `Exercise.animationName`, `LottieDemoView`, Lottie test and docs); illustration resolves Trainer art else the SF-Symbol fallback; old snapshots keep decoding; any future motion is designed separately. | US-TP12; FR-26 to FR-29; ADR-0008 |
| 8 | **Art provenance:** ChatGPT image generation (OpenAI), reference Trainers also generated with it from text only; ledger row names the source, cites OpenAI's terms for generated output, and points to the per-folder provenance files. | US-TP01; FR-1; Open Question 7 |
| 9 | **Bundling:** all Trainer art ships inside the app binary (asset catalog); no on-demand download; roughly 15-20 MB added. | US-TP02; FR-2 |
| 10 | **VoiceOver:** each pose pair is one element labeled with the exercise name and what the Trainer shows; single pose names the pose; individual images hidden; no per-pose descriptions. | US-TP09; FR-23 to FR-25 |
| 11 | **Switch-sides beat:** keep showing the same stretch's poses on the per-side "Switch sides" beat. | US-TP08; FR-18 |
| 12 | **Rest overlay on small phones:** shrink the ring and poses until everything fits on a 375x667 pt screen with both controls visible; exact sizes settled from screenshots during the build. | US-TP08, US-TP13; FR-18 |
| 13 | **Card color:** keep the app's card color (`.secondarySystemBackground`) and verify legibility on real screenshots; add a dedicated card color only if a pose reads poorly. | US-TP06, US-TP13; FR-19; Design Considerations |
| 14 | **Choice storage:** the explicit Trainer choice lives in the synced `UserProfile`, alongside the onboarding sex answer, so it follows the user and is erased with the account. | US-TP03, US-TP11; FR-5; Technical Considerations |
| 15 | **"Other" choice overlay:** exactly two options, no "decide later"; when the US-CC13 continuous-circuit explainer is due on the same arrival, the Trainer choice shows first. | US-TP10; FR-8 |
| 16 | **`version2` crawl art:** not bundled now; added by file drop when version 2 restores those movements. | US-TP02; FR-4; Non-Goals |
| 17 | **Attribution:** keep the captain's ledger wording; do not mention the public technique pages; keep the provenance files out of the public repository. | US-TP01; FR-1; Non-Goals |

## Verified facts on current main (2026-10-02)

Every fact the interview relied on was re-checked against `main` at `c55eac8`.
All hold, with the additions and differences marked **(new)**.

- The player has one shared illustration view, `ExerciseIllustration` (`Views/ActiveSession/ActiveSessionView.swift`), hosted by `ExerciseDemoView` (the standalone demo slot) and `WorkWindowCountdownView` (the rep work window, illustration at `size: 132` beside a `CountdownRing` of diameter 132).
  It renders a Lottie clip when `Exercise.animationName` resolves, else a per-`MovementPattern` SF Symbol; no clip ships (`Resources/Exercises.json` contains no `animationName`).
- `HoldCountdownView` replaces the illustration with a full-size (200 pt) `CountdownRing` while a hold runs.
- The player chooses the slot content in `ActiveSessionView.player`: `HoldCountdownView` while `isHolding`, else `WorkWindowCountdownView` when `currentStepAutoAdvances` (a rep-based strength/primal set), else `ExerciseDemoView` (an idle training hold before Start hold, and every rep-based warm-up/cooldown stretch).
  The exercise name and target sit below the card in `exerciseHeadline`.
- The slot height is `ExerciseDemoView.height` = 220 pt, framed by `exerciseSlotCard()` on `Theme.Colors.secondaryBackground` (`.secondarySystemBackground`).
  With the player's `Theme.Spacing.lg` (24 pt) padding, the card is 327 pt wide on a 375 pt phone and 345 pt on a 393 pt phone, which leaves about 147-156 pt per pose in a pair.
- `RestView.nextUp` names the next movement in text only; `viewModel.currentStep` is already the upcoming effort while the rest runs.
  **(new)** The rest overlay distinguishes three rest kinds: `.transition` rests (between stations in a round, between warm-up/cooldown stretches, and at block boundaries) render as the "Next: <exercise>" transition beat; `.roundRest` renders as "Next up ... Round N of M"; the per-side switch-sides beat renders as "Same stretch ... Side 2 of 2".
- Catalog: 76 movements in `Resources/Exercises.json`, 73 served (the three `version2` crawls are withheld by `MockExerciseService`), 26 of them mobility.
  Two entries share the display name "Cossack Squat" (`squat_cossack`, strength; `mobility_cossack`, mobility), and the art has a distinct pair for each in the leg and mobility folders.
- `UserProfile.sex` is `Sex` (`male`/`female`/`other`, `Models/Enums.swift`), captured by the onboarding `SexPicker`; no post-onboarding editor exists.
- `docs/asset-attribution.md` rule: no bundled third-party asset ships without a source/license row first.
- "Coach" is the premium AI chat; the word "trainer" appears nowhere in app code, `CONTEXT.md` or `AGENTS.md` today, so the new term collides with nothing.
- **(new)** Lottie is referenced in more places than the interview listed: the `packages:` entry and its comment in `ios/RepToday/project.yml`, `import Lottie` in `ActiveSessionView.swift`, the `Exercise.animationName` doc comment, a comment in `.github/workflows/ci.yml` ("Lottie stays the app's only dependency"), and the AGENTS.md CI paragraph.
  Beyond `ExerciseLibraryTests.testEveryAnimationNameResolvesToABundledFile`, two more tests depend on the field: `ModelsTests.testExerciseRoundTripWithAnimationName` and `ModelsTests.testExerciseDecodesWithoutAnimationName`.
  `VisualWorkWindowEvidenceTests` asserts the label "Push-up demonstration" inside the work window.
- **(new)** `Exercise` uses synthesized `Codable` (no custom `init(from:)` or `CodingKeys`), so removing `animationName` leaves any persisted record that still carries the key decodable; `JSONDecoder` ignores unknown keys.
  Because the field was always `nil` and synthesized encoding omits `nil` optionals, existing snapshots almost certainly do not carry the key at all.
- **(new)** The art was reviewed against card colors `#202226` (dark) and `#EBEDF0` (light), but the card renders `.secondarySystemBackground`, which is `#1C1C1E` (dark) and `#F2F2F7` (light) in the standard appearance.
  The colors are close; per decision 13 the card keeps its color and legibility is verified on real screenshots (US-TP13).
- **(new)** The countdown ring's track is drawn in `Theme.Colors.surface`, the same color as the card, so today the track is invisible inside the card; once the ring sits on the screen background its track becomes visible.

## Art inventory and coverage (re-run 2026-10-02, read-only)

The coverage check matched each catalog movement's display-name slug (for example "Glute Bridge" -> `glute-bridge-start.png`) against each Trainer's `png/` folder, disambiguating the two "Cossack Squat" entries by family folder.

- **Format** (verified with `sips` on all 302 PNGs): 600x600, 8-bit RGBA, sRGB with an embedded profile, transparent background, every file under 80,000 bytes.
  Each start/end pair shares one frame, so the two poses sit in one fixed square without jumping; the art notes say to display the full 600 px square aspect-fit and never trim transparency.
- **Volume:** 302 PNGs, 17,784,576 bytes in total (151 per Trainer).
  Six of them (the Prone Y, T and W raise variants) map to no catalog movement; the 296 that map to a movement total 17,498,123 bytes.
  The 12 files for the three `version2` crawls total 759,895 bytes and are not bundled now (decision 16).
  The bundled set is therefore 284 PNGs (142 per Trainer, covering the 73 served movements), 16,738,228 bytes of raw PNG.
- **Coverage:** 75 of 76 catalog movements were found by name; the exception is Prone Y-T-W Raises.

| Coverage per Trainer | Male | Female |
| --- | --- | --- |
| Served movements with a full start/end pair | 70 of 73 | 70 of 73 |
| Served movements with one pose only | 2 (end only) | 2 (end only) |
| Served movements with no usable art | 1 | 1 |
| `version2` (withheld) movements with a full pair | 3 of 3 | 3 of 3 |

**Gap list (served movements lacking a full pair):**

- **Wall Scapular Pull** (`pull_wall_scapular_pull`): end pose only, both Trainers.
  It is a beginner staple and the entry rung of the Pull foundation's counting chain (`CONTEXT.md`, "Foundation"), so it is the most visible gap.
- **Reverse Snow Angel** (`pull_reverse_snow_angel`): end pose only, both Trainers.
- **Prone Y-T-W Raises** (`pull_ytw`): no usable art.
  The back folder splits it into Y, T and W variants, each with one pose per Trainer (male: T end, W end, Y end; female: T start, W start, Y end).
- The back folder README promises 32 files (16 per Trainer, including separate Y, T and W pairs); 22 are present (11 per Trainer).
  Re-exporting it would likely close all three gaps.

**Closed since the interview:** the male Assisted Pistol Squat (`squat_pistol_assisted`) now has a full pair, as the captain reported; re-verified.

The full per-movement table is in the appendix.

## User Stories

Every UI story's visual check runs in a booted iOS Simulator (iPhone 16 for the default size and iPhone SE (3rd generation) for the small size), either by hand or through hosted surfaces (`HostedSurface.host(_:size:)` + `AccessibilityTree`) in the `RepToday` unit bundle.
Unit-level behavior is validated in `RepTodayTests` (`@testable import RepToday`).
Each story adds a row to `docs/test-coverage.md` and an entry to `docs/implementation-log.md`.

### US-TP01: Attribution ledger row for the Trainer art

**Description:** As the project owner, I want the Trainer art's source and terms recorded before any of it ships so that the app never distributes an asset with unknown provenance.

**Acceptance Criteria:**

- [ ] `docs/asset-attribution.md` gains a "Trainer pose art" section with a cleared row covering every Trainer image set, landed in the same change as, or before, the first bundled image (US-TP02).
- [ ] The row's source states, in the captain's wording: trainer characters and pose art generated with ChatGPT image generation (OpenAI) from text prompts for RepToday; no third-party artwork or real-person likeness used; OpenAI's terms for generated output apply; provenance retained in each art folder's generation log and manifest.
  The core folder, which has no `generation-log.json`, is handled per Open Question 7.
- [ ] The license/terms column cites OpenAI's Terms of Use section on ownership of output (`https://openai.com/policies/terms-of-use/`), re-read at implementation time so the citation matches the current text.
- [ ] The row uses the captain's wording only and does not mention the public exercise-technique pages the art folders' READMEs list as form references (decision 17).
- [ ] The row names no private filesystem path, account, or personal data, and the provenance files themselves stay in the captain's workspace: no generation log, prompt file, manifest or verification file is committed to this public repository (decision 17).
- [ ] Markdown renders and every link in the section resolves.

**Validation Test:**

- **Setup:** The branch carrying US-TP01.
- **Steps:**
  1. Open `docs/asset-attribution.md` in a Markdown preview.
  2. Compare the source text with the captain's wording in decision 8.
  3. Open the cited OpenAI terms URL.
  4. Check `git log` for the asset catalog: the first commit adding a Trainer image set must not predate this row.
- **Expected Result:** The row is present, matches the captain's wording (with the core folder handled per Open Question 7), and cites the live terms page.
- **Failure Indicator:** A Trainer image is in the bundle with no row, the row paraphrases away "no third-party artwork or real-person likeness", or it adds wording or file names beyond the captain's.

### US-TP02: Bundle the Trainer art in the asset catalog, keyed by exercise id

**Description:** As a user training offline, I want every Trainer image inside the app so that the art appears with no network and no download.

**Acceptance Criteria:**

- [ ] Each mapped PNG becomes one image set in `Resources/Assets.xcassets`, inside a namespaced `Trainer` folder, named by **exercise id**, Trainer and pose (for example `Trainer/female/hinge_glute_bridge-start`), never by display-name slug, so the two "Cossack Squat" entries cannot collide.
- [ ] Image sets are single-scale, universal, rendered as original (not template), and keep the full 600x600 canvas untrimmed.
- [ ] The repository carries a repeatable import step (recommended: a script under `tools/` with an explicit slug-to-id map, run against a copy of the art root) that names every file it skipped; documented in `docs/implementation-log.md`.
- [ ] Art ships for every **served** movement that has art (284 PNGs today).
  The three `version2` crawls' art (12 files) is not bundled now; it is added by file drop, with no code change, when version 2 restores those movements (decision 16).
  The six Prone Y/T/W variant files map to no movement and are not bundled (decision 6 defers their presentation).
- [ ] No Trainer image is tagged for On-Demand Resources or downloaded at runtime.
- [ ] The app-size delta is measured (Release build for a generic iOS device, `.app` size and `Assets.car` size before and after) and recorded in `artifacts/reports/US-TP02/validation.md`; the expected raw PNG payload is about 16.7 MB (16,738,228 bytes).
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.

**Validation Test:**

- **Setup:** A clean checkout of the branch; `xcodegen generate`.
- **Steps:**
  1. Build the `RepToday` scheme for the Simulator.
  2. In a unit test, load `UIImage(named: "Trainer/male/squat_cossack-start", in: appBundle, with: nil)` and `.../mobility_cossack-start`.
  3. Compare the two images' pixel data with the leg-folder and mobility-folder source files.
  4. Turn on Airplane Mode in the Simulator and open a session.
- **Expected Result:** Both Cossack images load and match their own family's source; art renders with no network; the measured size delta is recorded.
- **Failure Indicator:** An image set is named by slug, the two Cossack entries resolve to the same art, an image is trimmed or scaled, or any art is fetched at runtime.

### US-TP03: Trainer preference and default resolution

**Description:** As a user, I want the app to pick the Trainer that matches my onboarding answer so that I see a fitting demonstrator without setting anything up.

**Acceptance Criteria:**

- [ ] A closed `Trainer` enum (`male`, `female`) exists, `Codable`, `CaseIterable` and `Identifiable`, with display copy in one source.
- [ ] The user's explicit choice is stored as an optional field on the synced `UserProfile` (`UserProfile.trainer: Trainer?`), beside the onboarding sex answer, absent by default (decision 14).
- [ ] One pure function resolves the effective Trainer: the explicit choice if present; else `male` for `Sex.male` and `female` for `Sex.female`; else unresolved for `Sex.other`.
- [ ] A profile persisted before this field existed decodes unchanged with the choice absent, so an existing user resolves from their stored sex answer with no migration.
- [ ] An explicit choice wins over the sex default in every case (a male user who picks the female Trainer sees the female Trainer).
- [ ] One write function sets the explicit choice (FR-5): it re-reads the stored user immediately before saving and changes only `profile.trainer`, so a write from a stale snapshot never rolls back another writer's progress or a CloudKit import (the `InjuryFlagsViewModel`/`SessionCompletionService` precedent).
  US-TP10 and US-TP11 both write through it, and nothing else writes `profile.trainer`.
- [ ] Account deletion removes the choice along with the profile, so a fresh onboarding resolves from the new answer.
- [ ] Unit tests cover all nine combinations of sex (male, female, other) x {no choice, male, female} plus the legacy-decode case.
- [ ] A unit test proves the write function keeps a field another writer changed after the caller loaded the user.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.

**Validation Test:**

- **Setup:** Unit test with JSON fixtures for `UserProfile` and an in-memory user service.
- **Steps:**
  1. Decode a profile without the new key for each `Sex` and resolve.
  2. Set an explicit choice opposite to the sex default and resolve.
  3. On an `other` profile, set an explicit male choice and resolve, then an explicit female choice and resolve.
  4. Round-trip a profile with an explicit choice.
  5. Load a user, change its consistency through a second writer, then set the Trainer through the write function from the first load.
- **Expected Result:** male -> male, female -> female, other -> unresolved; the explicit choice always wins, including on an `other` profile; the round trip preserves it; the legacy JSON decodes; the second writer's change survives the Trainer write.
- **Failure Indicator:** A legacy profile fails to decode, "other" silently defaults to a Trainer, an explicit choice on an `other` profile still resolves as unresolved, the sex default overrides an explicit choice, or the Trainer write rolls back the second writer's change.

### US-TP04: Pose resolver

**Description:** As the player, I need one place that answers "which poses exist for this movement and Trainer" so that every surface shows art the same way and a new file lights up with no code change.

**Acceptance Criteria:**

- [ ] One resolver returns, for an exercise id and a Trainer, exactly one of: a start/end pair, a single start pose, a single end pose, or no art.
- [ ] It looks up the asset catalog by the US-TP02 naming convention through an injectable lookup, so tests run without the real bundle.
- [ ] Each Trainer resolves independently (a movement can be a pair for one Trainer and a single pose for the other).
- [ ] Adding a missing image set under the naming convention changes the resolver's answer with no Swift change.
- [ ] Unit tests: `push_wall` resolves to a pair for both Trainers; `pull_wall_scapular_pull` to end only; `pull_ytw` to no art; a stubbed lookup proves per-Trainer independence and the "file drop" upgrade from end-only to pair.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.

**Validation Test:**

- **Setup:** The bundled catalog from US-TP02 plus a stub lookup.
- **Steps:**
  1. Resolve `push_wall`, `pull_wall_scapular_pull` and `pull_ytw` for both Trainers against the real bundle.
  2. With the stub, resolve a movement that has only an end pose, then add a start pose to the stub and resolve again.
- **Expected Result:** pair / end only / no art for the three real lookups; the stubbed movement moves from end only to pair.
- **Failure Indicator:** A partial pair resolves as a pair, a missing movement crashes, or the resolver keys on display name.

### US-TP05: Build-time art gap report

**Description:** As the captain, I want every build to list which served movements still lack a full pair for either Trainer so that missing art stays visible instead of silently falling back.

**Acceptance Criteria:**

- [ ] A build phase on the `RepToday` target, declared in `ios/RepToday/project.yml`, runs a checker under `tools/` that reads `Resources/Exercises.json` and the asset catalog.
- [ ] For every **served** movement (audience not `version2`) and each Trainer lacking a full pair, it prints one Xcode `warning:` line naming the exercise id, display name, Trainer, and the missing pose(s).
- [ ] It prints one `warning:` for any Trainer image set whose name maps to no catalog id or no valid pose, so a misnamed file drop is visible too.
- [ ] Gaps never fail the build; the checker fails the build only if it cannot read its own inputs, so a broken check cannot pass silently.
- [ ] The phase declares its input files so it runs under user-script sandboxing and adds no third-party tool or package.
- [ ] Against today's art the report shows exactly six warnings: Wall Scapular Pull, Reverse Snow Angel and Prone Y-T-W Raises, once per Trainer.
- [ ] The warnings are visible in the CI `ios` job log.

**Validation Test:**

- **Setup:** The branch with US-TP02 and US-TP05.
- **Steps:**
  1. Build the `RepToday` scheme and read the build log's warnings.
  2. Temporarily delete the female `hinge_glute_bridge-start` image set and build again.
  3. Restore it, add an image set named `Trainer/male/not_a_movement-start`, and build again.
- **Expected Result:** Step 1 shows the six expected warnings and the build succeeds; step 2 adds a Glute Bridge warning for the female Trainer; step 3 adds an unknown-asset warning; every build succeeds.
- **Failure Indicator:** No warnings appear, a gap fails the build, a `version2` movement is reported, or the misnamed asset passes unreported.

### US-TP06: Trainer poses on the exercise card

**Description:** As a user mid-session, I want to see the Trainer's start and end positions side by side on the exercise card so that I can tell at a glance how the movement looks.

**Acceptance Criteria:**

- [ ] `ExerciseIllustration` resolves the effective Trainer's poses through the US-TP04 resolver and is the single source for every host (no second copy of the art logic).
- [ ] A full pair renders start on the left and end on the right, each aspect-fit to the full 600x600 canvas, equal in size, inside the card at its current height (`ExerciseDemoView.height`, 220 pt), about 150 pt per pose.
- [ ] A single available pose renders centered in the card.
- [ ] No usable art (today: Prone Y-T-W Raises) renders today's per-`MovementPattern` SF-Symbol glyph with today's behavior.
- [ ] The poses are static: no flipbook, cross-fade, rep-synced change, or pulse.
- [ ] Per-side movements show the art as drawn on both sides (no mirroring for side 2).
- [ ] Every card state shows the art: the rep work window, a running timed hold (US-TP07), an idle training hold before Start hold, and a rep-based warm-up/cooldown stretch.
- [ ] After an in-session swap the card shows the substitute's art with no extra surface.
- [ ] Art renders on the card color in both light and dark appearance.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.
- [ ] Verify in iOS Simulator (iPhone 16 and iPhone SE (3rd generation), light and dark).

**Validation Test:**

- **Setup:** A female-onboarded user; a 15-minute session that includes a rep-based strength set, a warm-up stretch, and (by swap or fixture) Wall Scapular Pull and Prone Y-T-W Raises.
- **Steps:**
  1. Start the session and look at the warm-up stretch card.
  2. Advance to a rep-based strength set.
  3. Swap the current movement.
  4. Reach Wall Scapular Pull, then Prone Y-T-W Raises.
  5. Switch the Simulator to dark appearance and repeat step 2.
- **Expected Result:** Steps 1-3 show the female Trainer's start and end poses side by side, filling the card without changing its height; the swap shows the substitute's poses; Wall Scapular Pull shows one centered end pose; Prone Y-T-W Raises shows the SF-Symbol glyph; dark appearance renders cleanly.
- **Failure Indicator:** The card grows or shrinks, a pose is cropped or the pair jumps between frames, the male Trainer appears, a single pose is left-aligned, or a blank card appears.

### US-TP07: Compact ring beside the exercise name for work windows and holds

**Description:** As a user following along from the floor, I want the poses to keep the whole card while the countdown sits beside the exercise name so that I can read the movement and the time left together.

**Acceptance Criteria:**

- [ ] During a rep work window the card shows the poses only; the countdown is a compact `CountdownRing` beside the exercise name in the headline row.
- [ ] During a running timed hold (bookend or training) the card keeps the poses instead of today's full-card ring, and the same compact ring sits beside the exercise name.
- [ ] When no countdown runs (idle pre-hold, rep-based stretch), the headline row has no ring and the name keeps its full width.
- [ ] The ring keeps its accessibility contract: labels stay "Work window, N seconds remaining" and "Hold, N seconds remaining", `.updatesFrequently` stays, and the sweep stays stilled under Reduce Motion.
- [ ] The exercise name still wraps rather than truncates at the largest Dynamic Type sizes, and the ring's clock still shrinks to fit.
- [ ] Nothing visible without scrolling today moves below the fold on a 375x667 pt screen at default Dynamic Type, and the ring is visible without scrolling there.
- [ ] Every timer behavior is unchanged: auto-start, auto-advance, Done, + More time, Pause/Resume, the halfway and done cues, and the switch-sides beat.
- [ ] `VisualWorkWindowEvidenceTests` and any other suite asserting the ring inside the card are updated to the new layout, keeping their intent (illustration present, ring present, labels exact).
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.
- [ ] Verify in iOS Simulator (iPhone 16 and iPhone SE (3rd generation), light and dark, default and largest accessibility Dynamic Type).

**Validation Test:**

- **Setup:** A session with a rep-based strength set, a warm-up hold, and a training hold.
- **Steps:**
  1. Watch a rep work window run; tap + More time once.
  2. Let the warm-up hold auto-start; let a per-side hold reach "Switch sides".
  3. On the training hold, view the idle card, then tap Start hold.
  4. Repeat steps 1-3 on iPhone SE (3rd generation) and at the largest accessibility text size.
- **Expected Result:** The poses fill the card in every state; a compact ring beside the name counts down during the work window and both holds and extends by 15 s on + More time; the idle card has no ring; nothing is clipped or pushed below the fold on the small phone.
- **Failure Indicator:** The full-size ring replaces the poses during a hold, the ring sits inside the card, the name truncates, or the ring is hidden below the fold on the small phone.

### US-TP08: Next movement's poses on the rest overlay

**Description:** As a user resting between stations or rounds, I want to see the next movement's poses so that I can get into position before the countdown ends.

**Acceptance Criteria:**

- [ ] On a transition beat (every `.transition` rest: between stations, between warm-up/cooldown stretches, and at block boundaries) the upcoming movement's poses appear under "Next: <exercise>".
- [ ] On a between-round rest the upcoming movement's poses appear under the "Next up" text.
- [ ] On the per-side "Switch sides" beat the same stretch's poses appear under the "Same stretch ... Side 2 of 2" text (decision 11), drawn as-is with no mirroring.
- [ ] The poses use the same resolver, Trainer, pair/single/fallback rules and card chrome as the exercise card, so they render on the app's card color.
- [ ] On a 375x667 pt screen at default Dynamic Type the heading, ring, next-up text, poses, and both controls (+15s, Skip rest) are all visible without clipping or overlap, with the controls still pinned at the bottom; the rest ring and the poses shrink as needed to achieve this (decision 12).
- [ ] The exact ring and pose sizes are settled from the US-TP13 screenshots during the build and recorded in `docs/implementation-log.md`.
- [ ] Rest behavior is unchanged: countdown, auto-advance, +15s, Skip rest, Pause/Resume, and cues.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.
- [ ] Verify in iOS Simulator (iPhone 16 and iPhone SE (3rd generation), light and dark).

**Validation Test:**

- **Setup:** A 20-minute session whose strength block has at least two stations and two rounds.
- **Steps:**
  1. Finish the first station's work window and look at the transition beat.
  2. Finish the round and look at the between-round rest.
  3. Reach a per-side warm-up stretch and let side 1 end on the "Switch sides" beat.
  4. Repeat on iPhone SE (3rd generation).
- **Expected Result:** The transition beat and the between-round rest show the next movement's poses, the switch-sides beat shows the same stretch's poses, and on the small phone the ring and poses shrink so everything fits with both controls reachable.
- **Failure Indicator:** The poses show the movement just finished, the overlay clips or overlaps on the small phone, or the controls move.

### US-TP09: VoiceOver for the pose art

**Description:** As a VoiceOver user, I want the pose art announced once, briefly, with the movement name so that I know a demonstration is there without hearing every image.

**Acceptance Criteria:**

- [ ] A pose pair is one accessibility element labeled "<Exercise name>, trainer showing start and end positions" (for example "Glute Bridge, trainer showing start and end positions").
- [ ] A single pose is one element labeled "<Exercise name>, trainer showing end position" or "<Exercise name>, trainer showing start position".
- [ ] The individual pose images are hidden from VoiceOver.
- [ ] No per-pose written description is added; the exercise name and the existing spoken cues carry the instruction.
- [ ] The SF-Symbol fallback keeps today's "<Exercise name> demonstration" label.
- [ ] The same labels apply on the exercise card and the rest overlay.
- [ ] Label strings live in one copy source and are asserted through `AccessibilityTree.spokenStrings(in:)` in a hosted-surface test, which also asserts no element exists per individual image.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.

**Validation Test:**

- **Setup:** VoiceOver on in the Simulator (Accessibility Inspector) or a hosted-surface test.
- **Steps:**
  1. Focus the card on Glute Bridge, Wall Scapular Pull and Prone Y-T-W Raises.
  2. Swipe through the rest overlay's next-up area.
- **Expected Result:** "Glute Bridge, trainer showing start and end positions"; "Wall Scapular Pull, trainer showing end position"; "Prone Y-T-W Raises demonstration"; one focus stop per pose group.
- **Failure Indicator:** Each image is a separate stop, an image announces a file name, or the label omits the exercise name.

### US-TP10: One-time Trainer choice for users who answered "other"

**Description:** As a user who answered "other", I want to choose my Trainer the first time the art appears so that the demonstrator is my choice rather than a guess.

**Acceptance Criteria:**

- [ ] When the effective Trainer is unresolved (US-TP03), arriving at the player shows a choice between the two Trainers before any Trainer art is shown.
- [ ] The choice offers exactly two options, one per Trainer, with no "decide later", skip, or dismiss-without-choosing path (decision 15).
- [ ] Each option is presented per Open Question 4.
- [ ] The choice is a modal overlay layer in the style of the US-CC13 explainer, meets the 60 pt active-screen touch target, and supports VoiceOver, Dynamic Type and Reduce Motion.
- [ ] While the choice is up, the session is handled per Open Question 3.
- [ ] The choice is written through the US-TP03 Trainer write function (FR-5) the moment it is made, and the art appears for the chosen Trainer immediately.
- [ ] Once a choice exists (made here or in Settings), the prompt never appears again.
- [ ] Users whose sex answer is male or female never see the prompt.
- [ ] If the US-CC13 continuous-circuit explainer is also due on the same arrival, the Trainer choice shows first and the explainer follows once a Trainer is chosen; the two are never stacked (decision 15).
- [ ] Unit tests cover show/no-show gating and the session's handling while the choice is up, per Open Question 3; a hosted-surface test covers the overlay's labels.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.
- [ ] Verify in iOS Simulator.

**Validation Test:**

- **Setup:** Fresh install; onboard with sex "other".
- **Steps:**
  1. Start the first session.
  2. Choose the female Trainer.
  3. End the session, start another.
  4. Repeat with a male-onboarded install.
- **Expected Result:** Step 1 shows the choice, with the session handled as Open Question 3 settles; step 2 shows the female poses; step 3 shows no prompt; the male install never sees it.
- **Failure Indicator:** The prompt repeats after a choice, appears for a male or female answer, handles the session other than as Open Question 3 settles, or stacks over the explainer.

### US-TP11: Trainer row in Settings

**Description:** As any user, I want to switch my Trainer in Settings so that I can change the demonstrator whenever I like.

**Acceptance Criteria:**

- [ ] `SettingsView` gains a Trainer row, placed per Open Question 5, styled like the existing Settings rows (`Theme` tokens, `minTouchTarget`, `listRowBackground(Theme.Colors.surface)`).
- [ ] The row shows the effective Trainer (the sex default when no explicit choice exists); for an unresolved "other" user it shows the state set per Open Question 6.
- [ ] Selecting a Trainer persists it as the explicit choice immediately, through the US-TP03 Trainer write function (FR-5); the next exercise card or rest preview uses it.
- [ ] Choosing in Settings satisfies the US-TP10 one-time choice.
- [ ] VoiceOver reads the row's label and current value; the control works at the largest Dynamic Type size.
- [ ] No other Settings section changes.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.
- [ ] Verify in iOS Simulator.

**Validation Test:**

- **Setup:** A male-onboarded user who has never opened the Trainer row.
- **Steps:**
  1. Open Profile -> Settings and read the Trainer row.
  2. Switch to the female Trainer and start a session.
  3. Relaunch the app and reopen Settings.
- **Expected Result:** Step 1 shows the male Trainer; step 2 shows the female poses; step 3 still shows the female Trainer.
- **Failure Indicator:** The row shows nothing for a defaulted user, the change needs a relaunch, or it reverts after relaunch.

### US-TP12: Retire the Lottie demo path

**Description:** As a maintainer, I want the unused Lottie path removed so that the app carries no dead third-party dependency, while every saved session still resumes.

**Acceptance Criteria:**

- [ ] `ios/RepToday/project.yml` no longer declares the Lottie package or depends on it, and its explanatory comment is removed; the regenerated project resolves no Swift package.
- [ ] `import Lottie`, `LottieDemoView`, the Lottie branch of `ExerciseIllustration`, `Exercise.animationName` and its doc comment are removed.
- [ ] `ExerciseLibraryTests.testEveryAnimationNameResolvesToABundledFile` and `ModelsTests.testExerciseRoundTripWithAnimationName` are removed.
- [ ] `ModelsTests.testExerciseDecodesWithoutAnimationName` is replaced by a legacy-decode test: an `Exercise` JSON **carrying** `"animationName"` still decodes, and an `ActiveSessionState` snapshot fixture whose exercises carry the key decodes and resumes.
- [ ] The US-O01 "Lottie fast-follow" language is removed or rewritten in `ActiveSessionView.swift` comments, `AGENTS.md` (the US-CC11 passage and the CI paragraph), `CONTEXT.md` (the US-CC11 story text), `docs/asset-attribution.md` (the "Exercise demo animations (US-O01)" section; the "Removed assets" history stays), and the `.github/workflows/ci.yml` comment.
- [ ] Historical records (`docs/implementation-log.md` entries, older PRDs) stay as point-in-time records; `docs/test-coverage.md` rows for removed tests are updated.
- [ ] `grep -rni lottie ios .github` returns nothing, and `grep -rn animationName ios/RepToday/RepToday` returns nothing.
- [ ] Typecheck, lint, the `RepToday` unit suite, and the `RepTodayUITests` build-for-testing pass.

**Validation Test:**

- **Setup:** On `main`, start a session, complete a few sets, and background the app so a paused snapshot is saved; then install the branch build over it.
- **Steps:**
  1. Launch the branch build and open the Ready Screen.
  2. Resume the paused session.
  3. Run the two grep guards and `xcodegen generate` from a clean clone.
- **Expected Result:** The session resumes at its saved position with the Trainer art showing; both greps return nothing; the project generates and builds with no package resolution.
- **Failure Indicator:** The snapshot fails to decode or is discarded, a Lottie reference survives, or the build still fetches a package.

### US-TP13: Accessibility, appearance and small-phone evidence

**Description:** As the captain, I want one evidence pass across every state on both phone sizes and both appearances so that I can judge the feature pixel by pixel before release.

**Acceptance Criteria:**

- [ ] A hosted-surface suite (for example `TrainerPoseEvidenceTests`) renders production views through `HostedSurface.host(_:size:)` at 393x852 and 375x667 pt in light and dark, writing PNGs through `EvidenceOutput.directory(for:)`.
- [ ] Covered states: rep work window (pair), running hold (pair), idle training hold, rep-based stretch, single-pose movement (Wall Scapular Pull), no-art fallback (Prone Y-T-W Raises), transition beat, between-round rest, the US-TP10 choice overlay, and the US-TP11 Settings row.
- [ ] The suite asserts the US-TP09 labels and the compact ring labels on the live accessibility tree.
- [ ] Committed PNGs and a `validation.md` live under `artifacts/reports/US-TP13/`, regenerated with `REPTODAY_WRITE_EVIDENCE=1`.
- [ ] Covered rest states also include the per-side switch-sides beat, and the 375x667 pt captures are the screenshots that settle the rest-overlay ring and pose sizes (decision 12).
- [ ] Pose legibility on the app's card color (`.secondarySystemBackground`) is judged from these screenshots in light and dark; a dedicated card color is added only if a pose reads poorly, and that finding is recorded in `validation.md` (decision 13).
- [ ] Manual QA recorded in `validation.md`: art legibility on a real device from about 2 m on the floor, light and dark; live VoiceOver focus order; Reduce Motion ring stilling.
- [ ] Typecheck, lint, and the `RepToday` unit suite pass.
- [ ] Verify in iOS Simulator.

**Validation Test:**

- **Setup:** The full feature branch.
- **Steps:**
  1. Run the `RepToday` unit suite with `REPTODAY_WRITE_EVIDENCE=1`.
  2. Open every PNG under `artifacts/reports/US-TP13/`.
  3. Run the manual QA checklist on a device.
- **Expected Result:** Every state renders cleanly on both sizes and appearances with no clipping, misalignment or invisible art; accessibility assertions pass; manual QA items are recorded.
- **Failure Indicator:** A state is missing, art is low-contrast on either card color, anything clips on the small phone, or an assertion fails.

## Functional Requirements

**Provenance and bundling**

- FR-1: `docs/asset-attribution.md` must carry the Trainer art row (decision 8 wording, OpenAI terms citation, provenance pointer) before any Trainer image is bundled, without mentioning the public technique pages, and the provenance files must stay out of this repository.
- FR-2: All Trainer art must ship inside the app binary in the asset catalog, with no On-Demand Resources and no runtime download.
- FR-3: Trainer image sets must be named by exercise id, Trainer and pose, so adding a missing pose is a file drop with no Swift change.
- FR-4: Files that map to no catalog movement (today the Prone Y, T and W variants) and art for `version2` movements must not be bundled; `version2` art is added by file drop when version 2 restores those movements.

**Trainer selection**

- FR-5: The system must store an optional explicit Trainer choice per user in the synced `UserProfile`, so it follows the user and is erased with the account.
  Every write of the choice (the US-TP10 overlay and the US-TP11 Settings row) must go through one write function that re-reads the stored user immediately before saving and changes only `profile.trainer`, so it never rolls back another writer's progress.
- FR-6: The effective Trainer must be the explicit choice if present, else male for a male sex answer, else female for a female sex answer, else unresolved.
- FR-7: Existing users must resolve by the same rule from their stored answer, with no data migration.
- FR-8: An unresolved user must be asked once, on first arrival at the player, before any Trainer art is shown, with exactly two options and no "decide later", and the choice shown before the US-CC13 explainer when both are due; the options' presentation and the session's handling while the choice is up follow Open Questions 4 and 3.
- FR-9: Settings must offer a Trainer row that shows the effective Trainer and sets the explicit choice immediately; its placement and its unresolved state follow Open Questions 5 and 6.

**Display**

- FR-10: A full pair must render start left and end right, side by side, static, aspect-fit to the full untrimmed canvas, inside the exercise card at its current height.
- FR-11: Art must render as drawn; no mirroring for side 2 of a per-side movement.
- FR-12: The exercise card must show the art in the rep work window, the running timed hold, the idle pre-hold, and the rep-based stretch states.
- FR-13: After a swap the card must show the substitute's art.
- FR-14: The countdown ring for a work window and a running hold must render as a compact ring beside the exercise name, outside the card.
- FR-15: The full-size hold ring must no longer replace the art.
- FR-16: The ring's labels, `.updatesFrequently` trait and Reduce Motion behavior must be unchanged.
- FR-17: On a 375x667 pt screen at default Dynamic Type nothing visible without scrolling today may move below the fold.
- FR-18: The rest overlay must show the upcoming movement's art on transition beats and between-round rests, and the same stretch's art on the switch-sides beat, shrinking the ring and poses as needed to fit a 375x667 pt screen with both controls visible.
- FR-19: Art must render on the app's card color (`.secondarySystemBackground`) in both light and dark appearance; a dedicated card color is added only if screenshots show a pose reading poorly.

**Incomplete art**

- FR-20: A movement with only one pose for the effective Trainer must show that pose centered in the card.
- FR-21: A movement with no usable art must show today's SF-Symbol fallback.
- FR-22: Every build must emit one warning per served movement and Trainer lacking a full pair, and one per Trainer image set that maps to nothing, without failing the build.

**Accessibility**

- FR-23: A pose pair must be one accessibility element labeled "<name>, trainer showing start and end positions".
- FR-24: A single pose must be one element labeled "<name>, trainer showing start position" or "<name>, trainer showing end position".
- FR-25: Individual pose images must be hidden from VoiceOver, and no per-pose descriptions may be added.

**Lottie retirement**

- FR-26: The Lottie package, `LottieDemoView`, the Lottie branch of `ExerciseIllustration` and `Exercise.animationName` must be removed.
- FR-27: Any persisted `Exercise` or active-session snapshot that carries `animationName` must still decode and resume.
- FR-28: Lottie-specific tests must be removed or converted as US-TP12 lists, and the legacy-decode guarantee must be tested.
- FR-29: Current-state docs and comments must stop describing a Lottie seam; historical records stay as written.

## Non-Goals (Out of Scope)

- No Trainer art on the Ready-screen session preview or the Progress-tab ladder (a reasonable follow-up once the art is bundled).
- No mirroring of art for side 2 of a per-side movement.
- No presentation for Prone Y-T-W Raises beyond the SF-Symbol fallback; one pair versus three variants is decided once its art exists.
- No motion: no flipbook, cross-fade, rep-synced animation, video, or Lottie replacement; any future motion is designed on its own.
- No on-demand or remote art download.
- No bundled art for the `version2` crawls (Gorilla Walk, Lizard Crawl, Underswitch) until version 2 restores them.
- No dedicated card color for the art unless a pose reads poorly on the app's card color.
- No mention of the public exercise-technique pages in the attribution ledger, and no provenance files (generation logs, prompts, manifests, verification files) in this repository.
- No per-pose written descriptions or spoken pose instructions.
- No editor for the onboarding sex answer, and no change to what the sex answer is used for elsewhere.
- No more than two Trainers.
- No Trainer art in the Coach chat, and no change to the Coach.
- No new telemetry event or property; the 13-event schema is unchanged.
- No engine, timing, completion-logging, cue, or session-persistence change.

## Design Considerations

- **One illustration seam.** `ExerciseIllustration` stays the single source for every host, now resolving Trainer art instead of Lottie; `ExerciseDemoView`, the work window, the hold, and the rest preview all render through it.
- **Card first.** The poses own the card at its current 220 pt height; the countdown moves next to the exercise name, as ADR-0008 records.
  The state tones (US-CC10) already mark every transition, so the ring no longer needs the card.
- **Full canvas, no trimming.** Display the full 600x600 square aspect-fit; trimming transparency or fitting each pose's bounds separately breaks the shared framing and makes poses jump.
- **Card color.** The art is drawn for `#202226`/`#EBEDF0`; the card keeps the app's `.secondarySystemBackground` (decision 13), and legibility is judged from the US-TP13 screenshots; a dedicated card color is added only if a pose reads poorly.
  Rest-overlay art sits in the same card chrome so it is judged on the same color.
- **Rest overlay on small phones.** The rest ring and the poses shrink as needed so a 375x667 pt screen shows everything with both controls visible; sizes are settled from screenshots during the build (decision 12).
- **Ring on the screen background.** Out of the card, the ring's `Theme.Colors.surface` track becomes visible on `systemBackground`; check it in both appearances.
- **Copy.** All new strings (Trainer names, the choice overlay, the Settings row, accessibility labels) live in one copy source each, identity-framed and plain, never loss-framed.
- **Reuse.** The choice overlay follows `ContinuousCircuitExplainerView` (overlay layer, `.isModal`, Reduce Motion stilling); whether it also holds a user pause while shown is Open Question 3.
  The Settings row follows the existing rows in `SettingsView`.

## Technical Considerations

- **Storage of the choice (decision 14).** `UserProfile.trainer: Trainer?` keeps the choice with the user's other onboarding answers, so it follows them across devices through the CloudKit-mirrored Cloud store and is erased by account deletion with no separate reset.
  It decodes as `nil` from every existing profile, which is exactly "derive from the sex answer".
  A device-local `AppState` key was rejected because it would need its own reset on account deletion and would not follow the user.
  Because `UserServiceProtocol.save(_:)` writes the whole `User` aggregate, both choice surfaces write through the one FR-5 function that re-reads the stored user and changes only `profile.trainer`.
- **Asset catalog.** Single-scale universal image sets avoid 1x/2x/3x duplication; the 600 px source covers about 150 pt at 3x (450 px).
  `actool` may recompress, so measure the archived size rather than assuming the raw 16.7 MB.
- **Memory.** At most four 600x600 images are on screen at once (about 1.4 MB decoded each); no caching layer is needed beyond the system's.
- **Resolver lookup.** Use an injectable "does this image set exist" lookup (`UIImage(named:in:with:)` in production) so unit tests do not depend on the bundle.
- **Build phase.** Declare `inputFiles` for `Exercises.json` and the asset catalog so the phase runs under `ENABLE_USER_SCRIPT_SANDBOXING`; use only tools available on stock macOS and the CI runner.
- **Snapshot compatibility.** Synthesized `Codable` ignores unknown keys, so removing `animationName` is safe; the US-TP12 legacy fixture makes that guarantee executable.
- **Evidence.** Hosted surfaces go through `HostedSurface.host(_:size:)` and `AccessibilityTree`, and PNG paths through `EvidenceOutput.directory(for:)`, per `AGENTS.md`.
- **Dependency.** After US-TP12 the app has no third-party Swift package; update the CI comment and the AGENTS.md CI paragraph that say Lottie is the only one.
- **Order.** US-TP01 lands no later than US-TP02; US-TP03 and US-TP04 precede the UI stories; US-TP12 can land once US-TP06 has replaced the Lottie branch; US-TP13 closes the PRD.

## Success Metrics

- 70 of 73 served movements show a full pair for both Trainers at launch; all 73 once the back folder is re-exported and Prone Y-T-W is presented.
- The build-time report lists exactly the known gaps (six warnings today) and nothing unexpected.
- Zero layout regressions: on a 375x667 pt screen nothing visible without scrolling today moves below the fold, confirmed by the US-TP13 evidence.
- The measured app-size increase stays within the 15-20 MB the captain was told (about 16.7 MB of raw PNG is bundled); any excess is reported, not silently shipped.
- Third-party Swift packages drop from one to zero.
- Every saved active-session snapshot from before the change still resumes.
- The captain signs off the US-TP13 evidence as pixel-correct in both appearances and both phone sizes.

## Open Questions

Questions 1-7 of the first draft were settled by the captain on 2026-10-02 and are now decisions 11-17 above.
The items below remain open.
Items 3-7 are product choices the interview did not settle; each carries a marked recommendation, the acceptance criteria that depend on one say "per Open Question N", and the captain's answer is needed before the story that depends on it starts.

1. **Captain action before release (recommended, not confirmed done).** Re-export the back folder (README lists 32 files, 22 present), which likely closes Wall Scapular Pull (a beginner staple and the Pull foundation's entry rung) and Reverse Snow Angel, and supplies Y, T and W pairs for the deferred Prone Y-T-W decision.
2. **Go-ahead.** Implementation is not authorized; the captain confirms the go before any story starts.
3. **The session while the Trainer choice is up (US-TP10, FR-8).** Decision 15 settles the options and the order relative to the US-CC13 explainer, but not what happens to the session behind the choice.
   The player has already started by then, so the first work window or hold would otherwise count down behind an overlay that cannot be dismissed without choosing.
   **Recommendation:** hold the session on a US-CC06 user pause while the choice is up, as the US-CC13 explainer does, and resume from the exact remainder once a Trainer is chosen.
4. **What each Trainer option shows (US-TP10, FR-8).** Decision 15 settles exactly two options but not how each is presented.
   **Recommendation:** show each Trainer's start pose for the current movement (its single available pose if the start is missing, or the Trainer's name alone if it has none), so the user picks the demonstrator they are about to see.
5. **Where the Trainer row sits in Settings (US-TP11, FR-9).** Decision 1 adds a Settings row but does not place it.
   **Recommendation:** a new Trainer section above the destructive Account section, so the destructive action stays last, in the existing section style.
6. **What the Settings row shows before an "other" user chooses (US-TP11, FR-9).** Decision 1 gives that user no default, so the row has no effective Trainer to show.
   **Recommendation:** a neutral "Not chosen yet" value, never a guessed Trainer.
7. **The core folder's provenance file names (US-TP01).** The captain's ledger wording (decision 8, kept by decision 17) says provenance is "retained in each art folder's generation log and manifest".
   The core folder holds `prompts.json`, `manifest.json` and `verification.json` and no `generation-log.json`, while the back, leg, mobility and primal folders and the push folder's `Male`/`Female` subfolders each hold a `generation-log.json`.
   **Recommendation:** keep the captain's wording verbatim with no file names added to the public row, and have the captain confirm that the core folder's `prompts.json` counts as its generation log; otherwise the captain amends the wording for the core folder or adds a `generation-log.json` to it.

## Appendix: per-movement coverage (2026-10-02)

"pair" = start and end present; "end only" = only the end pose; "none" = no file matches the movement.
`version2` movements are withheld from every user, excluded from the build-time gap report, and their art is not bundled now (decision 16).

| Art folder | Exercise id | Display name | Audience | Male | Female |
| --- | --- | --- | --- | --- | --- |
| push | `push_wall` | Wall Push-Up | beginner | pair | pair |
| push | `push_incline` | Incline Push-Up | beginner | pair | pair |
| push | `push_knee` | Knee Push-Up | beginner | pair | pair |
| push | `push_standard` | Standard Push-Up | beginner | pair | pair |
| push | `push_diamond` | Diamond Push-Up | intermediate | pair | pair |
| push | `push_archer` | Archer Push-Up | advanced | pair | pair |
| push | `push_one_arm_assisted` | Assisted One-Arm Push-Up | advanced | pair | pair |
| push | `push_one_arm` | One-Arm Push-Up | advanced | pair | pair |
| push | `push_floor_dips` | Floor Tricep Dips | beginner | pair | pair |
| push | `push_pike` | Pike Push-Up | advanced | pair | pair |
| back | `pull_superman` | Superman Hold | beginner | pair | pair |
| back | `pull_reverse_snow_angel` | Reverse Snow Angel | advanced | end only | end only |
| back | `pull_ytw` | Prone Y-T-W Raises | advanced | none | none |
| back | `pull_wall_scapular_pull` | Wall Scapular Pull | beginner | end only | end only |
| back | `pull_floor_row` | Supine Floor Row | intermediate | pair | pair |
| back | `pull_floor_row_single_arm` | Single-Arm Supine Floor Row | advanced | pair | pair |
| leg | `squat_wall_sit` | Wall Sit | beginner | pair | pair |
| leg | `squat_bodyweight` | Bodyweight Squat | beginner | pair | pair |
| leg | `squat_sumo` | Sumo Squat | intermediate | pair | pair |
| leg | `squat_cossack` | Cossack Squat | advanced | pair | pair |
| leg | `squat_shrimp` | Shrimp Squat | advanced | pair | pair |
| leg | `squat_pistol_assisted` | Assisted Pistol Squat | advanced | pair | pair |
| leg | `squat_pistol` | Pistol Squat | advanced | pair | pair |
| leg | `lunge_reverse` | Reverse Lunge | beginner | pair | pair |
| leg | `lunge_split_squat` | Split Squat | intermediate | pair | pair |
| leg | `hinge_glute_bridge` | Glute Bridge | beginner | pair | pair |
| leg | `hinge_single_leg_bridge` | Single-Leg Glute Bridge | beginner | pair | pair |
| leg | `hinge_bridge_march` | Marching Glute Bridge | intermediate | pair | pair |
| leg | `hinge_long_lever_bridge` | Long-Lever Single-Leg Bridge | advanced | pair | pair |
| leg | `hinge_nordic_assisted` | Assisted Nordic Curl | advanced | pair | pair |
| leg | `hinge_nordic` | Nordic Curl | advanced | pair | pair |
| leg | `hinge_good_morning` | Bodyweight Good Morning | beginner | pair | pair |
| leg | `hinge_single_leg_rdl` | Single-Leg Romanian Deadlift | intermediate | pair | pair |
| core | `core_forearm_plank` | Forearm Plank | beginner | pair | pair |
| core | `core_side_plank` | Side Plank | intermediate | pair | pair |
| core | `core_bird_dog` | Bird Dog | beginner | pair | pair |
| core | `core_dead_bug` | Dead Bug | intermediate | pair | pair |
| core | `core_bear_hold` | Bear Hold | advanced | pair | pair |
| core | `core_hollow_hold` | Hollow Hold | advanced | pair | pair |
| core | `core_hollow_rock` | Hollow Rock | advanced | pair | pair |
| core | `core_tuck_l_sit` | Tuck L-Sit | advanced | pair | pair |
| core | `core_one_leg_l_sit` | One-Leg L-Sit | advanced | pair | pair |
| core | `core_l_sit` | L-Sit | advanced | pair | pair |
| primal | `primal_bear_crawl` | Bear Crawl | beginner | pair | pair |
| primal | `primal_crab_walk` | Crab Walk | intermediate | pair | pair |
| primal | `primal_ground_to_standing` | Ground-to-Standing Get-Up | advanced | pair | pair |
| primal | `primal_bear_shoulder_tap` | Bear Hover Shoulder Tap | advanced | pair | pair |
| primal | `primal_gorilla_walk` | Gorilla Walk | version2 | pair | pair |
| primal | `primal_lizard_crawl` | Lizard Crawl | version2 | pair | pair |
| primal | `primal_underswitch` | Underswitch | version2 | pair | pair |
| mobility | `mobility_deep_squat_hold` | Deep Squat Hold | beginner | pair | pair |
| mobility | `mobility_9090_hip` | 90/90 Hip Stretch | advanced | pair | pair |
| mobility | `mobility_cat_cow` | Cat-Cow Flow | beginner | pair | pair |
| mobility | `mobility_thoracic_rotation` | Thoracic Rotations | advanced | pair | pair |
| mobility | `mobility_worlds_greatest` | World's Greatest Stretch | advanced | pair | pair |
| mobility | `mobility_pigeon` | Pigeon Pose | advanced | pair | pair |
| mobility | `mobility_frog` | Frog Stretch | advanced | pair | pair |
| mobility | `mobility_down_dog` | Downward Dog | beginner | pair | pair |
| mobility | `mobility_kneeling_hip_flexor` | Kneeling Hip-Flexor Stretch | beginner | pair | pair |
| mobility | `mobility_wall_chest_opener` | Wall Chest Opener | beginner | pair | pair |
| mobility | `mobility_forward_fold` | Standing Forward Fold | beginner | pair | pair |
| mobility | `mobility_childs_pose` | Child's Pose | beginner | pair | pair |
| mobility | `mobility_lizard_lunge` | Lizard Lunge | advanced | pair | pair |
| mobility | `mobility_supine_twist` | Supine Spinal Twist | beginner | pair | pair |
| mobility | `mobility_thread_needle` | Thread the Needle | advanced | pair | pair |
| mobility | `mobility_standing_quad` | Standing Quad Stretch | beginner | pair | pair |
| mobility | `mobility_figure_four` | Figure-Four Glute Stretch | beginner | pair | pair |
| mobility | `mobility_wall_calf` | Wall Calf Stretch | beginner | pair | pair |
| mobility | `mobility_butterfly` | Butterfly Stretch | beginner | pair | pair |
| mobility | `mobility_cobra` | Cobra Stretch | beginner | pair | pair |
| mobility | `mobility_puppy_pose` | Puppy Pose | advanced | pair | pair |
| mobility | `mobility_cossack` | Cossack Squat | advanced | pair | pair |
| mobility | `mobility_hip_circles` | Hip Circles | beginner | pair | pair |
| mobility | `mobility_side_bend` | Standing Side Bend | beginner | pair | pair |
| mobility | `mobility_ankle_rocks` | Ankle Rocks | advanced | pair | pair |
| mobility | `mobility_arm_circles` | Arm Circles | beginner | pair | pair |
