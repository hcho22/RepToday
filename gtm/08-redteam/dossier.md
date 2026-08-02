# Red Team Dossier - v2 (2026-08-02)

This file replaces the v1 dossier of 2026-07-15 as the Phase-5 gate record.
The v1 persona files (`skeptic-thesis.md`, `redteam-investor.md`, `redteam-competitor.md`, `redteam-user.md`, `redteam-lawyer.md`, `_findings.json`) are frozen v1 attacks against the v1 package; they are historical evidence, not current findings.
The v1 surviving-objections list is preserved in Appendix A below, with v2 resolutions marked.

## 1. Scope and method

Five personas attacked the v2 package between 2026-08-01 and 2026-08-02:

- [redteam-investor-v2.md](redteam-investor-v2.md) - skeptical seed investor (thesis, channels, kill criteria, teaser)
- [redteam-competitor-v2.md](redteam-competitor-v2.md) - head of growth, Peloton App (positioning, angles, channel plan, site)
- [redteam-user-v2.md](redteam-user-v2.md) - cynical 41-year-old target user (drafts, site renders, screenshots, video frames)
- [redteam-lawyer-v2.md](redteam-lawyer-v2.md) - App Store reviewer / FTC-minded lawyer (every public-facing line)
- [completeness-critic-v2.md](completeness-critic-v2.md) - completeness critic (deliverables vs the master prompt, phase gates)

They produced 58 findings: 26 MUST-FIX, 16 SURVIVING-OBJECTION, 16 NOTE.
(By persona: investor 6/4/2, competitor 2/3/2, user 3/5/5, lawyer 6/3/4, critic 9/1/3.)
Fixes were applied by five lanes (strategy, screenshots, site, social, leftovers); this dossier is the disposition record.
Every finding below is dispositioned; none were silently dropped.
Dispositions marked "verified" were spot-checked against the tree while writing this record, not taken from lane self-reports alone.

## 2. Disposition of every v2 objection

FIXED names the file and the change.
DEFERRED names why and where it is tracked.
SURVIVING ships visibly in section 3.
Several fixes carry a small residue; residues are collected in section 5 so nothing hides inside a FIXED label.

### Investor

| # | Sev | Objection (short) | Disposition |
|---|-----|-------------------|-------------|
| I-1 | MUST-FIX | K0 kill line reads a signal the kit declares unmeasurable | FIXED - `07-thesis/investment-thesis.md` K0 now reads only zero-follower metrics (saves per 1k, watch-through, comment sentiment, 200-impression floor); waitlist legs re-labeled "activates only once the waitlist exists (pre-publication action #1)"; `06-channels/channel-plan.md` A1 gated identically |
| I-2 | MUST-FIX | K0 has a degenerate denominator and no under-sampled state | FIXED - K0 adjudicates only over readable posts (>=200 impressions, >=10 per platform) and a shortfall reports as the named state "K0 under-sampled", distinct from pass and fire; the 5x-median kill is gone (verified at thesis line 208) |
| I-3 | MUST-FIX | Three documents give three verdicts for the same week-8 observation | FIXED - one binding day-14 / week-8 / week-16 ladder, wording verified identical in `investment-thesis.md`, `channel-plan.md` A1, and `read-the-results.md` item 6 |
| I-4 | MUST-FIX | Bet (d)'s word-of-mouth leg measured by nothing | FIXED for post-launch - new K9 block in the thesis (unattributed-install share from the first-party schema plus organic App Store search impressions, direction-not-level, labeled [ASSUMPTION]); pre-launch WOM is stated in the thesis as unmeasured and ships as a surviving objection (section 3, item 6) |
| I-5 | MUST-FIX | Channel plan says the PMF kit does not exist | FIXED before this run's lanes (verified: `channel-plan.md` section 5 records the kit landing, 16 angles, 6 pairs, D-101; no "empty" sentence remains) |
| I-6 | MUST-FIX | K1 pre-registered with two denominators | FIXED at the canonical layer - thesis K1 now carries the binding sentence "Canonical denominator, binding in every document: installs with `onboarding_started`, per the schema formula ... no other denominator may be substituted at read time" (verified at thesis line 186); residue: the teaser row's "of installs" shorthand is stale (section 5) |
| I-7 | SURVIVING | Every accountability mechanism is a blank ([FOUNDER TO FILL] K8 coder, outside reviewer, K0 coverage) | SURVIVING - section 3 item 7 |
| I-8 | SURVIVING | The "base case" is an optimistic case wearing a base-case label | SURVIVING - section 3 item 8 |
| I-9 | SURVIVING | Even full success is not a venture case | SURVIVING - section 3 item 2 |
| I-10 | SURVIVING | Kill thresholds calibrated against the founder's own aspirations | SURVIVING - section 3 item 9 |
| I-11 | NOTE | K2 gray zone 10-12% has no stated verdict | OPEN - carried to the week-12 review agenda; per lane scope, NOTE-class items were not edited this run |
| I-12 | NOTE | K2/K3 medians rest on blog-grade provenance | CARRIED - week-8 review must retry the primary sources (Adjust, RevenueCat) before any K2/K3 walk-away call |

### Competitor

| # | Sev | Objection (short) | Disposition |
|---|-----|-------------------|-------------|
| C-1 | MUST-FIX | The site refuses the demand the channel plan depends on capturing | FIXED - `03-site/index.html` and `index-b.html` hero aside and launch FAQ now say "nothing to sign up for today; a waitlist opens before this page ever goes live", aligned with channel-plan A4; waitlist-live is a hard pre-publication precondition |
| C-2 | MUST-FIX | A1 kill criterion keyed to a metric the package declares unmeasurable | FIXED - A1 kill replaced with the binding ladder over in-list zero-follower metrics; the waitlist-tap leg activates only once the waitlist exists (same change as I-1/I-3) |
| C-3 | SURVIVING | The hero experience is copyable at the visible layer (cached "Today's pick" plus 813K ratings) | SURVIVING - section 3 item 1, marked strongest; the recommended copy-resistance re-ranking of the angle order was NOT applied this run and is carried to the founder as a production-order decision |
| C-4 | SURVIVING | Months of pre-launch posting is a free R&D window for incumbents | SURVIVING - section 3 item 4 |
| C-5 | SURVIVING | No answer to the instructor counterattack | SURVIVING - section 3 item 11; the recommended site-FAQ addition and drafted comment reply were not applied this run (verified: no instructor FAQ in `index.html`); carried as an explicit open item |
| C-6 | NOTE | The Day-2 paywall review is dated 2020 on screen | FIXED - date removed from screen ("Real App Store review of a fitness app."); fact-check found the date IS sourced (Doctormounir, 02/06/2020, `pain-point-frequency.md`), contra the staleness framing, and the documented date is kept in the Day-2 guardrails for comment replies |
| C-7 | NOTE | The P15 tap-count demo invites bad-faith counting | OPEN - production staging note carried (on-screen counter starts at zero after the app is open); no file change this run |

### User

| # | Sev | Objection (short) | Disposition |
|---|-----|-------------------|-------------|
| U-1 | MUST-FIX | "Months of research" and "hundreds" are unverifiable founder-conduct claims | FIXED - `05-social-pmf/week-1-drafts.md` Day 2 now says "the number-one complaint in the app reviews and forum threads I mined before building this" (rank 1 in `pain-point-frequency.md`); caption now "Paywall complaints ranked first in the 24 sources I mined before building" (24 = distinct URLs in that file's Sources list); guardrails pin both numbers |
| U-2 | MUST-FIX | Mobile hero is a text wall; the mock is cut at the fold | FIXED - `03-site/index.html` and `index-b.html` mobile hero restructured (trimmed deduplicated subhead, compact mock, proof strip moved below the mock); all four PNGs re-shot; session card, Start button, and consistency line verified above the fold on both variants |
| U-3 | MUST-FIX | Screenshot 04 ships the killed "whole game" phrase | FIXED with a different disposition - fact-check showed the line IS shipped build copy (`ios/.../ActiveSessionView.swift`, visible text lines 452-456), so under brand-guidelines section 10 the staged screen may depict it; the marketing-authored "Tuesday off. " prefix was removed so the mock shows the exact build string, the PNG re-rendered, and the README records that ad/marketing surfaces may not use "whole game" / "show up" headlines (the Jillian Michaels collision), which is the product-copy flag the lawyer's ruling asked for |
| U-4 | SURVIVING | "No questions" reads as "not built for me" | SURVIVING - section 3 item 12; the adaptive-start angle stays in the queued seed pool for the day-14 rebuild, not scheduled in week 1 |
| U-5 | SURVIVING | "Forever" from an app that does not exist yet | SURVIVING - section 3 item 5 |
| U-6 | SURVIVING | Founder lines written like taglines, not speech | SURVIVING - carried as production direction: paraphrase, post the slightly fumbled take |
| U-7 | SURVIVING | The page is a dead end, and two assets show two statuses | SURVIVING, narrowed - the dead end is now explained on-page by the waitlist sentence (C-1); residue: the `gate-test-asset-v2.png` "TestFlight opening soon" status vs the site's status was not reconciled this run and is carried as an open item |
| U-8 | SURVIVING | "The Strength Phase, once you earn it" reads pay-plus-homework | SURVIVING - section 3 item 14; the reply belongs in the review-response playbook and has not been drafted yet |
| U-9 | NOTE | "Most workout apps..." trips the ad detector | CARRIED - AB-1 already tests exactly this; the persona's prediction (leg B wins) is logged for the read |
| U-10 | NOTE | Airplane-mode hook loses the couch ICP | CARRIED - feeds the day-7 midpoint and day-14 reads; no pre-registration change |
| U-11 | NOTE | The 2020 date on screen invites the "six years" comment | FIXED - same change as C-6/L-4 |
| U-12 | NOTE | Length chips next to "no questions" copy invite "that's literally a question" | CARRIED - keep the "one tap, never blocks Start, session already built" reply ready wherever that screenshot and claim co-occur |
| U-13 | NOTE | Frame-strip title cards near-illegible | OPEN - contrast check deferred to the video production pass; if the real title cards render at strip contrast they need a pass before the cut |

### Lawyer

| # | Sev | Objection (short) | Disposition |
|---|-----|-------------------|-------------|
| L-1 | MUST-FIX | Screenshot 04's week-note must not ship in marketing | FIXED via the ruling's own escape clause - the string is verified shipped app copy (see U-3), so it stays as depicted product UI with the non-build prefix removed; the marketing-surface restriction is recorded in the screenshots README |
| L-2 | MUST-FIX | Site FAQ invents progression-tier names and counts | FIXED - both site variants' progression FAQ now names only library-verified movements with generic "easier and harder tiers" wording and no counts; fact-check: the push-up tiers all exist in `Exercises.json`, and the squat claim was wrong in the other direction (six tiers ending at pistol squat, not five ending at shrimp squat), confirming the cut |
| L-3 | MUST-FIX | "There is nothing to sell" is falsified by the measurement plan | FIXED - both variants' data FAQ now: never sold, on-device / private iCloud, planned anonymous per-install usage events, waitlist-email disclosure, aligned with `06-channels/event-metric-schema.md` so the FAQ, the schema, and the future nutrition label tell one story |
| L-4 | MUST-FIX | Day-2 draft states an unverified date and founder-conduct quantities | FIXED - attribution is now "Real App Store review of a fitness app." with lower-third "Solo developer, building Rep Today."; quantities replaced with the sourced rank and count (U-1); fact-check nuance: the 2020 date was documented in `pain-point-frequency.md` (the "invented detail" premise was wrong), but it came off screen anyway per U-11/C-6 |
| L-5 | MUST-FIX | The five PNGs carry no in-asset disclosure | FIXED for the PNGs - all five verified carrying "Screen images simulated. App is pre-release." visible and unclipped (01 was stale and was re-rendered; 04 re-rendered with the copy fix); README documents the disclosure rule (verified, README line 10); residue: the canonical name-clearance line is still absent from the README warning block (section 5) |
| L-6 | MUST-FIX | The 100ms benchmark gate does not block the investor teaser | FIXED at the wording layer - `09-extras/investor-teaser.html` now qualifies both statements ("designed to build ... a real-device benchmark is a pre-publication gate and has not yet been run"; "per the same PRD spec (device benchmark pending)"), which removes the unmeasured-spec-as-fact posture; residue: "investor teaser" has not been added to the checklist item's blocking list (verified unchanged; section 5) |
| L-7 | SURVIVING | "Under 100 milliseconds" is spec-derived and stated as fact on consumer surfaces | SURVIVING - section 3 item 13; AB-4 leg B additionally gained a substantiation gate in `ab-pairs.md` (may not post until the benchmark record exists) |
| L-8 | SURVIVING | "Forever" is a promise no pre-revenue solo founder can guarantee | SURVIVING - section 3 item 5; carried forward from v1 |
| L-9 | SURVIVING | The name is legally naked and the package builds equity on it | SURVIVING - section 3 item 3; carried forward from v1, updated for the D-106 plain "Rep Today" name |
| L-10 | NOTE | "hiit" is the weakest relevance claim in the keyword field | OPEN - verified still present in `channel-plan.md` A2; carried to the founder for an ASO decision: drop it or write the one-sentence relevance rationale |
| L-11 | NOTE | "Relief" survives in internal labels one slip from a caption | CARRIED - production guardrail: when P08 is produced, "relief" must not appear in any hook, caption, or on-screen text |
| L-12 | NOTE | The site's mock caption paraphrases the mandated disclosure sentence | OPEN - handed to packaging: add the canonical sentence to the site footer legal block or amend brand-guidelines section 2 to bless the caption form |
| L-13 | NOTE | The video carries no clearance caveat, by a rule rewritten after the v1 fix | CARRIED - legally defensible (nothing false is stated); the founder consciously owns that a polished video presents an uncleared wordmark |

### Completeness critic

| # | Sev | Objection (short) | Disposition |
|---|-----|-------------------|-------------|
| CC-1 | MUST-FIX | recap.html is the v1 front door verbatim | PARTIAL, then HANDED TO PACKAGING - the killed listing name at line 65 was fixed this run (verified: plain "Rep Today", suffix recorded as killed by D-106); the full rebuild (deliverables table, dead directory links, screenshot links, v2 gate links, link check) is packaging work, section 5 |
| CC-2 | MUST-FIX | README.md map routes into directories that do not exist | HANDED TO PACKAGING - section 5 |
| CC-3 | MUST-FIX | sources.md omits all five v2 research files (~141 citations) | HANDED TO PACKAGING - section 5 |
| CC-4 | MUST-FIX | self-grade.md is the stale v1 grade asserting green | HANDED TO PACKAGING - section 5 |
| CC-5 | MUST-FIX | Dead relative links after the D-102 git mv (gate-report.md, self-grade.md, skeptic-thesis.md) | HANDED TO PACKAGING - fold into the packaging link-check pass, section 5 |
| CC-6 | MUST-FIX | channel-plan.md line 110 says the kit is missing | FIXED before this run's lanes (verified; same finding as I-5) |
| CC-7 | MUST-FIX | product-facts-brief.md still names the killed listing name | FIXED before this run's lanes (verified: line 7 reads plain "Rep Today" with the D-106 / naming-decision.md citation) |
| CC-8 | MUST-FIX | The execution record maps only the v1 run | HANDED TO PACKAGING - section 5 |
| CC-9 | MUST-FIX | Phase-5 v2 gate evidence absent from 08-redteam/ | FIXED - this dossier is that evidence; the v1 persona files are labeled frozen v1 attacks in the header above, and Appendix A preserves the v1 surviving objections |
| CC-10 | SURVIVING | Dual-generation tree with no authority manifest | SURVIVING, mitigated - superseded-by-D-106 banners were added this run to `01-research/aso-landscape.md` (TL;DR and recommended-listing sections) and `01-research/name-collisions.md`; the recap rebuild (CC-1) is the remaining mitigation; the structural weakness ships in section 3 item 16 |
| CC-11 | NOTE | aso-landscape.md recommends the killed title with no pointer | FIXED - superseded notes added (see CC-10); the dated research evidence was left intact rather than rewritten, to avoid falsifying a dated record |
| CC-12 | NOTE | social-launch-kit.md frozen body links a dead path | OPEN - harmless inside a do-not-use file; fold into the packaging link-check if the file is touched |
| CC-13 | NOTE | What was checked and found sound | No action - this is the critic's positive record, kept as evidence that the Phase 1-4 gates are real |

## 3. The surviving objections

These ship because no rewrite fixes them.
Ordered by how much they should worry the founder.

**1. THE STRONGEST - the wedge is copyable at the only layer the audience sees.** (competitor)

> Positioning.md already concedes "perceived instant-open can be faked with caching," and that concession is the whole counter-playbook: an incumbent ships a "Today's pick, ready when you open" card that server-caches one recommended class overnight, then runs the identical screen-record format - cold open, one Start button, tap counter - with an instructor's face on it.
> A scroller cannot distinguish deterministic on-device generation from a cached recommendation in 8 seconds, so the speed angles are copyable at the only layer the audience sees, and the incumbent's version carries "4.9 stars, 813K ratings" where Rep Today's carries "not released yet."
> Only free-forever and no-streaks are structurally safe (the incumbent's own paywall and retention machinery forbid copying them), and a moat that narrow must carry the whole company.

This one is strongest because it has a named actor with a live adjacent ad flight, a concrete one-quarter mechanism, and no possible copy fix; it attacks the hero claim itself, not the packaging.
It sits beside the thesis summary in recap.html.

**2. Even full success is not a venture case.** (investor)

> By its own arithmetic, total success at the 90-day review means above-median retention on a product grossing perhaps $30K optimistic in year 1, in a category where the top decile takes 92.6% of revenue, with paid acquisition permanently underwater.
> There is no articulated mechanism by which surviving the kill criteria compounds into a venture-scale outcome; the strongest honest pitch is "cheap, well-instrumented option on a small business," and the teaser should not be surprised when investors read it that way.

**3. The name is still legally naked, and the whole package builds equity on it.** (lawyer, carried from v1)

> No USPTO search, no App Store Connect reservation, a descriptive mark with a narrow perimeter, REP Fitness owning "rep" web mindshare, and reptoday.com held by a domain investor; the collision scan is a search sample, not clearance.
> Everything shipped before clearance is rework-at-risk.

**4. Months of pre-launch posting is a free R&D window for incumbents.** (competitor)

> Whatever concept wins the public message tournament, wins in public: a competitor reads the same signals and can have a matching creative live before Rep Today can accept its first install.
> The tradeoff may still be right for a zero-audience founder, but time-to-listing is a competitive variable, not a background task.

**5. "Forever" is a promise no pre-revenue solo founder can guarantee.** (lawyer + user, carried from v1)

> If Rep Today shuts down, is sold, or pivots, every asset that said "Free means the workouts. All of them. Forever." becomes the record of a broken promise; softening it would gut the brand's central pledge, so the founder carries this liability knowingly.
> The user's version: "you cannot promise forever, you might not exist in a year, and indie apps change their pricing the week they get traction" - and no copy edit fixes it because it is true.

**6. Pre-launch word of mouth sits outside the falsification schedule.** (investor, residue of I-4)

> K9 now instruments post-launch WOM direction (unattributed-install share, organic search impressions), but nothing measures whether word of mouth is forming before launch, and the thesis says so.
> The load-bearing growth mechanism of a zero-spend company is unfalsifiable until the listing exists.

**7. Every accountability mechanism is currently a blank.** (investor)

> Both named humans are [FOUNDER TO FILL]: the non-founder K8 coder and the outside reviewer who holds the walk-away call, and K0 runs pre-launch outside the reviewer's stated remit.
> Until the names exist, every criterion in this package is self-graded, and the enforcement section is a promise about a future promise.

**8. The "base case" is an optimistic case wearing a base-case label.** (investor)

> Combine the document's own two concessions - the 5,000-install base is a pure [ASSUMPTION] and "the pessimistic 1.0% may be closer to a true base case" - and the honest central scenario is roughly $700-$1,800 gross, not $3,700; the model's candor lives in footnotes while the table's middle row keeps the flattering label.

**9. Three kill thresholds are calibrated against the founder's own aspirations.** (investor)

> K1, K4, and K5 derive from the PRD's targets and the model's assumed base case, so the falsification apparatus partly tests whether reality matches the founder's guesses; a pass on those three is weaker evidence than a pass on the externally-anchored K2/K3/K6/K7, and the 90-day review must say so next to any verdict.

**10. The zero-follower sample-size limits are now honest, and honesty says the run may measure nothing.** (investor, residue of I-1/I-2)

> K0 is fixed so it cannot fake a verdict, which means the other outcome is now possible and likely: at zero followers, most posts may never clear the 200-impression readability floor, and eight weeks of posting can legitimately end in "K0 under-sampled" - no signal either way, with founder hours spent.
> The under-sampled state is the correct design; it is also an admission that the cheapest falsification may return no verdict at all.

**11. No answer exists to the instructor counterattack.** (competitor)

> The cheapest incumbent counter is a reframe: "a list of push-ups from an algorithm, or a coach who knows your name."
> Nothing in the positioning, the angle bank, or the site FAQ says why no-instructor is a feature rather than a poverty signal, and the first time the frame lands in comments, the founder is improvising on camera.

**12. "No questions" reads as "not built for me."** (user)

> "My first question at the hook is 'how does it know what I can do?' and nothing in week 1 answers it," even though the product brief has the answer (capped gentle cold start, asymmetric ramp).
> The promise is the strategy and stays; the package admits here that week 1 leaves "will this wreck my knees / bore me" unanswered, with the adaptive-start angle queued for the day-14 rebuild.

**13. "Under 100 milliseconds" is a precision claim carried forever.** (lawyer, carried from v1)

> Even after a passing benchmark, it remains unverifiable by consumers, and the substantiation burden - device matrix, percentiles, re-measurement every release - is carried forever by a one-person company for a number no tired parent at 9pm can perceive.

**14. "The Strength Phase, once you earn it" reads pay-plus-homework.** (user)

> "I pay $7.99 a month AND still have to earn the feature, which is a worse deal than a plain paywall because I might pay and never qualify."
> The design intent is the point of the product; the store-surface reading is a known comment generator and the reply is not yet drafted.

**15. Founder lines written like taglines will read as ad.** (user)

> "No tired person talking into a phone camera at home says these sentences; they are brand poetry, and delivered verbatim they will read rehearsed."
> Carried as production direction: keep the meaning, post the take where the founder fumbles slightly.

**16. The dual-generation tree still lacks an authority manifest.** (critic)

> v1 and v2 artifacts sit side by side for diffability, and any v1 document without a superseded-by banner is a live trap for a cold reader.
> Banners were added to the two worst offenders this run; the recap rebuild is the remaining mitigation, and the weakness is structural until then.

Also shipping as narrowed residues rather than full objections: the site remains a deliberate dead end until the waitlist goes live (now said on-page), and the TestFlight-status wording differs between the gate-test asset and the site.

## 4. What materially changed because the red team ran (Phase-5 gate evidence)

The gate requires at least one material change; this run produced these:

- The thesis's cheapest falsification was rebuilt so it cannot fake a verdict: K0 reads only zero-follower-measurable metrics over readable posts, with a named "K0 under-sampled" state, and its waitlist legs activate only once the waitlist exists.
- The three conflicting kill-criterion escalation ladders became one binding day-14 / week-8 / week-16 ladder, verbatim-identical in `investment-thesis.md`, `channel-plan.md` A1, and `read-the-results.md` item 6.
- A new K9 criterion instruments the previously unmeasured word-of-mouth leg of bet (d), direction-not-level, with the pre-launch gap stated instead of hidden.
- K1's denominator became canonical and binding in the thesis (installs with `onboarding_started`, per the schema).
- The site's data FAQ dropped the false absolute "there is nothing to sell" for a disclosure that matches the event schema, on both variants.
- The site's progression FAQ dropped invented tier names and counts for library-verified movements only; the fact-check found one of the "facts" was wrong in the other direction, proving the cut necessary.
- Both site heroes were restructured for the mobile fold and re-shot; the session card and Start button are now above the fold at 390x844 on both variants.
- The pre-launch waitlist contradiction was resolved in copy: the page now says a waitlist opens before it ever goes live, and waitlist-live is a hard pre-publication precondition.
- Day 2 of the week-1 drafts dropped an on-screen date and two unverifiable founder-conduct quantities for sourced claims pinned in the guardrails ("number-one complaint", "24 sources"); Day 4 dropped an "Every" absolute.
- AB-4's "under 100 milliseconds" leg gained a substantiation gate: it may not post until the real-hardware benchmark record exists.
- Screenshot 04's week-note was fact-checked against the build, found to be real shipped copy, trimmed to the exact build string, and re-rendered; the README now records the ad/marketing restriction on that phrase (the Jillian Michaels collision).
- Screenshot 01 was found stale (missing the mandated disclosure line) and re-rendered; all five PNGs now verifiably carry "Screen images simulated. App is pre-release."
- The investor teaser's two unqualified 100ms statements were qualified as PRD-spec-with-benchmark-pending.
- recap.html's killed-name line was corrected to the D-106 verdict, and superseded-by-D-106 banners were added to `aso-landscape.md` and `name-collisions.md`.

The red team ran.

## 5. Handed to packaging (not fixed, not dropped)

The completeness critic's packaging findings are Phase-6 work and are explicitly HANDED TO PACKAGING (task: "Package: recap.html, README, sources.md, decisions log, self-grade"):

- **recap.html rebuild** (CC-1): v2 deliverables table, D-106 naming card, -a/-b screenshot links, -v2 gate links, dead-directory links, refreshed dates, programmatic link check; must also surface this dossier's strongest surviving objection beside the thesis summary.
- **README.md map rewrite** (CC-2): v2 directory layout with rows for 05-social-pmf and 06-channels.
- **sources.md v2 append** (CC-3): the five v2 research files' citations with fetch timestamps, and a corrected total.
- **self-grade.md regrade** (CC-4): against the v2 section-11 checklist, keeping the v1 grade only as a labeled record.
- **Execution record** (CC-8): retitle as the v1 record with a v2 successor section mapping the v2 gates.
- **Dead-link sweep** (CC-5, CC-12): `04-video/gate-report.md`, `self-grade.md`, `08-redteam/skeptic-thesis.md`, and (if touched) `09-extras/social-launch-kit.md`.

Small residues from this run's fixes, also for the packaging pass:

- `09-extras/investor-teaser.html` K1 row still says "of installs"; align to "of onboarding starts" per the thesis's binding denominator (I-6).
- `08-redteam/pre-publication-checklist.md` benchmark item: add "investor teaser" to the blocking list (L-6).
- `09-extras/app-store-screenshots/README.md`: add the canonical clearance line to the warning block (L-5).
- Site footer legal block vs brand-guidelines section 2: add the canonical "Screen images simulated." sentence or amend the rule (L-12).
- Reconcile the TestFlight-status wording between `gate-test-asset-v2.png` and the site (U-7 residue).

---

## Appendix A - the v1 surviving objections (2026-07-15, frozen)

Preserved from the v1 dossier.
Items resolved or materially changed by the v2 run are marked; everything unmarked still stands and most of it is re-litigated more sharply in section 3.

### The adversarial skeptic (thesis claims)

> Nothing in this product is defensible ... Seven or Bend could copy the entire stack in one release cycle the moment it shows signs of working ... a fully successful 90-day experiment proves a feature set, not a company.

Still stands; sharpened in v2 into section 3 item 1 (a named competitor wrote the actual counter-playbook).

> The demand evidence is anecdote-grade and the category has never validated the core bet ... the anti-streak bet is validated by no one, including the apps cited as proof of demand.

Still stands.

> Every zero-budget channel reaches someone other than the customer.

Still stands.

> At the install volumes this plan itself forecasts, the 90-day verdict will be statistical noise.

Materially changed in v2, not resolved: the criteria now carry named under-sampled states (K0, K8) so noise reports as "measured nothing" instead of a verdict; the underlying power problem stands (section 3, item 10).

> The most likely outcome is the one the package is not calibrated to detect: unremarkable survival ... nothing forces a decision in the wide gray middle.

Still stands; v2 investor NOTE I-11 (the K2 10-12% corridor) is the same hole, still open.

### The skeptical seed investor

> No answer to the copy scenario exists ... the package can name no surviving asset.

Still stands (section 3, item 1).

> The distribution story has no base rate ... the plan's own per-channel realistic expectations sum closer to the pessimistic 2,000 installs than the base 6,000.

Still stands (section 3, item 8 is the v2 sharpening).

> The only spike channel acquires the wrong customer by the plan's own definition.

Still stands.

> By its own numbers, total success in year 1 is still not a business ... today it is a well-instrumented hobby.

Still stands (section 3, item 2).

> The evidence base is mined App Store reviews and forum comments the thesis itself calls 'directional, not measured'.

Still stands.

> Every mitigation still routes through one person's discipline ... this risk is structural and no rewrite removes it.

Still stands (section 3, item 7 adds that the accountability names are still blank).

### The competitor's head of growth

> The hero claim is imitable in one sprint.

Still stands (section 3, item 1).

> The paywall wedge does not bite the beloved incumbents.

Still stands.

> ASO whitespace is a countdown, not a moat.

Still stands.

> 42 movements will read as small next to Down Dog HIIT's marketed 1000+ exercises.

Still stands; the v2 site FAQ now answers it honestly with verified movements and no counts (L-2), which softens but does not remove it.

> 'Free means the workouts. All of them. Forever.' is an unverifiable promise from a zero-revenue solo developer.

Still stands (section 3, item 5).

> The channel plan's own numbers produce week-12 kill-criteria cohorts too small to be more than noise.

Materially changed, not resolved: see the skeptic's noise item above.

> Premium's day-one value is thin and mockable: 'they charge you for a feature they might not let you use.'

Still stands (section 3, item 14).

> The launch page has zero social proof.

Still stands.

> The App Store name 'Rep Today, Rest Tomorrow' hands competitors a one-line joke.

**RESOLVED IN V2**: the v2 naming tournament killed the "Rest Tomorrow" suffix (D-106); the listing name of record is plain "Rep Today" in every v2-authoritative asset.

### The cynical target user

> The package never answers why I open the app on day 12.

Still stands.

> Speed-to-start is not why I deleted four fitness apps; I quit in week three when life won.

Still stands.

> Everything here is a promise from an app with zero users, no date, and no way to try it.

Still stands.

> The brand bans photography, so I never see a human move.

Still stands.

> 'Rep Today, Rest Tomorrow' ... parses as 'never rest today'.

**RESOLVED IN V2**: the suffix was killed by D-106; the objection attached to the suffix and dies with it.

> My real 9pm failure mode is the kid-cries interruption at minute four, and nothing in any asset says whether a broken-off session counts as showing up.

Still stands; the facts brief still does not cover an abandoned session, so no copy can honestly promise anything here yet.

### The App Store reviewer / FTC-minded lawyer

> "Forever" is a promise no pre-revenue solo founder can guarantee.

Still stands (section 3, item 5).

> The entire public package markets, in the present tense, an app that has never been submitted to the App Store.

Still stands.

> The name is legally naked: no USPTO search has been performed ...

Still stands in updated form: the exposed name is now plain "Rep Today" (D-106), still unsearched and unreserved (section 3, item 3).

> "No account" as a marketing pillar does not remove account obligations (Guideline 5.1.1(v)).

Still stands.

> Even with a benchmark file behind it, "under 100 milliseconds" is an unverifiable-by-consumers precision claim ... carried forever by a one-person company.

Still stands (section 3, item 13); v2 additionally qualified the teaser's wording and gated AB-4's use of the number.

### The v1 gate verdict (preserved)

The v1 run's changes: the kill criteria were rewritten, the base-case economics were recomputed downward, a legal line that appeared in six assets was ruled false and replaced, the video was rebuilt, and the hero of the landing page changed.
The v1 red team ran; its full change list lives in git history at the 2026-07-15 version of this file.
