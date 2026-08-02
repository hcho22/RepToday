# Platform selection evidence: where a zero-audience founder gets honest signal fastest (R4, v2)

Research date: 2026-08-01.
Scope: consumer iOS fitness app (RepToday, pre-launch, zero users), founder with no audience and $0, ICP = busy desk-bound adults in their 30s-40s.
Candidates evaluated: TikTok, Instagram Reels, YouTube Shorts, Reddit, X, LinkedIn.
Every factual claim below carries a URL that was actually fetched on 2026-08-01 during this research pass.
Claims without a citation are labeled as reasoning or [ASSUMPTION].

## Recommendation (committed)

1. Primary test platform: TikTok.
2. Secondary test platform: YouTube Shorts.
3. Listening channel (not a broadcast channel): Reddit, specifically r/fitness30plus, r/bodyweightfitness, and r/getdisciplined for listening, with r/SideProject as the one venue where posting the product for feedback is the community's stated purpose.

The reasoning chain is at the bottom; the evidence legs come first.

## Leg 1: How each recommendation system treats brand-new, zero-follower accounts

### TikTok (platform-official)

TikTok's official newsroom explainer states that "neither follower count nor whether the account has had previous high-performing videos are direct factors in the recommendation system."
The For You feed ranks videos on user interactions (likes, shares, follows, comments), video information (captions, sounds, hashtags), and device/account settings, weighting strong interest signals like watching a full video more heavily.
This is the strongest platform-official statement among all six candidates that a zero-follower account's content is judged on the content itself.
Source: https://newsroom.tiktok.com/en-us/how-tiktok-recommends-videos-for-you (fetched 2026-08-01).

Buffer's analysis of the TikTok algorithm adds the mechanism: "If a video performs well with a small initial audience, TikTok may test it with a larger one. But that next boost depends on how that new audience reacts, not just the engagement numbers alone," and "even new users with zero followers can have their content pushed to large audiences - if it aligns with what the algorithm thinks people want to see."
Buffer is a third-party vendor analysis, not platform-official, but it is consistent with TikTok's own document above.
Source: https://buffer.com/resources/tiktok-algorithm/ (fetched 2026-08-01).

### Instagram Reels (platform-official)

Instagram's official ranking explainer lists the signals for Reels in order: your activity, your history of interacting with the poster, information about the reel, and information about the person who posted.
Critically, it includes creator popularity as a signal: "We consider popularity signals such as number of followers or level of engagement to help find compelling content."
Reels do surface content from accounts you don't follow, so discovery for new accounts exists, but Instagram is the only one of the three short-video platforms whose official documentation names follower count as a ranking input.
This is the cited discriminator that ranks Reels below TikTok and Shorts for a zero-follower founder.
Source: https://about.instagram.com/blog/announcements/instagram-ranking-explained (fetched 2026-08-01).

### YouTube Shorts (platform-official)

YouTube's official Shorts discovery guidance says the feed is ranked on performance and viewer personalization: "% of viewers who chose to view, avg. view duration and avg. % viewed," plus likes and post-watch survey results.
The document contains no mention of subscriber count as a ranking factor, and states "Our system has no opinion about what type of Shorts you make" and "Focus on what your audience likes. If you do that and people watch, recommendations will follow."
It also notes the honest constraint: "Even if you have good metrics on your Short, you may get fewer impressions if Shorts from other channels are performing even better."
Source: https://support.google.com/youtube/answer/11914225 (fetched 2026-08-01).

YouTube's general recommendations doc lists the viewer-side signals (watch history, search history, subscriptions, likes/dislikes, "not interested" feedback, surveys) and likewise never lists channel size as a factor.
Source: https://support.google.com/youtube/answer/16089387 (fetched 2026-08-01).

### Reddit (platform-official)

Reddit's ranking is community-vote based rather than follower-graph based, so a zero-karma account's post competes on votes within a subreddit; however, Reddit's spam policy and subreddit rules sharply constrain promotional posting (see Leg 3).
Reddit's official spam policy: "Post authentic content into communities where you have a personal interest" and "If your contributions to Reddit consist primarily of links to a business that you run, own, or otherwise benefit from, please be thoughtful about the frequency of posting, or consider advertising opportunities using our self-serve platform."
Source: https://support.reddithelp.com/hc/en-us/articles/360043504051-Spam (fetched 2026-08-01 via browser after direct fetch was blocked).

### X and LinkedIn

No platform-official document claiming follower-independent distribution for new accounts was fetched for X or LinkedIn during this pass, so no such claim is made for them.
The case against them rests on the demographic and engagement evidence in Legs 2 and 4.

## Leg 2: Time-to-signal and whether reach depends on follower count

Direct platform-official "time to signal" numbers do not exist; the closest citable evidence is the follower-independence statements above plus cross-platform engagement data.

Buffer's 2026 study of 52M+ posts (Buffer-user data, not platform-wide, a limitation the study itself states) found median engagement tiers: LinkedIn ~6.2%, Facebook ~5.6%, Instagram ~5.5% in the top tier; TikTok ~4.6% mid-tier; X ~2.5% in the bottom tier.
The same study found "Reels get 36% more reach than carousels - but carousels earn 12% more engagement," i.e. on Instagram the discovery format is Reels while deeper engagement comes from existing followers, which a zero-follower account does not have.
Source: https://buffer.com/resources/state-of-social-media-engagement-2026/ (fetched 2026-08-01).

[ASSUMPTION] Time-to-signal ordering: TikTok fastest (test-audience loop runs within hours of posting per the mechanism described in the Buffer TikTok analysis), YouTube Shorts comparable but with a longer evaluation tail, Reels slower for a zero-follower account because follower count is an official ranking signal.
Reasoning: this ordering is inferred from the cited mechanism descriptions, not from a fetched benchmark; no invented numbers are attached to it.

[ASSUMPTION] Reddit gives the fastest qualitative signal (comments within hours in an active subreddit) but the rules in Leg 3 mean that signal is only safely available in explicitly promo-tolerant venues like r/SideProject.
Reasoning: inferred from subreddit activity norms; no fetched quantitative source.

## Leg 3: Reddit self-promotion norms (the v1 blocker, now resolved with fetched rule text)

Site-wide policy (official): Reddit defines spam as "repeated or unsolicited actions (whether automated or manual) that negatively affect redditors, communities, and/or Reddit itself" and directs business owners to be thoughtful about posting frequency or use the ads platform; community moderators adjudicate what counts as spam in their communities.
Source: https://support.reddithelp.com/hc/en-us/articles/360043504051-Spam (fetched 2026-08-01).

r/bodyweightfitness (2.9M-scale bodyweight community, direct product-domain match): Rule 5 is "No advertising. See the full rules for our self-promotion policy."
Source: https://www.reddit.com/r/bodyweightfitness/about/rules.json (fetched 2026-08-01 via browser; old.reddit.com mirror was login-walled).

r/fitness30plus (exact ICP: fitness for people 30+): the rule is explicit and terminal: "No self promotion :: Reddit has a built in system for advertising if you want use Reddit as a platform to drive traffic to your website, blog, social media, products, services, surveys, apps or anything else. Do not link them here. You will be banned."
Source: https://www.reddit.com/r/fitness30plus/about/rules.json (fetched 2026-08-01 via browser).

r/getdisciplined (discipline-first audience match): "Do not post any links to external content... anyone posting links or shilling products will be permanently banned from the community without hesitation," plus account-age gates: "commenting requires an account at least 3 days old and posting requires an account at least 30 days old and 200 karma," plus "No Sales or Coaching Pitches."
Source: https://www.reddit.com/r/getdisciplined/about/rules.json (fetched 2026-08-01 via browser).

r/SideProject (795,804 subscribers at fetch time): its stated purpose is "a subreddit for sharing and receiving constructive feedback on side projects," and its structured rules list is empty, i.e. sharing your own project is the point of the community.
Sources: https://www.reddit.com/r/SideProject/about.json and https://www.reddit.com/r/SideProject/about/rules.json (fetched 2026-08-01 via browser).

Net: the ICP-matched fitness and discipline subreddits ban product promotion outright, some with permanent bans and karma gates, which rules Reddit out as a broadcast channel for a new account and confirms it as a listening and research channel, with r/SideProject as the single sanctioned feedback venue.

## Leg 4: Demographic fit for the 30s-40s desk-worker ICP (Pew, survey Feb 5 - Jun 18, 2025, n=5,022 US adults)

Platform use among US adults ages 30-49: YouTube 92%, Instagram 62%, TikTok 44%, Reddit 35%, LinkedIn 32%, X 25%.
Overall US adult use: LinkedIn 25%, Reddit 24%, X 21%.
Source: https://www.pewresearch.org/internet/fact-sheet/social-media/ (fetched 2026-08-01).

Reading for this ICP: YouTube has near-universal coverage of the target age band; Instagram covers a majority; TikTok covers just under half; Reddit over-indexes for 30-49 relative to all adults (35% vs 24%); X is the weakest consumer reach among the six for this band.
LinkedIn reaches 32% of 30-49 adults, but it is a professional-context network; positioning a consumer workout habit app there mismatches the usage context (reasoning, not a fetched fact).

## Reasoning chain to the committed recommendation

Step 1: eliminate X - lowest 30-49 reach of the six (25%, Pew) and bottom-tier median engagement (~2.5%, Buffer 52M-post study), with no official claim of follower-independent distribution fetched.
Step 2: eliminate LinkedIn as a test platform - professional context mismatch for a consumer fitness app (reasoning), despite decent 30-49 reach (32%, Pew); nothing fetched suggests consumer app-discovery behavior there.
Step 3: eliminate Reddit as a broadcast/test platform - the ICP-matched subreddits ban self-promotion outright with permanent-ban language and karma gates (fetched rules, Leg 3); retain it as the listening channel because the same communities are exactly where the ICP discusses fitness consistency problems, and Reddit over-indexes with 30-49 adults (35%, Pew).
Step 4: rank TikTok first among the three short-video platforms - it is the only platform whose official documentation affirmatively states follower count is not a direct ranking factor (TikTok newsroom), which is precisely the property a zero-audience founder needs for honest signal, and 44% of the 30-49 band uses it (Pew).
Step 5: rank YouTube Shorts second - official docs rank Shorts purely on viewer-choice and watch metrics with subscriber count absent from the documented factor list (YouTube Help), and YouTube's 92% reach in the 30-49 band (Pew) is the best ICP coverage of any candidate; the honest-competition caveat in YouTube's own doc means signal is real but can be slower.
Step 6: rank Instagram Reels third and exclude it from the initial two - it is the only short-video platform that officially lists "number of followers" as a ranking signal (Instagram ranking explainer), which biases early results against a zero-follower account and makes weak reach ambiguous between weak content and no audience, i.e. noisier signal.

Decision: test on TikTok and YouTube Shorts with identical content, listen on Reddit (r/fitness30plus, r/bodyweightfitness, r/getdisciplined), and use r/SideProject when direct product feedback is wanted.
Revisit Reels once any account exists with a follower base, since its discovery reach is real (Reels get 36% more reach than carousels per Buffer) but its ranking inputs penalize starting from zero.

## Sources fetched

All fetched 2026-08-01 (times approximate, US Pacific evening).

1. https://newsroom.tiktok.com/en-us/how-tiktok-recommends-videos-for-you - fetched 2026-08-01, ~8:10pm.
2. https://about.instagram.com/blog/announcements/instagram-ranking-explained - fetched 2026-08-01, ~8:10pm.
3. https://support.google.com/youtube/answer/11914225 - fetched 2026-08-01, ~8:11pm.
4. https://support.google.com/youtube/answer/16089387 - fetched 2026-08-01, ~8:11pm.
5. https://support.reddithelp.com/hc/en-us/articles/360043504051-Spam - fetched 2026-08-01, ~8:12pm (via browser; direct fetch returned 403).
6. https://www.reddit.com/r/bodyweightfitness/about/rules.json - fetched 2026-08-01, ~8:12pm (via browser).
7. https://www.reddit.com/r/fitness30plus/about/rules.json - fetched 2026-08-01, ~8:13pm (via browser).
8. https://www.reddit.com/r/getdisciplined/about/rules.json - fetched 2026-08-01, ~8:14pm (via browser).
9. https://www.reddit.com/r/SideProject/about/rules.json - fetched 2026-08-01, ~8:14pm (via browser; rules list empty).
10. https://www.reddit.com/r/SideProject/about.json - fetched 2026-08-01, ~8:14pm (via browser).
11. https://www.pewresearch.org/internet/fact-sheet/social-media/ - fetched 2026-08-01, ~8:12pm and ~8:15pm.
12. https://buffer.com/resources/state-of-social-media-engagement-2026/ - fetched 2026-08-01, ~8:16pm.
13. https://buffer.com/resources/tiktok-algorithm/ - fetched 2026-08-01, ~8:16pm.

Fetch-failure notes (not cited, no claims made from them): https://support.google.com/youtube/answer/12926071 returned 404; https://old.reddit.com/r/bodyweightfitness/about/rules was login-walled/blocked; direct WebFetch of support.reddithelp.com returned 403 before the browser workaround succeeded.
