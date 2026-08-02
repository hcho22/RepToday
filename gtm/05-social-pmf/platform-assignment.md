# Platform assignment for the PMF test kit

Committed in `../01-research/platform-signal-evidence.md` (all citations fetched 2026-08-01); this file restates the reasoning chain and adds the operating protocol.

## The two test platforms

### 1. TikTok (primary)

- TikTok's official newsroom explainer states that "neither follower count nor whether the account has had previous high-performing videos are direct factors in the recommendation system"; the For You feed ranks on interactions, video information, and settings, weighting full watches heavily.
  Source: https://newsroom.tiktok.com/en-us/how-tiktok-recommends-videos-for-you (fetched 2026-08-01).
- That is the strongest platform-official statement among all six candidates that a zero-follower account's content is judged on the content itself, which is exactly the property a pre-registered experiment needs: the result reflects the message, not the audience we do not have.
- Buffer's TikTok analysis describes the mechanism (small test audience, then a larger one if the first reacts): https://buffer.com/resources/tiktok-algorithm/ (fetched 2026-08-01).
- ICP reach: 44% of US adults 30-49 use TikTok (Pew, survey Feb-Jun 2025, n=5,022): https://www.pewresearch.org/internet/fact-sheet/social-media/ (fetched 2026-08-01).

### 2. YouTube Shorts (secondary)

- YouTube's official Shorts discovery guidance ranks on "% of viewers who chose to view, avg. view duration and avg. % viewed" plus likes and surveys, with subscriber count absent from the documented factor list: https://support.google.com/youtube/answer/11914225 (fetched 2026-08-01).
- Best ICP coverage of any candidate: 92% of US adults 30-49 use YouTube (Pew, same fact sheet).
- Honest constraint carried from YouTube's own doc: "Even if you have good metrics on your Short, you may get fewer impressions if Shorts from other channels are performing even better", so Shorts signal is real but can be slower; that is why it is secondary.

### Operating rule

Identical content posts to both platforms the same day (the research decision: "test on TikTok and YouTube Shorts with identical content").
Each angle names one PRIMARY platform in `angles.md`; the primary platform's metrics adjudicate the pre-registered signal, and the mirror is a free second sample, read but never adjudicating.

## Why not the others

- Instagram Reels: the only short-video platform whose official documentation names creator popularity, including "number of followers", as a ranking signal (https://about.instagram.com/blog/announcements/instagram-ranking-explained, fetched 2026-08-01).
  For a zero-follower account that makes weak reach ambiguous between weak content and no audience, i.e. noisier signal.
  Revisit once a follower base exists anywhere, since Reels discovery reach is real (Buffer: Reels get 36% more reach than carousels, https://buffer.com/resources/state-of-social-media-engagement-2026/, fetched 2026-08-01).
  Note: the v1 seed bank (`../09-extras/marketing-agent/angles.seed.json`) assigned static cards to Instagram; those platform assignments are superseded by this file, and the statics are refit as Shorts/TikTok assets or parked.
- X: lowest 30-49 reach of the six candidates (25%, Pew) and bottom-tier median engagement (~2.5%, Buffer 52M-post study), with no official claim of follower-independent distribution fetched.
  The v1 launch kit's 7-post X sequence (`../09-extras/social-launch-kit.md`) is therefore not the PMF test vehicle; see `week-1-drafts.md` for what was salvaged.
- LinkedIn: professional-context mismatch for a consumer fitness habit app (reasoning, not a fetched fact), despite 32% reach in the 30-49 band.
- Reddit as a broadcast channel: ruled out by fetched subreddit rules; see the listening protocol below.

## Reddit listening protocol (listening only, one sanctioned posting venue)

Fetched rules that bind this protocol (all 2026-08-01):

- r/fitness30plus: "No self promotion :: ... Do not link them here. You will be banned." - https://www.reddit.com/r/fitness30plus/about/rules.json
- r/bodyweightfitness: Rule 5 "No advertising." - https://www.reddit.com/r/bodyweightfitness/about/rules.json
- r/getdisciplined: no external links, "anyone posting links or shilling products will be permanently banned", plus account-age and karma gates (30 days old and 200 karma to post) - https://www.reddit.com/r/getdisciplined/about/rules.json
- r/SideProject: stated purpose is "sharing and receiving constructive feedback on side projects"; structured rules list empty - https://www.reddit.com/r/SideProject/about/rules.json and about.json
- Site-wide spam policy: post authentic content where you have personal interest; business owners should be thoughtful about frequency or use the ads platform - https://support.reddithelp.com/hc/en-us/articles/360043504051-Spam

The protocol:

1. Listening venues: r/fitness30plus, r/bodyweightfitness, r/getdisciplined.
   Read weekly; zero product mentions, zero links, ever, in these three.
   Genuine non-promotional participation is allowed and builds the account age and karma that r/getdisciplined gates on.
2. What to capture: verbatim quotes about starting friction, streak grief, paywall anger, and time windows, each logged with its permalink and fetch date into `../01-research/pain-point-frequency.md`'s successor file.
   This feeds the angle bank; Reddit's job in this kit is input, not output.
3. Language mining: comment threads under any hook theme we are testing tell us the words the ICP actually uses; hooks get rewritten from mined vocabulary, not from our own.
4. The one sanctioned posting venue: r/SideProject, where sharing your own project is the community's stated purpose.
   Gate: post only after TestFlight actually exists, framed as a feedback request from a solo builder, with the honest zero-users status stated.
   One post, then answer every comment; a removed post or mod warning is a full stop.
5. Never do: posting product links in the three listening subs, DM campaigns, engagement-bait comments, or using alt accounts.
   The site-wide spam policy plus the permanent-ban language in the ICP subs makes any of these an account-level and reputation-level risk with no upside for a listening channel.
