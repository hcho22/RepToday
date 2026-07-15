# Competitor Teardown: Freeletics

Research date: 2026-07-15 (all fetches 04:18-04:20 UTC).
All claims below are backed by pages actually fetched during this run; see Sources.

## TL;DR

Freeletics is a large, established AI-coach fitness app ("60 million athletes" claimed) positioned around personalized training plans across bodyweight, gym, weights, and running ([site](https://www.freeletics.com/en/), [App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)).
Its core product, the AI Coach, is paid; the free tier is described by a third-party reviewer as "more of an extended preview than a usable long-term option" ([fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)).
It front-loads a multi-question onboarding (goals, fitness level, equipment, days per week, session time) before the Coach builds a plan ([official blog](https://www.freeletics.com/en/blog/posts/getting-started-with-freeletics/), [fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)).
It uses badges, streaks, leaderboards on benchmark workouts, and community features ([App Store description](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212), [fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)).
Top review complaints on the App Store page center on subscription/cancellation friction, limited in-session customization, and doubts that the "AI" is real ([App Store reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews)).
Rep Today's wedge against it: zero pre-workout interrogation, a genuinely usable free tier, offline-deterministic generation, and explicitly no badges/streaks/leaderboards.

## 1. What it is and positioning

Freeletics' website hero reads "Personalized fitness in the palm of your hand" with the tagline "Any goal. Anywhere. Anytime." ([freeletics.com](https://www.freeletics.com/en/), fetched 2026-07-15).
The site pitches an "AI Coach for busy people" spanning HIIT, calisthenics, gym, weights, cardio, and running, and claims 60 million users, 450 million training sessions, and 700+ exercises ([freeletics.com](https://www.freeletics.com/en/)).
The App Store listing is "Freeletics: Workouts & Fitness" with subtitle "Home & Gym AI Coach, Planner", rated 4.6 stars from about 22K ratings on the fetched US page, and the description calls it "Europe's #1 fitness app" ([App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212), fetched 2026-07-15).

## 2. Pricing and free-tier shape

The fetched App Store page listed in-app purchases for the Training Coach at $34.99, $59.99, $74.99, and $79.99 (various durations) and a Training & Nutrition bundle at $49.99 and $89.99, plus a 14-day money-back guarantee ([App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212), prices as shown on 2026-07-15).
Freeletics' own blog states that on first login "you'll have access to the free version of the app, so you can explore and try out a few workouts right away", and that subscribing unlocks "your digital personal trainer, also known as the Freeletics Coach" ([freeletics.com blog](https://www.freeletics.com/en/blog/posts/getting-started-with-freeletics/)).
A third-party reviewer put UK pricing at roughly £6.99/month billed annually (~£83.99/yr) and £12.99-£17.99/month on monthly plans, and judged the free tier "more of an extended preview than a usable long-term option" ([fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)).
Another reviewer wrote that "most features you actually want to use require a premium subscription" ([fitnessdrum](https://fitnessdrum.com/freeletics-review/)).
Net: unlimited adaptive training is paid; the free tier is a sampler, the inverse of Rep Today's free-unlimited-workouts shape.

## 3. Onboarding and session-start friction

Freeletics' official getting-started guide says: "After you've signed up to Freeletics, you'll be guided through a series of questions about who you are, your fitness goals, training preferences, and overall fitness background" ([freeletics.com blog](https://www.freeletics.com/en/blog/posts/getting-started-with-freeletics/)).
A hands-on review describes it more concretely: "When you first sign up, you complete a detailed onboarding: goals, fitness level, available equipment, days per week, and even how much time you have per session" ([fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)).
Training is organized into 6-12 week "Training Journeys" that the Coach builds from those answers ([freeletics.com blog](https://www.freeletics.com/en/blog/posts/getting-started-with-freeletics/)).
Nothing fetched suggests the app opens directly to a ready session; the model is questionnaire first, plan second, session third.

## 4. Equipment assumptions and offline capability

Equipment is a first-class onboarding variable: the app spans bodyweight, dumbbells, barbells, gym machines, and running, and asks what you have access to ([App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212), [fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)).
The bodyweight path itself is equipment-free: "No equipment required for the core programme", "just floor space and your own bodyweight" ([fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)).
The workout preview "tells you if you need any equipment, such as dumbbells or a bench" ([fitnessdrum](https://fitnessdrum.com/freeletics-review/)).
Offline capability could not be verified from a fetchable primary source during this run: Freeletics' help-center articles on the topic returned HTTP 403 to fetches, and the fetched App Store description does not mention offline use ([App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)).
Treat Freeletics' offline behavior as unverified rather than absent.

## 5. Gamification

The fetched App Store description mentions badges, streaks, skill progressions, and community features with an "Instagram-like design" ([App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)).
A reviewer highlights named benchmark workouts ("like Aphrodite, Zeus, or Ares") and "chasing leaderboard times on benchmark workouts" as core competitive mechanics ([fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)).
So Freeletics leans on exactly the mechanics Rep Today refuses: streaks, badges, leaderboards, and social comparison.

## 6. Review themes (from fetched review pages only)

Praise themes on the fetched App Store reviews page: effective workouts with minimal equipment, motivating training journeys, and community features ([App Store reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews), fetched 2026-07-15).
Example: "I've used this app for almost a year to complete at-home workouts, with and without minor equipment" (reviewer misshatihati, [App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)).
Complaint themes: subscription/billing and cancellation friction, inability to swap exercises or adjust rest, no Apple Watch integration, and unresponsive support ([App Store reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews)).
Example: "they make it impossible to cancel and get a refund" (reviewer Maninho0087, [App Store reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews)).
Example: "There is no AI or adjustments or changes...all marketing BS" (reviewer big.kahanna, title "Limited", [App Store reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews)).

## 7. Wedge contrast: Rep Today vs Freeletics

- Session-start friction: Freeletics requires a multi-question onboarding (goals, level, equipment, days, time) before the Coach builds a plan ([blog](https://www.freeletics.com/en/blog/posts/getting-started-with-freeletics/), [fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)); Rep Today opens to a pre-generated session with one Start button and never asks "how long do you have?".
- Free tier: Freeletics locks its adaptive Coach behind $34.99-$79.99 IAPs ([App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)) and its free tier reads as a preview ([fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)); Rep Today's core loop of unlimited generated workouts is free forever.
- Gamification: Freeletics uses badges, streaks, and benchmark leaderboards ([App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212), [fitnesstoolsreviewed](https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/)); Rep Today ships a forgiving rolling Consistency Score and no XP/levels/badges/leaderboards anywhere.
- Trust in the "AI": Freeletics markets AI adaptation and some users call it out ("all marketing BS", [App Store reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews)); Rep Today can honestly say the workout engine is deterministic and on-device, with AI only tuning policy off the critical path.
- Equipment scope: Freeletics spans gym, weights, and running and asks about equipment up front ([App Store](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)); Rep Today is zero-equipment by design, so there is no equipment question to ask.
- [ASSUMPTION] Freeletics' billing-friction complaints suggest churn-driven distrust of fitness subscriptions in this segment; reasoning: multiple independent fetched App Store reviews complain about cancellation and refunds, so a paywall-never-gates-the-core-loop stance is a credible trust wedge, though the size of the effect is unmeasured.

## Sources

All fetched via WebFetch on 2026-07-15 (UTC).

- https://www.freeletics.com/en/ - fetched 04:18 UTC - hero message, positioning, user-count claims, AI Coach framing.
- https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212 - fetched 04:18 UTC - listing name/subtitle, 4.6-star/22K rating, description (badges, streaks, equipment scope, "Europe's #1"), IAP prices, review quotes.
- https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews - fetched 04:19 UTC - review themes and verbatim complaint quotes (Maninho0087, big.kahanna).
- https://fitnessdrum.com/freeletics-review/ - fetched 04:19 UTC - 6-question onboarding, free-tier restrictions, equipment shown in workout preview.
- https://www.freeletics.com/en/blog/posts/getting-started-with-freeletics/ - fetched 04:19 UTC - official onboarding questionnaire description, free vs Coach split, Training Journeys.
- https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/ - fetched 04:20 UTC - onboarding detail, UK pricing, free tier as preview, bodyweight equipment stance, benchmark leaderboards.

Fetch failures (claims dependent on these were dropped or marked unverified): help.freeletics.com articles on free tier and offline training (HTTP 403), trustpilot.com/review/freeletics.com (HTTP 403), hotelgyms.com review (HTTP 403), freeletics.com/en/coach/ (HTTP 404).
