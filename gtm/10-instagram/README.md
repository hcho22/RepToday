# Instagram carousels - launch profile presence

## Publication status: NOTHING HERE IS PUBLISHED, AND NOTHING HERE MAY BE

These are launch-ready assets that sit in the repo until the captain clears Gate 0.
Two things block them, and both are outside this folder:

1. **USPTO trademark clearance for "Rep Today" is not finalized.**
   `../08-redteam/pre-publication-checklist.md` marks that item *(blocking: everything public)*, and a carousel on a public profile is public.
2. **The Instagram account is not confirmed created.**
   The same checklist still carries an open item to verify handle availability for `@reptoday`, which login walls prevented checking.

Do not post these, schedule these, or hand them to anyone to post, until the captain says Gate 0 is clear.

## What this folder is

Five carousel posts that establish the Rep Today profile: what the product is, why it was made, who it is for, and the two positions it is willing to argue.
Each is 7 slides at 1080x1350 (Instagram 4:5 portrait), authored as HTML and rendered to PNG.

| # | Folder | Slot | What it does |
|---|--------|------|--------------|
| 1 | `carousel-1-you-do-not-pick/` | **Pinned** | What it is. The friction thesis, then the inversion: you do not pick a workout, the session is chosen for you. |
| 2 | `carousel-2-why-i-built-this/` | **Pinned** | Why we made it. First-person founder origin, deliberately small. Consistency dies in the gap between deciding to move and moving. |
| 3 | `carousel-3-this-is-for-you-if/` | **Pinned** | Who it is for. Recognition rather than aspiration, closing honestly on who it is *not* for. |
| 4 | `carousel-4-nothing-to-lose/` | Evergreen | The problem it solves. The forgiveness pillar as a manifesto: no streaks, badges, XP, or leaderboards anywhere. |
| 5 | `carousel-5-a-floor-and-a-wall/` | Evergreen | The constraint as identity. Zero equipment and offline generation as the whole design, not a feature bullet. |

### Pinned versus evergreen

Instagram allows exactly three pinned posts.
Carousels 1, 2 and 3 are those three: they are the permanent top row of the profile and are built to work **as a set**, answering what / why / who in that reading order.
A visitor who reads only the top row should come away knowing what the product does, why it exists, and whether it is for them.
They are written to stay true indefinitely, so they should not need rotation.

Carousels 4 and 5 are rotation posts.
They are not pinned, they argue one position each, and either can be re-posted whenever the feed needs a post without anything new to announce.
If a pinned post is ever replaced, replace it with another post that answers the same one of the three questions, so the top row keeps its shape.

## These are NOT experiment assets

`../05-social-pmf/` is a **pre-registered experiment**: 16 angles with frozen hooks and 6 A/B hook pairs, locked before any results existed.
Instagram is a non-adjudicating distribution mirror in that experiment.

This folder is a separate, additive surface, and the separation is load-bearing:

- **Carousel performance never adjudicates an angle.** No result from these posts kills, revives, or ranks anything in the angle bank. Nothing here is written to `creative-log.json`, and nothing here should be.
- **No slide or caption restates an A/B pair leg hook verbatim.** Putting a frozen leg's own sentence in front of a reader pre-exposes it and biases the day-N versus day-N+7 comparison the pair exists to resolve. `claim-audit.py` below enforces this mechanically.

  The rule is verbatim-scoped on purpose, and the scope is worth recording so it does not get quietly widened again: the pairs run on TikTok and YouTube Shorts, `../05-social-pmf/platform-assignment.md` explicitly excludes Instagram as a test platform, and the positioning pillars underneath the hooks are deliberately shared with this folder (see the line below), so a rule reaching past the strings would forbid the carousels from saying what the product is.
- **Nothing under `../05-social-pmf/` was modified.** Not one character. The audit script reads those files and never writes to them.

Drawing on Hero A, Hero B, and the five messaging pillars in `../02-brand/positioning.md` is fine and encouraged, because those are positioning rather than frozen experiment hooks.
That is what these carousels do.

### The headline adjustment, and why it was necessary

Two of the five carousels were briefed under working titles that turned out to be **verbatim A/B leg hooks**:

| Working title | Collides with | On-slide headline used instead |
|---|---|---|
| "Open the app. The workout is already there." | AB-1, leg B | **"You do not pick a workout."** (slide 1) then **"The session is chosen for you."** (slide 2) |
| "Missing a day never zeroes you out." | AB-2, leg B | **"There is nothing here to lose."** |

Both working titles are also approved hero headlines in `../02-brand/brand-guidelines.md` section 9, which is exactly why the collision is easy to miss: the A/B pairs froze the hero headlines as leg B of their pairs.
Where the two rules meet, the experiment-integrity rule governs the sentence and positioning governs the idea.

So carousel 1 leads on the truth underneath AB-1's leg B rather than on leg B's own line: **you do not pick the workout, the choosing is done for you, there is no menu.**
That is `positioning.md` pillar 1, which is shared on purpose, and it is what the whole carousel is built on, which is why the folder is `carousel-1-you-do-not-pick/`.

A handful of lines were also moved off strings that sat within about a word of a frozen hook, where the guard would have passed on a technicality rather than because the copy was clear of it: carousel 4's floor slide now reads "The shortest session is a full show-up." rather than pairing five minutes with counting as showing up (AB-5 leg A), and carousel 3's small-windows slide no longer situates one in a hotel room (AB-5 leg B's distinguishing move).
Near-miss paraphrase is where the verbatim rule is thinnest, so it is worth checking a new headline against `ab-pairs.md` by eye even when the script is green.

## Claim hygiene

Every asset here was written against `../02-brand/brand-guidelines.md` and checked against `../08-redteam/pre-publication-checklist.md`.
Three of the checks are automated and re-runnable, and all three were sabotage-checked rather than trusted.

### `claim-audit.py`

Runs automatically at the end of `render.sh`, and on its own:

```bash
python3 gtm/10-instagram/claim-audit.py
```

Fails the run on: em dashes, en dashes, `RepToday`, `REP Today`, `Rest Tomorrow`, any speed figure, any movement or exercise count, `day N of` framing, and any verbatim reuse of a sentence quoted in `angles.md` or `ab-pairs.md`.

It uses two scopes, because they answer different questions.
The **string and frozen-hook checks** cover publishable copy only, meaning the 40 slide HTML files and captions that actually reach a reader.
This README and the folder's tooling are excluded from those, because documenting a banned string requires quoting it, and string-matching the documentation would flag the very lines that record the rule.
The **character check** covers every file including this one, because the no-em-dash rule genuinely does extend to the README.

Inside a slide, those two checks read the copy **with the markup blanked out**, because a reader sees the headline and not its tags.
Matching the raw file missed anything spanning an inline tag, and this folder line-breaks its headlines with explicit `<br>` exactly where a break would land, so `71<br>movements` or a leg hook broken over two lines was invisible to the guard at precisely the place it was most likely to occur.
Tags are blanked rather than deleted, so reported line numbers still point at the real line, and both checks are also run against the raw file so an attribute value stays covered: every slide carries a `<title>` and an `aria-label`, which are authored copy a hook could hide in just as easily as a banned figure could.

That last check is a deliberate **superset** of the rule: it guards all 12 A/B leg hooks plus the angle bank's hooks and the mined review quotes, so it is stricter than "no A/B leg hook verbatim" requires.
It parses the frozen files live rather than hard-coding a hook list, so it cannot drift out of date.
Its two integrity self-checks (the PMF files are readable, and at least the 12 expected leg hooks parsed out of them) are **failures, not warnings**: a check that cannot run must not be able to print PASS, and both would otherwise leave the hook list empty and every hook comparison trivially satisfied.

Current result:

```
Audited 46 authored file(s) in gtm/10-instagram/, of which 40 are publishable copy (slides and captions).
Checked against 40 quoted sentence(s) frozen in gtm/05-social-pmf/.

PASS  0 em dashes, 0 en dashes, 0 'RepToday', 0 'Rest Tomorrow',
      0 speed figures, 0 movement counts, 0 'day N of' framings,
      0 verbatim reuses of a pre-registered PMF hook.
```

The guard was sabotage-checked rather than trusted: injecting an em dash, `RepToday`, `under 100 milliseconds`, and `57 movements` into one slide produced 5 findings, and separately injecting each of four real A/B leg hooks produced a finding every time.
All 12 leg hooks are confirmed present in the guarded set.
The two later repairs were sabotage-checked the same way: a movement count and a leg hook each split across a `<br>` are both caught, and pointing the script at a missing PMF directory fails the run instead of reporting a clean pass.

### `fit-check.py`

Runs automatically at the end of `render.sh`.
`brand-guidelines.md` section 5 requires that a fixed-canvas asset be rendered at final pixel size and checked, because clipping any required line is a hard failure.
That rule exists because `gate-test-asset-v2` shipped with its proof line cut mid-sentence and its entire legal line invisible, and only rendering revealed it.

The check enforces it: every slide must be exactly 1080x1350, with no ink within 72px of any edge.
Since each slide has 80px of padding, ink in that band means either an overflow clipped at the canvas boundary or a broken margin.
Both fail the build.

### `widow-check.py`

Also runs automatically at the end of `render.sh`.

Headlines carry explicit `<br>` breaks, which are predictable on a fixed canvas but easy to invalidate: any copy edit can silently re-widow a line, and a lone short word stranded on its own line is a defect at this type size.
This guard measures **real line boxes** rather than guessing at them.
It copies each slide beside its original so the relative stylesheet still resolves, injects a measuring script, and has headless Chrome walk every word with a `Range`, group words by the top of their client rect, and report the resulting lines.
That copy has to land in a tracked directory, so it is named uniquely per run and removed afterwards, and `.gitignore` carries the pattern as the backstop for a run killed before it can clean up.
Anything set at 40px or larger is checked (headlines, the stacked statements, the hotel-room-test conditions); body copy at 34px is ordinary prose and is left alone.
A line that is a single word of 6 characters or fewer fails, which catches the real defects ("it.", "plan.") while leaving a deliberate lone "workout." alone.

Grouping is by rect top **within a tolerance**, not by exact equality.
A bold `<span>` inside a regular-weight line reports a slightly different top for its own inline box, and exact matching read that as a second line and reported two widows that were not on screen.

Sabotage-checked: removing the explicit breaks from one headline reproduces the original `it.` widow, and restoring them passes.

### Claims deliberately not made

These are the traps specific to this package, recorded so a future editor does not "helpfully" restore them:

- **No speed figure, anywhere.** Not "under 100 milliseconds", not a number of any kind. The real-device p95 on iPhone XS / iOS 17 is still outstanding in the pre-publication checklist, and that item explicitly blocks social assets. `positioning.md` and `brand-guidelines.md` both still print the number; they are ahead of the evidence. What the copy claims instead is not speed at all but the absence of a decision ("the session is chosen for you"), which needs no benchmark to be true. Because these carry no number, that outstanding benchmark does **not** block this folder.
- **No movement or exercise count.** The figure printed across the GTM package is stale and the correct framing is an open captain decision. The copy says "bodyweight" and "no equipment" and counts nothing.
- **No app screens.** Every slide is typographic or diagrammatic. No slide depicts, mocks, or simulates a Ready Screen, so no slide carries the "Screen images simulated" disclosure and none needed to. This was the safest reading of section 10's pre-launch UI stand-in rule; the Ready Mark is the approved stand-in visual and is what these use.
- **No AI mention.** Keeping AI out of all five entirely is the simplest safe path, so none of them owes the AI disclosure.
- **No social proof.** Zero users, downloads, ratings, reviews, and testimonials exist, and nothing here implies otherwise.
- **No download CTA, and no destination promised on a slide.** There is no App Store listing, so the status line burned into the closing slide of all five is exactly "iOS, not released yet." and stops there. "Link in bio." lives in the five `caption.md` files only, deliberately: a caption is editable after posting and a rendered PNG is not, and neither the profile nor the domain that a bio link would point at is confirmed yet (the account is a Gate 0 blocker above, and `../08-redteam/pre-publication-checklist.md` blocks any asset carrying a URL until the domain is decided). If the bio destination does not exist at post time, drop that one caption line; nothing has to be re-rendered.
- **No competitor named, and no competitor motive claimed.** Slide copy describes mechanisms ("a workout that needs a server has already chosen when"), never why any company chose one. "Most" is the ceiling on every generalization; "every" appears nowhere.
- **No streak, countdown, challenge, or "day N of" framing** as a device. The mechanic is named exactly once per carousel, only to say it was not built, per section 7 rule 8.
- **No emojis**, in slides or captions.
- **The legal line is on the final slide of all five carousels**, verbatim and last, in Small / Slate, comfortably above the 24px floor.

### Two stale sources this folder had to route around

Worth flagging, because they will bite the next asset written from these documents:

1. **Mobility is no longer co-primary.** `brand-guidelines.md` section 1 and `positioning.md` pillar 5 both still describe mobility as co-primary with strength, and pillar 5's line is "Half your session can be the part other apps skip." The shipped engine contradicts this: US-M01 made every session strength-led and removed the mobility middle block entirely, leaving mobility as the warm-up and cooldown bookends. **Pillar 5 is therefore unused in all five carousels**, because publishing it would be a false claim about the shipped product.
2. **The "57 movements" figure** appears in `positioning.md` pillar 4 and throughout `03-site/index.html`. It is stale. Nothing here counts movements.

Neither was fixed here: this task's scope is the carousels, and both documents are owned elsewhere.

### Pre-publication checklist pass

Run against `../08-redteam/pre-publication-checklist.md`, item by item:

| Item | Applies? | Status for this folder |
|---|---|---|
| USPTO trademark search *(blocking: everything public)* | **Yes** | **BLOCKS publication.** Assets carry the canonical clearance line and never claim or imply clearance. |
| Verify Instagram handle availability for `@reptoday` | **Yes** | **BLOCKS publication.** The account is not confirmed created. |
| Device benchmark for the speed claim *(blocking: social)* | No | Does not block: no asset here carries a speed figure. |
| Verify every behavioural claim against the approved binary before launch day | **Yes, at launch** | Open. Every mechanic claimed here is in the shipped engine, but the package convention is to re-verify against the binary before launch day. |
| Domain decision / register before any asset carrying a URL ships | No | No asset here carries a URL. The captions say "Link in bio", which names the profile rather than a destination; that the bio has one to point at is part of the account item above. |
| Privacy policy, FAQ / event-schema / nutrition-label reconciliation | **Yes, narrowly** | One claim: carousel 1 slide 6 says iOS asks once for permission to write your sessions to Apple Health and that declining changes nothing. Verified against `RootView.swift` (the request is unconditional on entering the main tabs, so it is a system ask and not an in-app switch) and `HealthKitService.swift` (write-only, and a denial is a quiet no-op). Nothing here describes analytics, and no asset states a retention or sharing practice. |
| Account deletion path | No | Submission concern, not an asset concern. |
| Confirm App Store pricing, regenerate screenshot 05 | No | No asset here states a price. |
| Re-record the video voiceover | No | Video only. |
| Capture real App Store submission screenshots | No | No asset here depicts an app screen. |
| Landing page one low-pressure action | No | Site, already done. |
| Reddit self-promotion rules | No | Different channel. |
| Measurement items (K5, opt-out revisit, K8 rubric) | No | Carousels adjudicate nothing. |

Two blockers, both external to the assets and both Gate 0 items.
One item to re-check at launch.
No finding required a copy change beyond what is already recorded above.

## Design and build

### Why one HTML file per slide

Each slide is its own document (`slide-01.html` ... `slide-07.html`) rather than one `slides.html` holding every stage.
Headless Chrome's `--screenshot` captures one viewport per document, so a per-slide document renders at exactly 1080x1350 with no cropping step, no scroll position to get wrong, and no risk of a multi-stage page capturing only its first frame.
A single multi-stage document would need element-level clipping, which means a CDP or Puppeteer dependency, and the package's standing tooling decision (D-003 in `../decisions-log.md`) is free local tooling only: Chrome headless for capture.
Per-slide documents also re-render and diff independently, so a copy fix touches one file and one PNG.

`overflow: hidden` on `.slide` is deliberate. It turns any overflow into ink at the canvas edge, which is exactly what `fit-check.py` detects, so a layout that does not fit fails the build instead of shipping clipped.

### The design system

All of it lives in one shared `carousel.css`, so the brand tokens have a single definition across all 35 slides.

- **Theme: Paper only.** Section 4 names Paper the default for marketing and scopes Night to product-adjacent and video work. All five carousels are Paper, which also means the profile grid reads as one calm surface rather than five treatments.
- **Accent: Moss only.** Clay is unused across the entire folder, which satisfies "one accent per asset" with room to spare.
- **Type:** the section 5 marketing scale rendered at 2x for the 1080px canvas, all ratios preserved. Nothing is set below the scale. Headlines are sentence case with a period, never all-caps, never title case.
- **Spacing:** base-4, doubled. 80px canvas margin on every side, the section 5 minimum at 1080 wide.
- **Ready Mark:** the section 3 reference SVG, inline and unmodified, so the construction ratios travel with it. It appears small in the top left of each hook slide and in the wordmark lockup on each closing slide, with clear space well above the 25% minimum.
- **Composition:** every slide in every carousel uses the same three zones, so the eye lands in the same place across a whole swipe and the covers agree with the interiors.

  | Zone | Holds | Behaviour |
  |---|---|---|
  | `.rail-top` | the Ready Mark, or the eyebrow, or nothing | pinned to the top padding edge, `min-height: 64px` |
  | `.zone` | headline and body, as one block | optically centred, and the only zone that flexes |
  | `.rail-bottom` | the swipe affordance, or the sign-off block, or nothing | pinned to the bottom padding edge, `min-height: 32px` |

  Both rails reserve a minimum so the content zone starts and ends at the same y whether its rail holds the 64px mark, a 32px eyebrow, or nothing. The slack is split above and below the content block rather than dumped on one side, and the content block sits 48px above true centre, which is the usual optical correction for a text block: centred mathematically it reads as sitting low. The sign-off slide's balance is the reference the rest are tuned against.

  An earlier revision drove this with a single auto margin, so any slide carrying one pressed its content against the bottom edge while the rest sat near the middle. Across a swipe that read as a rendering fault rather than as deliberate whitespace, which is why the layout is now zone-based and why `.spacer` and `.anchor` no longer exist.

- **Headline line breaks are explicit.** Headlines carry `<br>` rather than relying on the browser, because a fixed canvas makes explicit breaks predictable and because auto-wrapping stranded single short words ("A missed day moves the / number. It cannot empty / it."). Two slide-02 headlines also dropped from Display to H1, which fits them in two clean lines instead of a widowed three and means every non-cover slide now sits in the H1/H2 range. `widow-check.py` is the guard, and it measures rather than guesses: see below.

- **Swipe affordance: the cover only.** Slide 1 of every carousel carries a quiet "Swipe" in the bottom rail and no interior slide does. Instagram already renders its own dot indicators once a reader is inside the post, so repeating the instruction on six of seven slides is noise, and the cover is the only slide where a reader does not yet know there is more. The rule is uniform across all five carousels; the bottom rail reserves the space on every slide either way, so the composition does not shift between a cover and an interior.

### Slide 1 reads at grid-thumbnail size

Tested, not assumed, and re-tested after the composition changed.
All five hook slides were downscaled and read back, and the Display-size hook is legible on every one, because every hook is 7 words or fewer.
The test was run at **128px wide** (a 4:5 tile 160px tall), which is stricter than the roughly 160px-wide grid cell the assets actually have to survive.
The Micro-scale overline does not resolve at that size, which is fine and expected: the headline is designed to carry the thumbnail by itself.
Hook headlines also sit within the central square of the 4:5 canvas, so they survive a 1:1 centre crop as well as the 4:5 grid tile.
If a future hook needs more words, shorten the words rather than shrinking the type, which the type scale forbids.

### Regenerating the PNGs

```bash
./gtm/10-instagram/render.sh                          # all five carousels
./gtm/10-instagram/render.sh carousel-1-you-do-not-pick  # just one
CHROME=/path/to/chrome ./gtm/10-instagram/render.sh    # if Chrome is not auto-found
```

The HTML is the source of truth and the PNGs under each `carousel-*/render/` are build output.
Both are committed, so a reviewer can see the assets without running anything.
Re-rendering on **the same Chrome build** reproduces them byte for byte, which is what makes a diff meaningful after a copy edit; a different Chrome version can rasterize, compress, or font-fall-back differently and produce a whole-folder binary diff with no copy change behind it, so read an unexplained 35-file image diff as a toolchain difference before reading it as a regression.
`render.sh` finds Chrome or Chromium itself, renders every slide at a forced device scale factor of 1, and then runs all three guards, so a layout that does not fit, a headline that widows, or a claim that collides fails the regenerate instead of reaching a reviewer.
Rendering a carousel that has no slides in it is also a failure rather than a green run over nothing, and each guard enforces that for itself rather than trusting the caller: a mistyped carousel name, an empty directory, or an empty path list fails in `fit-check.py` and `widow-check.py` too, because a check with nothing to check must never print PASS.

### Publishing, when Gate 0 clears

Upload `render/slide-01.png` through `render/slide-07.png` in order.
`caption.md` in each carousel folder holds the caption to paste, the per-slide alt text, and the hashtag set.
Set the alt text per slide in Instagram's accessibility field; it describes each slide's actual content and layout rather than decorating it, which matters more than usual here because these slides *are* text.
Hashtag sets are short, honest, and descriptive, with no engagement-bait or follower-farming tags.
