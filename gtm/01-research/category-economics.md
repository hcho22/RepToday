# Category Economics: Consumer Subscription Fitness Apps (Sourced Benchmarks)

Research date: 2026-07-14 (fetches 2026-07-15 UTC).
Every number below comes from a page fetched live during this run; the fetching URL is inline.
Where public data was thin or unreachable, the gap is stated instead of guessed.

## TL;DR

Health & fitness is the best-monetizing subscription app category per install, but the funnel is brutal: roughly 7% of downloads start a trial, ~38-40% of trials convert to paid, and category-median D30 retention sits in the low single digits.
Plan mix is dominated by annual subscriptions (~67-68%), the dominant monthly price is $9.99, and the median annual price is $39.94 (RevenueCat 2026 cohort).
The top 10% of health & fitness apps capture 92.6% of category revenue, and median revenue per newly launched subscription app fell 22% year over year (Adapty 2026 dataset).
No fitness-specific primary CAC source was fetchable this run; only secondary CPI ranges of roughly $1.50-$5.50 per install exist publicly.
For a zero-budget solo launch, paid UA math is irrelevant and the leverage is entirely in D1 retention and organic install volume.

## 1. Retention benchmarks (D1/D7/D30)

RevenueCat's State of Subscription Apps 2025 landing page shows health & fitness monetization retention data mostly in charts, with exact D1/D7/D30 figures locked inside the full 263-page PDF, which was not fetched this run (https://www.revenuecat.com/state-of-subscription-apps-2025).
UXCam's 2026 benchmark roundup (compiled from AppsFlyer State of App Marketing 2025, Adjust Mobile App Trends 2026, and data.ai State of Mobile 2026, per the page) lists health & fitness medians of D1 25%, D7 10%, D30 5%, with "strong performer" (75th percentile) ranges of D1 35-45%, D7 15-22%, D30 8-12% (https://uxcam.com/blog/mobile-app-retention-benchmarks/).
Sendbird's benchmark article (published 2024-03-12) cites Statista figures for health & fitness of D1 20.2%, D7 8.5%, D30 4%, and an AppsFlyer D30 figure of 2.78% (https://sendbird.com/blog/app-retention-benchmarks-broken-down-by-industry).
Takeaway: the fetched sources agree on the shape - D1 around 20-25%, D7 around 8-10%, D30 around 3-5% at the median, meaning 95%+ of installs are gone within a month for a typical app.
Gap: Adjust's own health & fitness retention post returned HTTP 429 on three attempts this run, and businessofapps.com returned HTTP 403, so their first-party numbers could not be verified and are excluded.

## 2. Free-to-paid and trial conversion

RevenueCat State of Subscription Apps 2026 landing page (cohort: 115,000+ apps, ~$16B in tracked subscription revenue), health & fitness category: download-to-trial 6.9% median (top quartile above 23%), trial-to-paid 37.7% median (top quartile above 51.4%), and download-to-paid at day 35 of 2.9% median (https://www.revenuecat.com/state-of-subscription-apps).
The prior-year 2025 report page showed a health & fitness median trial-to-paid of 39.9% with a P90 of 68.3% (https://www.revenuecat.com/state-of-subscription-apps-2025).
Adapty's health & fitness benchmarks page (from its State of In-App Subscriptions 2026 dataset: $3B revenue, 16,000+ apps) reports for weekly-plan subscriptions a 9.5% global install-to-trial rate (14.5% in North America) and 42.2% trial-to-paid (https://adapty.io/blog/health-fitness-app-subscription-benchmarks/).
Monetization model matters enormously: RevenueCat's 2026 trends post reports (all categories, not fitness-specific) a median day-35 conversion of 10.7% for hard-paywall apps versus 2.1% for freemium apps, and day-60 revenue per install of $3.09 versus $0.38 (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/).
Trial length also matters: the same 2026 post shows 3-day trials converting at a 25.5% median versus 42.5% for 17-32 day trials (aggregate, not fitness-specific).

## 3. Pricing and annual-vs-monthly mix

RevenueCat 2026 (health & fitness): dominant monthly price $9.99, median annual price $39.94, and a plan-duration mix of 68% annual, 24% monthly, 4% weekly (https://www.revenuecat.com/state-of-subscription-apps).
The 2025 report page similarly showed 67% yearly subscriptions and noted over 80% of trials last 5-9 days or more (https://www.revenuecat.com/state-of-subscription-apps-2025).
RevenueCat 2026 adds that 54% of health & fitness apps use 5-9 day trials and only 18.3% use a no-trial strategy, the lowest of any category.
Adapty reports annual plans grew from 51% of health & fitness revenue in 2023 to 61% in 2025, and calls it the only App Store category where annual keeps gaining share (https://adapty.io/blog/health-fitness-app-subscription-benchmarks/).
Monetization ceiling: RevenueCat 2026 shows health & fitness median revenue per install of $0.48 at day 14 (highest of all categories) and $0.66 at day 60, with median year-1 realized LTV per payer of $35.64 (top quartile above $69.19).
Adapty's dataset puts 12-month LTV per install at $1.21, also the highest among categories it tracks.

## 4. CAC for paid UA in fitness

No fitness-specific primary CAC source (an ad network or MMP publishing its own fitness CAC data on a fetchable page) was found this run; Business of Apps' benchmark pages returned HTTP 403 and Liftoff report pages were not reachable as fetchable primary data.
The best fetchable page is Airbridge's fitness-UA article, which is a secondary aggregation: it cites CPI ranges of $2.00-$5.50 (Facebook), $1.50-$4.50 (Google), $1.75-$4.00 (TikTok) attributed to Udonis, a $4.06 median US Apple Search Ads CPI attributed to AppTweak, and a "healthy blended cost per trial" of $20-$40 attributed to a Shamanth Rao analysis, while explicitly arguing that no universal cost-per-subscription benchmark is meaningful (https://www.airbridge.io/blog/cost-per-trial-cost-per-subscription-subscription-app-ua-metrics-fitness-app).
Treat these as directional only; a citable public primary number for fitness CAC was not found, and that gap should be stated in any downstream plan rather than papered over.
[ASSUMPTION] Combining the secondary CPI range ($1.50-$5.50) with RevenueCat's 2.9% median download-to-paid implies roughly $50-$190 per paying subscriber from cold paid traffic; this is arithmetic on two fetched numbers, not a published figure.

## 5. Churn and renewal

RevenueCat's 2026 trends post reports aggregate (all-category) annual-plan year-1 churn of roughly 72%, with 35% of all annual cancellations happening in month 1 (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/).
Adapty reports a 67.7% first renewal rate for health & fitness weekly subscriptions that started with a trial (https://adapty.io/blog/health-fitness-app-subscription-benchmarks/).
RevenueCat's 2025 page listed a 4.71% refund rate for health & fitness, among the highest categories (https://www.revenuecat.com/state-of-subscription-apps-2025).
Gap: a public health-&-fitness-specific monthly-plan renewal curve (month 1/3/12 subscriber retention) exists only inside the full RevenueCat PDF report, which was not fetched; no fetched page this run published those exact category numbers.

## 6. Market structure warnings

Adapty: the top 10% of health & fitness apps capture 92.6% of all category revenue; 31% more subscription apps launched in 2025 than 2024 while median revenue per new app dropped 22% (https://adapty.io/blog/health-fitness-app-subscription-benchmarks/).
RevenueCat's 2026 trends post adds that AI-branded apps show 36% worse 12-month retention than non-AI apps despite 41% higher year-1 LTV, a caution against leading marketing with "AI" (https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/).

## What these benchmarks imply for a zero-budget solo launch

Paid UA is not just unaffordable, it is structurally unattractive at Rep Today's price point.
[ASSUMPTION] At the implied $50-$190 cost per paying subscriber (see section 4) against ~$7.99/mo with a 4.71%-refund, high-churn category, payback would require many renewal cycles; a zero-budget launch loses nothing real by skipping paid UA.
Organic funnel math sets expectations: [ASSUMPTION] applying RevenueCat 2026 medians (6.9% download-to-trial x 37.7% trial-to-paid), 1,000 organic downloads yields roughly 26 paying subscribers, or about $200/month before churn, refunds, and Apple's cut.
Rep Today's ungated free tier is a freemium strategy, and freemium converts far worse at day 35 (2.1% vs 10.7% aggregate median); the model only pays off if the free core loop drives above-median retention and word of mouth, so revenue expectations for the first months should be near zero.
D1 retention is the single highest-leverage metric: category median D1 is 20-25%, and Rep Today's open-to-a-ready-session design attacks exactly the moment where 75-80% of installs are lost.
[ASSUMPTION] Beating D30 of 8-12% (the fetched 75th-percentile band) is a realistic "product works" bar for a retention-first app; category-median 3-5% D30 would mean the discipline mechanic is not landing.
Rep Today's planned 14-day trial is longer than the category norm (54% use 5-9 days), and fetched aggregate data shows longer trials convert better (42.5% for 17-32 day trials vs 25.5% for 3-day), so the longer trial is defensible.
Rep Today's ~$59.99/yr sits above the fetched $39.94 category median annual price while ~$7.99/mo sits below the dominant $9.99 monthly price; given the 68% annual mix, the annual offer will carry most revenue weight and deserves the positioning attention.
Given 92.6% revenue concentration and falling median revenue per new app, the first 1,000 downloads should be treated as a retention experiment, not an income stream.

## Sources

All fetched live with WebFetch during this run; timestamps UTC, minute precision.

- https://www.revenuecat.com/state-of-subscription-apps-2025 - fetched 2026-07-15T04:19Z; State of Subscription Apps 2025 landing page: H&F trial-to-paid 39.9% median / 68.3% P90, D14 ARPU $0.44, D60 $0.63, 67% yearly plans, 4.71% refund rate, month-1 realized LTV per payer $16.44 median.
- https://www.revenuecat.com/state-of-subscription-apps - fetched 2026-07-15T04:22Z; State of Subscription Apps 2026 landing page (115k+ apps, ~$16B): H&F download-to-trial 6.9%, trial-to-paid 37.7%, download-to-paid D35 2.9%, $9.99 dominant monthly / $39.94 median annual, 68/24/4 annual/monthly/weekly mix, D14 RPI $0.48, year-1 RLTV per payer $35.64.
- https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026/ - fetched 2026-07-15T04:19Z; aggregate 2026 benchmarks: hard paywall 10.7% vs freemium 2.1% D35 conversion, D60 RPI $3.09 vs $0.38, annual year-1 churn ~72%, trial-length conversion spread, AI-app retention penalty.
- https://uxcam.com/blog/mobile-app-retention-benchmarks/ - fetched 2026-07-15T04:20Z; 2026 compilation (attributes AppsFlyer 2025, Adjust 2026, data.ai 2026): H&F retention medians D1 25% / D7 10% / D30 5% and 75th-percentile bands.
- https://sendbird.com/blog/app-retention-benchmarks-broken-down-by-industry - fetched 2026-07-15T04:23Z; 2024 article citing Statista (H&F D1 20.2%, D7 8.5%, D30 4%) and AppsFlyer (D30 2.78%).
- https://adapty.io/blog/health-fitness-app-subscription-benchmarks/ - fetched 2026-07-15T04:21Z; Adapty State of In-App Subscriptions 2026 dataset ($3B, 16k+ apps): install-to-trial 9.5%, weekly trial-to-paid 42.2%, first renewal 67.7%, annual revenue share 61% (2025), install LTV $1.21, top-10% apps capture 92.6% of revenue, median new-app revenue down 22%.
- https://www.airbridge.io/blog/cost-per-trial-cost-per-subscription-subscription-app-ua-metrics-fitness-app - fetched 2026-07-15T04:21Z; secondary aggregation of UA costs: CPI ranges $1.50-$5.50 by channel (attributed to Udonis), $4.06 US ASA median (AppTweak), $20-$40 healthy blended cost per trial (Shamanth Rao).

Failed fetches (claims from these excluded): businessofapps.com (HTTP 403), rocketshiphq.com (HTTP 403), adjust.com blog posts (HTTP 429 on three attempts), appsflyer.com/infograms/app-retention-benchmarks/ (page contained no benchmark data, only a link to an interactive tool).
