# Rep Today - App Store product-page screenshots

> **WARNING: pre-release design comp, for marketing review only. NOT submission assets.**
> Every PNG in this set is rendered from hand-written HTML/CSS in `src/`, not captured from the app.
> App Store Review Guideline 2.3.3 requires screenshots that show the app in use, so the actual submission set must be captured from the built app on device or simulator, and each capture must be diffed screen by screen against these comps (Ready Screen, session player, progress view, plan screen) before any upload; where they differ, the real UI wins.
> Screenshot 5 states planned pricing and must be regenerated against final App Store Connect pricing before submission.
> Formal trademark and App Store name clearance are UNVERIFIED for Rep Today - the founder's next action.

Five screenshots sized for the 6.7-inch iPhone App Store slot, 1290x2796 PNG each.
Pre-launch set: no social proof, no ratings, no user counts, per brand guidelines section 10.
Every screenshot carries the disclosure line "Screen images simulated. App is pre-release." under the caption, per brand guidelines section 2.
The mocks reflect behavior specified and implemented in the codebase per the PRD (see `gtm/01-research/product-facts-brief.md`); final screenshots must be captured from the running app, and no mock has been diffed against the build.

## The set

| # | File | Caption | What the mock shows |
|---|------|---------|---------------------|
| 1 | `01-ready-screen.png` | Open the app. The workout is already there. | Ready Screen: pre-generated 10-minute session, duration chips (10 selected), six movement blocks across all three pillars, one dominant Start button. |
| 2 | `02-duration-chips.png` | Change the time, not your plans. | Same Ready Screen with the 20-minute chip selected and the session regenerated (seven movements, three rounds). Footnote: "Rebuilt on your phone in under 100 ms". |
| 3 | `03-active-session.png` | A floor, a wall, and five minutes. | Active session player: Push-ups (movement 3 of 6, round 1 of 2), timer ring at 0:26 of 40 sec, flat geometric push-up figure, "Up next: Rest, 20 sec", quiet Pause button. |
| 4 | `04-consistency.png` | Missing a day never zeroes you out. | Progress view: Consistency 82 over a rolling 30 days, trend line with a two-missed-days dip that recovers without reset, this-week dots (Tuesday missed, shown neutrally), the forgiveness rules, and the in-app week-note "You showed up. That's the whole game." (verified build copy, see note below). |
| 5 | `05-free-forever.png` | Free means the workouts. All of them. Forever. | Your plan screen: Free marked as current plan with the full workout entitlement list; Premium below at $7.99/mo or $59.99/yr (planned pricing) with 14-day trial that auto-renews until cancelled, framed as "Adds depth, not access". Footnote states that Premium never gates the workouts and that every session remains free to generate and start. |

Captions 1, 3, 4, and 5 are approved core copy used verbatim from `gtm/02-brand/brand-guidelines.md` section 8.
Caption 2 is new copy written to the same standard: identity-framed, plain, declarative, no hype, no question, no streak language, no em dashes.

## Screenshot 4 week-note: verified build copy, restricted elsewhere

The week-note "You showed up. That's the whole game." in screenshot 4 is verbatim in-app copy from the shipping build, not marketing copy.
Verified in the iOS source: `ios/RepToday/RepToday/Views/ActiveSession/ActiveSessionView.swift` renders "You showed up." and "That's the whole game." on the session completion screen (combined accessibility label "You showed up. That's the whole game." at line 461), and `RepTodayTests/PerSideSwapEvidenceTests.swift:1151` pins it.
It appears here only as depicted product UI inside a simulated screen.
Ad and marketing surfaces must NOT use "whole game" or "show up" as headlines or copy: the positioning tournament killed "Showing up is the whole game" for a word-level collision with a live Jillian Michaels ad ("All you have to do is show up"); see `gtm/02-brand/positioning.md` and `gtm/08-redteam/redteam-lawyer-v2.md`.

## Design decisions

- **One background system: Paper.** The guidelines name Paper the default for marketing, so the whole set uses Paper `#FAF7F2` with Ink `#1B2228` captions for coherence across the product page.
- **Composition.** Caption headline at top (72px, weight 700, sentence case with periods, centered, manual line breaks), then a CSS-drawn iPhone with Ink bezel, Dynamic Island, status bar, and home indicator.
- **Native UI scale.** Each phone screen is laid out in a 430x932 point space (the 6.7-inch point grid) and scaled 2.4x, so the app's real tokens render at native ratios: 17px body, 56px-tall 16px-radius Moss Start button, base-4 spacing, SF rounded stack.
- **One accent.** Moss `#2E6B4E` does all emphasis work (selected chip, Start, ring, ticks, chart line). Clay is unused. No gradients, no glows; the only shadow is the sanctioned light card shadow.
- **Honest data.** Single plausible user state throughout: Consistency 82, one missed Tuesday shown as a neutral outline dot, a trend dip that recovers rather than resets. No fabricated testimonials, downloads, or star ratings.
- **Chart.** Single-series Moss line on recessive 60/80/100 gridlines with a direct end label ("82"), per the dataviz method. Moss fails the categorical chroma floor by design (the brand is deliberately low-saturation); it is a lone series with 5.9:1 contrast and direct labeling, so identity never rests on color.
- **Illustration.** The push-up figure is flat geometric shapes in the brand palette with no facial detail, per guidelines section 9.

## Rebuilding

Sources live in `src/` (`shared.css` plus one HTML file per screenshot).
Render any of them with:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1290,2796 \
  --screenshot=01-ready-screen.png \
  "file://$PWD/src/01-ready-screen.html"
```
