# Red Team: The Competitor's Counter

Persona: Head of Growth at Down Dog (Yoga Buddhi Co.).
I run growth for a six-app portfolio with a 4.9-star Yoga app at 326K US ratings and a 4.9-star HIIT app at 48K ratings, per Rep Today's own research file (competitor-down-dog.md).
Their positioning names me by name as the villain.
This is what I do about it, and what in their package I can truthfully shred in public.

## My counter plan, so you know what you are actually up against

### What I neutralize in one sprint

**"Quick Start" mode.**
My users' settings already persist; Rep Today's own teardown concedes "there is a start button and settings persist" (competitor-down-dog.md, section 3).
I ship a setting that boots the app straight into a generated session with one Start button, plus a lock-screen widget and an App Intent.
For every returning user, the visible difference between us and "opens ready" is now zero, and I have a marketing page and 374K ratings to say so.

**Perceived instant-open.**
I pre-generate and cache the next session on session end.
Nobody stopwatch-times an app; "under 100 milliseconds" versus "instant-feeling" is a distinction only their landing page cares about.
Their own positioning.md admits this: "A competitor can fake perceived instant-open with caching."

**The forgiving-score story.**
My streak is already "only as a stat, not loss-framed pressure" per their own research (competitor-down-dog.md, section 5).
One marketing page titled "No streak anxiety, ever" and one copy change in the Activity tab, and pillar 4 of their messaging is contested ground.
Their positioning.md already concedes the anti-streak ground "is already contested."

**The ASO whitespace.**
The week "micro workout" shows any Apple Search Ads popularity, I put "Micro" in the Down Dog HIIT subtitle or keyword field.
That is one metadata update against my 48K ratings at 4.9 stars, and their whitespace closes permanently.
Whitespace only stays open while it is worthless; the moment it is worth something, the incumbent with the ratings takes it, and their channel plan's number one channel has no answer to that.

### What I structurally cannot copy

**Free unlimited forever.**
Down Dog "moved to a mandatory subscription model in September 2018" (their teardown, quoting my own FAQ).
The subscription is the entire business; I cannot un-paywall six apps to chase one pre-launch competitor.

**No account.**
My cross-app subscription is keyed to a login; "you must be signed in with the same email you used to make the purchase."
I cannot remove mandatory login without rebuilding entitlements.

So the honest strategic read: everything in their hero is copyable in a sprint, and the two things I cannot copy are buried at pillar 5 and in a band item.
Remember that; it drives my final demand.

## MUST-FIX defects

### MF1. The positioning statement lies about how Down Dog works, and I will demo it on stage

Target: positioning.md, positioning statement.
The line: "configure-first generators that interview you before you can move (Down Dog, Freeletics)."
Down Dog does not interview anybody.
There is a first-run setup, then settings persist and every subsequent open is one Start tap; their own research file says exactly this.
The day that sentence appears on a launch page or in a Show HN, I reply with a ten-second screen recording of a returning user opening Down Dog and pressing Start once, and their credibility on their single core claim is gone in their own launch thread.
Demand: reword to what is verifiably true, for example "apps that require an account and configuration before your first session (Down Dog) or an onboarding interview (Freeletics)," and audit every asset for the word "interview" applied to Down Dog.
Severity: high.

### MF2. The site's "AI Programmer" card is the exact "all marketing BS" pattern their own plan weaponizes

Target: 03-site/index.html, mechanism card 2.
The lines: "The AI tunes, it never generates" and "an AI Programmer adjusts your Session Policy."
Per product-facts-brief.md, at MVP the Programmer is "deterministic on-device heuristics (option C) with exactly one optional LLM call" for a single description sentence.
So at launch there is no AI tuning anything; there are if-statements and one optional LLM string.
Their own channel-plan.md quotes a Freeletics review, "There is no AI or adjustments or changes...all marketing BS," as a weapon, and then their own site hands me the identical opening.
The HN thread they are planning will find the discrepancy in one comment, and I will help.
The same plan also says "Do not lead any channel with AI" and cites 36% worse retention for AI-branded apps; the mechanism section of their only marketing page gives the AI a named, numbered card anyway.
Demand: rewrite card 2 to describe what ships, deterministic on-device tuning at launch with AI planned later, or remove "AI" from the site entirely.
Severity: high.

### MF3. The phone mock invents a product guarantee that is nowhere in the facts brief and is probably false

Target: 03-site/index.html, hero phone mock.
The line: "Nothing repeats from yesterday. Bear crawl is new this week."
The facts brief promises a "variety window," not a categorical no-repeat-from-yesterday guarantee.
With a 42-movement library serving daily sessions of 5 to 60 minutes, zero overlap between consecutive days is not plausible at the long durations, and fitness reviewers count.
An unsubstantiated product-behavior claim rendered inside a fake product screenshot is the most screenshot-able kind of false advertising.
Demand: replace with a line the engine actually guarantees, sourced from the facts brief.
Severity: high.

### MF4. The App Store subtitle is still an open decision, and the wrong candidate is winning

Target: channel-plan.md (ASO section) and decisions-log.md D-005.
The plan itself flags that D-005 selected the subtitle "Opens to a ready workout" over the ASO-researched "No Equipment Micro Workouts."
Their own aso-landscape.md states the wedge phrasing is worthless as metadata because "nobody searches 'opens ready'."
The subtitle is the highest-weight keyword slot they will own; spending it on an unindexed slogan is a gift to me.
The wedge belongs in screenshot 1, where it converts, not in the subtitle, where it evaporates.
Demand: resolve the conflict now, ship the keyword subtitle, put the wedge line in the first screenshot, and record the reversal in the decisions log.
Severity: medium.

### MF5. Trademark is "pending" on the public footer while the plan only schedules a trademark search

Target: 03-site/index.html footer and channel-plan.md pre-spend rhythm.
The footer says "Trademark and App Store name clearance pending."
The weekly rhythm's pre-launch Monday lists only "trademark search," never a filing.
The day they launch, any competitor can bid on "rep today" in Apple Search Ads for pennies, because their brand term will have no volume and they will have no registered mark to complain with.
I would not even need to be first; the 7-minute-workout name squatters their own ASO research documents do this for sport.
Demand: file the trademark application as a blocking pre-launch item and add brand-term conquest monitoring to launch week.
Severity: medium.

### MF6. The only durable wedge is missing from the hero

Target: positioning.md hero message and 03-site/index.html hero subhead.
The subhead reads: "A full bodyweight session, built on your phone in under 100 milliseconds. No questions, no account, no internet needed. Press Start."
Speed, questions, offline: everything in that sentence I can neutralize in one sprint, per my counter plan above.
The one claim I structurally cannot match, unlimited free workouts forever, appears nowhere until the pricing section.
Their positioning.md even acknowledges the durable claim is "the full stack at once," then writes a hero that leads with the most copyable fraction of the stack.
Demand: put the free-forever line in the hero subhead alongside instant-open, so the message I cannot copy is the first one anyone reads.
Severity: medium.

### MF7. The mock session does not add up to its own label

Target: 03-site/index.html, hero phone mock.
The screen says "15 min" over four blocks: push-ups 3x8, two minutes of hip hinge, 40 seconds of bear crawl, and 3x30s squat holds.
Generously, with rests, that is ten to eleven minutes.
Every trainer and every competitor's social intern will do this arithmetic under the launch post.
Demand: make the blocks plausibly fill the labeled duration, or relabel the mock to 10 minutes.
Severity: low.

## SURVIVING OBJECTIONS

These stand no matter how the copy is rewritten.
Publish them; pretending otherwise is worse.

**S1. The hero claim is imitable in one sprint; only the business model is not.**
Cached pre-generation plus a quick-start setting plus a widget erases the perceived difference for every incumbent's returning users.
The moat is free-forever plus no-account, and a moat that narrow must carry the whole company.

**S2. The paywall wedge does not bite the apps people actually love.**
Rep Today's own research found my US review set "contained no pricing complaints; users treat the subscription as fair."
The free-forever pitch converts people burned by scam paywalls like 30 Day Fitness, not Down Dog or Seven subscribers, and that pool is smaller than the positioning implies.

**S3. ASO whitespace is not a moat, it is a countdown.**
"Micro workout" is empty because it is worthless; the moment it is not, any incumbent with five-digit ratings takes it with a subtitle edit.
Rank at launch is decided by rating volume, and Rep Today starts at zero against 118K to 530K.

**S4. 42 movements will read as small next to 1000-plus, and repeat fatigue is a predictable review theme.**
My HIIT app markets "over 1000 exercises" and "you'll never get the same workout twice."
A daily-use app drawing from 42 movements will surface "already repetitive" one-star reviews within weeks, and I will quote them.

**S5. "Free means the workouts. All of them. Forever." is an unverifiable promise from a zero-revenue solo developer.**
Free-forever apps from solo founders historically flip the paywall or go abandoned, and every user has lived that story once.
I have charged money since 2018 and shipped continuously; that counter-message writes itself and no copy edit can pre-empt it.

**S6. The channel plan's own numbers cannot feed its own kill criteria.**
Single-digit daily ASO installs, a few hundred one-week HN installs skewed to engineers who are explicitly not the ICP, and tens per permitted Reddit post.
The week-12 review will be judging kill thresholds against cohorts small enough that the answer is mostly noise.

**S7. Premium's day-one value is thin and mockable.**
$7.99 a month buys "deeper analytics" and a Strength Phase that is "earned ... never self-selected," meaning it is gated by both payment and merit.
"They charge you for a feature they might not let you use" is a line I get to say for free.

**S8. The launch page has zero social proof and borrows its emotion from other apps' angry reviews.**
Both evidence quotes on the site are about other products, and the captions admit "we don't have any yet."
Honest, yes; but the page argues from theory against incumbents holding hundreds of thousands of five-star ratings.

**S9. The App Store name "Rep Today, Rest Tomorrow" hands every competitor a one-line joke.**
A consistency app whose title schedules tomorrow off.
"So do you open it tomorrow or not?" costs me one tweet, and no GTM copy can rewrite a locked name.

## What Rep Today should change NOW because of this counter

1. Lead the hero with the claim I cannot copy: free unlimited workouts forever, no account, next to instant-open, not five sections below it (MF6).
2. Fix the Down Dog "interview" falsehood before any public asset ships; the launch-thread demo that punishes it takes me ten minutes to record (MF1).
3. De-AI the marketing site to match what actually ships at MVP, because the Freeletics "marketing BS" review they plan to quote cuts both ways (MF2).
4. Treat ASO whitespace as optionality, not a channel; ship the keyword subtitle, and assume "micro workout" is taken by an incumbent the month it shows volume (MF4, S3).
5. File the trademark and budget for brand-term conquest defense on day one (MF5).
6. Plan for the repeat-fatigue review wave from a 42-movement library: sequence the messaging so variety is never overpromised, starting with the fabricated no-repeat line in the mock (MF3, S4).
