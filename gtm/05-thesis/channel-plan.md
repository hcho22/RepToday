# Channel Plan - Rep Today

Constraints this plan is built for: one solo founder, zero ad budget, iOS-only, pre-launch with zero users (product-facts-brief.md).
Every channel below is judged on one question: does it feed the kill criteria in [investment-thesis.md](investment-thesis.md) with real cohorts, at a founder-hours cost that can be sustained alongside development.
All founder-hours figures are [ASSUMPTION]-labeled estimates; no time-cost benchmark for any of these channels was found in research.
Attribution honesty, stated once and assumed throughout: a solo iOS app has weak install attribution, so most channel signals below are spikes correlated with actions, not tracked conversions [ASSUMPTION].

## Ranked channels

### 1. App Store search (ASO)

**What it is.**
Organic discovery through App Store search: title, subtitle, keyword field, screenshots, and the ratings that compound them.

**Why it fits.**
It is the only channel that works every day without founder attention, and the research found a concrete opening: "micro workout" is near-empty whitespace, with only two title-ranked apps, both showing too few ratings for the App Store to display a score (https://itunes.apple.com/search?term=micro+workout&country=US&entity=software&limit=10, https://apps.apple.com/us/app/bare-minimum-micro-workouts/id6759055696, https://apps.apple.com/us/app/1hundred-micro-workout/id1538015864).
The head terms are unwinnable at launch: "home workout" leaders carry 118K-530K ratings at 4.8-4.9 stars (https://apps.apple.com/us/app/home-workout-no-equipments/id1313192037, https://apps.apple.com/us/app/workout-for-women-home-gym/id839285684), and "7 minute workout" has at least seven apps with the literal phrase in their titles (https://itunes.apple.com/search?term=7+minute+workout&country=US&entity=software&limit=10).

**Concrete first actions.**
Ship the researched metadata: title "Rep Today, Rest Tomorrow" (24/30 chars, brand-only, per aso-landscape.md).
Subtitle: decided, not open - decisions-log.md D-005 selected the wedge subtitle "Opens to a ready workout" over the ASO research's keyword candidate "No Equipment Micro Workouts" (27/30 chars), and this plan follows that decision rather than reopening it.
D-005's condition is that the losing candidate's terms move to the keyword field, so the field must actually contain them; the research's original 94-char field omitted both.
Load the amended keyword field: `micro,equipment,bodyweight,quick,daily,home,mobility,stretching,minute,hiit,exercise,routine,busy,5` (99/100 chars; drops the original's low-intent `travel` and `men` to make room - aso-landscape.md, decisions-log.md D-005).
Do not chase "workout planner" (gym-tracker intent, https://itunes.apple.com/search?term=workout+planner&country=US&entity=software&limit=10), "7 minute workout" (name-squatted), or "weight loss" (banned by the no-health-claims rule).
Before locking anything, validate volume with the free Apple Search Ads keyword popularity scores, because the research had no volume tooling and labels every volume statement [ASSUMPTION] (aso-landscape.md).

**Cost.**
[ASSUMPTION] 4-6 founder-hours up front for metadata and screenshots, then 1 hour/week reviewing search data and iterating monthly; reasoning: metadata is a bounded writing task and iteration is App Store Connect review plus small edits.

**Realistic expectation.**
Single-digit to low-double-digit installs per day at steady state in the first quarter; the whitespace term likely has low search volume today precisely because no successful app has trained users to search it [ASSUMPTION, aso-landscape.md], so ASO is the floor and the compounding layer, not the spike.

**Leading indicator.**
App Store Connect search impressions and product-page conversion rate, plus keyword rank for "micro workout" and "no equipment workout"; feeds kill criterion K5 (organic installs/week).

### 2. TestFlight beta as a channel

**What it is.**
A recruited 20-50 person beta cohort, treated both as the first distribution channel and as the instrument that measures the kill criteria before the public can see a failure.

**Why it fits.**
It is the only channel that works pre-launch, and the thesis's cheapest falsification test lives here: moderated first-run observation directly measures onboarding-to-first-session completion (K1) and wedge comprehension (K8) before any launch is burned (investment-thesis.md).
The audience to recruit is the researched ICP: busy desk-bound adults whose demand-side ask is already on record, "I need an app that requires little decision-making ... tell me exactly what to do," offline included (https://hn.algolia.com/api/v1/items/36666806).

**Concrete first actions.**
Recruit from the founder's own network plus participate-first community presence (channels 3 and 4 below), explicitly asking for tired non-athletes rather than fitness enthusiasts.
Freeze the K8 coding rubric before the first session, then run moderated first-run sessions over screen share, recorded and coded against that rubric by someone other than the founder; K8 requires at least 25 observed first runs, pooled across TestFlight and consented early post-launch recordings (investment-thesis.md section 5).
Ask every tester, unprompted, to describe the app in one sentence after a week; count how many reach for "it's already ready when you open it."

**Cost.**
[ASSUMPTION] 3-5 founder-hours/week for four to six weeks: recruitment messages, moderated sessions at 30 minutes each, and feedback triage; reasoning: working toward K8's 25 pooled first-run observations plus asynchronous feedback handling is roughly a half-day per week.

**Realistic expectation.**
Not installs; answers.
A 30-50 person cohort produces no revenue signal but decides whether the wedge is comprehensible and whether K1 is in its expected 45-60% band before launch.

**Leading indicator.**
Invite-to-install rate, first-session completion in moderated runs, and the share of unprompted descriptions that mention the ready-on-open behavior.

### 3. Hacker News / Product Hunt launch posts

**What it is.**
One-shot build-in-public launch posts: a Show HN telling the engineering story of a deterministic, offline, sub-100ms on-device workout engine, and a Product Hunt launch for the product story.

**Why it fits.**
The demand-side evidence for the exact product ask was found on HN itself: the "little decision-making ... tell me exactly what to do" request with an offline requirement is an HN comment (https://hn.algolia.com/api/v1/items/36666806), and the anti-streak sentiment is documented there too ("Then after 200 days, I lost my streak and... breathed a sigh of relief.", https://hn.algolia.com/api/v1/items/38919053).
The honest technical angle is differentiated in a category where "AI coach" marketing draws skepticism: a top Freeletics review reads "There is no AI or adjustments or changes...all marketing BS" (https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews), while Rep Today can truthfully say the AI never generates a workout and is never on the start path (product-facts-brief.md).
A related caution from the fetched data: AI-branded apps show 36% worse 12-month retention than non-AI apps, so the story leads with determinism, not AI (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/).

**Concrete first actions.**
Draft the Show HN now and cold-test it on engineers who have never heard the pitch (thesis pre-spend action 7).
Launch on the App Store first, run one quiet week to shake out crashes, then post Show HN; Product Hunt follows within the same month.
Prepare for the comment thread honestly: pricing questions, "why not Android," and streak-philosophy debates are predictable, and the founder answers all of them in person on launch day.

**Cost.**
[ASSUMPTION] 6-10 founder-hours total per launch post: writing, asset prep, and a full day of comment presence; reasoning: the post is short but launch-day responsiveness is the actual work.

**Realistic expectation.**
High variance by nature: most Show HNs get little traction, and a front-page result is the difference between the base and optimistic install scenarios in the thesis model [ASSUMPTION].
Plan for the modest case: a few hundred installs per successful post, concentrated in one week, skewed toward engineers rather than the 9pm-parent ICP.

**Leading indicator.**
Launch-day installs versus the prior week's baseline, and the D7 retention of the spike cohort versus organic cohorts; a spike that retains at half the organic rate is audience mismatch, not success.

### 4. Reddit communities

**What it is.**
Participate-first presence in r/bodyweightfitness, r/fitness30plus, and secondarily r/flexibility and r/getdisciplined: answering questions as a member for weeks before any product mention.

**Why it fits.**
r/fitness30plus is the ICP almost verbatim: 197,000 members, the fastest-growing of the researched set at +11.9% in the past year, self-described as fitness for people over 30 with "struggling" and "progress" as top discussion themes (https://gummysearch.com/r/fitness30plus/).
r/bodyweightfitness is the audience bullseye at multi-million scale (4.8M members per https://gummysearch.com/r/bodyweightfitness/, 2.5M per the stale https://frontpagemetrics.com/r/bodyweightfitness), and fitness apps are already among its frequently discussed products (gummysearch fetch, creator-landscape.md).

**The honest caveat, stated plainly.**
Self-promotion rules for every one of these subreddits could NOT be verified: reddit.com and every mirror attempted were blocked during the research run (creator-landscape.md).
[ASSUMPTION] Large fitness subreddits typically restrict app promotion heavily; treat every subreddit as no-promotion until the founder has read the actual rules pages manually, which is the mandatory first action.

**Concrete first actions.**
Read the rules of all four subreddits manually before anything else.
Spend 3-4 weeks answering questions with zero product mentions, in the founder's real voice.
If and only if rules permit, one honest post per community at launch, framed as a solo builder sharing what he built and asking for critique, never as an ad.

**Cost.**
[ASSUMPTION] 2-3 founder-hours/week, ongoing; reasoning: participation is 20-30 minutes a day of reading and answering, and it doubles as user research.

**Realistic expectation.**
Tens of installs per accepted post, plus TestFlight recruits and qualitative signal; the channel's real yield is trust and feedback, not volume.
A removed post or a mod warning is a full stop for that community, not a workaround puzzle.

**Leading indicator.**
Comment karma and reply quality in-community; after any permitted post, install spikes correlated to the post day and TestFlight signups mentioning Reddit.

### 5. Creator partnerships

**What it is.**
Zero-budget outreach to a small set of researched creators whose audiences match, with asks that cost them nothing: early access, a founder conversation, or story material, never a sponsorship.

**Why it fits.**
GMB Fitness is nearly Rep Today's positioning in creator form: 370,987 subscribers, "no gym equipment," targeting "people who don't want to feel limited physically but have more important things to do than spend hours every day working out," with results in "15-45 minutes, a few times a week" (https://socialcounts.org/youtube-live-subscriber-count/UC_ruB7qtdk4KufASPRuWhZA, https://gmb.io/).
Hybrid Calisthenics (4,469,187 subscribers) matches on tone: Hampton Liu's shame-free philosophy ("There's no reason to be ashamed if you can't do a push-up," https://www.newsweek.com/wholesome-fitness-influencer-praised-removing-shame-personal-training-1591196) mirrors the non-streak, never-penalized Consistency Score exactly, but his stated anti-selling stance ("we don't need people to sell us our own health," https://www.hybridcalisthenics.com/about) makes promotion of a paid tier unlikely; the free-unlimited-workouts framing is the only viable pitch (creator-landscape.md).
The Bioneer (951,919 subscribers, video essays on training ideas, https://socialcounts.org/youtube-live-subscriber-count/UCIh_TPYPqjJuS_-nOfAIlfg) is a story pitch: a deterministic, no-gamification workout engine is essay material, not ad inventory.
Deprioritized per research: Tom Merrick sells his own app (https://www.bodyweightwarrior.co.uk/about/), Strength Side sells $150+ competing programs with no partnership surface found (https://strengthside.com/), and the pain/rehab cluster (Squat University, MoveU, Conor Harris) is a positioning mismatch (creator-landscape.md).

**Concrete first actions.**
Three personal emails, not a campaign: GMB (founder conversation plus early access), Hybrid Calisthenics (free-tier-only framing, early access, zero ask beyond a look), The Bioneer (the engine story as essay material).
Include a working TestFlight link and a one-paragraph honest description; no press kit theater.

**Cost.**
[ASSUMPTION] 1-2 founder-hours/week; reasoning: the outreach list is three names, and the work is writing three good emails and following up once.

**Realistic expectation.**
Long shots, honestly: expected response rate is low and no researched creator has an obvious incentive to promote a potential competitor [ASSUMPTION].
One genuine mention from any of them would beat months of other channels, which is why the asks stay cheap enough to justify the attempt.

**Leading indicator.**
Reply rate to the three emails; any mention followed by an install spike and a retained cohort.

### 6. Short-form video

**What it is.**
Founder-made vertical clips (TikTok, Reels, Shorts) built around the one moment the product owns: cold open of the app, a complete session already on screen, one tap on Start; the whole demo fits in under 10 seconds.

**Why it fits.**
The core claim is inherently visual and needs no talking head: "Open the app. Your workout is already there." is the locked hero message (positioning.md), and a screen recording proves it faster than any copy.
The contrast format writes itself against the researched competitor friction: NTC's account-plus-quiz-plus-browse flow (https://www.whistleout.com/CellPhones/Guides/nike-training-club-app-review), Down Dog's configure-then-generate settings stack (https://www.downdogapp.com/faq), Freeletics' onboarding interview (https://www.freeletics.com/en/blog/posts/getting-started-with-freeletics/).

**Concrete first actions.**
Batch-record five clips in one sitting from the simulator or a device: the 10-second one-tap open, the duration-chip regeneration, the airplane-mode session build, a miss-a-day Consistency Score explainer, and a "what 7 minutes actually looks like" clip.
Post two per week and stop iterating formats that get no traction after four weeks.

**Cost.**
[ASSUMPTION] 3-5 founder-hours/week if done seriously; reasoning: recording is cheap but editing, captions, and posting cadence are the real cost, and this is the easiest channel to let quietly eat development time.

**Realistic expectation.**
[ASSUMPTION] Low and slow without an existing audience: organic short-form reach for a new zero-follower account is unpredictable, and no research file contains evidence on short-form conversion for fitness apps; treat the first 90 days as format discovery, expect near-zero installs, and keep it ranked last for that reason.

**Leading indicator.**
View-through rate on the 10-second demo clip and profile-tap rate; any single clip that outperforms the account baseline by 10x becomes the template.

## What NOT to do at zero budget

**No paid UA, and not only because there is no budget.**
The only fetchable CPI data is secondary: roughly $1.50-$5.50 per install across Facebook, Google, and TikTok, with a $4.06 median US Apple Search Ads CPI (https://www.airbridge.io/blog/cost-per-trial-cost-per-subscription-subscription-app-ua-metrics-fitness-app).
[ASSUMPTION] Combining that CPI range with the 2.9% median download-to-paid at day 35 (https://www.revenuecat.com/state-of-subscription-apps) implies roughly $50-$190 per paying subscriber from cold traffic; this is arithmetic on two fetched numbers, not a published figure (category-economics.md).
The 2.9% is the blended all-model median and is used here only as a paid-UA sanity bound; the thesis's own model stands on the freemium-only 2.1% (see the reconciliation note in investment-thesis.md section 4).
Against a median year-1 realized LTV per payer of $35.64 (https://www.revenuecat.com/state-of-subscription-apps) and a freemium model that converts at a 2.1% day-35 median versus 10.7% for hard paywalls (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/), paid acquisition is underwater before the first dollar is spent.

**Do not lead any channel with "AI."**
AI-branded apps show 36% worse 12-month retention than non-AI apps in the fetched 2026 data (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/), and the product's true story is the opposite: the AI never generates a workout (product-facts-brief.md).

**Do not post to any subreddit before manually reading its rules.**
The rules could not be verified by research and the assumption is heavy restriction (creator-landscape.md).

**Do not buy reptoday.com.**
$3,895 at HugeDomains (https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com) buys zero installs; reptoday.app showed NXDOMAIN, a strong availability signal (https://dns.google/resolve?name=reptoday.app&type=NS).

**Do not chase the squatted or mismatched keywords.**
"7 minute workout" is name-squatted with at least seven literal-title apps, "workout planner" is gym-tracker intent, and "weight loss" is barred by the no-health-claims rule (aso-landscape.md).

## First 90 days: a weekly operating rhythm one founder can sustain

Total GTM budget: [ASSUMPTION] 8-12 founder-hours/week, capped so development and bug response stay primary; reasoning: GTM time beyond this comes directly out of shipping fixes, which the kill criteria depend on.

**Weeks -4 to 0 (pre-launch).**
Mon: 1h - clearance and setup work through the thesis pre-spend list (trademark search and, if the search is clean, a filed USPTO application before launch - the competitor red team is right that an unfiled common-word name is an invitation; App Store Connect record, ASA keyword validation, funnel instrumentation).
Tue/Thu: 30m each - participate-first Reddit presence, zero product mentions; read all subreddit rules in week -4.
Wed: 2-3h - TestFlight: recruiting, then moderated first-run sessions; K1 and K8 get their first read here, and K8's full 25-run sample pools these with early post-launch recordings.
Fri: 1-2h - draft and cold-test the Show HN post; finalize ASO metadata and screenshots.

**Weeks 1-4 (launch month).**
Mon: 1h - metrics hour: every kill-criterion metric reviewed against its expected band, written down, no exceptions.
Tue/Thu: 30m each - community participation; launch posts to permitted subreddits in week 2 or 3.
Wed: development priority - ship fixes surfaced by the first public cohorts.
One-off, week 2: Show HN (full day of comment presence); Product Hunt in week 3 or 4.
Fri: 1h - respond to every App Store review; send the three creator emails in week 1 and one follow-up in week 3; in week 1, set up brand-term monitoring (a daily App Store search for "rep today" and the brand phrases) so a competitor bidding or keyword-squatting on the name is seen the week it starts, not the month after.

**Weeks 5-12 (steady state).**
Mon: 1h - metrics hour against the kill criteria; at week 8 and week 12, a formal written check: which criteria are in band, which fired, and what that means per the thesis.
Tue/Thu: 30m each - community participation and TestFlight/beta feedback triage.
Wed (biweekly): 1h - ASO iteration from search-impression data.
Fri: 2h - one content unit: a short-form clip or a build-in-public note, alternating; drop whichever format shows nothing by week 12.
The rhythm ends at week 12 with the 90-day kill-criteria review, and the plan's honest promise is that the review is allowed to say stop.
