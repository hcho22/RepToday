# Investment Thesis - Rep Today

Status: pre-launch iOS app. Zero users, zero downloads, zero revenue, zero testimonials (product-facts-brief.md).
This document is a falsifiable case, not a proof.
It is written so that a skeptical reader finishes either convinced or precisely informed about why they are not, and both outcomes are treated as success.
Every external number carries its source URL inline; every guessed number is labeled [ASSUMPTION] with the reasoning shown.
No health claims are made anywhere in this document.

## 1. The bet in one paragraph

Rep Today matters only if four things are true at once.
(a) Session-start friction is a real churn driver in fitness apps: the moment between opening an app and starting to move is where users are lost, and the category's configure-first and browse-first designs make that moment expensive.
(b) A product that opens to a ready session, forgives missed days instead of zeroing streaks, and keeps unlimited workouts free forever converts tired non-athletes whom the category ignores - the parent at 9pm, not the gym rat.
(c) One solo founder with zero ad budget can reach those people through engineer-facing launch posts, participate-first fitness communities, and steady App Store search discovery.
The "micro workout" whitespace is a costless option layered on top of that search presence, not a reach mechanism: its search volume is unmeasured and likely low (section 3, aso-landscape.md), so nothing in this bet is allowed to rest on it.
(d) The retention economics of a habit-shaped product carry the premium conversion: freemium fitness monetizes badly at the median, so this only works if the free core loop retains meaningfully above category medians and word of mouth compounds.
If any one of the four fails, the company fails, and the kill criteria in section 5 are designed to detect which one failed within 90 days of launch.

## 2. Evidence for

The strongest citable support, claim by claim, each tied to its fetched source.

**The demand for a zero-decision workout app is expressed verbatim by real people.**
A Hacker News commenter asking for a workout app: "I suffer from moderate ADHD and need an app that requires little decision-making. Big buttons, pre-programmed workouts, etc. ... No, I need the app to tell me exactly what to do," and the same commenter required offline functionality (https://hn.algolia.com/api/v1/items/36666806).
An in-category App Store review complains of "excessive scrolling, multiple clicks to get to something" (https://apps.apple.com/us/app/centr-strength-fitness-app/id1382530817).

**The paywall-gates-everything complaint is real, in-category, and repeated.**
"you cannot use this app unless you pay for it. You just can't." (https://apps.apple.com/us/app/30-day-fitness-workout-at-home/id1099771240).
"the app won't do anything until you sign up for the free trial (which, if you forget, will convert to paid) ... that's not a good first impression for an app that's advertised as 'free'" (https://hn.algolia.com/api/v1/items/39991813).
Rep Today's free tier is unlimited workouts forever, and the paywall never gates the core loop (product-facts-brief.md).

**The streak-loss-to-quit mechanism is documented, and competitors already hedge against it.**
"Then after 200 days, I lost my streak and... breathed a sigh of relief." (https://hn.algolia.com/api/v1/items/38919053).
"That was it, back to 0, through no fault of my own. ... and just stopped using it entirely after that." (https://hn.algolia.com/api/v1/items/40903998).
One in-category example exists: a BetterMe reviewer losing streaks to sync failures, "When that happens I loose my streaks." (https://apps.apple.com/us/app/betterme-health-coaching/id1264546236).
Seven, the closest competitor by workout shape, allows 3 skip days per month before breaking a streak, a partial concession to exactly the brittleness Rep Today's non-streak Consistency Score removes (https://apps.apple.com/us/app/seven-7-minute-workout/id650276551, https://seven.app/).

**No researched competitor combines Rep Today's three differentiators.**
The teardown of the four closest competitors (Seven, Bend, Wakeout, pliability) found that no competitor combines all three of Rep Today's differentiators: a session already generated on open, a forgiving non-streak consistency metric, and an unlimited free core loop (competitors-additional.md, sources including https://apps.apple.com/us/app/seven-7-minute-workout/id650276551, https://apps.apple.com/us/app/bend-stretching-flexibility/id1513988468, https://wakeout.app/, https://apps.apple.com/us/app/pliability-stretch-mobility/id1175346453).
Wakeout, the lowest-friction product found anywhere in the research, still advertises "Four taps. Under 30 seconds" and asks outcome, location, and position before starting (https://wakeout.app/); Rep Today's design is zero questions before Start.
The honest caveat on the quadrant: this is a statement about roughly a dozen researched apps, not the whole store, and the corner may be empty because it monetizes badly - an ungated free tier converts at a 2.1% day-35 median versus 10.7% for hard paywalls (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/), so rational incumbents may have looked at this quadrant and declined it.
The big-brand catalogs are browse-and-pick with signup and quizzes up front: NTC requires an account and a goals quiz (https://www.whistleout.com/CellPhones/Guides/nike-training-club-app-review, https://www.reviewed.com/health/content/nike-training-club-review-workout-app), Down Dog is login-mandatory and configure-then-generate (https://www.downdogapp.com/faq), Freeletics runs a multi-question onboarding before its Coach builds a plan (https://www.freeletics.com/en/blog/posts/getting-started-with-freeletics/).

**Adjacent scale suggests the demand shape.**
Seven claims over 30 million users for zero-equipment micro-workouts (https://seven.app/), and Bend claims over 15 million users for a short daily movement habit (https://bend.com/).
Both figures are vendor self-reported marketing claims, likely cumulative downloads rather than active users; no third-party number exists in the research.
Rep Today is not creating a behavior; it is removing the friction and the punishment from a behavior two large apps already validated.
The confound, named: both witnesses built that scale on the streak-and-gamification mechanics Rep Today bans, and no gamification-free micro-workout app at scale exists anywhere in the research, so the anti-streak version of this demand is validated by nobody, including these two.

**The "micro workout" App Store phrase is near-empty whitespace.**
Only two apps rank with the phrase in their title, and both show too few ratings for the App Store to display a score (https://itunes.apple.com/search?term=micro+workout&country=US&entity=software&limit=10, https://apps.apple.com/us/app/bare-minimum-micro-workouts/id6759055696, https://apps.apple.com/us/app/1hundred-micro-workout/id1538015864).
By contrast, the crowded head terms are owned by apps with 118K to 530K ratings at 4.8-4.9 stars (https://apps.apple.com/us/app/home-workout-no-equipments/id1313192037, https://apps.apple.com/us/app/workout-for-women-home-gym/id839285684).

**The category monetizes per install better than any other, and Rep Today's pricing choices match the fetched benchmarks.**
Health & fitness shows a median revenue per install of $0.48 at day 14, the highest of all categories, with median year-1 realized LTV per payer of $35.64 (https://www.revenuecat.com/state-of-subscription-apps).
Annual plans dominate (68% of plan mix per RevenueCat, same URL) and are the only App Store category share still growing per Adapty (https://adapty.io/blog/health-fitness-app-subscription-benchmarks/).
Rep Today's planned 14-day trial is longer than the category norm.
In aggregate data, longer trials correlate with higher conversion: 42.5% median for 17-32 day trials versus 25.5% for 3-day trials (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/).
Stated honestly: the cited band does not cover 14 days, the data is all-category rather than fitness-specific, and the correlation is confounded by app type, so causality is unknown; the 14-day choice is a bet, not a benchmarked position.

## 3. Evidence against, and what we could not verify

This section gets the same rigor as the last one, deliberately.

**The anti-streak ground is already contested.**
An HN search for "streak anxiety" surfaced builders already marketing against it: "There's no streak anxiety, no leaderboard"; "No streak anxiety. No guilt. No 'you failed today' energy." (https://hn.algolia.com/api/v1/search?query=%22streak%20anxiety%22&tags=comment).
Forgiveness is not a defensible claim on its own; it ships as messaging pillar 4, not the headline (positioning.md).

**The streak-pain evidence is mostly out-of-category.**
The vivid streak-loss quotes are about Duolingo and habit apps, not fitness apps; only one fitness-app streak complaint was found, and it is about losing streaks to bugs, not about streak pressure itself (review-mining.md, https://apps.apple.com/us/app/betterme-health-coaching/id1264546236).

**No citable connectivity-pain evidence exists.**
Targeted searches for complaints about streaming or video requirements in workout apps returned zero hits; the offline claim is stated as product fact, never as claimed market pain (review-mining.md, positioning.md).
Marketing must not lead with connectivity pain until better evidence exists.

**Nike Training Club undercuts the free wedge.**
NTC is genuinely free with no premium tiers or upsells (https://www.whistleout.com/CellPhones/Guides/nike-training-club-app-review) and its visible reviews praise exactly that: "Thank you from the bottom of my heart Nike for providing all this for free" (https://apps.apple.com/us/app/nike-training-club-wellness/id301521403).
"Free unlimited workouts" is a wedge against paywalled apps, not against NTC; the wedge against NTC is friction and mechanics only.

**Counter-evidence: some users want more control, not less.**
Freeletics reviewers complain "Not being able to customize the workouts. This is the biggest issue for me" and "there's no option to simply swap out or modify a specific exercise" (https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212).
Zero-decision positioning will repel the customizer segment by design.

**The review evidence itself is skewed.**
App Store web pages surface only a handful of curated reviews, which skew positive; that limits how much negative signal could be mined per app, and it means the complaint themes above are directional, not measured (review-mining.md method note).

**Reddit self-promotion rules could not be verified.**
reddit.com and every mirror attempted were blocked during the research run, so no subreddit's promotion rules were verified; [ASSUMPTION] large fitness subreddits typically restrict app promotion heavily, and every subreddit must be treated as no-promotion until a human reads the actual rules (creator-landscape.md).

**No primary CAC source exists for fitness.**
No fitness-specific primary CAC data was fetchable; only secondary CPI aggregations of roughly $1.50-$5.50 per install exist publicly (https://www.airbridge.io/blog/cost-per-trial-cost-per-subscription-subscription-app-ua-metrics-fitness-app).
Any paid-acquisition plan would be built on unverified numbers, which is one more reason there is no paid-acquisition plan.

**The market structure is hostile to new entrants.**
The top 10% of health & fitness apps capture 92.6% of all category revenue, 31% more subscription apps launched in 2025 than 2024, and median revenue per newly launched subscription app fell 22% year over year (https://adapty.io/blog/health-fitness-app-subscription-benchmarks/).

**iOS-only is a capacity choice, and it concedes most of the ICP's phones.**
The reasons are practical: the build is Apple-native end to end (SwiftUI, StoreKit 2, CloudKit, HealthKit; product-facts-brief.md), one founder cannot build, ship, and support two platforms while running the channel plan, and every subscription benchmark used in this document is App Store data.
The concession is real: most of the world's tired parents hold Android phones, and the iOS 17+ floor narrows the reachable set further [ASSUMPTION: no platform-share source was fetched in research; the direction is not in doubt even though the exact fraction is].
Android happens only if the 90-day review clears and capital or revenue pays for the second platform (section 7); until then, every install figure in this document is iOS-only by construction.

**Category retention medians are brutal.**
Fetched medians for health & fitness sit around D1 20-25%, D7 8.5-10%, D30 3-5% (https://uxcam.com/blog/mobile-app-retention-benchmarks/, https://sendbird.com/blog/app-retention-benchmarks-broken-down-by-industry), meaning 95%+ of installs are gone within a month for a typical app.
The thesis requires beating these medians materially, and there is currently zero user data suggesting Rep Today will.

**Freemium monetizes far worse than hard paywalls.**
Aggregate median day-35 conversion is 2.1% for freemium apps versus 10.7% for hard-paywall apps, and day-60 revenue per install is $0.38 versus $3.09 (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/).
Rep Today's ungated free tier is a deliberate bet against the better-monetizing model.

**The "micro workout" whitespace may be empty because nobody searches it.**
[ASSUMPTION] "micro workout" likely has low search volume today precisely because no successful app has trained users to search it; it is a differentiator with growth optionality, not a traffic source (aso-landscape.md).
No search-volume data of any kind was available; all ASO prioritization rests on who ranks, not on measured volume (aso-landscape.md method limitation).

**Trademark and listing clearance are unverified.**
No USPTO or registry search was performed, and App Store Connect name reservation was not checked; the collision scan found the name clean but REP Fitness owns significant "REP" mindshare in fitness search (name-collisions.md, https://www.repfitness.com).

## 4. The economics sketch

A small model with every input labeled.
All revenue figures are gross, before Apple's commission, refunds, and taxes; see the ignore list below.

**Inputs.**

- Organic installs, first 12 months: pessimistic 2,000 / base 5,000 / optimistic 20,000. [ASSUMPTION] No citable public benchmark for a solo pre-launch iOS app's organic installs was found in any research file. Reasoning: the crowded head keywords are owned by incumbents with 118K-530K ratings (https://apps.apple.com/us/app/home-workout-no-equipments/id1313192037, https://apps.apple.com/us/app/workout-for-women-home-gym/id839285684), the whitespace term has unproven volume (aso-landscape.md), and the only spike mechanisms available at zero budget are launch posts. The base case assumes one modest launch spike of roughly 600 installs across the Show HN and Product Hunt posts, matching the channel plan's few-hundred-per-post modest case (channel-plan.md), plus a steady state near 90 installs/week, the top of the channel plan's realistic ASO band plus community posts; optimistic assumes a front-page launch post or an App Store feature; pessimistic assumes no spike lands.
- Download-to-paid rate: pessimistic 1.0% [ASSUMPTION, below the freemium median because the unlimited free tier removes upgrade pressure] / at-benchmark 2.1%, the aggregate freemium median at day 35 (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/) / optimistic 4.0%, the PRD's own free-to-paid target, which requires top-quartile behavior. The 2.1% scenario is labeled at-benchmark rather than neutral on purpose: the benchmark population is live, marketed, conversion-optimized apps, and treating its median as the midpoint for a zero-budget solo app whose free tier deliberately removes upgrade pressure is itself an assumption; the pessimistic 1.0% may be closer to a true base case.
- Cross-check via the trial funnel: category medians of 6.9% download-to-trial times 37.7% trial-to-paid imply roughly 2.6% download-to-paid (https://www.revenuecat.com/state-of-subscription-apps); the prior-year trial-to-paid median was 39.9% (https://www.revenuecat.com/state-of-subscription-apps-2025). Treat this as directional at best, not confirmation: those funnel medians come from paywall-driven apps while K6 expects Rep Today's trial starts at half the median by design, and the chain multiplies aggregate all-category conversion into fitness-specific LTV, mixing benchmark populations.
- One number to stand on. Three download-to-paid medians appear across this package: 2.1% (freemium-only, day 35, https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/), 2.6% (funnel-implied, the multiplication above), and 2.9% (the blended all-model day-35 median from https://www.revenuecat.com/state-of-subscription-apps, used in channel-plan.md's paid-UA arithmetic). They measure overlapping but different populations. The model stands on the freemium-only 2.1%, because Rep Today is freemium; the other two appear only as a directional cross-check and a paid-UA sanity bound.
- Revenue per payer, year 1: $35.64, the category median year-1 realized LTV per payer (https://www.revenuecat.com/state-of-subscription-apps).
- Prices as planned: ~$7.99/mo and ~$59.99/yr with a 14-day trial (product-facts-brief.md). The $59.99 annual sits above the $39.94 category median annual while $7.99 sits below the $9.99 dominant monthly, and the fetched 68% annual plan mix means the annual offer carries most revenue weight (https://www.revenuecat.com/state-of-subscription-apps). [ASSUMPTION] The $35.64 benchmark is used unadjusted despite Rep Today's higher annual price, because churn and mix effects on realized LTV are unknowable pre-launch; this could bias the model in either direction.

**Outputs, 12-month gross revenue.**

| Scenario | Installs | Download-to-paid | Payers | Year-1 gross revenue |
| --- | --- | --- | --- | --- |
| Pessimistic | 2,000 | 1.0% | 20 | ~$700 |
| Base (at-benchmark) | 5,000 | 2.1% | 105 | ~$3,700 |
| Optimistic | 20,000 | 4.0% | 800 | ~$28,500 |

Say it plainly: even the optimistic case is under $30K gross in year 1, and the base case is roughly $310 a month.
This is not a year-1 income story under any honest input set.
The first 1,000 downloads should be treated as a retention experiment, not an income stream (category-economics.md, on the fetched 92.6% concentration and falling median revenue per new app, https://adapty.io/blog/health-fitness-app-subscription-benchmarks/).
What the reader is being asked to underwrite is the cost of running that experiment cleanly, which is close to zero dollars and mostly founder time.

**What the model deliberately ignores.**
Apple's commission and the 4.71% category refund rate (https://www.revenuecat.com/state-of-subscription-apps-2025).
Annual-plan churn timing, noting aggregate annual year-1 churn runs around 72% with 35% of annual cancellations in month 1 (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/).
Revenue timing: $35.64 is twelve-month realized LTV per payer, applied here to every payer regardless of acquisition month, so a payer acquired in month 11 is credited with a full year of value; this overstates calendar-year-1 revenue, plausibly by a third or more, and the overstatement makes the already-small numbers look bigger, not smaller.
Word-of-mouth compounding, App Store featuring, the $3,895 reptoday.com domain (https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com), development opportunity cost, and any year-2 effects.
The model is a sanity check on magnitude, not a forecast.

## 5. Kill criteria - the centerpiece

Here is what would have to be true, what we would expect to see in the first 90 days post-launch, and the observation that should make you walk away.
Kill thresholds are checked on cohorts at least four weeks after launch and after at least one fix iteration, so a bad first week does not trigger a false kill.
PRD targets referenced below: onboarding-to-first-session 60% by month 3, D7 20%, D30 10%, Weekly Active Exercisers 35% of installs, free-to-paid 4%.

Two instrument rules apply to every criterion below, because at the channel plan's forecast volumes a single weekly cohort separates the expected band from the kill threshold by one to three users, which is noise.
Minimum cohort rule: no rate criterion (K1-K4, K6, K7; K5 counts installs directly) is judged on fewer than 200 users [ASSUMPTION: no external standard exists for this; 200 is a judgment call that widens the expected-band-to-kill-line margin from one to three users to several, and it is not a power calculation]. Weekly cohorts are pooled across consecutive weeks until the floor is met.
Fixed evaluation dates: the pooled reads happen at the week-8 and week-12 reviews already scheduled in the channel plan, not at dates of the founder's choosing.
The honest statistical caveat: even pooled, these samples carry wide confidence intervals, and if 90 days of volume cannot fill the pools, the review's verdict is "insufficient data", which extends the experiment rather than passing it.

| # | Metric | Expected band (90 days) | Kill threshold | Why this threshold |
| --- | --- | --- | --- | --- |
| K1 | Onboarding-to-first-session completion | 45-60% | Below 35% after two fix iterations | The PRD target is 60% by month 3, and the entire positioning is that starting is instant. [ASSUMPTION] No public category benchmark for this metric was fetched, so the threshold is set at roughly half the PRD's own target: if fewer than about a third of installers complete one session in a product whose sole claim is effortless starting, the wedge premise is false, not just untuned. |
| K2 | D7 return rate | 12-20% | At or below 10%, the top of the category median band, on pooled cohorts at both the week-8 and week-12 reviews | The PRD target is 20%; fetched category medians are D7 8.5-10% (https://sendbird.com/blog/app-retention-benchmarks-broken-down-by-industry, https://uxcam.com/blog/mobile-app-retention-benchmarks/). The thesis requires beating these medians materially, so the kill line sits at the median band itself, not below it: a friction-free, forgiveness-first product retaining at category median means the design does not change behavior, which is bet (b) failing, not survival. |
| K3 | D30 return rate | 6-12% | At or below 5%, the top of the category median band, on pooled cohorts at month 2+ | The PRD target is 10%; the fetched median band is 3-5% and the 75th-percentile band is 8-12% (https://uxcam.com/blog/mobile-app-retention-benchmarks/). At-median D30 means the discipline mechanic is not landing (category-economics.md draws exactly this line), and bet (b) requires beating the median, not touching it. |
| K4 | Week-4 Weekly Active Exercisers share of installs | 15-35% [ASSUMPTION: band anchored on the PRD's 35% target with room below, since no external WAE benchmark exists] | Below 10% at week 8 | WAE is the PRD's own definition of the product working: people who actually exercise weekly, not people who open the app. At under 10%, fewer than a third of the PRD's target share shows up weekly, and the habit product has no habit. |
| K5 | Organic installs per week | Launch spike, then a steady state near the base case's ~90/week that holds or grows | Rolling 4-week average below 90/week at the fixed week-8 and week-12 reviews (launch-spike week excluded), after at least one ASO metadata iteration and one launch post | With zero ad budget, organic discovery is the only engine, and the market concentrates 92.6% of revenue in the top 10% of apps (https://adapty.io/blog/health-fitness-app-subscription-benchmarks/). [ASSUMPTION] The 90/week floor is set at the steady-state run rate the section 4 base case actually requires; a 50/week floor would sustain only ~2,600 installs/year, letting the app pass K5 all year while the base case is already dead. The rolling 4-week average, read on fixed dates, means a single uptick week cannot reset the clock. This kills bet (c). |
| K6 | Trial starts as share of installs | 3-7% | Below 1.5% after one paywall placement iteration | The fetched category median download-to-trial is 6.9% (https://www.revenuecat.com/state-of-subscription-apps). At under a quarter of median, premium depth is either invisible or unwanted, and the free tier is cannibalizing rather than feeding conversion. |
| K7 | Free-to-paid conversion (day-35 cohort view) | 1.5-3% early, building toward the PRD's 4% | Below 1% at month 3 | The freemium aggregate median is 2.1% at day 35 (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/). Half of median or worse means the monetization bet (d) fails even if retention holds, and the product is a free utility, not a business. |

**K8, the qualitative kill signal: the wedge fails to be perceived.**
Instrument, pre-registered: a written coding rubric drafted and frozen before the first TestFlight session; at least 25 observed first runs, pooled across moderated TestFlight sessions and consented early post-launch recordings; recordings coded against the rubric by a named person who is not the founder [FOUNDER TO FILL: name of the non-founder coder]; plus unprompted one-sentence descriptions from beta users and early reviews.
Expected: first-time users see the ready session, understand nothing is being asked of them, and press Start; when asked to describe the app, they reach for some version of "it's already ready when you open it."
Kill signal, with pre-registered numbers: more than 50% of rubric-coded first runs show users hunting for a workout list, scrolling for a browse screen, or asking where to pick a workout; or fewer than 30% of unprompted descriptions mention the ready-on-open behavior. [ASSUMPTION: both thresholds are founder priors with no external benchmark; the point of pre-registering them is that they are fixed before any data arrives.]
If 25 observed first runs cannot be reached by the 90-day review, K8 is reported as under-sampled, not passed.
Why: the durable claim is the combined stack of instant, offline, question-free, never-paywalled (positioning.md); if that stack is not perceived without explanation, the positioning has failed regardless of what the retention numbers momentarily show, because there is nothing for word of mouth to carry.
A secondary qualitative signal: if early reviews cluster on wanting to customize sessions, the app is acquiring the customizer segment the positioning deliberately gave up (https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212 shows that segment's complaints), which means the channels are reaching the wrong audience.

Any single kill criterion firing is a stop-and-diagnose event.
Two or more firing simultaneously, or K1/K8 firing at all, is the walk-away signal: the core premise, not the execution, is what failed.

The at-median rule, stated separately because it is the likeliest gray-middle outcome: retention sitting at the category median band at the day-90 review counts as bet (b) failing even if no other criterion fires.
Median-ish survival is not a pass; the thesis's stated bar is beating the medians materially, and the instrument is now calibrated to that bar.

Enforcement, because self-graded kill criteria have a base rate problem: the 90-day review will be published publicly, in the same venues as the launch posts, within two weeks of the day-90 mark, and the launch date - which fixes the review's due date - gets recorded in the decisions log on App Store submission day.
A named outside person receives the raw kill-criteria numbers at the week-8 and week-12 reviews and holds the walk-away call against the thresholds as written [FOUNDER TO FILL: name of the outside reviewer].

Provenance note on the retention anchors: the D7/D30 medians behind K2 and K3 come from marketing-blog aggregations - uxcam.com compiles AppsFlyer, Adjust, and data.ai figures without figure-level links, and sendbird.com's 2024 post cites Statista data of unstated vintage (https://uxcam.com/blog/mobile-app-retention-benchmarks/, https://sendbird.com/blog/app-retention-benchmarks-broken-down-by-industry).
Primary fetches from Adjust and Business of Apps failed during research (category-economics.md), so the walk-away lines carry blog-grade provenance until a primary dataset replaces them.

## 6. What the founder should do before spending anything

In order, cheapest falsification first.

1. **Run the moderated TestFlight cohort before any public launch.**
Recruit 20-50 testers, freeze the K8 coding rubric first, then record moderated first-run sessions and measure K1 and K8 directly; K8's 25-run sample pools these sessions with consented early post-launch recordings.
This is the cheapest possible test of the entire wedge: if observed first runs do not show comprehension of "it's already ready," nothing downstream matters, and the fix costs a design iteration instead of a burned launch.
2. **Clear the name.**
Run a USPTO trademark search and create the App Store Connect record to confirm the listing name "Rep Today, Rest Tomorrow" is available; both were explicitly unverified in research (name-collisions.md).
The collision scan was clean, but REP Fitness owns "REP" mindshare in fitness search (https://www.repfitness.com), so clearance is a legal question, not a search-results question.
3. **Do not buy reptoday.com.**
It is a $3,895 investor-held domain (https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com); reptoday.app returned NXDOMAIN, a strong availability signal (https://dns.google/resolve?name=reptoday.app&type=NS), and a pre-revenue app does not need the .com.
4. **Validate ASO keywords with the free Apple Search Ads popularity scores before locking metadata**, exactly as the ASO research recommends, since every volume statement in it is an [ASSUMPTION] (aso-landscape.md).
5. **Read the subreddit rules manually** for r/bodyweightfitness, r/fitness30plus, r/flexibility, and r/getdisciplined before posting anything, because none could be verified in research (creator-landscape.md).
6. **Instrument every kill-criterion metric before launch day**: onboarding funnel events, D7/D30 cohorts, WAE, trial starts, and weekly install counts must be measurable from the first cohort, or the 90-day evaluation in section 5 cannot happen.
7. **Draft the launch post and test the story cold.**
The build-in-public angle (a deterministic, offline, sub-100ms workout engine with no AI on the start path) is aimed at the audience where the demand quote came from (https://hn.algolia.com/api/v1/items/36666806); show the draft to a few engineers who have never heard the pitch and check whether the wedge lands in one read.

Total cash required for all seven: approximately zero beyond the existing $99/yr Apple developer account, and the trademark search is free to perform before any filing decision.

**Founder commitment and sustainability, stated because every channel routes through one person.**
Commitment status: [FOUNDER TO FILL: full-time or nights-and-weekends, and total hours per week across development, support, and GTM].
Runway: [FOUNDER TO FILL: months sustainable at zero app income].
What breaks first if hours drop: the weekly metrics ritual, then fix-iteration speed, in that order, and both feed the kill criteria directly.
A sustained drop below the channel plan's 8-12 GTM hours per week is itself a soft kill signal for bet (c), because no channel in the plan except ASO runs without founder attention.

## 7. Verdict

Written as the skeptical investor's summary, because that is the correct posture.
The differentiation is real and verifiable: no researched competitor combines ready-on-open, non-streak forgiveness, and an ungated free tier, and the complaint evidence behind two of the three wedge claims is in-category and quotable.
But the market context is the worst part of the story: revenue concentration of 92.6% in the top decile, median new-app revenue falling 22% year over year (https://adapty.io/blog/health-fitness-app-subscription-benchmarks/), a freemium model that converts at 2.1% against the hard paywall's 10.7% (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/), a free wedge that Nike neutralizes at infinite budget, and an honest revenue model that tops out under $30K gross in the optimistic year-1 case.
There is no demand proof yet, only demand evidence, and the difference is the whole company.
What makes this fundable as an experiment rather than dismissible as a hobby is that it is cheap, instrumented, and self-terminating: the kill criteria are concrete, the falsification tests cost near zero, and the founder has committed in writing to the observations that should end it.
The rational position is to underwrite 90 days of data, not a business: if K1 through K8 survive the first quarter with the retention numbers above category median, there is something real here, and what a check would then buy is specific - an Android build to reach the majority of the ICP the iOS-only launch concedes (section 3), full-time founder focus in place of spare hours, and creator partnerships with real budget.
What a check would not buy is paid acquisition: the channel plan's own arithmetic puts cold-traffic CAC at $50-$190 per payer against a $35.64 year-1 LTV, so this business as modeled cannot absorb ad money, and it says so.
If the criteria do not survive, the thesis says to walk away, and it means it.
