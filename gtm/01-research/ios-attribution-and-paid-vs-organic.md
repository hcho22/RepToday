# iOS attribution and the paid-vs-organic verdict (R1)

Research date: 2026-08-01.
Scope: current state of iOS app-install ad attribution and what it implies for RepToday, a pre-launch iOS app with zero users, zero budget, and no App Store listing yet.
Method note: every cited claim was retrieved live on 2026-08-01 via WebFetch or WebSearch.
Two facebook.com Business Help Center pages block direct fetching (JavaScript-only rendering); their quoted content was retrieved through WebSearch result excerpts on 2026-08-01 and is marked "via search excerpt" below.

## 1. App Tracking Transparency (ATT): what it requires

Since iOS 14.5, apps must use the AppTrackingTransparency framework to get explicit user permission before tracking users across other companies' apps and websites or accessing the device advertising identifier (IDFA).
Source: Apple, User Privacy and Data Use (fetched 2026-08-01): https://developer.apple.com/app-store/user-privacy-and-data-use/

Apple's definition of tracking includes "sharing a list of emails, advertising IDs, or other IDs with a third-party advertising network" and placing a third-party SDK that combines your app's user data with other developers' apps for ad targeting.
That definition covers the normal mechanics of running Meta app-install ads with user-level measurement.
Source: same Apple page (fetched 2026-08-01).

If the user denies the prompt, "the device's advertising identifier value will be all zeros and you may not track them."
Apps may not gate functionality on consent, incentivize tracking, or fingerprint devices; Apple states such apps "may be rejected from the App Store."
Source: same Apple page (fetched 2026-08-01).

Opt-in reality: AppsFlyer reported in April 2024 that globally about 50% of users of apps that show the prompt now opt in to tracking, with the US at 44% and the UK at 46% (Q1 2024 data), and that 68% of non-gaming app developers show the ATT prompt at all.
Source: AppsFlyer newsroom, ATT data findings (fetched 2026-08-01): https://www.appsflyer.com/company/newsroom/pr/att-data-findings/
Caveat: this is a vendor panel, opt-in rates vary widely by vertical and country, and an Adjust 2025 benchmark page that reports materially lower global figures could not be fetched (HTTP 429), so no 2025-2026 number is cited here.
[ASSUMPTION] For a small US fitness app, planning on roughly a one-third to one-half opt-in rate among prompted users is a reasonable band, reasoning from the cited Q1 2024 US figure of 44% plus known cross-vertical variance; treat it as a planning band, not a measured fact.

## 2. SKAdNetwork / AdAttributionKit: what advertisers actually get back

AdAttributionKit is Apple's current privacy-preserving attribution framework, the successor built on SKAdNetwork's model, and it explicitly does not require the ATT prompt: "you don't need to use the AppTrackingTransparency prompt," and deriving data to uniquely identify a device is prohibited.
Source: Apple, Ad Attribution overview for developers (fetched 2026-08-01): https://developer.apple.com/app-store/ad-attribution/

What a winning postback contains: the advertised item ID, conversion type (including whether the install was a redownload), a conditional publisher item ID, a source identifier carrying limited campaign information, and conversion values supporting "up to 64 signals of user value" configured by the advertiser.
Source: same Apple developer page (fetched 2026-08-01).

Postbacks arrive 24-48 hours after install or re-engagement, with a 30-day click-through attribution window, a 24-hour view-through window, and up to three postbacks per user on iOS 18+ as conversion values update across windows.
Source: same Apple developer page (fetched 2026-08-01).

Crowd anonymity is the core privacy mechanism: "conversion-value and source-app-id are conditional values that are only included ... when certain thresholds are met," and Apple's real-time crowd anonymity check determines the postback data tier.
In plain terms: at low install volumes the advertiser receives postbacks with the most valuable fields stripped out.
Source: same Apple developer page (fetched 2026-08-01).

Apple's advertiser-facing help states the same two safeguards from the buying side: "Crowd anonymity sends less data in the postback when there are fewer conversions," and a deliberate time delay between conversion and postback reduces "the ability to tie a specific postback to a device or user."
Attribution is last-click across ads.
Source: Apple Ads Help, AdAttributionKit (fetched 2026-08-01): https://ads.apple.com/app-store/help/attribution/0093-adattributionkit-to-measure-performance

Net effect (inference, from the cited mechanics): there is no user-level attribution on iOS without opt-in on both sides of the funnel; small advertisers live entirely inside aggregated, delayed, threshold-gated postbacks, and the smaller the campaign, the less data each postback carries.

## 3. Meta app-promotion campaigns for iOS post-ATT

Meta's own iOS 14.5+ documentation states the SKAdNetwork API "will not report real-time data to Meta, and may be delayed as little as 24 hours and up to 60 days," and reports results "aggregated at the campaign level," with statistical modeling used to fill in ad-set and ad-level views.
Source: Meta Business Help Center (via search excerpt, retrieved 2026-08-01): https://www.facebook.com/business/help/331612538028890

Meta caps iOS 14.5+ app-install structure: up to 9 campaigns per app and up to 5 ad sets per campaign, all ad sets in a campaign locked to one optimization type, and each ad set optimizing for only one of 8 prioritized conversion events.
Source: Meta Business Help Center (via search excerpt, retrieved 2026-08-01): https://www.facebook.com/business/help/651033805513936

Advantage+ app campaigns are Meta's current default app-buying product: "Advantage+ app campaigns use Meta AI to optimize your bidding, audiences and placements," support up to 50 creatives, and Meta recommends integration with the Meta SDK or a mobile measurement partner for conversion data.
Meta's own stated performance claim is modest: "Advertisers who used Advantage+ app campaigns saw 7% improvement in cost per action, on average."
Source: Meta for Business, Advantage+ app campaigns (fetched 2026-08-01): https://www.facebook.com/business/ads/meta-advantage-plus/app-campaigns

Meta documents no absolute minimum budget, but its delivery system has a de facto floor: an ad set becomes "learning limited" when it is unlikely to receive about 50 optimization events in the week after the last significant edit, and low budget is listed as a cause.
Meta's recommended fixes are raising budget, raising bid or cost control, or optimizing for a more frequent event.
Source: Meta Business Help Center, About learning limited (via search excerpt, retrieved 2026-08-01): https://en-gb.facebook.com/business/help/269269737396981

Inference from the two cited mechanics together: to get statistically usable install signal from Meta on iOS you need roughly 50 optimization events per ad set per week just to exit learning, AND enough conversion volume to clear Apple's crowd anonymity tiers, AND tolerance for postbacks delayed 24 hours to 60 days.
[ASSUMPTION] At plausible fitness-app install costs, that implies at minimum hundreds of dollars per week per ad set before the measurement system produces anything trustworthy; this is an estimate derived from the cited 50-events threshold multiplied by any realistic cost per install, since neither Meta nor Apple publishes a CPI figure that can be cited here.

## 4. Apple Ads (Apple Search Ads) economics at small budgets

Apple Ads Advanced is cost-per-tap: "With cost-per-tap (CPT) pricing, you only pay when a customer engages with your ad," and "There's no minimum spend, and you can invest as much or as little as you want."
New advertisers get a 100 USD starter credit.
Source: Apple Ads Advanced overview (fetched 2026-08-01): https://ads.apple.com/en/app-store/advanced

So Apple Ads is the friendliest paid channel at tiny budgets: no minimum, daily budget caps, pay per tap.
But it has a hard gate for RepToday today: Apple's own campaign setup checklist requires you to "Have an app live on the App Store" before creating a campaign.
Source: Apple Ads Help, Create Campaigns (fetched 2026-08-01): https://ads.apple.com/app-store/help/campaigns/0005-create-campaigns

Apple's advertising policies additionally condition eligibility on App Store guideline and policy compliance.
Source: Apple Advertising Policies (fetched 2026-08-01): https://ads.apple.com/policies

## 5. Verdict: where does the first signal come from?

Verdict: for RepToday right now, organic short-form plus a waitlist is not just better than paid social for first signal; paid app-install advertising is structurally unavailable, and the nearest paid substitute would produce worse signal per dollar than organic produces per hour.
Committing clearly: run zero paid spend pre-launch; build first signal from organic short-form content and a first-party waitlist.

The reasoning, leg by leg, with fact and inference separated:

Fact: Apple Ads requires an app live on the App Store before a campaign can be created (cited in section 4).
Fact: Meta's app-promotion product is built around a registered app with the Meta SDK or an MMP integrated and conversion events flowing (cited in section 3).
Inference: with no App Store listing, RepToday literally cannot run an app-install campaign on either platform today, so "paid vs organic for first signal" is not a choice between two live options; the only paid option pre-launch is web-objective ads pointed at a landing page.

Fact: even when install ads become possible at launch, iOS measurement is aggregated, delayed 24 hours to 60 days, campaign-level, and partly modeled (Meta, cited), and Apple strips conversion values and source app IDs from postbacks below crowd anonymity thresholds (Apple, cited).
Fact: Meta's delivery system flags ad sets as learning limited below roughly 50 optimization events per week, with low budget as a listed cause (cited).
Inference: a zero-to-tiny budget sits exactly in the regime where both systems are designed to return the least information; the first few hundred dollars of iOS app-install spend buys noise, not signal.

Fact: ATT consent is required for any user-level cross-app tracking, roughly half of prompted users at best say yes by the most favorable cited panel (AppsFlyer, Q1 2024), and Apple forbids incentivizing consent (cited in section 1).
Inference: small-budget paid social cannot even fall back to user-level measurement to compensate for thin SKAdNetwork data.

Inference (the organic leg): organic short-form plus a waitlist inverts every one of these constraints.
Distribution costs time instead of money, so zero budget is not a handicap.
Measurement is first-party and web-side: a waitlist landing page with email capture involves no IDFA, no ATT prompt, no SKAdNetwork, and no crowd anonymity threshold, so every visit, source, and signup is observable directly and immediately.
The signal quality is also richer for a pre-launch product: comments, saves, shares, and completion behavior on short-form content test whether the discipline-first, no-streaks, opens-to-a-ready-session message resonates, which is message-market fit evidence that an install postback could never carry.
And the waitlist compounds: emails collected now are a launch-day install channel that no attribution framework can degrade.

Inference (what paid is for, later): paid social and Apple Ads become useful after launch as a scaling and price-discovery tool once organic has found a message worth amplifying, once the listing exists, and once budgets are large enough to clear learning phase and crowd anonymity tiers.
Apple Ads, with its no-minimum cost-per-tap model and 100 USD credit (cited), is the natural first paid experiment at that point, not Meta.

## Sources fetched

All fetched 2026-08-01, approximate times US Pacific, morning session.

1. https://developer.apple.com/app-store/user-privacy-and-data-use/ (WebFetch, 2026-08-01 ~09:05)
2. https://developer.apple.com/app-store/ad-attribution/ (WebFetch, 2026-08-01 ~09:20)
3. https://ads.apple.com/app-store/help/attribution/0093-adattributionkit-to-measure-performance (WebFetch, 2026-08-01 ~09:15)
4. https://ads.apple.com/en/app-store/advanced (WebFetch, 2026-08-01 ~09:25)
5. https://ads.apple.com/app-store/help/campaigns/0005-create-campaigns (WebFetch, 2026-08-01 ~09:40)
6. https://ads.apple.com/policies (WebFetch, 2026-08-01 ~09:35)
7. https://www.appsflyer.com/company/newsroom/pr/att-data-findings/ (WebFetch, 2026-08-01 ~09:25)
8. https://www.facebook.com/business/ads/meta-advantage-plus/app-campaigns (WebFetch, 2026-08-01 ~09:45)
9. https://www.facebook.com/business/help/331612538028890 (WebSearch excerpt, 2026-08-01 ~09:10; direct fetch blocked by JS-only rendering)
10. https://www.facebook.com/business/help/651033805513936 (WebSearch excerpt, 2026-08-01 ~09:10; direct fetch blocked by JS-only rendering)
11. https://en-gb.facebook.com/business/help/269269737396981 (WebSearch excerpt, 2026-08-01 ~09:15; direct fetch blocked by JS-only rendering)
