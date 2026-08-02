# R5 - "Creative carries the targeting": what primary sources actually document

Research date: 2026-08-01.
All quotes below come from pages fetched live on 2026-08-01; the full URL list with timestamps is in "Sources fetched" at the end.
Scope: verify the v2 strategy assumption that modern AI-driven ad delivery (Meta Advantage+, TikTok Smart+, Google App campaigns) reads the creative and the destination to decide who sees an ad, demoting manual interest targeting.

## 1. What the primary sources actually say

### Meta: delivery reads ad content plus behavioral signals; Advantage+ automates audience creation

Meta's own explainer on machine-learning ad delivery ("Good Questions, Real Answers", Meta for Business) states that the delivery models consider the creative itself, not only the advertiser's audience settings: "Our models consider that person's behavior on and off Facebook, as well as other factors, such as the content of the ad, the time of day, and interactions between people and ads."
The same page confirms the advertiser-chosen audience still exists as an input: "Advertisers choose their target audience through our self-service tools."
It also documents a creative quality layer: "To generate an ad's quality score, our machine learning models consider the feedback of people viewing or hiding the ad, as well as assessments of low-quality attributes (like too much text in the ad's image, sensationalized language or engagement bait)."
URL: https://www.facebook.com/business/news/good-questions-real-answers-how-does-facebook-use-machine-learning-to-deliver-ads

Meta's 2022 Advantage+ shopping launch announcement documents that audience selection is automated away from manual per-segment choices: "Advantage audience creates a personalized audience based on your Page details and automatically adjusts over time to help you reach more relevant people."
It also documents creative-level personalization: "Advantage+ creative automatically adjusts ad creative for each person who views your ad," and that the product "eliminates the manual steps of ad creation and automates up to 150 creative combinations at once."
URL: https://about.fb.com/news/2022/08/introducing-new-automation-tools-to-increase-sales-and-drive-growth/

Meta's Andromeda engineering post (Dec 2024) describes the retrieval engine behind Advantage+ automation.
It says Advantage+ automation spans "audience creation, optimal budget allocation, dynamic placement across Meta surfaces, and creative generation," and includes "predictive targeting."
It describes the model learning from "people and ads data" and reconstructing "latent user-ad interaction signals on-the-fly" to capture "Complex latent relationships between people's interests, products, and services."
It also anticipates a creative explosion, noting "the number of ads creatives in Meta's recommendation systems is expected to grow significantly" and that retrieval selects "from tens of millions of ad candidates into a few thousand relevant ad candidates."
Net: at the infrastructure level, matching is learned from user-ad interaction data over a very large creative pool, and audience creation is one of the automated functions.
URL: https://engineering.fb.com/2024/12/02/production-engineering/meta-andromeda-advantage-automation-next-gen-personalized-ads-retrieval-engine/

Meta's Advantage product page (marketing copy, thin on mechanism) says the system will "Optimize campaigns in real-time and match ads to the people most likely to take action" and describes applying "AI across your campaign's audience, placement and budget."
URL: https://www.facebook.com/business/ads/meta-advantage

### TikTok: Smart+ takes assets and goals; the system chooses the audience

TikTok's newsroom announcement says Smart+ "automates the performance advertising process across targeting, bidding, and creative to deliver the right ad to the right person."
It states the advertiser's inputs plainly: "Advertisers simply input their assets, budget, and targeting goals," after which Smart+ "automatically creates or selects the best creative asset" and "chooses the right audience."
URL: https://newsroom.tiktok.com/tiktok-is-building-for-the-future-with-smart-plus?lang=en

TikTok's Ads Manager help article confirms the division of labor: advertisers supply "Key Performance Indicators ("KPIs"), creative assets, and target geography and language," while TikTok handles "campaign and audience targeting, optimization, and creative" to "deliver the right ad to the right person as determined by our system."
It also documents creative-led budget behavior: the system will "shift budget towards the highest-performing creative and pause poor performers," with fatigue detection and auto-refresh.
On TikTok, then, creative assets are literally the main advertiser-controlled input to who gets reached, since targeting beyond geography and language is system-determined.
URL: https://ads.tiktok.com/help/article/about-smart-plus-campaign

### Google: App campaigns explicitly read the destination (the store listing)

Google's App campaigns documentation is the clearest primary source for "the destination is an input."
It states: "You don't need to create individual ads for different networks and formats," and "Our system will test different asset combinations using your ad text ideas, images, videos, and assets from your app's store listing."
Advertiser input is minimal: "all you need to do is provide some text, a starting bid and budget, and let us know the languages and locations for your ads," after which "Google Ads will test different ad combinations and serve the best-performing ads" across Search, Google Play, YouTube, Display, and Discover.
So for App campaigns there is no manual interest targeting at all, and the App Store listing is directly consumed as ad material.
URL: https://support.google.com/google-ads/answer/6247380

Google's Quality Score documentation adds a nuance on landing pages for Search: "landing page experience" is defined as "How relevant and useful your landing page is to people who click your ad," but the same page states "Quality Score is not an input in the ad auction" and calls it "a diagnostic tool meant to give you a sense of how well your ad quality compares to other advertisers."
So the fetched Google doc supports "the landing page is evaluated for relevance" as a diagnostic quality component, not as a documented audience-selection mechanism.
URL: https://support.google.com/google-ads/answer/2404197

## 2. What is NOT substantiated by primary sources (honest gaps)

Gap 1: no fetched primary source states that Meta reads landing page content to decide WHO sees an ad.
Meta documents that delivery models consider "the content of the ad" and behavioral signals, and that Advantage audience is built "based on your Page details," but I found no Meta-authored sentence saying the landing page's text or content is parsed for audience selection.
The strategy's phrase "the landing page is targeting infrastructure" is therefore an inference for Meta, supported directly only in Google App campaigns (store listing assets are consumed) and indirectly via post-click conversion signals (pixel events on the landing page feed optimization, per the "Good Questions" post's mention of "things a person does outside of Facebook that businesses share with us via our Business Tools, like visiting a website, purchasing a product or installing an app").

Gap 2: "demoting manual interest targeting" is my paraphrase of direction, not a quoted Meta position.
The primary sources show automation of audience creation (Advantage+ shopping, Smart+, App campaigns run without interest targeting), but the fetched Meta pages do not say manual interest targeting is deprecated or ignored; the "Good Questions" post explicitly keeps advertiser-chosen audiences as an input.

Gap 3: two Meta Business Help Center pages could not be verified.
Fetches of "About Advantage+ Audience" (facebook.com/business/help/273363992030035) and "About Advantage+ Sales Campaigns" (facebook.com/business/help/1362234537597370) returned only page titles with no body content (JS-rendered), so nothing from those pages is cited or claimed here.
Any claim about Advantage+ audience treating selections as "suggestions" that Meta can expand beyond is widely repeated in secondary sources but is NOT cited here because the primary page did not render.

Gap 4: Andromeda is about retrieval infrastructure, not a targeting policy statement.
The engineering post proves Meta invests in matching a huge creative pool to users via learned interaction signals; it does not state that creative content semantically determines audience, and "creative generation" there refers to capacity for many creatives, not a claim that the model reads your video to pick your audience.

Gap 5: platform-reported performance numbers (Meta's "12% lower cost per purchase conversion" for Advantage+ shopping, TikTok's Smart+ ROAS claims) are vendor self-reported and unaudited; treat them as directional marketing claims.

## 3. Practical consequence for RepToday (inference, clearly separated from the sources)

Everything in this section is inference from the documented mechanisms above, not a sourced claim.

Inference 1: the reliable levers RepToday controls are the creative assets and the conversion events, not audience settings.
On TikTok Smart+ the only targeting inputs left are geography and language; on Google App campaigns there is no ad-level targeting at all; on Meta the documented delivery inputs include ad content and pixel/app events.
So the creative matrix should be built as an audience-definition instrument: each concept (for example "no streaks, a forgiving Consistency Score," "opens to a ready session, zero decisions," "5 to 60 minutes, zero equipment, works offline") should be self-selecting for a distinct person, because the delivery system will find the people who respond to that concept.

Inference 2: the landing page and future App Store listing matter mostly through two documented channels, not through semantic audience parsing (for Meta).
Channel one is conversion signals: the events fired on the page (waitlist signup, trial start once live) are the optimization target the systems learn from, so the page must fire clean, distinct events for the action we actually want.
Channel two is Google-specific: App campaigns assemble ads from the store listing itself, so listing copy and screenshots must carry the same discipline-first, no-gamification message as the ads, or Google will build off-message ads for us.
[ASSUMPTION] Message-matched landing pages also improve conversion rate, which improves the signal quality the delivery AI learns from; this is standard practice reasoning, not something the fetched pages state.

Inference 3: since RepToday is pre-launch with zero users, the systems have zero interaction history to learn from, so the creative and the conversion event definition are the ONLY signal we can seed.
That argues for a wide creative matrix (many distinct concepts, not many variants of one concept) at test start, and for resisting the urge to add interest stacks that the documented automation paths either ignore or treat as a starting point.

Inference 4: expect creative-level, not audience-level, learning: TikTok documents shifting budget to winning creatives and pausing losers automatically, so the test readout should be per-concept performance, and fatigued concepts need planned refresh.

## Sources fetched

All fetched live on 2026-08-01, approximately 20:05-20:12 PDT.

- https://www.facebook.com/business/news/good-questions-real-answers-how-does-facebook-use-machine-learning-to-deliver-ads (2026-08-01, ~20:07 PDT)
- https://about.fb.com/news/2022/08/introducing-new-automation-tools-to-increase-sales-and-drive-growth/ (2026-08-01, ~20:10 PDT)
- https://engineering.fb.com/2024/12/02/production-engineering/meta-andromeda-advantage-automation-next-gen-personalized-ads-retrieval-engine/ (2026-08-01, ~20:06 PDT)
- https://www.facebook.com/business/ads/meta-advantage (2026-08-01, ~20:12 PDT)
- https://newsroom.tiktok.com/tiktok-is-building-for-the-future-with-smart-plus?lang=en (2026-08-01, ~20:10 PDT)
- https://ads.tiktok.com/help/article/about-smart-plus-campaign (2026-08-01, ~20:10 PDT)
- https://support.google.com/google-ads/answer/6247380 (2026-08-01, ~20:07 PDT)
- https://support.google.com/google-ads/answer/2404197 (2026-08-01, ~20:12 PDT)

Attempted but NOT citable (fetch returned title only, no body): https://www.facebook.com/business/help/273363992030035 and https://www.facebook.com/business/help/1362234537597370.
