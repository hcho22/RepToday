# RepToday → Market: Orchestration Prompt (v2)

> Paste into a fresh agentic session with repo access. Edit the `[EDIT ME]` blocks first.
> **Changed in v2:** working name is now RepToday · discipline positioning is now the spine, not a feature · channel strategy rebuilt around creative-carries-targeting · new social PMF-test engine · new marketing-agent build spec (built, not run).

---

## 0. Context you are inheriting

Read `prd-fitsnack-mvp-v6_0702.md` in full before anything else. It is the source of truth for what the product *is*. Do not market a product that differs from it.

Non-negotiable product facts. Contradicting these is a failure, not a creative choice:

- Zero-equipment bodyweight only. Floor and a wall. The "hotel room test."
- Sessions 5–60 min, generated **on-device, deterministically, offline, in under 100ms**. The AI never generates a workout — it asynchronously tunes a Session Policy. Get this split right or don't mention it.
- The app **opens to a ready session**. It never asks "how long do you have?" before Start.
- Consistency Score is **forgiving and rolling — not a streak**. A return after a gap is celebrated, never penalized.
- Three pillars: bodyweight strength, mobility, primal movement. Mobility is co-primary, never a warm-up.
- **No XP, no levels, no badges, no leaderboards, no streaks.** Anywhere. Including in ad copy and social posts.
- Free tier: unlimited workouts forever. Premium ~$7.99/mo, ~$59.99/yr, 14-day trial.
- Pre-launch, iOS-first. **Zero users. Zero downloads. Zero revenue. Zero testimonials. No App Store listing yet.**

**Naming state.** Working name is **RepToday**. Prior candidates Cairn and Stack remain live alternates. Eliminated: Groundwork, Keystone, Keizoku (collisions). Your naming task has changed from *propose a name* to **stress-test RepToday and either confirm it or beat it**. Run it through the same tournament rubric as the challengers — incumbency is not a score. See the clearance rule in §2.4.

---

## 1. Mission

Take this product to market. Produce a complete, locally-runnable go-to-market package: brand, positioning, landing page, launch video, a social-first channel strategy, a PMF-testing kit the founder can run in week one, and an honest investment thesis with its own kill criteria.

**You are not writing a proof. You are writing a falsifiable case.** Zero traction exists. A reader should finish either convinced or *precisely informed about why they aren't* — the second outcome is equally successful.

---

## 2. Guardrails (hard failures)

1. **No new spending.** Only keys and services already in `.env` or project config. Nothing purchased, subscribed to, or signed up for. If a deliverable needs a paid tool, produce it another way or drop it and say so in the recap.
2. **Publish nothing.** Everything local. No deploys, no domain registration, no accounts created, no posts made, no emails sent, no ad accounts touched. Draft for *future* publication only.
3. **Truth policy — you will be graded hardest here.**
   - **Invent freely:** names, taglines, visual identity, copy, narrative, creative concepts, hypotheses, and projections *clearly labeled as projections*.
   - **Never invent:** market statistics, competitor facts, user counts, downloads, revenue, testimonials, quotes, endorsements, press mentions, App Store rankings, survey results, study findings, or citations.
   - Every factual claim carries a **live URL you actually fetched**. A URL you did not fetch does not count. A dead link is a failed claim — delete the claim, not the link.
   - Any number that is a guess is labeled **[ASSUMPTION]** with reasoning shown. A conclusion's confidence equals its weakest link, not its average.
   - **Zero placeholder social proof.** No "join 10,000 users," no invented five-star quotes, no fake press logos. The landing page must be credible *without* social proof, because there is none. That is a design constraint, not an excuse.
4. **No clearance claims.** You cannot run a USPTO search. You may check App Store, domain, and web collisions and report findings. Every naming document must state that formal trademark and App Store name clearance are **UNVERIFIED and are the founder's next action**. Implying a name is "cleared" is a hard failure.
5. **No health or medical claims.** No calorie burn, weight loss, body composition, posture correction, pain or injury claims, no before/afters. Consistency, habit, mobility, and movement claims are fine when framed honestly. Assume FTC substantiation rules and App Store health guidelines apply to every line you write, including social drafts.
6. **Never ask a question.** Where a decision is missing, choose the option most consistent with the product's principles, mark it **[DECIDED BY AGENT]** in the decisions log with the rejected alternative and why, and continue. A halted run is worse than a documented assumption.
7. **Stay in the project directory.** All output under `/gtm/`. Do not modify app source or the PRD.

---

## 3. Voice rules `[EDIT ME]`

*Derived from the PRD's copy contracts. Replace if wrong — the agent cannot ask.*

- Identity-framed, never loss-framed. "You're someone who moves," not "don't break your streak."
- Plain, declarative, short. No hype stacking, no three-adjective runs, no "revolutionary," "unlock," "game-changing."
- **No bro-fitness register.** No grind, beast mode, "no excuses," 5am-club, discipline-as-punishment, or shame. See §4 — this is the most likely way this campaign fails.
- Never mock the user's current state. The audience is a tired parent at 9pm, not a gym rat at 5am.
- Specific over aspirational: "a 7-minute session is already on screen when you open the app" beats "your fitness journey, reimagined."
- Honest about what it isn't: not a strength program, not coaching, not a gym replacement.
- No emojis in product-adjacent copy. Permitted sparingly in social drafts where the platform demands it — flag each instance.

---

## 4. The discipline brief (positioning spine)

Discipline is the product's spine, so it is also the campaign's spine — and it is the single highest-risk creative decision in this package, because "discipline" in fitness marketing collapses into David Goggins within one draft.

**The definition you are marketing:**

> Discipline is not effort. Discipline is *showing up*. Every decision between "I should work out" and "I am working out" is friction, and friction is what actually kills consistency. RepToday deletes the decisions. The session is already on the screen. Five minutes counts. Missing yesterday costs you nothing.

**The inversion that makes it ownable:** every competitor sells intensity and asks the user to supply the discipline. RepToday supplies the discipline structurally and asks the user for almost nothing. **The app is the disciplined one.**

**Hard rules for every discipline-adjacent line:**
- Discipline is *made easy*, never *demanded*.
- Never imply the user has failed. The forgiving score exists precisely because they will miss days.
- Never romanticize suffering, early mornings, or willpower.
- The enemy in every narrative is **friction and decision fatigue**, never the user's character.

**Make this a tournament question, not an assumption.** At least one competing pitch in §6 must argue that "discipline" is the wrong lead word — that it carries too much shame baggage to be rehabilitated in a 6-second hook, and that consistency, friction, or "already ready" should lead instead. The judge panel decides on merit. If discipline loses on the scorecard, report that honestly; do not protect it because this brief exists.

---

## 5. Channel doctrine

You have been given a marketing-agent transcript (Cody Schneider) as a **strategy source**. Read it as method, not as fact — see §5.3.

### 5.1 What transfers, and why

- **Creative carries the targeting.** Meta's newer ad-serving reads the creative and the landing page to decide who sees it, which demotes interest-targeting. The consequence for you: **the landing page is targeting infrastructure, not a brochure.** Its copy must literally name the pain state and the outcome, because the algorithm reads it. Write Phase 2 accordingly.
- **The market picks the message, not the founder.** A single core offer usually needs 10–20+ positioning variants before the winner is visible. Do not ship one hero message and a few tweaks. Ship a **matrix**.
- **Mine complaints in the user's own words.** Reddit, App Store reviews, YouTube comments on functional-fitness and mobility channels. Rank pain points by frequency of mention; the top three seed the creative.
- **Solve for entropy.** Creative systems stagnate. Inject fresh DNA from the free Meta Ad Library (competitor ads), plus YouTube and podcast transcripts in-category.
- **Structured creative logs.** Every asset ships with the JSON record of the angle, hook, pain point, and format that produced it, so a future system can learn which inputs won.
- **Brand-guide QA pass.** Run generated creative back through a vision check against the brand guide — legibility, palette, type — before it is called done.
- **Continuous, not campaign-based.** Deliver a running system with a cadence, not a launch-week plan that ends.

### 5.2 What does NOT transfer — and this is the important part

The transcript describes **paid Meta ads for B2B web SaaS**. RepToday is a **pre-launch consumer iOS app with zero budget, no App Store listing, and a no-spend guardrail**. Do not bolt the playbook on wholesale. Specifically:

- **The Facebook Marketing API loop cannot run.** No spend, no publishing, no ad account. You will **build the system, not operate it.** See §7.
- **iOS attribution is materially weaker than the transcript's web case.** App-install campaigns run through Apple's post-ATT attribution stack rather than clean pixel-to-Stripe tracing. **Research and verify the current state with live sources** — do not assert it from this prompt. Then answer, with citations: *does a zero-budget pre-launch iOS app get better first signal from paid social or from organic short-form plus a waitlist?* Commit to an answer.
- **Do not build a data warehouse.** The transcript's Airbyte/ClickHouse layer unifies live revenue and CRM data. RepToday has **no users and no data sources**. Building a warehouse now is infrastructure theater. Deliver instead a **one-page event and metric schema** — the events worth defining before launch (install → onboarding complete → first session started → first session *completed* → day-7 return → subscribe) so instrumentation exists when there is something to instrument. The PRD's own success metrics are the starting list.
- **Paid generation tools are out.** No HeyGen, Kie AI, Seedance, or equivalents unless already in `.env`. Use ffmpeg, headless-browser capture, and HTML/SVG→frames.

### 5.3 The transcript is not a citable source

Facts inside it were spoken from memory, some self-corrected mid-sentence and one explicitly flagged "don't quote me." **Nothing from the transcript may appear as a fact in any deliverable.** Use it for method. If a claim from it matters, re-verify it independently and cite the primary source, or drop it.

### 5.4 Deliverable

A **ranked channel plan** with, for each channel: the reasoning, the cost assumption, the first-90-days expected signal, and the specific kill criterion. Rank for a founder with **$0 and no audience**, then add a second ranking for **"if $500/mo appeared"** — and say plainly whether that money should be spent at all yet.

---

## 6. Orchestration

The patterns below are a floor. Log the topology you chose in the recap.

- **Parallel researchers**, one per angle: per-competitor teardowns (Down Dog, Freeletics, Nike Training Club, Ladder, Sweat, Caliber, Peloton App, Apple Fitness+, plus three you find), App Store review-mining for the *complaints* that map to this wedge, Reddit and YouTube-comment pain-point mining, category economics with sourced benchmarks, ASO keyword landscape, creator/community landscape (Strength Side's audience and adjacent), and a free Meta Ad Library sweep of fitness-app creative.
- **Positioning + name tournament.** ≥4 agents pitch a full positioning + name + hero message, blind to each other. **One must argue against leading with "discipline"** (§4). Judge panel of ≥3 with published, *differing* rubrics — one weights differentiation, one conversion, one defensibility and legal risk. Publish the full scorecard including losers and margins. A tournament whose margins aren't visible is theater.
- **Skeptic agents** get the last word on every load-bearing claim. Objections that survive ship *visibly* in the final docs, not in a footnote.
- **Red team the package** as: a skeptical seed investor · a competitor's head of growth planning a counter · a cynical target user seeing the ad mid-scroll at 9pm · an App Store reviewer and an FTC-minded lawyer reading every claim including the social drafts.
- **Completeness critic** before any phase closes, checked against that phase's stated exit criteria, with authority to send it back.

---

## 7. The arc

**Phase 1 — Research, discipline positioning, brand.**
Research → tournament → locked positioning, name verdict on RepToday (with §2.4 caveat), messaging hierarchy, ICP, competitive map showing the unowned quadrant, complete brand guidelines (logo concept, hex palette, type scale, voice, do/don't).
*Gate:* hand the guidelines **alone** to a fresh agent that has seen nothing else and have it produce one new asset. Off-brand result means the guidelines are incomplete. Ship the test artifact.

**Phase 2 — Landing page as targeting infrastructure.**
Static, runs locally, documented one-line serve command. Responsive. Credible with zero social proof. Copy names the pain state explicitly (§5.1). Every factual claim links out. Ship **two hero variants** matching the top two positioning angles.
*Gate:* screenshot-verified at 390×844 and 1440×900, both saved and inspected. Broken layout at either width is a fail.

**Phase 3 — Launch video.**
Built with available tooling only.
*Gate — this replaces "you watched it":* `ffprobe` output confirming duration, resolution, and audio stream; frames extracted at 0/25/50/75/100% and **actually viewed**; frame strip saved into the package; script matches frames and passes §3.

**Phase 4 — The PMF test kit.** *(new — see §8)*

**Phase 5 — Break it.**
Red team per §6, rewrite what broke, re-run.
*Gate:* at least one thing changed materially. If nothing changed, the red team performed rather than ran.

**Phase 6 — Package.** `recap.html` as the single front door.

---

## 8. The social PMF engine

The founder's real question in week one is not "how do I get installs" — it is **"which promise makes a stranger stop scrolling?"** Build the instrument that answers it.

**Structure it as pre-registered experiments, not content.** Every post is a hypothesis:

| Field | Requirement |
|---|---|
| Angle ID | Traces to a mined pain point with its source link |
| Hypothesis | The specific belief being tested, in one sentence |
| Hook | First 3 seconds / first line — the only thing being varied within a pair |
| Format | Platform-native, specified |
| Success signal | A **pre-registered** number: saves, watch-through, comment sentiment, waitlist clicks |
| Kill criterion | What result retires this angle |

Requirements:

- **≥15 distinct positioning angles**, not 15 rewrites of one. At minimum, angles must span: friction/decision-fatigue, the 5-minute floor, forgiveness-after-missing, zero-equipment/travel, mobility-as-relief-not-warmup, the on-device speed claim, and *at least one deliberately contrarian angle* — including one that argues against the fitness-industry consensus the product actually opposes.
- **A/B pairs where only the hook changes**, so the variable is isolated.
- **Platform assignment with reasoning.** Do not spray one asset across five networks. Pick the two platforms where a founder with no audience can get honest signal fastest and justify it against the ICP.
- **A 14-day posting cadence** with a mid-point review gate and explicit rules for killing losers and doubling down on winners.
- **A one-page read-the-results guide**: what a win looks like at zero followers, what is noise at this sample size, and what result should make the founder *change the product*, not the copy. Note honestly where n is too small to conclude anything.
- **Ready-to-post drafts** for the first week: full copy, on-screen text, shot list or static layout.
- **No fabricated engagement, no invented "here's what happened when I posted this."** These are drafts, not case studies.

---

## 9. Deliverables

**Required:**
1. Brand + naming verdict (tournament scorecard, RepToday confirmed or beaten, collision findings, clearance caveat)
2. Brand guidelines + fresh-agent test artifact
3. Landing page, two hero variants, mobile + desktop screenshots
4. Launch video + frame strip + script
5. **Social PMF test kit** (§8)
6. **Ranked channel plan** ($0 ranking + "if $500 appeared" ranking + a verdict on whether to spend)
7. **Pre-launch event & metric schema** (§5.2) — one page, no warehouse
8. Investment thesis with explicit kill criteria: what must be true, what to expect in 90 days, and the observation that should make someone walk away
9. Decisions log · 10. Red team dossier (objections, responses, what changed) · 11. `recap.html`

**Then choose 2–3, no more, from:** ad creative matrix for the #1 channel (with the JSON angle log per §5.1) · marketing-agent build spec — the system, documented and runnable, but never run, that would operate the loop the day budget exists · one-page investor teaser · social profile assets · product walkthrough video · onboarding email sequence · pitch deck.
Choose by one rule: **which makes this company feel most real to a stranger?** Name what you dropped and why. Three polished beats six rushed; dropping the rest is the correct answer, not a shortfall.

**Plus: invent one deliverable nobody would ask for.** The thing that makes a reader say "they actually thought about this." It goes in the recap map like everything else.

---

## 10. Output structure

```
/gtm/
  recap.html            ← single front door, links everything
  README.md             ← run the site + play the video, in 3 commands
  01-research/          ← incl. pain-point mining with source links
  02-brand/
  03-site/
  04-video/
  05-social-pmf/
  06-channels/
  07-thesis/
  08-redteam/
  09-extras/
  decisions-log.md
  sources.md            ← every URL cited, with fetch timestamp
```

`recap.html` must explain the business in under five minutes of reading, state the naming verdict *and* its unverified-clearance status, carry the thesis summary and the **strongest surviving objection side by side**, and link every deliverable with working relative paths.

---

## 11. Self-grade before finishing

Fix what fails, then report the grade honestly — including anything you failed and chose not to fix, and why.

- [ ] No spend. No publication. Nothing live. No ad account touched.
- [ ] Every factual claim has a URL you fetched; `sources.md` complete; zero dead links.
- [ ] Zero fabricated stats, users, quotes, testimonials, engagement, or social proof — including inside mockups and social drafts.
- [ ] Nothing from the provided transcript is cited as fact anywhere.
- [ ] Every guess labeled `[ASSUMPTION]` with reasoning.
- [ ] No health claims. No XP/levels/badges/streak language. No bro-fitness register anywhere — re-read every discipline line against §4.
- [ ] Naming verdict carries the "trademark + App Store clearance UNVERIFIED — founder's next action" caveat.
- [ ] Nothing contradicts the PRD: offline generation, ready-on-open, zero-equipment, forgiving score, mobility co-primary.
- [ ] The anti-discipline pitch was genuinely argued and scored, not strawmanned.
- [ ] Site verified at both widths; screenshots in package; landing copy names the pain state explicitly.
- [ ] Video: `ffprobe` output + frame strip in package; script passes voice rules.
- [ ] Brand guidelines passed the fresh-agent test; the test artifact ships.
- [ ] PMF kit has ≥15 distinct angles, isolated-variable A/B pairs, pre-registered success signals, and honest sample-size limits.
- [ ] Channel plan commits to a ranking and answers the paid-vs-organic question with citations rather than hedging.
- [ ] Red team ran; something changed because of it; surviving objections visible in final docs.
- [ ] recap.html links everything; every link resolves.
- [ ] **Nothing is a placeholder pretending to be finished work.** Stubs are labeled stubs in the recap.
