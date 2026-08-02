# Red team v2 - skeptical seed investor

Persona: seed investor deciding whether to take the meeting.
Posture: I read the package looking for reasons to say no in under ten minutes.
Scope read: 07-thesis/investment-thesis.md, 06-channels/channel-plan.md, 06-channels/event-metric-schema.md, 05-social-pmf/read-the-results.md, 05-social-pmf/angles.md, 09-extras/investor-teaser.html, 02-brand/naming-decision.md, 01-research/category-economics.md, plus 01-research/product-facts-brief.md for ground truth.
Verdict up front: the honesty is real and unusual, but the "falsifiable case" framing has holes where the falsification instrument cannot actually fire, and two documents disagree about what a fired K0 even means.

## Objections

### 1. MUST-FIX - K0's kill line depends on a signal the kit itself declares unmeasurable

Target: 07-thesis/investment-thesis.md, K0 (lines 200-207, "waitlist taps are still zero"); 06-channels/channel-plan.md A1 kill criterion (line 53); versus 05-social-pmf/angles.md, "Measurement honesty" (line 15).
The K0 kill condition requires "profile-link taps to the waitlist stay at zero", and the expected band promises "low-hundreds of waitlist visits".
The angle bank's own measurement-honesty section states that profile-link taps are NOT reliably measurable at zero followers, that TikTok gates clickable bio links behind account requirements a new account may not meet, that no link destination exists pre-launch, and that "no signal below depends on an unmeasurable quantity".
So the thesis's centerpiece pre-launch kill criterion reads a quantity its own instrument disclaims, which means the waitlist leg of K0 is guaranteed-zero theater, not falsification.
Smallest honest fix: make the waitlist leg of K0 conditional on the landing page being live before the cadence starts and measured via the schema's `landing_page_view`/`waitlist_signup` events with `referrer_source`, or delete the taps leg and let K0 adjudicate on the views criterion alone.

### 2. MUST-FIX - the K0 views criterion has a degenerate denominator and no under-sampled state

Target: 07-thesis/investment-thesis.md K0 (line 206, "no concept beats the account's median views by 5x"); 05-social-pmf/read-the-results.md ("any post under 200 impressions is unread, not failed").
"5x the account's median views" is degenerate at zero followers: if the median is zero or near-zero, any random post clears 5x, so the kill can never fire; if the platform seeds every post with a few hundred views, 5x may be unclearable, so the kill always fires.
Worse, the kit's own readability floor means an 8-week run where most posts sit under 200 impressions is unreadable by rule, and K0 as written would report that as "did not fire" rather than "measured nothing".
K8 already has the right pattern ("under-sampled, not passed"); K0, the criterion the thesis calls its cheapest falsification, lacks it.
Smallest honest fix: define the K0 read over readable posts only (>=200 impressions), require a pre-registered minimum count of readable posts per platform for K0 to adjudicate at all, and name the shortfall outcome as its own reported state, "K0 under-sampled", distinct from pass and fire.

### 3. MUST-FIX - two documents give two different verdicts for the same week-8 observation

Target: 06-channels/channel-plan.md A1 kill criterion (line 53) versus 07-thesis/investment-thesis.md K0 (lines 206, 211) and 05-social-pmf/read-the-results.md item 6.
For the identical observation (8 weeks, 16+ posts per platform, no concept clears), the channel plan says "stop the cadence and rebuild the concept matrix before posting again", read-the-results says "the channel thesis goes back for revision", and the thesis says bet (c)'s organic leg "is failed... regardless of what the product later measures".
A kill criterion with three escalation ladders is not pre-registered; it is a menu, and the founder will pick the lenient reading when the data is bad.
Smallest honest fix: declare the thesis's K0 paragraph the single binding ladder, and edit channel-plan A1 and read-the-results item 6 to point at it instead of restating their own softer versions.

### 4. MUST-FIX - bet (d)'s word-of-mouth leg is required by the thesis and measured by nothing

Target: 07-thesis/investment-thesis.md, section 1 bet (d) (line 18) and section 4 ignore list (line 167); 06-channels/event-metric-schema.md (no referral or source-attribution instrument beyond `referrer_source` on web events).
The bet states the business only works if "word of mouth compounds", yet no criterion in K0-K8 measures referral or word of mouth, and the economics model "deliberately ignores" WOM compounding.
That leaves the load-bearing growth mechanism of a zero-spend, paid-UA-underwater company outside the falsification schedule entirely, which is exactly the kind of gap the "falsifiable case" framing claims not to have.
Smallest honest fix: either add a cheap WOM proxy to the schema and the 90-day review (e.g. a one-tap "how did you hear about this" on the waitlist and post-launch, or unattributed-install share as a named metric), or add one sentence to section 5 stating visibly that bet (d)'s word-of-mouth leg is uninstrumented and cannot be falsified inside the 90-day window.

### 5. MUST-FIX - the channel plan says the PMF kit does not exist while the thesis says it shipped

Target: 06-channels/channel-plan.md, section 5 (line 110): "Note: `05-social-pmf/` is empty at this writing; the kit is a committed v2 deliverable... and A1 depends on it landing."
The kit is in the package (seven files, including the angle bank K0 reads from), and investment-thesis.md line 202 says "the kit ships in this package".
A decision document that misstates whether its own rank-1 channel's instrument exists undermines the package's core claim of being carefully cross-checked, and an investor who notices one stale cross-reference discounts every other one.
Smallest honest fix: replace the stale note with "the kit ships at 05-social-pmf/ (D-101)".

### 6. MUST-FIX - K1 is pre-registered with two different denominators

Target: 09-extras/investor-teaser.html, kill table K1 row ("45-60% of installs complete one session"); 07-thesis/investment-thesis.md K1 (line 184, "fewer than about a third of installers"); versus 06-channels/event-metric-schema.md derived metrics (line 34, divided by installs with `onboarding_started`).
The schema computes K1 as session-starters over onboarding-starters, while the teaser and the thesis rationale both phrase it as a share of installs; those denominators diverge exactly when the app crashes or is abandoned before onboarding, which is a failure mode the metric should catch.
A pre-registered threshold with an ambiguous denominator can be recomputed post hoc under whichever definition passes, and the schema's own pre-registration note forbids exactly that.
Smallest honest fix: pick the schema's denominator as canonical and change the teaser row and the thesis wording to "of onboarding starts", or redefine the schema formula over installs; one sentence either way, but it must be one denominator in all three files.

### 7. SURVIVING-OBJECTION - every accountability mechanism is currently a blank

Target: 07-thesis/investment-thesis.md, K8 instrument (line 193) and enforcement paragraph (line 217); 09-extras/investor-teaser.html founder section.
The thesis correctly names the base-rate problem of self-graded kill criteria, then leaves both named humans as [FOUNDER TO FILL]: the non-founder K8 coder and the outside reviewer who holds the walk-away call.
Until those names are filled, and additionally for K0, which runs pre-launch and sits outside the outside-reviewer's week-8/week-12 remit as written, every criterion in this package is self-graded, and the enforcement section is a promise about a future promise.
This is honestly flagged, so it is not a truth violation, but the package should carry it as an open condition of credibility rather than a formality: no meeting until the two names exist and K0's reviewer coverage is stated.

### 8. SURVIVING-OBJECTION - the "base case" is an optimistic case wearing a base-case label

Target: 07-thesis/investment-thesis.md, section 4 inputs (lines 143-146) and outputs table.
The install base case (5,000) is a pure [ASSUMPTION] with no benchmark, and the document itself concedes that the 2.1% conversion midpoint comes from live, marketed, conversion-optimized apps and that "the pessimistic 1.0% may be closer to a true base case".
Combine the document's own two concessions and the honest central scenario is roughly 2,000-5,000 installs at ~1%, i.e. $700-$1,800 gross, not $3,700; the model's candor lives in footnotes while the table's middle row keeps the flattering label.
Carry this visibly: relabel the middle row "at-benchmark (likely optimistic)" or state under the table that the document's own reasoning puts the true central case between the first two rows.

### 9. SURVIVING-OBJECTION - even full success is not a venture case, and the package never says what scale looks like

Target: 07-thesis/investment-thesis.md, section 7; 09-extras/investor-teaser.html, "The ask".
By the package's own arithmetic, total success at the 90-day review means above-median retention on a product grossing perhaps $30K optimistic in year 1, in a category where the top decile takes 92.6% of revenue, with paid acquisition permanently underwater ($50-$190 CAC against $35.64 LTV), and the proposed use of funds is an Android build that doubles platform cost on those same unit economics.
There is no articulated mechanism by which surviving the kill criteria compounds into a venture-scale outcome; "underwrite 90 days of data" is a coherent angel-scale experiment, but the package should either sketch the year-2+ path that makes the option valuable (what WOM coefficient, what ceiling, what pricing power) or own the angel-scale framing explicitly.
As written, the strongest honest pitch here is "cheap, well-instrumented option on a small business", and the teaser should not be surprised when investors read it that way.

### 10. SURVIVING-OBJECTION - the kill thresholds are calibrated against the founder's own aspirations

Target: 07-thesis/investment-thesis.md, K1 (threshold set at "roughly half the PRD's own target"), K4 (band "anchored on the PRD's 35% target"), K5 (floor "set at the steady-state run rate the section 4 base case actually requires").
Three of the walk-away lines are derived from the PRD's targets and the model's own assumed base case, both of which are [ASSUMPTION]s, so the falsification apparatus partly tests whether reality matches the founder's guesses rather than any external bar.
The thesis labels each derivation honestly, and for K1/K4 no external benchmark exists to borrow, so this is a real limit to carry, not a fix to make.
The carry: the 90-day review should state, next to any K1/K4/K5 verdict, that the threshold provenance is self-referential, so a pass on those three is weaker evidence than a pass on the externally-anchored K2/K3/K6/K7.

### 11. NOTE - the K2 gray zone between 10% and 12% has no stated verdict

Target: 07-thesis/investment-thesis.md, K2 row (expected band 12-20%, kill at or below 10%) and the at-median rule (line 213).
A pooled D7 of 11% is above the kill line, above the cited median band (8.5-10%), and below the expected band, so it neither fires K2 nor triggers the at-median rule, yet the thesis bar is "beating the medians materially".
One sentence naming who adjudicates the 10-12% corridor at the week-12 review would close it.

### 12. NOTE - K2/K3 walk-away lines rest on blog-grade provenance, already confessed

Target: 07-thesis/investment-thesis.md, provenance note (lines 219-220).
The D7/D30 medians behind the two most load-bearing retention kills come from marketing-blog aggregations of unstated vintage, and primary fetches failed; the thesis says so plainly.
Nothing to fix pre-launch, but the week-8 review should retry the primary sources (Adjust, RevenueCat PDF) before any walk-away call is made on K2 or K3.

## What this persona did not find

No invented users, stats, quotes, or testimonials anywhere in the read set; the teaser's traction section is the bluntest I have seen.
The teaser's factual claims spot-checked against product-facts-brief.md (667/667 tests, pricing, offline core loop) are accurate, and the trademark caveat is carried on the teaser footer and at the top of naming-decision.md as required.
The zero-spend verdict is genuinely structural (no listing means no install ads), not rationalized thrift, and the category-economics file states its gaps instead of papering them.

## Counts

MUST-FIX: 6 (objections 1-6).
SURVIVING-OBJECTION: 4 (objections 7-10).
NOTE: 2 (objections 11-12).
