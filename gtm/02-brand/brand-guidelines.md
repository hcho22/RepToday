# Rep Today - Brand Guidelines v2.0

This document is self-contained.
A designer or writer who has read nothing else should be able to produce an on-brand asset from it.

---

## 1. What the brand is

**Rep Today** is a micro-workout iOS app that deletes the friction between deciding to move and moving.
Open the app and a complete zero-equipment bodyweight session is already on screen, built on the phone, offline, in under 100 milliseconds.
One dominant Start button.
No questions, no account, no paywall in the core loop, and no XP, levels, badges, streaks, or leaderboards anywhere.
Mobility is co-primary with strength, not a warm-up.
Discipline is the brand's internal spine, never its surface language (see §8).

**Brand essence:** *ready*.
The product's entire personality flows from one moment: you open the app and the work is already prepared for you.

**Personality (in order):** calm, prepared, honest, quietly confident.
The brand is the competent friend who lays your shoes by the door - it never cheers at you, never guilts you, never sells at you.

**Emotional register:** relief, not aspiration.
The audience is a tired parent at 9pm, not a gym rat.
Every asset should lower the reader's heart rate, not raise it.

## 2. Name usage

- The name is **Rep Today** - two words, both capitalized, never "RepToday", "REP Today", or "Rep today" in prose. (The bundle id `com.reptoday.app` and code module `RepToday` are technical identifiers, not display forms.)
- App Store listing name: plain **Rep Today**. App Store subtitle: **"Opens to a ready workout"**. Under-icon display name: **Rep Today**.
  The old listing suffix "Rest Tomorrow" is retired everywhere: under hostile paraphrase it read as grind-culture or as prescribing rest, and it fought the forgiveness pillar.
  Never revive it in any copy, asset, or metadata.
- The name is an instruction, not a noun: do a rep, today. Copy may lean on this ("The name is the whole program.") but never explain the pun at length.
- Never claim the name is trademark-cleared, and never imply a clearance process is underway when none is.
  The canonical legal line, wherever a legal line is needed: "Pre-launch. 'Rep Today' has not been trademark-searched or registered, and the App Store name has not been reserved."
  (Video end cards carry the short pre-release disclosure "Screen images simulated. App is pre-release." instead of the full legal line.)
  Any asset, static or video, that depicts a simulated or staged app screen carries the same "Screen images simulated. App is pre-release." sentence; on static assets it is appended after the legal line, not substituted for it.

## 3. Logo: the Ready Mark

**Concept.** A rounded square (the screen) holding a single filled circle in its lower third (the Start button, already there).
That is the whole logo: the app's promise - open it and the session is waiting - drawn in two shapes.

**Construction.**
- Rounded square: stroke, corner radius = 22% of side length, stroke weight = 7% of side length.
- Circle: filled, diameter = 30% of the square's side, centered horizontally, its center sits at 70% of the square's height.
- Clear space around the mark: at least 25% of the square's side on all sides.
- Minimum size: 24px. Below that, use the circle alone.

**Reference SVG (Moss on transparent):**

```svg
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <rect x="10" y="10" width="80" height="80" rx="17.6" fill="none" stroke="#2E6B4E" stroke-width="5.6"/>
  <circle cx="50" cy="66" r="12" fill="#2E6B4E"/>
</svg>
```

**Wordmark.** The mark sits left of the name set in the brand type (see §5), Bold, Ink (or Bone on dark), with a gap equal to 50% of the mark's width: `[mark] Rep Today`. The name's cap height = 2/3 of the mark's height, optically centered on the mark.

**App icon.** Moss (#2E6B4E) background, the Ready Mark in Bone (#F1EEE8) with the rect stroke and circle both Bone. No gradients, no gloss, no figure silhouettes.

**Don't:** rotate the mark, add a play triangle, add a dumbbell/flame/heartbeat, put the circle top or center (the low circle is the thumb-reachable Start), or use more than one color in the mark.

## 4. Color

Calm, natural, low-saturation. The category's neon HIIT palette is exactly what this brand is not.

### Light ("Paper") - default for marketing

| Token | Hex | Role | Contrast |
|-------|-----|------|----------|
| Paper | `#FAF7F2` | background (warm off-white) | - |
| Ink | `#1B2228` | headlines, body text | 15.05:1 on Paper |
| Slate | `#525E66` | secondary text, captions | 6.24:1 on Paper |
| Moss | `#2E6B4E` | primary accent: buttons, links, the mark | 5.9:1 on Paper; white text on Moss 6.31:1 |
| Clay | `#B05C3F` | rare warm accent: one highlight per asset, max | 4.42:1 on Paper (large text/graphics only) |

### Dark ("Night") - product-adjacent and video

| Token | Hex | Role | Contrast |
|-------|-----|------|----------|
| Night | `#14181C` | background | - |
| Bone | `#F1EEE8` | headlines, body text | 15.41:1 on Night |
| Mist | `#A7B0B8` | secondary text | 8.11:1 on Night |
| Fern | `#5FA981` | accent on dark (Moss's dark-mode form) | 6.35:1 on Night |

### Rules

- One accent per asset. Moss (or Fern on dark) does all interactive/emphasis work; Clay appears at most once per asset, or not at all.
- Never use pure white `#FFFFFF` or pure black `#000000` as a background.
- No gradients, no glows, no neon. Flat fills only. (The one exception: the light card shadow specified in §6, which is a depth cue, not a glow.)
- Text always Ink/Slate on Paper, or Bone/Mist on Night. Never set body text in Moss or Clay.

## 5. Typography

**Typeface:** the system rounded sans. On Apple platforms this is SF Pro Rounded (the app itself renders all UI in it); on the web use the stack:

```css
font-family: ui-rounded, "SF Pro Rounded", -apple-system, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
```

Rounded is a deliberate brand choice - warm and unaggressive - and it matches the shipped app exactly. No second typeface; no serif anywhere.

**Scale (marketing, 1rem = 16px):**

| Style | Size / line-height | Weight | Use |
|-------|--------------------|--------|-----|
| Display | 56/60 | 700 | hero headlines |
| H1 | 40/46 | 700 | page/section titles |
| H2 | 28/34 | 600 | section heads |
| H3 | 22/28 | 600 | card titles |
| Body | 17/26 | 400 | paragraphs |
| Small | 14/20 | 400 | captions, legal |
| Micro | 12/16 | 500, +0.04em tracking, uppercase allowed | overlines/labels only |

- Headlines set in sentence case, with a period when the headline is a sentence. Never all-caps headlines, never title case.
- Numbers matter to this brand ("5 to 60 minutes", "under 100 milliseconds"): keep numerals as digits, not words, in marketing copy.
- Overlines/labels: prefer sentence case. Never uppercase a proper name (iOS, App Store) - if uppercasing would mangle one, don't uppercase.
- Non-body text (overlines, labels, stat callouts) may be set in Moss (Fern on dark) for emphasis or Slate/Mist when quiet; body text never.
- **Fixed-canvas assets** (social cards, video frames): design against this scale at 2x (e.g. Display 112px on a 1080-wide canvas), keeping all ratios. Canvas margin: at least 80px at 1080 wide. The legal/clearance line, when required, always sits last, in Small, Slate/Mist, never below 24px rendered at 1080 wide.
- **Fit before ship (fixed canvases):** everything specified for the asset, the legal line and the full proof line included, must sit fully inside the canvas.
  Render the asset at final pixel size and check; clipping any required line is a hard failure.
  If copy overflows, cut optional content first (status lines, secondary messages, the large mark's size), never the proof or legal lines, and never shrink type below this scale to make room.

## 6. Spacing, shape, and layout

Mirrors the shipped app's tokens: base-4 spacing (4/8/16/24/32/48/64), 16px card corner radius, 56px button height, generous whitespace.

- Buttons: 56px tall, 16px radius, Moss fill, white label, weight 600. One primary button per view - the Start-button philosophy applies to marketing too: one dominant action per asset.
- Cards: Paper (or Night surface `#1E242A`), 16px radius, 24px padding, no drop shadows heavier than `0 1px 3px rgba(27,34,40,.08)`.
- Layouts breathe: at least 96px between landing-page sections; max text measure 34em.

## 7. Voice

The audience is a tired adult at 9pm. Write like the competent friend, not the coach.

**Rules (each line of copy must pass all):**

1. Identity-framed, never loss-framed: "You're someone who moves," never "Don't break your streak."
2. Plain, declarative, short. No hype stacking, no three-adjective runs, no "revolutionary / game-changing / unlock your potential."
3. No bro-fitness register: no grind, no beast mode, no "no excuses," no shame. Discipline means showing up, and showing up is made easy.
4. Never mock the user's current state.
5. Specific over aspirational: "a 7-minute session is already on screen when you open the app" beats "your fitness journey, reimagined."
6. Honest about what it isn't: not a strength program, not coaching, not a gym replacement. Say so when relevant.
7. No health/medical claims: no calories, weight loss, pain cures, body-composition promises, or before/afters. Consistency, habit, mobility, movement - framed honestly - are fine.
8. No XP/levels/badges/streak language, even negatively framed praise ("earn your badge") - and when contrasting with streaks, name the mechanic, don't celebrate it.
9. No emojis in product-adjacent copy. (Social drafts: sparing, only where the channel demands it, and note it.)
10. No em dashes; use plain dashes. Sentences short enough to read at 9pm.

**Claims hygiene (each factual line must also pass all):**

11. No unqualified market absolutes: never "every workout app asks..." - "most" is the ceiling on any generalization about competitors, because our own research found exceptions.
12. No data-practices claims beyond the documented architecture: never assert what the app does or does not record, store, or send unless the shipped mechanic is the claim (e.g. "generated on your phone, offline" is fine; "that is the only fact the app records" is the banned cautionary example).
13. Competitor-motive claims stay internal: never publish why competitors build what they build ("their machinery serves retention, not you"). Surface copy states Rep Today's own mechanics only.
14. Pre-launch truth: the product has zero users, downloads, ratings, or testimonials. Never invent or imply any. The demo of the mechanism is the only proof; first-person claims in video must be visibly the founder demoing their own app.

**Voice do/don't:**

| Don't write | Write instead |
|-------------|---------------|
| "Crush your goals with AI-powered workouts!" | "Open the app. The workout is already there." |
| "Don't lose your 30-day streak!" | "Missing a day never zeroes you out." |
| "Transform your body in 6 weeks" | "Five minutes on a hotel-room floor still counts." |
| "No excuses. Get after it." | "Got 10 minutes? That's a session." |
| "The revolutionary fitness experience" | "A session is ready in under 100 milliseconds, on your phone, offline." |

## 8. Discipline register (do/don't)

Discipline is the internal spine of the brand: it governs strategy, product narrative at essay length, and the About layer.
It is never the surface lead word - no headline, hook, subject line, ad, or App Store field leads with "discipline", because the market's prior on the word is the drill-sergeant register and it is absent from the audience's own pain vocabulary.

The internal definition (essay-length writing only, never compressed into short formats):
discipline is not effort, discipline is showing up; every decision between "I should work out" and "I am working out" is friction; the app deletes the decisions.
The inversion sentence "the app is the disciplined one" ships at essay length only (About page, manifesto) and in exactly one pre-registered PMF test angle - nowhere else.

**Hard rules for any discipline-adjacent copy:**

- Made easy, never demanded: the app supplies the readiness; it never asks the user to supply willpower.
- Never implies the user failed, lacks character, or needs fixing.
- Never romanticizes suffering, early mornings, or willpower - no 5am mythology, no "earn your rest".
- The enemy is friction, never the user's character.

**Discipline do/don't:**

| Don't write | Write instead |
|-------------|---------------|
| "Discipline delivered. No excuses left." | "The session is on screen before you finish sitting down." |
| "Finally build the discipline you've been missing." | "You never lacked the will. You lacked a workout that was already there." |
| "5am. Every day. That's the standard." | "9pm after the kids are down counts. Five minutes counts." |

## 9. Approved core copy

Use these lines verbatim where they fit; write new lines to the same standard.

**Hero A (primary):**

- Headline: **"Open the app. The workout is already there."**
- Subhead: "Rep Today builds a ready session the moment you open it - 5 to 60 minutes, no equipment, no questions, works offline. Five minutes counts. Missing a day never zeroes anything."
- Proof line (always in viewport with the hero): "Generated on your phone, offline, in under 100ms. Unlimited free workouts, no account required."
- Hero visual: the mechanic itself - a screen recording of cold open to ready session. The demo is the proof; no social-proof stand-ins.

**Hero B (secondary):**

- Headline: **"Missing a day never zeroes you out."**
- Subhead: "Rep Today opens to a ready session, counts five minutes as a full show-up, and scores consistency on a rolling scale. Come back after a week away and the app celebrates it."
- Proof line: "No streaks, no badges, no XP, anywhere. A missed day can dent your score. Nothing can ever zero it."

Scope note on "no questions": it means the open-to-start path - no quiz, no sign-up, nothing between open and Start.
iOS permission prompts (HealthKit, if the user opts in) and the optional Sign in with Apple offer exist off that path; copy built on this line must never claim the app asks nothing anywhere, and should add the open-to-start scoping where space allows.

**Messaging hierarchy (order of emphasis in any multi-message asset):**

1. It opens ready. Nothing to answer, nothing to pick. Line: "You do not pick a workout. It is on screen when the app opens."
2. Free means the workouts. All of them. Forever. Premium (about $7.99/mo or $59.99/yr, 14-day trial) gates only depth, never the core loop. Honesty caveat: this wedge works against paywalled apps, not against genuinely generous free tiers like Nike Training Club's.
3. A score that forgives. Line: "Miss a day and your score dips. It never resets."
4. A floor and a wall. That is the whole equipment list. Line: "Airplane mode, hotel room, basement with no bars. The session still builds."
5. Mobility is a pillar, not a warm-up. Line: "Half your session can be the part other apps skip."

**Beta / TestFlight announcements (pre-launch):**

- Approved status line, usable as overline or sentence: "TestFlight beta for iOS - opening soon."
- Status lines state availability as fact.
  They never count down, never name a date that is not actually committed, and never advertise scarcity ("limited spots", "only 100 testers") even when a platform cap technically exists.
  "Opening soon" is honest status, not an urgency mechanic; the §11 urgency ban targets countdowns and scarcity, not availability facts.
- Until a public TestFlight link or a real waitlist exists, beta assets carry no CTA button or link; the announcement is informational.
  Once a real link exists, the one CTA is "Join the beta" (one dominant action per asset, §6), pointing only at the actual link.
- Beta status may be added as one short sentence at the end of the Hero A or Hero B subhead (e.g. "The first TestFlight builds go out soon.") without counting against the verbatim rule.

**Other approved lines:**

- Secondary: "A floor, a wall, and five minutes."
- Free tier: "Free means the workouts. All of them. Forever."
- Onboarding joke (ads only): "Open the app. Press Start. That was the onboarding."
- Identity: "You're someone who moves."

**Approved 6-second hooks (video/social only):**

- Hero A hook: "Most workout apps open with a question. This one opens with the workout." (Never "every workout app" - "most" is the ceiling, see §7 rule 11.)
- Hero B hook (founder-on-camera mandatory): "I skipped four days and my app celebrated my comeback. On purpose. I built it that way."
- Inversion test angle (one pre-registered PMF angle only): "The most disciplined thing I own is a workout app. Watch."
- Contrarian angle (mechanics only, no competitor-intent claims): "I built a workout app with no streaks, on purpose. Watch what happens when I miss a day."

## 10. Imagery and illustration

- **Show floors and walls, not gyms.** Living rooms at night, hotel rooms, a hallway, morning light on a carpet. Never racks, barbells, chalk, mirrors-and-iron gyms.
- **Show ordinary bodies in ordinary clothes.** A person in socks on a rug beats a model in performance gear. Never before/afters, never shredded torsos, never sweat-drenched hero shots.
- **UI-forward is the safest asset.** The Ready Screen (session on screen, one Start button) is the brand's best image; show it real, uncropped, unexaggerated.
- **Pre-launch UI stand-in.** Until a real build exists to screenshot, never mock a fictional Ready Screen with invented session content; the Ready Mark at display scale (with generous clear space) is the approved stand-in visual.
  If a staged screen is ever composed before real screenshots exist, it may show only shipped mechanics and must carry the "Screen images simulated. App is pre-release." disclosure (§2), in static assets as well as video.
- Illustration style, when used: flat geometric shapes in the brand palette, generous negative space, no faces drawn in detail, no motion lines or explosion marks.
- Photography treatment: natural light, slightly warm, no HDR punch, no teal-orange grading.

## 11. What Rep Today never does (brand-wide)

- Never asks the user a question in an ad ("Ready to transform?"). The product doesn't interrogate; neither does the marketing.
- Never counts anything the user could lose (days, streaks, points).
- Never fabricates social proof - no invented testimonials, user counts, or star ratings. Pre-launch assets must be credible with zero social proof: lead with the mechanism, not the crowd.
- Never claims medical outcomes.
- Never uses urgency mechanics (countdowns, "limited spots").
- Never implies the name/trademark is cleared.
- Never leads surface copy with the word "discipline" (see §8), and never publishes claims about competitors' motives or its own data practices beyond shipped mechanics (see §7 rules 11-13).
