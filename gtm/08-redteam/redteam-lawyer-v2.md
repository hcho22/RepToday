# Red Team v2: App Store Reviewer + FTC-Minded Lawyer

Persona: an App Store reviewer applying the App Review Guidelines, and an FTC-minded advertising lawyer applying substantiation rules, reading every public-facing line.
Scope read line by line: `03-site/index.html`, `03-site/index-b.html`, `04-video/script.md`, `05-social-pmf/week-1-drafts.md`, `05-social-pmf/angles.md`, `05-social-pmf/ab-pairs.md`, `09-extras/investor-teaser.html`, `09-extras/app-store-screenshots/` (README + all five src files), `09-extras/review-response-playbook.md`, `02-brand/brand-guidelines.md` sections 7-11, `06-channels/channel-plan.md` ASO section.
Ground truth: `01-research/product-facts-brief.md`, `02-brand/positioning.md`, `02-brand/naming-decision.md`.

Checked and found clean, so no objection is manufactured on these: the v1 "same-day relief" health claim is gone from both site variants and no public mobility line makes a symptom or outcome promise; screenshot 05 now carries "Trial auto-renews until cancelled" and "Planned pricing, set at launch" beside the $7.99/$59.99 figures; the free-vs-Strength-Phase boundary sentence appears on the site and in screenshot 05; every third-party quote on the site is explicitly disclaimed as not from a Rep Today user; founder-on-camera is mandatory wherever a first-person line exists, so nothing in the social kit is testimonial-shaped from a zero-user product; "most" not "every" holds across all hooks; no XP/levels/badges/streak language and no loss-framed copy was found anywhere in scope; the clearance caveat is present verbatim on both site footers and the investor teaser footer.

---

## MUST-FIX

### 1. Ruling on the known flag: screenshot 04's in-app line "Today you showed up. That's the whole game." must not ship in a marketing asset

Target: `09-extras/app-store-screenshots/src/04-consistency.html` line 96 (`.week-note`) and the README table row for screenshot 4.
The positioning tournament killed the headline "Showing up is the whole game" for a word-level collision with a live Jillian Michaels ad ("All you have to do is show up"), and this mock re-imports the killed phrase into the asset class with the most permanent public exposure, dressed as product UI.
It is also an unverified functionality claim: no ground-truth document contains this string as shipped app copy, and brand guidelines section 10 permits staged screens to show only shipped mechanics.
Ruling: the phrase does not get to re-enter the package through the back door of a hand-built screenshot.
Smallest honest fix: change the week-note to approved copy ("Tuesday off. Today you showed up." or "You're someone who moves."), re-render the PNG, update the README row; separately, if this string really is in-app copy in the build, file a product-copy flag to the founder to re-review it against the killed-headline decision rather than reproducing it in marketing.

### 2. The site FAQ invents progression-tier specifics that exist nowhere in the ground truth

Target: `03-site/index.html` and `03-site/index-b.html`, FAQ "Will I run out of movements?" (the six named push-up tiers "wall, incline, knee, standard, diamond, archer" and "the squat runs five, from a wall sit to a shrimp squat").
`product-facts-brief.md` supports progression chains and "cleared movement tiers" generically, but names no tier counts and no tier names, and the brief says contradicting or exceeding it is a hard failure.
This is the identical defect class as the v1 must-fix on the then-unsourced mid-session swap: public functionality claims the package cannot substantiate, which become Guideline 2.3 misrepresented-functionality problems if the build differs.
Smallest honest fix: verify the tier chains against the build or PRD and add them to the facts brief with a citation, or cut the named tiers and keep only the general progression-chain sentences the brief already supports.

### 3. "There is nothing to sell" is falsified by the package's own measurement plan

Target: `03-site/index.html` and `index-b.html`, FAQ "Is my data sold?"; cross-reference `06-channels/event-metric-schema.md`.
The FAQ says "Your history lives on your device ... There is nothing to sell", while the event schema commits the launch build to uploading anonymous per-install usage events (session starts, completions, difficulty, retention events) and the web plan collects waitlist emails with source tags.
"Never sold" can be promised; "nothing to sell" is a data-practices absolute beyond the documented architecture, the exact claim class positioning.md's hygiene rules ban (the killed "that is the only fact the app records" line is the named cautionary example), and it will contradict the privacy nutrition label the app must file.
Smallest honest fix: replace "There is nothing to sell." with "It is never sold.", and when instrumentation ships add one sentence disclosing minimal anonymous usage measurement so the FAQ, the schema, and the nutrition label tell one story.

### 4. Day-2 social draft states unverified facts: a review date and founder-conduct quantities

Target: `05-social-pmf/week-1-drafts.md`, Day 2 (shot 1 attribution "Real App Store review of a fitness app, 2020"; shot 2 "the most common complaint ... I found in months of research"; caption "I read hundreds like it before building").
The only 2020 date in `review-mining.md` belongs to a different review (a Centr review); the quoted 30 Day Fitness review carries no documented date, so "2020" is an invented factual detail under the truth policy.
"Months of research" and "hundreds" are quantities about the founder's own conduct that nothing in the package substantiates, and the truth policy bans invented stats without an [ASSUMPTION] label or founder verification.
Smallest honest fix: attribution becomes "Real App Store review of a fitness app"; the spoken lines become "the most common complaint I found mining app reviews" and "I read a lot of these before building", unless the founder personally verifies the date and quantities before recording.

### 5. The five screenshot PNGs carry no in-asset disclosure, violating the package's own brand rule

Target: `09-extras/app-store-screenshots/src/shared.css` canvas layout and all five rendered PNGs; secondarily the README warning block.
Brand guidelines section 2 requires any static asset depicting a simulated or staged app screen to carry "Screen images simulated. App is pre-release." appended after the canonical legal line; these five staged-screen PNGs carry neither, and the README disclosure does not travel with a PNG that gets dropped into a deck or a review thread.
The README also proposes App Store listing usage of the name while omitting the canonical clearance line that naming-decision.md makes mandatory context for any listing-name surface.
Smallest honest fix: add a small footer strip in `shared.css` carrying "Screen images simulated. App is pre-release." to all five comps and re-render; add the canonical legal line ("Pre-launch. 'Rep Today' has not been trademark-searched or registered, and the App Store name has not been reserved.") to the README warning block.

### 6. The under-100ms benchmark gate does not block the investor teaser, which states the claim twice

Target: `08-redteam/pre-publication-checklist.md` Substantiation item 1 (blocking list "site, video, screenshots, social"); `09-extras/investor-teaser.html` ("in under 100 milliseconds" in the three-sentence pitch and the wedge section).
The number is a PRD requirement, not a device measurement, and the checklist correctly blocks publication of four asset classes on a real-hardware benchmark, but the teaser, the one document aimed at investors, is missing from the blocking list.
An unsubstantiated performance figure handed to investors is a worse posture than the same figure in an ad, and the omission means the teaser could honestly clear the checklist while carrying an unmeasured spec as fact.
Smallest honest fix: add "investor teaser" to that item's blocking list; optionally change the teaser's wording to "designed to build every session in under 100 milliseconds" until the benchmark record exists.

---

## SURVIVING-OBJECTION

### 7. "Under 100 milliseconds" is spec-derived and stated as fact in every consumer surface

Targets: both site heroes, meta descriptions, engine cards and FAQs; `04-video/script.md` VO line 3; screenshot 02 footnote; `05-social-pmf/ab-pairs.md` AB-4 leg B.
The posture is honestly framed in governance (the checklist blocks publication on a real-device benchmark including the slowest supported iPhone) but the copy itself carries no qualification, so the day the benchmark misses on an iPhone XS, every asset changes at once.
Even after a passing benchmark, this remains an unverifiable-by-consumers precision claim whose substantiation burden (device matrix, percentiles, re-measurement every release) is carried forever by a one-person company; carried forward from v1 and still true.

### 8. "Forever" is a promise no pre-revenue solo founder can guarantee

Targets: site pricing headline, screenshot 05 caption, video scene 7, Day-2 social draft.
The free tier's perpetuity depends on the product surviving; if it shuts down or is sold, every "All of them. Forever." asset becomes the record of a broken promise.
Softening it would gut the brand's central pledge, so the founder carries this liability knowingly; carried forward from v1.

### 9. The name is still legally naked, and the whole package builds equity on it

Targets: every asset carrying the wordmark; `02-brand/naming-decision.md` known-risks section.
No USPTO search, no App Store Connect reservation, a descriptive mark with a narrow perimeter, REP Fitness owning "rep" web mindshare, and reptoday.com held by a domain investor; the collision scan is a search sample, not clearance.
The caveat is present on the written surfaces and the founder's next action is defined, but no wording fixes the exposure: everything shipped before clearance is rework-at-risk; carried forward from v1.

---

## NOTE

### 10. "hiit" in the ASO keyword field is the weakest relevance claim in the metadata

Target: `06-channels/channel-plan.md` A2 keyword field (`...,minute,hiit,exercise,...`).
The product claims interval training nowhere, and the package's own truth posture argues against borrowing a category it does not serve; Apple's metadata rules disfavor irrelevant keywords (Guideline 2.3.7 territory), though adjacency arguments exist.
Recommend dropping "hiit" or writing one sentence of relevance rationale into the ASO section so the choice is deliberate, not drift.

### 11. "Relief" survives in internal labels one editing slip from a public caption

Targets: `05-social-pmf/angles.md` P08 row name "Mobility as relief, not warm-up"; `05-social-pmf/cadence-14-day.md` day 11; `05-social-pmf/read-the-results.md` item 3.
Ruling on the danger zone: every public mobility line ("Half your session can be the part other apps skip", "programmed for how a desk day actually feels") describes programming, not symptoms, and passes; "relief" is a symptom word and appears only in internal angle names.
Keep it that way: when P08 is produced, the word "relief" must not appear in any hook, caption, or on-screen text, or it becomes the implied therapeutic claim v1 already had to remove once.

### 12. The site's mock caption paraphrases the mandated disclosure sentence

Target: `03-site/index.html` and `index-b.html` phone caption "Ready Screen (pre-release mock of the product UI)" plus the footer legal block.
Substantively disclosed, but brand guidelines section 2 specifies the exact sentence "Screen images simulated. App is pre-release." for staged screens on static surfaces; the letter and the practice diverge.
Either add the canonical sentence to the site footer legal block or amend section 2 to bless the caption form, so the rule stays enforceable.

### 13. The video carries no clearance caveat, by a rule rewritten after the v1 fix

Target: `04-video/script.md` scene 8; `02-brand/brand-guidelines.md` section 2 parenthetical; `04-video/gate-report.md` line "trademark caveat lives in the written assets".
Nothing false is stated, so this is legally defensible: omission is not a clearance claim, and the v1 must-fix was about the false word "pending", which is gone.
But the sanction was created in v2 by editing the rule rather than applying the offered short-form line ("Name not yet trademark-searched or registered."), and the founder should consciously own that a polished launch video presents a locked wordmark and listing subtitle for an uncleared name.

---

Counts: 6 MUST-FIX, 3 SURVIVING-OBJECTION, 4 NOTE.
