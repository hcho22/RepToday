# Dark-appearance accent contrast - validation

## What was asked

In dark appearance every filled accent button drew its white label (`Theme.Colors.onAccent`) on the dark AccentColor `#788F9E`, which measures 3.38:1.
The labels use `Theme.Typography.button` (17 pt semibold at the default size), which is not WCAG large text, so the bar is 4.5:1.
The light-appearance accent `#2E4F61` already passed (8.72:1) and stays unchanged.
This was recorded as an open question in `artifacts/reports/US-TP13/validation.md` ("White on the accent in `.borderedProminent` buttons").

## Why one shade could not do it

WCAG contrast depends only on relative luminance (L), so no hue or chroma adjustment changes it.
White on the accent reaches 4.5:1 only when L(accent) <= 0.183.
Accent-colored small text on `#1C1C1E` (cards, inset-grouped list rows, a dark sheet's background) reaches 4.5:1 only when L(accent) >= 0.228.
The ranges are disjoint, and the app has small accent text on `#1C1C1E`: the Settings "Privacy Policy" link, the injury screen's "Try again", the Coach failure banner's "Try again", and the paywall's "Restore purchases", "Retry plans", "Terms of Use" and "Privacy Policy".
The smallest same-hue single shade (`#637988`) would have dropped those from 5.03:1 to 3.74:1.

The captain chose option A plus fixes for the three spots that already fell short ("A plus the three fixes", 2026-10-05).

## What changed

| Token (asset) | Light | Dark | Used for |
| --- | --- | --- | --- |
| `Theme.Colors.accent` (`AccentColor`) | `#2E4F61` (unchanged) | `#788F9E` (unchanged) | Text, icons, links, toggles, rings, bars |
| `Theme.Colors.accentFill` (`AccentFill`, new) | `#2E4F61` | `#637988` | Every fill that carries white content |
| `Theme.Colors.onAccentSecondary` (`OnAccentSecondary`, new) | white at 90% | white at 100% | Paywall plan price and trial lines, chevron |
| `Theme.Colors.accentBadgeFill` (`AccentBadgeFill`, new) | accent at 12% | accent at 8% | The Profile "Premium" badge's wash |
| `Theme.Colors.accentOnElevatedSurface` (`AccentOnElevatedSurface`, new) | `#2E4F61` | `#788F9E`, `#7E96A5` in a sheet | The injury screen's "Try again", whose coach-routed sheet raises its rows to `#2C2C2E` |

`#637988` keeps the accent's OKLCH hue and chroma and lowers lightness by 0.071; it is the lightest 8-bit shade on that line that reaches 4.5:1.
`#7E96A5` is the same hue raised by 0.022, the smallest 8-bit step that clears 4.5:1 on `#2C2C2E`.
The token resolves to it only at the elevated interface level a sheet uses, so the same screen pushed from Settings keeps the text accent.
8% is the largest whole-percent wash that keeps the badge caption at 4.5:1.

Every prominent button now goes through `View.accentFilledButtonStyle()` (`DesignSystem/AccentFilledButtonStyle.swift`), which is `.borderedProminent` tinted with `accentFill`.
The selected duration, rating and onboarding chips, the Coach's user bubble, the paywall plan card and the injury Save button fill with `accentFill` directly.
Light appearance renders exactly as before: every new token equals the old light value.
No layout, copy or behavior changed.

## Before and after, dark appearance

Ratios are computed from the 8-bit sRGB values the asset catalog ships; surfaces are the system's dark colors.
Text needs 4.5:1, large text (22 pt semibold and up here) and non-text UI need 3:1.

| Usage | Bar | Before | After |
| --- | --- | --- | --- |
| White label on filled controls: prominent buttons, selected chips, Coach user bubble, paywall plan name, injury Save | 4.5 | 3.38 fail | 4.54 pass |
| Paywall plan price and trial lines on the plan card | 4.5 | 3.06 fail | 4.54 pass |
| Profile "Premium" badge caption on its wash over `#1C1C1E` | 4.5 | 4.27 fail | 4.53 pass |
| Injury "Try again" on the coach sheet's raised row `#2C2C2E` | 4.5 | 4.12 fail | 4.51 pass |
| Injury "Try again" on the pushed Settings row `#1C1C1E` | 4.5 | 5.03 pass | 5.03 pass |
| Accent small text on `#000` (onboarding Privacy Policy link, "Signed in with Apple", navigation back buttons) | 4.5 | 6.21 pass | 6.21 pass |
| Accent small text on `#1C1C1E` (Settings Privacy Policy link, Coach "Try again", paywall Restore/Retry/Terms/Privacy) | 4.5 | 5.03 pass | 5.03 pass |
| Accent large text on `#1C1C1E` (consistency scores, Progress tiles, completion stats) | 3 | 5.03 pass | 5.03 pass |
| Accent large text on `#000` (player target, transition "Next" name) | 3 | 6.21 pass | 6.21 pass |
| Accent icons, countdown ring, progress bar on `#000` | 3 | 6.21 pass | 6.21 pass |
| Accent icons, ladder markers, chart bars, calendar dots, toggles on `#1C1C1E` | 3 | 5.03 pass | 5.03 pass |
| Accent icon on the policy-note wash (accent 10% over `#000`) | 3 | 5.71 pass | 5.71 pass |
| Accent icon on the upsell card wash (accent 8% over `#000`) | 3 | 5.81 pass | 5.81 pass |
| Accent bar on its 12% track over `#1C1C1E` (Progress capsules) | 3 | 4.27 pass | 4.27 pass |
| White toggle knob on the accent track | 3 | 3.38 pass | 3.38 pass |
| Filled control against the `#000` page | 3 | 6.21 pass | 4.62 pass |
| Filled control against a `#1C1C1E` sheet (paywall plan card) | 3 | 5.03 pass | 3.74 pass |
| Progression-map ladder rail (accent 50% on `#1C1C1E`) | decorative | 2.24 | 2.24 |

The ladder rail is decorative and hidden from accessibility, so no ratio applies; it is out of scope.
A filled control's edge is not required to contrast with the page because its label identifies it, and it still clears 3:1.

Light appearance, unchanged: white on `#2E4F61` 8.72:1, the price line at 90% white 7.44:1, accent text on white 8.72:1, the badge caption 6.49:1.

## Automated regression checks

`RepTodayTests/AccentContrastTests` resolves every color from the shipped asset catalog and every surface from the system's dynamic colors under the matching trait collection (light, dark, dark elevated), then asserts:

- white and `OnAccentSecondary` on `AccentFill` reach 4.5:1 in light, dark and a dark sheet;
- `AccentColor` text reaches 4.5:1 on every background, card, grouped row and sheet background it sits on;
- `Theme.Colors.accentOnElevatedSurface` reaches 4.5:1 on its row in light, dark and a dark sheet;
- the badge caption reaches 4.5:1 on its wash in both appearances;
- light appearance, the dark text accent and `accentOnElevatedSurface` outside a sheet are pinned to their values.

Non-vacuity, checked 2026-10-05: restoring the old values (dark `AccentFill` = `#788F9E`, the badge wash at 12%, the price line at 90%, the Retry color = the accent) failed every test except the `AccentColor`-text one, with the expected ratios (3.38, 3.06, 4.27, 4.12); the new values pass them all.

## Screens (dark appearance)

`RepTodayTests/DarkAccentContrastEvidenceTests` hosts the production surfaces in dark appearance and writes these PNGs (regenerate with `REPTODAY_WRITE_EVIDENCE=1`).
For Start moving, Start, Done, Skip rest, the paywall plan card and the coach's injury-offer button it also reads the fill back off the rendered pixels and asserts `#637988` (within 2/255) with white at 4.5:1 or better.
The paywall and the coach-routed injury screen are hosted at the elevated interface level a sheet uses (`HostedSurface.host(level: .elevated)`), and the injury tests read back both the row behind "Try again" and the label's own color: `#7E96A5` on the sheet's raised `#2C2C2E` row, the unchanged `#788F9E` on the pushed screen's `#1C1C1E` row.

- `01-onboarding-duration.png` - selected duration chip, "Start moving"
- `02-ready.png` - selected duration chip, "Start"
- `03-player-work-window.png` - "Done"
- `04-rest-overlay.png` - "Skip rest" beside the unchanged accent ring and "Next" name
- `05-paywall-sheet.png` - plan cards with full-white price lines, accent links on the sheet background
- `06-coach-bubble-and-retry.png` - the user's bubble, the failure banner's "Try again"
- `07-coach-injury-offer.png` - the coach's filled accept button
- `08-profile-premium-badge.png` - the "Premium" badge on its 8% wash
- `09-injury-retry-sheet.png` - "Try again" on the sheet's raised row
- `10-injury-retry-pushed.png` - "Try again" pushed from Settings, in the unchanged text accent

## Notes

Earlier stories' committed dark baselines (for example `US-TP13`, `US-AC02`) still show the old fill; they are point-in-time records and were not regenerated.
Seen while capturing, out of scope for this change: the injury screen's load-failure caption uses `Theme.Colors.danger` (system red `#FF453A`), which measures 4.09:1 on the coach sheet's raised `#2C2C2E` row (4.99:1 on the pushed screen's `#1C1C1E`).

## Recovery

Revert the change. It touches only colors in the asset catalog and view styling; no data, persistence, server or entitlement is involved.
It reaches users with the next App Store submission.
