# FitSnack → Market: Orchestration Prompt

> Paste this into a fresh agentic session with repo access. Edit the two `[EDIT ME]` blocks first.

---

## 0. Context you are inheriting

Read `prd-fitsnack-mvp-v6_0702.md` in full before doing anything else. It is the source of truth for what the product actually is. Do not market a product that differs from it.

Non-negotiable product facts (contradicting these is a failure, not a creative choice):

- Zero-equipment, bodyweight only. Every movement works with a floor and a wall ("hotel room test").
- Sessions 5–60 min, generated **on-device, deterministically, offline, <100ms**. The AI never generates a workout — it asynchronously tunes a Session Policy. This split is the technical wedge; get it right or don't mention it.
- The app **opens to a ready session**. It never asks "how long do you have?" before Start.
- Discipline over optimization. Consistency Score is forgiving and rolling — **not a streak**. A return after a gap is celebrated, never penalized.
- Three pillars: bodyweight strength, mobility, primal/animal movement. Mobility is co-primary, not a warm-up.
- **No XP, no levels, no badges, no leaderboards.** Anywhere. Including in ad copy.
- Free tier: unlimited workouts forever. Premium (~$7.99/mo, ~$59.99/yr, 14-day trial) unlocks depth.
- Pre-launch. iOS-first. **Zero users. Zero downloads. Zero revenue. Zero testimonials.**

**Naming state.** Current name "FitSnack" likely under-serves the discipline-first positioning. Eliminated: Groundwork (taken), Keystone (live iOS collision), Keizoku (live iOS collision). Live candidates: **Cairn**, **Stack**. You may recommend keeping FitSnack or propose new options, but you must justify against positioning, App Store collision, and domain availability — and see the clearance rule in §2.

---

## 1. Mission

Take this product to market. Produce a complete, locally-runnable go-to-market package a stranger could open and act on: brand, name recommendation, positioning, landing page, launch video, channel plan, and an honest investment thesis with its own kill criteria.

**You are not writing a proof. You are writing a falsifiable case.** The product has no traction. Anyone who reads your thesis should finish either convinced or *precisely informed about why they aren't* — and the second outcome is equally successful.

---

## 2. Guardrails (hard failures if violated)

1. **No new spending.** Only keys/services already present in the project's `.env` or config. Nothing purchased, subscribed to, or signed up for. If a deliverable requires a paid tool, produce it another way or drop it and say so.
2. **Publish nothing.** Everything local. No live deploys, no domain registration, no social accounts created, no posts made, no emails sent. Draft assets for *future* publication only.
3. **Truth policy — read carefully, this is the one you will be graded hardest on.**
   - **Invent freely:** names, taglines, visual identity, copy, narrative, creative concepts, hypotheses, projections *clearly labeled as projections*.
   - **Never invent:** market statistics, competitor facts, user counts, download numbers, revenue, testimonials, quotes, endorsements, press mentions, App Store rankings, survey results, study findings, or citations.
   - Every factual claim in the thesis, deck, or landing page carries a **live URL you actually fetched**. A URL you did not fetch does not count. A dead link is a failed claim — delete the claim, not the link.
   - Any number that is a guess is labeled **[ASSUMPTION]** with the reasoning shown. Any number from research carries its source inline.
   - **Zero placeholder social proof.** No "Join 10,000 users," no fake five-star quotes, no fabricated logos-of-companies-that-use-us. Design the landing page to be *credible without social proof*, because there isn't any. This is a design constraint, not an excuse.
4. **No trademark clearance claims.** You cannot complete a USPTO search. You may check App Store and web for collisions and report what you find. You must state explicitly that formal trademark and App Store name clearance remain **unverified and are the founder's next action**. Any document implying a name is "cleared" is a hard failure.
5. **No health or medical claims.** No "burn X calories," no "lose weight in N days," no injury/pain/posture cure claims, no body-composition promises, no before/afters. Claims about consistency, habit, mobility, and movement are fine when framed honestly. Assume FTC substantiation rules and App Store health guidelines apply to every line of ad copy you write.
6. **Never ask a question.** Where you need a decision you do not have, choose the option most consistent with the product's stated principles, mark it **[DECIDED BY AGENT]** in a running decisions log, state the alternative you rejected and why, and continue. A halted run is worse than a documented assumption.
7. **Stay in the project directory.** All output under `/gtm/`. Do not modify the app source or the PRD.

---

## 3. Founder voice rules `[EDIT ME]`

*Default, derived from the product's own copy contracts in the PRD. Replace with your real rules if these are wrong — the agent cannot ask.*

- Identity-framed, never loss-framed. "You're someone who moves," not "Don't break your streak."
- Plain, declarative, short. No hype stacking, no three-adjective runs, no "revolutionary/game-changing/unlock your potential."
- No bro-fitness register. No grind, no beast mode, no "no excuses," no shame, no discipline-as-punishment. Discipline here means *showing up*, and showing up is made easy.
- Never mock the user's current state. The audience is a tired parent at 9pm, not a gym rat.
- No emojis in product-adjacent copy. Sparing use permitted in social drafts only if the channel demands it — and note where.
- Specific over aspirational: "a 7-minute session is already on screen when you open the app" beats "your fitness journey, reimagined."
- Honest about what it isn't. It is not a strength program, not coaching, not a replacement for a gym.

Any founder-voiced script (launch video VO, founder note, cold outreach) must pass these. Self-check each line before shipping it.

---

## 4. Orchestration

The patterns below are a floor, not a ceiling. Design whatever shapes the work calls for, and log the topology you chose in the recap.

- **Fan out parallel researchers** across distinct sources and angles: competitor teardowns (per-competitor, one agent each — Down Dog, Freeletics, Nike Training Club, Ladder, Sweat, Caliber, Peloton App, Apple Fitness+, plus at least three you find), App Store review-mining for the *complaints* that map to this product's wedge, category economics (fitness app CAC/LTV/retention benchmarks — sourced, not guessed), ASO keyword landscape, and creator/community landscape (Strength Side's audience and adjacent).
- **Tournament for positioning and name.** ≥4 independent agents each pitch a full positioning + name + hero message, blind to each other. A judge panel of ≥3 with *published, differing rubrics* (one weights differentiation, one weights conversion, one weights defensibility/legal risk) scores them. Publish the scorecard, including the losers and why they lost. A tournament where the winner's margin isn't visible is theater.
- **Adversarial verification.** A skeptic agent whose only job is to refute each load-bearing claim in the thesis. It gets the last word before a claim ships. Objections that survive go into the final docs *visibly*, not into a footnote.
- **Red team the whole package.** Attack it as (a) a skeptical seed investor, (b) a competitor's head of growth planning a counter, (c) a cynical target user seeing the ad in-feed, (d) an App Store reviewer and an FTC-minded lawyer reading every claim. Their objections and your responses ship in the final package.
- **Completeness critic** before any phase is called done. It checks the phase against its own stated exit criteria and can send it back. A phase is not done because you got tired of it.

---

## 5. The arc (each phase has a gate)

**Phase 1 — Market & brand.**
Research → tournament → locked positioning, name recommendation (with the §2.4 clearance caveat), messaging hierarchy, ICP definition, competitive map showing the unowned quadrant, and a complete brand guideline (logo concept, palette with hex, type scale, voice, do/don't).
*Gate:* a stranger could produce a new on-brand asset from the guidelines alone, with zero further input. Test this — have a fresh agent that has read *only the guidelines* produce one new asset. If it comes back off-brand, the guidelines are incomplete.

**Phase 2 — Landing page.**
Static, runs locally, no build step required beyond a plain server command you document. Responsive. Credible with zero social proof. Every factual claim links out.
*Gate:* screenshot-verified at 390×844 (mobile) and 1440×900 (desktop), both screenshots saved into the package and inspected by you. Broken layout at either width is a fail.

**Phase 3 — Launch video.**
Produce with tooling already available (ffmpeg, headless browser capture, SVG/HTML→frames — no paid services).
*Gate — this replaces "you watched it":* the file exists, `ffprobe` confirms duration/resolution/audio stream; extract frames at 0%, 25%, 50%, 75%, 100% and **view them**; save the frame strip into the package; confirm the VO/caption script matches the frames and passes §3. A video you cannot show frames from does not exist.

**Phase 4 — Break it.**
Red team per §4. Rewrite whatever the red team broke, then re-run it. Surviving objections ship visibly.
*Gate:* at least one thing in the package changed materially because of the red team. If nothing changed, the red team didn't run — it performed.

**Phase 5 — Package.**
`recap.html` as the single front door.

---

## 6. Deliverables

**Required:**
1. Brand + naming decision doc (tournament scorecard, name recommendation, collision findings, clearance caveat)
2. Brand guidelines
3. Landing page (+ mobile/desktop screenshots)
4. Launch video (+ frame strip + script)
5. Channel plan: ranked, with the reasoning and the *cost assumption* for each, given a founder with no ad budget
6. Investment thesis with **explicit kill criteria** — "here is what would have to be true, here is what we'd expect to see in the first 90 days, and here is the observation that should make you walk away"
7. Decisions log (every `[DECIDED BY AGENT]`)
8. Red team dossier (objections + responses + what changed)
9. `recap.html`

**Then choose 2–3 from:** ad creatives for your #1 channel · one-page investor teaser · social profile assets + first-week post drafts · product walkthrough video · onboarding email sequence · pitch deck.
Choose by one rule: *which makes this company feel most real to a stranger?* Say which you dropped and why. **Three polished beats six rushed — dropping the rest is the correct answer, not a shortfall.**

**Plus: invent one deliverable nobody would ask for.** It should be the thing that makes someone say "oh, they actually thought about this." It goes in the recap map like everything else.

---

## 7. Output structure

```
/gtm/
  recap.html              ← single front door, links everything
  README.md               ← how to run the site + play the video, in 3 commands
  01-research/
  02-brand/
  03-site/
  04-video/
  05-thesis/
  06-redteam/
  07-extras/
  decisions-log.md
  sources.md              ← every URL cited, with fetch timestamp
```

`recap.html` must: explain the business in under 5 minutes of reading; state the name recommendation and its unverified-clearance status; carry the thesis summary *and* the strongest surviving objection side by side; and link to every single deliverable with working relative paths.

---

## 8. Self-grade before you finish (fix anything failing, then say so)

- [ ] No spend. No publication. Nothing live.
- [ ] Every factual claim has a URL **you fetched**; `sources.md` is complete; zero dead links.
- [ ] Zero fabricated stats, users, quotes, testimonials, or social proof anywhere — including in mockups and ad creative.
- [ ] Every guess is labeled `[ASSUMPTION]` with reasoning shown.
- [ ] No health/medical claims. No XP/levels/badges/streak language. No bro-fitness register.
- [ ] Name recommendation carries the explicit "trademark + App Store clearance UNVERIFIED — founder's next action" caveat.
- [ ] Nothing contradicts the PRD (offline generation, ready-on-open, zero-equipment, forgiving score, mobility co-primary).
- [ ] Site verified at both widths; screenshots in package.
- [ ] Video: `ffprobe` output + frame strip in package; script passes voice rules.
- [ ] Brand guidelines passed the fresh-agent test.
- [ ] Red team ran; something changed because of it; objections visible in final docs.
- [ ] recap.html links everything; every link resolves.
- [ ] **Nothing is a placeholder pretending to be finished work.** If something is a stub, it is labeled a stub in the recap.

Report your self-grade honestly at the end, including anything you failed and chose not to fix, and why.
