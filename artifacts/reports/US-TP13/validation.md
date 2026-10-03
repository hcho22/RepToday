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
So is Settings left open on the Profile tab showing the Trainer a player choice stored once the tab returns (`testSettingsTrainerRowRereadsWhenTheTabReturns`).

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

## Control label contrast

Measured from the `08-between-round-rest` and `02-running-hold-pair` captures by sampling the button fill and the label's glyph color and computing the WCAG contrast ratio.
The labels are `Theme.Typography.button` (17 pt semibold), which is not WCAG "large text", so the bar is 4.5:1.

| Label | Appearance | Before | After |
| --- | --- | --- | --- |
| "+15s" (rest overlay) | dark | 4.47:1 (accent `#788F9E` on fill `#262629`) | 15.09:1 (`Theme.Colors.textPrimary`) |
| "+15s" (rest overlay) | light | 7.20:1 (accent `#2E4F61` on fill `#E9E9EB`) | 17.32:1 |
| "Stop hold" (player) | dark | 4.47:1 (same accent on the same fill) | 15.09:1 |
| "Stop hold" (player) | light | 7.20:1 | 17.32:1 |

Both are `.bordered` buttons whose label took the accent color; they now use the primary text token, and the gray fill keeps them visibly secondary to the prominent button beside them.

One sweep of every `.bordered` button in the app found one more with the same accent-on-gray label: "Back" in onboarding (`OnboardingView.swift`).
It is fixed the same way, with `Theme.Colors.textPrimary` (and `Theme.Colors.textSecondary` while it is disabled during the final save).
The other three `.bordered` buttons already set their own label color and never had the defect: "Got it" on the classics note (`ReadyView.swift`, primary text), "Discard" on the resume card (`ReadyView.swift`, secondary text), and "Got it" on the foundations note (`ProgressTabView.swift`, primary text).

### White on the accent in `.borderedProminent` buttons (open brand-color question)

White (`Theme.Colors.onAccent`) on the dark-mode accent `#788F9E` measures 3.38:1; in light mode, on `#2E4F61`, it measures 8.72:1.
Every `.borderedProminent` label in the app ("Start", "Resume", "Done", "Start hold", "Skip rest", "Keep climbing", "Got it", the onboarding primary, the Coach accept buttons) uses `Theme.Typography.button`: the `headline` style, semibold, which scales with Dynamic Type.
The app does not limit Dynamic Type, so every size applies: 14 pt (xSmall), 15, 16, 17 pt (Large, the default), 19, 21, 23, and 28-53 pt at the accessibility sizes.
WCAG large text is at least 18 pt regular or at least 14 pt bold, and semibold (weight 600) is not bold (weight 700 and up).
So these labels are large text only at xLarge (19 pt) and above, where the bar is 3:1 and 3.38:1 passes.
At the default size and the three smaller ones (14-17 pt) they are not large text, the bar is 4.5:1, and 3.38:1 fails in dark mode.
Light mode passes at every size.

This is left open for the captain as a brand-color question: meeting 4.5:1 in dark mode means changing the dark AccentColor or the `onAccent` token, which this change does not do.
The same white-on-accent pairing also draws the Theme-styled accent fills (selected duration and onboarding chips, the paywall purchase button, the Coach's user bubble), so one decision covers them too.

## Fold check (FR-17)

At default Dynamic Type on the emulated SE the exercise name, the compact ring and the whole round tracker (its label and set dots) end inside the player's scroll area, above the controls, in the rep work window, a running hold, a single-pose movement and the no-art fallback.
A name that wraps beside the ring makes the headline row taller, so on the SE the exercise card shrinks its poses to make room, never below the rest preview's 110 pt card floor; on the 393x852 phone the card keeps its full 220 pt and each pose about 160 pt.
Starting a training hold on the SE brings the ring in beside the name, so the poses can shrink a few points as the hold starts (8.5 pt for Forearm Plank).
At the largest accessibility text size the headline sits below the fold on the SE, exactly as the name did before (the controls grow too); it remains reachable by scrolling.

## Manual QA for the captain (not run here)

Physical-device checks this suite cannot make, left for the captain:

- [ ] Art legibility on a real phone from about 2 m on the floor, light and dark.
- [ ] Live VoiceOver focus order through the card, the headline, the ring and the controls, and on the rest overlay.
- [ ] Reduce Motion: the compact ring and the rest ring step rather than sweep; the glyph fallback is still.
- [ ] The Trainer choice and Settings switch on a device signed in to iCloud, then the choice on a second device after sync.
