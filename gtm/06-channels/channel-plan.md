# Channel Plan v2 - RepToday

Status: decision document only. Nothing in this file is published, posted, or spent until the founder says go.
Built for: pre-launch iOS app, zero users, zero downloads, zero revenue, no App Store listing yet, solo founder, no audience.
Supersedes `channel-plan-v1.md`; carried-forward items are named in "What changed since v1".

## 1. Channel doctrine

**(a) Creative carries the targeting, so the landing page and listing are targeting infrastructure.**
The current ad-delivery systems take creative and a destination and choose the audience themselves: TikTok Smart+ takes "assets, budget, and targeting goals" and "chooses the right audience" (https://newsroom.tiktok.com/tiktok-is-building-for-the-future-with-smart-plus?lang=en, fetched 2026-08-01), with advertiser targeting limited to geography and language (https://ads.tiktok.com/help/article/about-smart-plus-campaign, fetched 2026-08-01); Google App campaigns build ads directly from "assets from your app's store listing" with no ad-level interest targeting at all (https://support.google.com/google-ads/answer/6247380, fetched 2026-08-01); Meta's delivery models consider "the content of the ad" alongside behavioral signals (https://www.facebook.com/business/news/good-questions-real-answers-how-does-facebook-use-machine-learning-to-deliver-ads, fetched 2026-08-01), and Advantage+ automates audience creation (https://about.fb.com/news/2022/08/introducing-new-automation-tools-to-increase-sales-and-drive-growth/, fetched 2026-08-01).
Honest gap, per the research file: no fetched Meta source says the landing page is parsed for audience selection; for Meta the page matters through the conversion events it fires, which is documented, and the "landing page as targeting" claim is direct only for Google's listing consumption (01-research/creative-carries-targeting-sources.md, section 2).
The practical consequence holds either way: the levers RepToday controls are the creative, the listing, and the events the page fires, so those assets must each carry one self-selecting message.

**(b) The market picks the message, not the founder.**
The observed Meta auction is crowded on time-compression, AI-coach claims, trials, and physique promises, while ready-on-open, friction-deletion, anti-streak forgiveness, and zero-equipment-as-identity appeared unoccupied (01-research/meta-ad-library-sweep.md, Ad Library sweeps fetched 2026-08-01), and the top mined pains are paywall rage, streak grief, and decision fatigue (01-research/pain-point-frequency.md, fetched 2026-08-01).
Those territories and pains seed a variant matrix of distinct concepts, not variants of one founder-picked hero, and the PMF kit at `05-social-pmf/` is the instrument that runs that matrix and reads per-concept results.
Delivery systems shift budget and reach to winning creatives on their own, so per-concept readout is the native unit of learning (https://ads.tiktok.com/help/article/about-smart-plus-campaign, fetched 2026-08-01).

**(c) Continuous cadence, not a launch week.**
TikTok and Shorts rank each video on its own engagement, so every post is an independent experiment and signal accrues per post, not per event (https://newsroom.tiktok.com/en-us/how-tiktok-recommends-videos-for-you, fetched 2026-08-01; https://support.google.com/youtube/answer/11914225, fetched 2026-08-01).
A launch-week spike model would spend the whole matrix in seven days and read noise.
The plan is a steady posting rhythm the founder can sustain for a quarter, with the launch itself as one more beat in the cadence.

## 2. The paid-vs-organic verdict

**Run zero paid spend pre-launch; build first signal from organic short-form content and a first-party waitlist.**

The reasoning, from 01-research/ios-attribution-and-paid-vs-organic.md (all cited pages fetched 2026-08-01):

Structural: install ads cannot run at all today.
Apple Ads requires an app live on the App Store before a campaign can be created (https://ads.apple.com/app-store/help/campaigns/0005-create-campaigns).
Meta's app-promotion product is built around a registered app with the Meta SDK or an MMP integrated (https://www.facebook.com/business/ads/meta-advantage-plus/app-campaigns).
So "paid vs organic" pre-launch is not a choice between two live options; the only paid option is web-objective ads to a landing page.

Signal: tiny budgets are nearly signal-free even after launch.
iOS install measurement is aggregated, delayed 24 hours to 60 days, campaign-level, and partly modeled (https://www.facebook.com/business/help/331612538028890, via search excerpt 2026-08-01), Apple strips conversion values from postbacks below crowd anonymity thresholds (https://developer.apple.com/app-store/ad-attribution/), and Meta flags ad sets learning-limited below roughly 50 optimization events per week (https://en-gb.facebook.com/business/help/269269737396981, via search excerpt 2026-08-01).
ATT opt-in caps user-level fallback at roughly 44% US per the most favorable cited panel (https://www.appsflyer.com/company/newsroom/pr/att-data-findings/).
[ASSUMPTION] At plausible fitness-app install costs that implies hundreds of dollars per week per ad set before measurement produces anything trustworthy, per the reasoning in the attribution file.

Inversion: organic short-form plus a waitlist flips every constraint.
Distribution costs time instead of money, waitlist measurement is first-party and web-side with no IDFA, no ATT, no SKAdNetwork, and comments, saves, and completion behavior carry message-market-fit evidence an install postback never could.
Paid becomes useful after launch as a scaling and price-discovery tool, with Apple Ads (no minimum, cost-per-tap, 100 USD starter credit, https://ads.apple.com/en/app-store/advanced) as the natural first experiment, not Meta.

## 3. Ranking A - founder with $0 and no audience

### A1. Organic short-form: TikTok primary, YouTube Shorts secondary, running the PMF kit matrix

Reasoning: TikTok is the only platform whose official documentation states follower count is not a direct ranking factor (https://newsroom.tiktok.com/en-us/how-tiktok-recommends-videos-for-you, fetched 2026-08-01), and YouTube's Shorts guidance ranks on viewer-choice and watch metrics with subscriber count absent, with 92% of US 30-49 adults on YouTube (https://support.google.com/youtube/answer/11914225 and https://www.pewresearch.org/internet/fact-sheet/social-media/, both fetched 2026-08-01).
That is exactly the property a zero-audience founder needs for honest signal, and the product's core claim is a sub-10-second visual demo nobody in the observed ad field runs (01-research/meta-ad-library-sweep.md).
Reels is deferred because Instagram officially lists follower count as a ranking signal (https://about.instagram.com/blog/announcements/instagram-ranking-explained, fetched 2026-08-01).
Cost: $0 cash; [ASSUMPTION] 4-6 founder-hours/week for batch-recording, captioning, and posting, reasoning from the v1 estimate for the same work.
First-90-days signal: [ASSUMPTION] 20-30 posts per platform, most near-zero views, with the deliverable being a per-concept ranking and 1-3 concepts that clearly outperform the account baseline, plus low-hundreds of waitlist visits once the waitlist exists (pre-publication action #1); reasoning: zero-follower reach is unpredictable and no fetched benchmark exists.
Kill criterion: the single escalation ladder, stated identically here, in investment-thesis.md K0, and in read-the-results.md item 6.
Day 14, the midpoint gate: kill the losing angles and rebuild the concept matrix once from what the midpoint taught.
Week 8, if no angle has cleared its pre-registered floor over readable posts (at least 200 impressions): bet (c) is revised, not failed; the organic-first channel thesis is weakened, rebuilt from Reddit-listening input, and a second 14-day window runs on the rebuilt matrix.
Week 16, if there is still no signal: K0 trips, bet (c) is declared failed, and that is the walk-away observation for the marketing side.
No waitlist-tap quantity enters this criterion until the waitlist exists (pre-publication action #1).

### A2. App Store search / ASO preparation for launch day

Reasoning: ASO is the one channel that compounds unattended after launch, and the research found concrete whitespace: "micro workout" had only two title-ranked apps, both with too few ratings to display a score, while head terms carry 118K-530K ratings at 4.8-4.9 stars (https://itunes.apple.com/search?term=micro+workout&country=US&entity=software&limit=10 and https://apps.apple.com/us/app/home-workout-no-equipments/id1313192037, fetched 2026-07-15, per 01-research/aso-landscape.md).
Pre-launch the work is preparation: listing copy, screenshots, and the keyword field, all carrying the same message the winning short-form concept proves, because Google App campaigns will later assemble ads from the listing itself (https://support.google.com/google-ads/answer/6247380, fetched 2026-08-01).
Ships as researched and decided: title "Rep Today" (the v1 "Rest Tomorrow" suffix was killed by the v2 tournament, D-106), the D-005/D-009 wedge subtitle "Opens to a ready workout", and the amended 99/100-char keyword field `micro,equipment,bodyweight,quick,daily,home,mobility,stretching,minute,hiit,exercise,routine,busy,5`.
Cost: $0; [ASSUMPTION] 4-6 founder-hours once, then monthly iteration post-launch, per the v1 estimate.
First-90-days signal: none until launch by design; at launch, keyword ranks for "micro workout" and "no equipment workout" plus search impressions in App Store Connect; [ASSUMPTION] single-digit daily installs at steady state in the first quarter, per the v1 reasoning that whitespace terms are whitespace partly because volume is low.
Kill criterion: if by 30 days post-launch Apple's own keyword popularity tooling shows the chosen terms at floor popularity and search impressions are effectively zero, rewrite the keyword field around terms users demonstrably type rather than defending the whitespace thesis.

### A3. Reddit: listening channel plus the one sanctioned venue

Reasoning: the ICP-matched subreddits ban promotion outright with fetched rule text: r/fitness30plus says "Do not link them here. You will be banned", r/getdisciplined permanently bans product links and gates posting behind 30 days and 200 karma, r/bodyweightfitness rule 5 is "No advertising" (rules JSON fetched 2026-08-01, per 01-research/platform-signal-evidence.md).
So Reddit is a listening channel for pain language and message testing, and r/SideProject (795,804 subscribers at fetch, stated purpose "sharing and receiving constructive feedback on side projects", https://www.reddit.com/r/SideProject/about.json, fetched 2026-08-01) is the single venue where posting the product is sanctioned.
Reddit over-indexes for the 30-49 band at 35% vs 24% of all adults (https://www.pewresearch.org/internet/fact-sheet/social-media/, fetched 2026-08-01).
Cost: $0; [ASSUMPTION] 1-2 founder-hours/week of reading and note-taking, less than v1's participate-first plan because broadcast is off the table.
First-90-days signal: a running file of verbatim pain quotes feeding the creative matrix, plus one r/SideProject feedback post; [ASSUMPTION] 10-40 comments on that post if it lands, near-zero installs, reasoning from typical feedback-thread scale, not a fetched number.
Kill criterion: if 4 consecutive weeks of listening produce no new usable pain language, cut to a monthly sweep; if the r/SideProject post is removed or draws no substantive feedback, do not repost variants, take the answer.

### A4. Personal network and the waitlist

Reasoning: the waitlist is the measurement spine of the whole plan, because web-side email capture is the one funnel no iOS attribution constraint can degrade, and emails collected now are a launch-day install channel (01-research/ios-attribution-and-paid-vs-organic.md, section 5).
The personal network seeds it honestly: direct asks to people who match the desk-bound 30s-40s profile, identity-framed as "for people who want movement to fit the life they already have", never loss-framed.
Cost: $0 cash plus whatever the landing page already costs; [ASSUMPTION] 1 founder-hour/week.
First-90-days signal: [ASSUMPTION] 30-100 waitlist signups from network plus short-form spillover, with source tagged per signup; reasoning: solo-founder network scale, no benchmark exists.
Kill criterion: if direct personal asks convert below 1 in 5 [ASSUMPTION as a threshold], the pitch is wrong before the market ever sees it; rewrite the one-sentence pitch before spending more asks.

### A5. Creator seeding by honest DM, at zero cost

Reasoning: the v1 research identified three fit creators worth exactly three personal emails: GMB Fitness (370,987 subscribers, no-equipment, busy-adult positioning), Hybrid Calisthenics (4.47M subscribers, shame-free philosophy matching the forgiving Consistency Score, but anti-selling, so free-tier-only framing), and The Bioneer (951,919 subscribers, essay channel, pitched the deterministic-engine story) (sources fetched 2026-07-15, per 01-research/creator-landscape.md and channel-plan-v1.md).
The asks cost the creators nothing: early access, a founder conversation, story material, never a sponsorship.
Cost: $0; [ASSUMPTION] 1-2 founder-hours total plus one follow-up each.
First-90-days signal: reply rate on three emails; [ASSUMPTION] expected replies zero to one, and one genuine mention would outproduce months of other channels, which is why the cheap attempt is justified.
Kill criterion: no reply after one follow-up ends the thread; do not broaden the list into cold-DM spam, because the list was three names precisely because only three fit.

## 4. Ranking B - if $500/mo appeared

**Verdict: mostly do not spend it yet.**
Install ads are structurally unavailable pre-launch (no listing, cited above), and at $500/mo even post-launch the spend sits below Meta's roughly-50-events-per-week learning threshold and Apple's crowd anonymity tiers, buying noise, not signal (01-research/ios-attribution-and-paid-vs-organic.md).
The money's job is to wait.

Re-ranked list:

1. Organic short-form with the PMF kit - unchanged at #1; money does not improve a channel whose constraint is founder time and concept quality.
2. ASO preparation - unchanged at #2, still $0.
3. Launch reserve for Apple Ads: hold roughly $350-400/mo of the budget untouched until the listing is live, then spend it on the app's own brand term and the proven keyword set via cost-per-tap campaigns with no minimum spend plus the 100 USD starter credit (https://ads.apple.com/en/app-store/advanced, fetched 2026-08-01). Tradeoff: the cash sits idle for weeks, but this is the only paid channel where small budgets buy interpretable, intent-matched signal.
4. Creator gift budget: roughly $50-100/mo to upgrade the three honest DMs with a small genuine gesture and to cover better capture gear for the founder's own content. Tradeoff: it slightly blurs the "costs them nothing" purity of A5, so gifts must be disclosed and ask-free.
5. Optional single web-objective smoke test: at most $50-100 once, TikTok or Meta traffic to the waitlist page, only after a short-form concept has already won organically and only to check whether the winning message survives contact with a cold paid audience. Tradeoff: web-objective ads measure clicks to a page, not installs, so this validates message, not economics; skipping it entirely is acceptable.
6. Reddit listening and personal-network waitlist - unchanged, $0 by nature.

What the first $500 should NOT buy: install campaigns (impossible pre-launch), follower or engagement buys (poisons the honest-signal property that made TikTok and Shorts the pick), ASO tools (Apple's free keyword popularity data suffices at this scale), or the reptoday.com domain ($3,895 at HugeDomains buys zero installs, https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com, fetched 2026-07-15).

## 5. What changed since v1

- Added the creative-carries-targeting doctrine (section 1a), grounded in the new primary-source file 01-research/creative-carries-targeting-sources.md; v1 had no doctrine layer.
- Added the dual $0 / $500-per-month ranking; v1 assumed $0 only.
- The PMF kit at `05-social-pmf/` replaces the v1 social-launch-kit thinking as the organic instrument, and short-form video moved from v1's rank 6 to rank 1: v1 ranked it last for lack of evidence on zero-follower reach, and the v2 platform-signal research fetched the platform-official documentation that resolves exactly that unknown. The kit has since landed in `05-social-pmf/` (16 pre-registered angles, 6 A/B hook pairs, a 14-day cadence, and a read-the-results protocol; decisions-log.md D-101), and A1 runs on it.
- Reddit demoted from v1's participate-then-maybe-post plan to listening plus r/SideProject only, because the subreddit rules v1 could not fetch were fetched in v2 and they ban promotion outright.
- Changed by the v2 tournament: the listing title drops the "Rest Tomorrow" suffix to plain "Rep Today" (D-106). Carried forward unchanged: the D-005 wedge subtitle "Opens to a ready workout" reaffirmed by D-009; the amended 99/100-char keyword field (listed in A2); the do-not list (no "AI"-led messaging, no squatted "7 minute workout" chase, no "weight loss" keyword, no reptoday.com purchase).
- Carried forward as launch-window actions outside this continuous-channel ranking: the TestFlight beta cohort and the Show HN / Product Hunt one-shot posts, both still specified in channel-plan-v1.md.

## Sources

Reused from the research files, with fetch dates as recorded there.

Fetched 2026-08-01 (01-research/ios-attribution-and-paid-vs-organic.md):
- https://developer.apple.com/app-store/user-privacy-and-data-use/
- https://developer.apple.com/app-store/ad-attribution/
- https://ads.apple.com/app-store/help/attribution/0093-adattributionkit-to-measure-performance
- https://ads.apple.com/en/app-store/advanced
- https://ads.apple.com/app-store/help/campaigns/0005-create-campaigns
- https://www.appsflyer.com/company/newsroom/pr/att-data-findings/
- https://www.facebook.com/business/ads/meta-advantage-plus/app-campaigns
- https://www.facebook.com/business/help/331612538028890 (via search excerpt)
- https://en-gb.facebook.com/business/help/269269737396981 (via search excerpt)

Fetched 2026-08-01 (01-research/creative-carries-targeting-sources.md):
- https://www.facebook.com/business/news/good-questions-real-answers-how-does-facebook-use-machine-learning-to-deliver-ads
- https://about.fb.com/news/2022/08/introducing-new-automation-tools-to-increase-sales-and-drive-growth/
- https://newsroom.tiktok.com/tiktok-is-building-for-the-future-with-smart-plus?lang=en
- https://ads.tiktok.com/help/article/about-smart-plus-campaign
- https://support.google.com/google-ads/answer/6247380

Fetched 2026-08-01 (01-research/platform-signal-evidence.md):
- https://newsroom.tiktok.com/en-us/how-tiktok-recommends-videos-for-you
- https://about.instagram.com/blog/announcements/instagram-ranking-explained
- https://support.google.com/youtube/answer/11914225
- https://www.pewresearch.org/internet/fact-sheet/social-media/
- https://www.reddit.com/r/fitness30plus/about/rules.json
- https://www.reddit.com/r/getdisciplined/about/rules.json
- https://www.reddit.com/r/bodyweightfitness/about/rules.json
- https://www.reddit.com/r/SideProject/about.json

Fetched 2026-08-01 (01-research/meta-ad-library-sweep.md and 01-research/pain-point-frequency.md): Meta Ad Library search pages and the App Store / HN Algolia pages listed in those files' own source sections.

Fetched 2026-07-15 (v1 research, carried forward per decisions-log.md D-101):
- https://itunes.apple.com/search?term=micro+workout&country=US&entity=software&limit=10
- https://apps.apple.com/us/app/home-workout-no-equipments/id1313192037
- https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com
- Creator pages cited in 01-research/creator-landscape.md (GMB, Hybrid Calisthenics, The Bioneer)
