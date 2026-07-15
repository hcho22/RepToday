# Name Collision and Availability Check

Candidates: **Rep Today** (incumbent), **Cairn**, **Stack**, **FitSnack** (abandoned old name, for the record).
All fetches performed 2026-07-15 between 04:18Z and 04:22Z via live WebFetch.
App Store checks use Apple's public iTunes Search API (US storefront), which reflects live App Store listings.

**Formal trademark clearance is UNVERIFIED for every candidate.**
No USPTO (or any trademark registry) search was performed in this run, and App Store name reservation/clearance in App Store Connect was not and cannot be checked from here.
Both remain the founder's next action before committing to any name.
Nothing below is a clearance claim; it is a collision scan only.

## TL;DR

- **Rep Today**: cleanest of the four. No app named "Rep Today" (or close variant) appeared in a US App Store search for "rep today"; the fitness space is crowded with "Rep Counter"-style tracker names but none use "Today". Main web collision is REP Fitness, a large home gym equipment brand (equipment, not apps). reptoday.com is confirmed for sale at HugeDomains for $3,895; reptoday.app returned NXDOMAIN (strong availability signal); github.com/reptoday returned 404 (available signal).
- **Cairn**: direct App Store collision - "Cairn - Hiking Safety Tracker" is a live Health & Fitness app, the same category Rep Today would launch in. The Cairn outdoor subscription box brand existed and was acquired by Outside in 2021, then rebranded; its current status is unclear from fetched pages. github.com/cairn is taken.
- **Stack**: extremely generic. The exact name "Stack" is a Ketchapp game with 56k+ ratings; "Stack Team App" occupies the Sports category; Stack Sports is a large sports-tech company (50,000+ sports organizations). github.com/stack is a personal account. Weakest candidate on findability and confusion grounds.
- **FitSnack**: the abandoned name is actively colliding - a live App Store fitness app ("Home Workout to Lose Weight" by Stanislau Shvaika) brands itself "FITsnack" and describes "daily micro home workouts", nearly the same concept. The rebrand away from this name looks well justified. fitsnack.com has live nameservers (registered).

## Rep Today (incumbent; listing name "Rep Today, Rest Tomorrow")

**App Store.**
A US App Store search for "rep today" returned 10 apps, none named "Rep Today" or a close variant, and only one Health & Fitness result ("AI Fitness Coach: Basic Fit") ([iTunes Search API, "rep today"](https://itunes.apple.com/search?term=rep+today&entity=software&country=US&limit=15)).
The "Rep" prefix is crowded in fitness trackers: "RepCount - Gym Workout Tracker", "RepCounter Pro", "Rep Counter with rest timer", and "Rep Counter: Workout Tracker" are all live Health & Fitness apps ([iTunes Search API, "rep count"](https://itunes.apple.com/search?term=rep+count&entity=software&country=US&limit=10)).
These are gym-logging tools, not micro-workout generators, and none include "Today", so the full name reads distinct.

**Web.**
REP Fitness (repfitness.com) is a large home gym equipment retailer selling racks, benches, bars, weights, cardio equipment, apparel, and supplements ([repfitness.com](https://www.repfitness.com)).
It is an equipment brand, not an app, but it owns significant "REP" mindshare in fitness search results.

**Domains.**
reptoday.com is listed for sale at HugeDomains with a buy-now price of $3,895 (or $162.29/mo for 24 months at 0%), re-verified live this run ([HugeDomains profile](https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com)).
reptoday.app returned DNS Status 3 (NXDOMAIN, no delegation) via Google Public DNS ([dns.google resolve](https://dns.google/resolve?name=reptoday.app&type=NS)).
NXDOMAIN means the domain is not delegated in DNS, which is a strong but not conclusive signal it is unregistered (a registered-but-undelegated domain is possible); the .app registry RDAP endpoint returned 403 to direct fetch, so registry-level confirmation was not obtained.

**Social handles.**
github.com/reptoday returned HTTP 404, an availability signal ([github.com/reptoday](https://github.com/reptoday)).
X/Twitter and Instagram handle checks are inconclusive from here: both sit behind login/anti-bot walls that prevent unauthenticated verification, so no claim is made either way.

## Cairn

**App Store.**
A US search for "cairn" returned 11 apps including "Cairn - Hiking Safety Tracker" by FITCLIMB COM LLC, which is listed in Health & Fitness, plus "Cairn - Private Journal" (Lifestyle), "Cairn Stone Balancing" (Games), "Cairn-Style & Vibes" (Social), and Cairn University (Education) ([iTunes Search API, "cairn"](https://itunes.apple.com/search?term=cairn&entity=software&country=US&limit=15)).
The hiking safety tracker is a direct same-category collision: a fitness/outdoor app already using the Cairn name in Health & Fitness.

**Web.**
The Cairn outdoor gear subscription box brand existed: a fetched May 2022 review states "In mid-2021 Cairn was acquired by Outside Magazine" and notes "the official switch to a new name: Outside Discovery Collection", with the reviewer unable to determine whether subscriptions still existed ([My Subscription Addiction review](https://www.mysubscriptionaddiction.com/2022/05/cairn-may-2022-review-coupon.html)).
The brand's current status is unclear from fetched pages; a fetch of www.cairn.us returned empty content (inconclusive), and a fuller history article at backpackers.com returned 403.

**Domains and handles.**
cairn.com has live nameservers, i.e. registered ([dns.google resolve](https://dns.google/resolve?name=cairn.com&type=NS)).
github.com/cairn is taken by an active software research studio organization ([github.com/cairn](https://github.com/cairn)).

## Stack

**App Store.**
The exact name "Stack" belongs to a Ketchapp casual game with 56,096 ratings; the same search surfaced "Stack Team App" (Sports category, team communication), "STACK Construction Management", and several other Stack-named games ([iTunes Search API, "stack"](https://itunes.apple.com/search?term=stack&entity=software&country=US&limit=15)).
No Health & Fitness "Stack" appeared in the top results, but the name is saturated across categories, which would make search discoverability very poor.

**Web.**
Stack Sports (stacksports.com) is a large sports technology company powering "over 50,000 sports organizations worldwide" with apps and platforms for leagues, recruiting, and events ([stacksports.com](https://www.stacksports.com)).
stack.com has live nameservers ([dns.google resolve](https://dns.google/resolve?name=stack.com&type=NS)), though direct fetches of stack.com and www.stack.com failed DNS resolution this run, so the state of that website is unverified.

**Handles.**
github.com/stack is taken by an individual developer's personal account ([github.com/stack](https://github.com/stack)).

## FitSnack (abandoned name, for the record)

**App Store.**
A US search for "fitsnack" returned "Home Workout to Lose Weight" by Stanislau Shvaika (Health & Fitness) as the first result; per the fetched listing data, the app operates under the "FITsnack" brand, described as a "daily micro home workouts plan" with short sessions performed several times a day ([iTunes Search API, "fitsnack"](https://itunes.apple.com/search?term=fitsnack&entity=software&country=US&limit=15)).
That is a near-identical concept (micro home workouts) already using the name in the same category, which by itself validates the rebrand.

**Domains and handles.**
fitsnack.com has live nameservers, i.e. registered ([dns.google resolve](https://dns.google/resolve?name=fitsnack.com&type=NS)).
github.com/fitsnack returned HTTP 404, an availability signal ([github.com/fitsnack](https://github.com/fitsnack)), though the name is not worth pursuing.

## Caveats

- The iTunes Search API returns ranked search results, not an exhaustive registry; an app with an identical or similar name could exist without surfacing in these queries.
- Prices, listings, and DNS state are as fetched on 2026-07-15 and can change.
- Trademark status: UNVERIFIED for Rep Today, Cairn, Stack, and FitSnack alike. A USPTO search (and ideally counsel review) plus App Store Connect name reservation are the founder's required next steps.

## Sources

All timestamps UTC, 2026-07-15; the fetch run spanned 04:18:47Z to 04:21:34Z.

- https://itunes.apple.com/search?term=rep+today&entity=software&country=US&limit=15 - fetched 04:19Z; no "Rep Today" collision in US App Store search results; one unrelated fitness result.
- https://itunes.apple.com/search?term=cairn&entity=software&country=US&limit=15 - fetched 04:19Z; "Cairn - Hiking Safety Tracker" live in Health & Fitness plus other Cairn-named apps.
- https://itunes.apple.com/search?term=stack&entity=software&country=US&limit=15 - fetched 04:19Z; exact-name "Stack" game (56,096 ratings) and Stack Team App (Sports).
- https://itunes.apple.com/search?term=fitsnack&entity=software&country=US&limit=15 - fetched 04:19Z; live app branded "FITsnack" doing daily micro home workouts.
- https://itunes.apple.com/search?term=rep+count&entity=software&country=US&limit=10 - fetched 04:21Z; four live "Rep"-prefixed Health & Fitness tracker apps.
- https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com - fetched 04:20Z; reptoday.com for sale, $3,895 buy-now or $162.29/mo x 24.
- https://dns.google/resolve?name=reptoday.app&type=NS - fetched 04:20Z; Status 3 NXDOMAIN, availability signal for reptoday.app.
- https://dns.google/resolve?name=stack.com&type=NS - fetched 04:20Z; stack.com registered (live NS records).
- https://dns.google/resolve?name=cairn.com&type=NS - fetched 04:20Z; cairn.com registered (live NS records).
- https://dns.google/resolve?name=fitsnack.com&type=NS - fetched 04:21Z; fitsnack.com registered (live NS records).
- https://www.repfitness.com - fetched 04:20Z; REP Fitness home gym equipment brand, web collision for "Rep".
- https://www.stacksports.com - fetched 04:21Z; Stack Sports sports-tech company, 50,000+ organizations.
- https://www.mysubscriptionaddiction.com/2022/05/cairn-may-2022-review-coupon.html - fetched 04:21Z; Cairn box acquired by Outside mid-2021, renamed Outside Discovery Collection, status unclear.
- https://github.com/reptoday - fetched 04:20Z; HTTP 404, handle availability signal.
- https://github.com/cairn - fetched 04:20Z; taken by an active software org.
- https://github.com/stack - fetched 04:21Z; taken by an individual developer.
- https://github.com/fitsnack - fetched 04:21Z; HTTP 404, handle availability signal.

Failed/inconclusive fetches (no claims made from these): https://rdap.org/domain/reptoday.app (403), https://www.cairn.us (empty content), https://stack.com and https://www.stack.com (DNS resolution failed), https://backpackers.com/gear/reviews/outdoor-gear-subscription-box/ (403).
