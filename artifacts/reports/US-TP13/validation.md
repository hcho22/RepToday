# US-TP13 validation - Trainer pose art evidence

Date: 2026-10-02.
Branch: `fm/reptoday-trainer-images`.
Spec: `.claude/agent/tasks/prd-trainer-pose-art_261002.md`; decision: `docs/adr/0008-static-trainer-pose-art-replaces-lottie-demo.md`.

## How the PNGs here are produced

`TrainerPoseEvidenceTests` (in the `RepToday` unit bundle) hosts the production `ActiveSessionView` and `SettingsView` over real catalog movements and the real bundled art, asserts the accessibility contract on the live tree, and writes one PNG per state, size and appearance.

```bash
xcodebuild -project ios/RepToday/RepToday.xcodeproj -scheme RepToday \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RepTodayTests/TrainerPoseEvidenceTests REPTODAY_WRITE_EVIDENCE=1 test
```

Sizes: 393x852 pt (iPhone 16) and 375x667 pt (iPhone SE, 3rd generation), each in dark and light.
The small size is rendered with an iPhone SE's own safe area (a 20 pt status bar, no home indicator) through `HostedSurface.host(_:size:style:emulatingSafeArea:)`, so it is faithful on whichever Simulator runs the suite.
Settings and the largest-text capture are hosted at full content height (`*-x1400`, `*-x1100`) so the row and the wrapped name are in frame.

## States covered

| File prefix | State | Asserted on the live tree |
| --- | --- | --- |
| `01-rep-work-window-pair` | Rep work window, female Trainer, Glute Bridge | "Glute Bridge, trainer showing start and end positions"; "Work window, N seconds remaining"; ring 80 pt and above the controls |
| `02-running-hold-pair` | Auto-started warm-up hold, male Trainer, Deep Squat Hold | pair label; "Hold, N seconds remaining"; ring compact and above the controls |
| `03-idle-training-hold` | Training hold before Start hold, Forearm Plank | pair label; no ring; Start hold present; starting it brings the ring and keeps the poses |
| `04-rep-based-stretch` | Rep-based warm-up stretch, Cat-Cow Flow | pair label; no ring |
| `05-single-pose` | Wall Scapular Pull (end pose only) | "Wall Scapular Pull, trainer showing end position"; centered |
| `06-no-art-fallback` | Prone Y-T-W Raises (no usable art) | "Prone Y-T-W Raises demonstration"; no Trainer label |
| `07-transition-beat` | Between-station transition beat | "Next: Bodyweight Squat"; Bodyweight Squat's pair; fit (below) |
| `08-between-round-rest` | Between-round rest | "Next up, Wall Push-Up"; Wall Push-Up's pair; fit |
| `09-switch-sides-beat` | Per-side warm-up stretch, switch-sides beat | "Same stretch"; Kneeling Hip-Flexor Stretch's pair; fit |
| `10-trainer-choice` | One-time Trainer choice for an "other" user | title, exactly "Male Trainer" and "Female Trainer" (hint, at least 60 pt tall), no Trainer art yet, the work window frozen behind it, no explainer; choosing "Female Trainer" by VoiceOver activation shows her art, stores her, and the explainer follows |
| `11-settings-trainer-row` | Settings, male answer | row "Trainer" with value "Male Trainer", above Account |
| `12-settings-trainer-not-chosen` | Settings, unresolved "other" | value "Not chosen yet" |
| `13-largest-dynamic-type-work-window` | `accessibility5`, Long-Lever Single-Leg Bridge, SE width | the name wraps beside the compact ring and never runs under it |

The harness renders dark captures with the app scene in dark as well (`HostedSurface.host` sets the scene's trait override), so the accent color resolves to its dark variant exactly as it does on a device.

Every state also asserts one focus stop per pose group and no element named after an image file or an individual pose.
A swap showing the substitute's poses is asserted without a capture (`testSwapShowsTheSubstitutesPoses`).

## Rest overlay sizes (decision 12)

Both pieces are flexible: the ring within 96-200 pt and the pose card within 110-220 pt, with the overlay's middle taking the height before its spacers.
Measured by the suite's fit assertions (`US-TP13 REST FIT` lines in the test log):

| Size | Rest ring | Pose group | Controls |
| --- | --- | --- | --- |
| 393x852 | 197-200 pt | 160 pt | on screen, below the poses |
| 375x667 (SE) | 141-151 pt | 125-135 pt | on screen, below the poses |

Heading, ring, next-up text, poses and both controls (+15s, Skip rest) stack without overlap on both sizes.

## Card color (decision 13)

Judged from the dark and light captures: the art reads clearly on `.secondarySystemBackground` in both appearances, so no dedicated card color was added.
The compact ring's track (`Theme.Colors.surface`) is visible on the screen background in both appearances, as the PRD anticipated.

## Control label contrast on the player

Measured from the `08-between-round-rest` and `02-running-hold-pair` captures by sampling the button fill and the label's glyph color and computing the WCAG contrast ratio.
The labels are `Theme.Typography.button` (17 pt semibold), which is not WCAG "large text", so the bar is 4.5:1.

| Label | Appearance | Before | After |
| --- | --- | --- | --- |
| "+15s" (rest overlay) | dark | 4.47:1 (accent `#788F9E` on fill `#262629`) | 15.09:1 (`Theme.Colors.textPrimary`) |
| "+15s" (rest overlay) | light | 7.20:1 (accent `#2E4F61` on fill `#E9E9EB`) | 17.32:1 |
| "Stop hold" (player) | dark | 4.47:1 (same accent on the same fill) | 15.09:1 |
| "Stop hold" (player) | light | 7.20:1 | 17.32:1 |

Both are `.bordered` buttons whose label took the accent color; they now use the primary text token, and the gray fill keeps them visibly secondary to the prominent button beside them.

Not changed here, recorded for the captain:

- The same accent-on-gray `.bordered` label measures 4.47:1 in dark on four other screens outside this feature (`ReadyView.swift` two buttons, `ProgressTabView.swift`, `OnboardingView.swift`).
- White text on the dark-mode accent in every `.borderedProminent` button ("Skip rest", "Done", "Start hold", and app-wide) measures 3.38:1 (light mode 8.72:1); it passes only the 3:1 large-text bar.
  Fixing it means changing the dark AccentColor or the `onAccent` token, which is a brand decision.

## Fold check (FR-17)

At default Dynamic Type on the emulated SE the exercise name and the compact ring end above the controls, as the name did before this change; the ring sits beside the name, so the headline row is no taller.
At the largest accessibility text size the headline sits below the fold on the SE, exactly as the name did before (the controls grow too); it remains reachable by scrolling.

## Manual QA for the captain (not run here)

Physical-device checks this suite cannot make, left for the captain:

- [ ] Art legibility on a real phone from about 2 m on the floor, light and dark.
- [ ] Live VoiceOver focus order through the card, the headline, the ring and the controls, and on the rest overlay.
- [ ] Reduce Motion: the compact ring and the rest ring step rather than sweep; the glyph fallback is still.
- [ ] The Trainer choice and Settings switch on a device signed in to iCloud, then the choice on a second device after sync.
