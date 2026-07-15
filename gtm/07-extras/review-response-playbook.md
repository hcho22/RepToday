# Review Response Playbook (pre-launch)

Purpose: when the first 1-star review lands at 11pm, the founder answers well in 5 minutes instead of badly in 30 seconds.

Status honesty: Rep Today has zero users, zero downloads, and zero reviews.
Every review in this document is a PREDICTION, written in realistic user words and derived from complaint themes mined from competitor reviews (see `../01-research/review-mining.md` and the competitor teardowns).
No quote below is attributed to a real Rep Today user, because none exist.

Every response must pass the voice rules in `../02-brand/brand-guidelines.md` section 7.
The register is the competent friend.
Never defensive, never corporate.

---

## 1. Principles

1. Respond to every substantive review, positive or negative. Silence reads as absence.
2. Never argue. The reviewer's experience is real even when their explanation is wrong.
3. Thank precisely, not effusively. "Thanks for saying exactly what's missing for you" beats "Thank you SO much for your amazing feedback!"
4. When the complaint is a design choice, say what the product deliberately does and own it. Do not pretend the design is a limitation we are working on.
5. When it is a bug, say so plainly and give an honest timeline. "Fixed in the next update, about two weeks out" beats "we're looking into it."
6. Never promise a feature to make a review go away. A promise made under a 1-star is a debt collected later, publicly.
7. Never use a response as ad copy. No taglines, no feature lists the reviewer did not ask about, no upsells.
8. Sign as the founder. First person, one human, no "the team apologizes for any inconvenience."
9. Keep responses between 60 and 120 words. Long enough to be specific, short enough to be read.
10. If the review points a user at a competitor that genuinely fits them better, it is fine to say so. Honesty is the brand.

---

## 2. The likely reviews, by theme

### Theme 1: "Let me customize / choose my workout"

**Predicted review (hypothetical):**
"The workouts themselves are decent but I can't build my own routine.
I want to pick which exercises I do and in what order.
Every other app lets you do this. 2 stars until I can make my own workout."

**Why we expect it.**
This is the documented counter-evidence in our own mining: Freeletics reviewers complain "Not being able to customize the workouts. This is the biggest issue for me" and "there's no option to simply swap out or modify a specific exercise" ([apps.apple.com/us/app/freeletics-workouts-fitness/id654810212](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212), cited in `review-mining.md`).
Zero-decision positioning will attract exactly the users who eventually want control.

**Pre-written response:**
"Thanks for trying it and for saying exactly what's missing for you.
Rep Today is built around one idea: when you open it, a session is already there, so there is nothing to decide before you start.
That is deliberate, and it means we will never become a full workout builder.
What you can do today: swap any movement inside a session, and change the duration with one tap.
If designing your own program is the main thing you want, a workout-builder app will honestly serve you better.
If you want to show up daily without deciding anything, that is the job we are trying to do well.
- the founder"

**Product follow-up:**
If this theme recurs, check whether the in-session swap is discoverable; users asking for something that exists is a UI finding, not a feature request.

### Theme 2: "Too easy" / "Too hard"

**Predicted review (hypothetical), easy direction:**
"I'm not a beginner. Day one gave me something my grandmother could do.
There's no way to tell it I'm already fit."

**Predicted review (hypothetical), hard direction:**
"Was going fine for two weeks, then a session left me wrecked and I dreaded opening the app again."

**Why we expect it.**
Difficulty jumps are a documented in-category complaint: a Sweat reviewer wrote "Then you get to week 9 and especially week 10 and it pushes you way harder" ([apps.apple.com/us/app/sweat-fitness-app-for-women/id1049234587?see-all=reviews](https://apps.apple.com/us/app/sweat-fitness-app-for-women/id1049234587?see-all=reviews), per `competitor-sweat.md`).
And any deliberately gentle cold start will read as insulting to fit users.

**Pre-written response (too easy):**
"You are right, and it is on purpose, so let me own it.
Every new user starts capped and gentle for about a week, because most people quit apps that hurt them on day two.
If a session felt too easy, tell the app so at the end; it climbs from there, and it climbs faster when you keep saying so.
The first week costs a fit user a little patience.
I chose that trade deliberately, and I understand if it costs a star here.
- the founder"

**Pre-written response (too hard):**
"That session failing you is the exact thing the difficulty system exists to prevent, so thank you for reporting it.
The design is asymmetric: when you mark a session too hard, the next one backs off immediately, and climbing back up happens gradually.
If it did not back off after you told it, that is a bug and I want the details - the movement and duration would help.
Either way, a shorter session still counts as fully showing up.
- the founder"

**Product follow-up:**
Too-easy reviews: verify the post-session "too easy" signal is visible and check cold-start cap tuning against real telemetry.
Too-hard reviews: treat as a possible Asymmetric Ramp bug first; reproduce before replying with the design explanation.

### Theme 3: "Where are the streaks? I want badges"

**Predicted review (hypothetical):**
"There's nothing to earn. No streak counter, no badges, no levels.
I stuck with Seven for months because of my streak.
What is supposed to keep me coming back here?"

**Why we expect it.**
Seven, the closest competitor by workout shape, retains users on exactly these mechanics; a fetched Seven review reads "I just reached 105 days, it helps me stay motivated" (`competitors-additional.md`, [apps.apple.com/us/app/seven-7-minute-workout/id650276551](https://apps.apple.com/us/app/seven-7-minute-workout/id650276551)).
Users trained by that pattern will notice its absence and some will miss it.

**Pre-written response:**
"Fair question, and the answer is a hard design choice, not an oversight.
Rep Today will never have streaks, badges, levels, or leaderboards.
A streak works until the first missed day, and then it punishes; the mined pattern is that people quit entirely after losing one.
What we track instead is a rolling Consistency Score: a missed day dents it, and it never resets to zero.
If a counter you can lose is what keeps you moving, Seven does that well.
We are betting some people last longer without one.
- the founder"

**Product follow-up:**
None on the mechanic; it is load-bearing.
If volume is high, make the Consistency Score's forgiveness more legible in-app and in the listing.

### Theme 4: "There are streaks after all" (the other direction)

**Predicted review (hypothetical):**
"They advertise 'no streaks' but there's literally a score that goes down when you miss a day.
That's a streak with extra steps. False advertising."

**Why we expect it.**
The anti-streak positioning is loud, and users burned by streak apps are primed to detect the mechanic anywhere; `review-mining.md` Theme B shows how raw that nerve is ("Every day will be a reminder that I lost that streak unfairly", [hn.algolia.com/api/v1/items/40903998](https://hn.algolia.com/api/v1/items/40903998)).
A skeptic will test whether the Consistency Score is a rebranded streak.

**Pre-written response:**
"That is a sharp read and it deserves a straight answer.
The difference is what happens when you miss.
A streak resets to zero; one bad Tuesday erases three months.
The Consistency Score dips a little and recovers; three months of showing up still shows.
Come back after a gap and the app serves you an easy, winnable session rather than a penalty.
If any part of the app made a miss feel like a reset, tell me where, because that would be a failure of the whole design.
- the founder"

**Product follow-up:**
Audit every surface where the score is shown for loss-framed presentation (red arrows, drop animations); the mechanic is forgiving, the rendering must be too.

### Theme 5: "Why is X behind premium?"

**Predicted review (hypothetical):**
"Says free, then half the screens have a lock icon.
Another fitness app that's really a subscription funnel. Deleting."

**Why we expect it.**
Paywall resentment is the strongest mined theme: "you cannot use this app unless you pay for it. You just can't" ([apps.apple.com/us/app/30-day-fitness-workout-at-home/id1099771240](https://apps.apple.com/us/app/30-day-fitness-workout-at-home/id1099771240)) and "the app won't do anything until you sign up for the free trial" ([hn.algolia.com/api/v1/items/39991813](https://hn.algolia.com/api/v1/items/39991813)), both in `review-mining.md` Theme E.
Users arrive pre-burned and will read any lock icon as bait.

**Pre-written response:**
"Here is the exact line, so you can hold me to it.
Every workout is free.
Unlimited sessions, all durations, the full movement library, forever - not a trial.
Premium is depth for people who want it: deeper analytics and, once earned, the Strength Phase.
If you ever find an actual workout behind a lock, that is a bug, and I would genuinely like a screenshot.
You can use Rep Today daily for years and pay nothing, and that is the intended shape, not a loophole.
- the founder"

**Product follow-up:**
If this recurs, count the lock icons a free user sees in a normal week; premium surfaces may be too visible even if nothing core is gated.

### Theme 6: "Too simple / no videos of real trainers"

**Predicted review (hypothetical):**
"For 2026 this feels barebones.
No trainer videos, no coaching cues from a real person.
Apps like Centr and Sweat have actual humans showing you the moves."

**Why we expect it.**
The category's big players sell trainer personality (Centr, Sweat per their teardowns), so their users equate production value with quality; meanwhile Centr's own reviews complain about the cost of that model ("I don't want to pay $20 a month for a centr member ship", `review-mining.md`, [apps.apple.com/us/app/centr-strength-fitness-app/id1382530817](https://apps.apple.com/us/app/centr-strength-fitness-app/id1382530817)).

**Pre-written response:**
"You are right that there are no filmed trainers, and there will not be.
Everything in Rep Today is built on your phone, offline, in under 100 milliseconds; a streaming video library breaks that promise and usually brings a bigger subscription with it.
Simple is the product, not a budget cut.
If a trainer on screen is what gets you moving, apps like Centr do that well and I will not pretend otherwise.
If clearer movement demonstrations would have helped you, tell me which movement lost you - that part I can keep improving.
- the founder"

**Product follow-up:**
Track which movements get named in "I couldn't follow this" feedback and improve their in-app demonstrations first.

### Theme 7: "Does nothing my free YouTube videos don't"

**Predicted review (hypothetical):**
"I can search '10 minute bodyweight workout' on YouTube and get a thousand free videos.
Why does this app exist?"

**Why we expect it.**
Free-alternative comparisons are standard for any paid-tier fitness app, and the mined NTC evidence shows users actively celebrating free options ("Thank you from the bottom of my heart Nike for providing all this for free", `review-mining.md`, [apps.apple.com/us/app/nike-training-club-wellness/id301521403](https://apps.apple.com/us/app/nike-training-club-wellness/id301521403)).

**Pre-written response:**
"Honest answer: if YouTube is working for you, keep using it, it is a great free resource.
What this app does that a video cannot: when you open it, a session is already there at your usual length, adjusted by how the last one went, with no searching, no choosing, and no connection needed.
The video does not know you, and picking one is the nightly decision that quietly kills the habit for a lot of people.
The workouts here are free too, so the comparison costs nothing to run for a week.
- the founder"

**Product follow-up:**
None; this is a positioning question, and if it recurs the listing copy should lead harder with the ready-on-open mechanism.

### Theme 8: "Said no account, then asked me to sign in with Apple"

**Predicted review (hypothetical):**
"The listing says no account needed, then boom, an Apple sign-in screen.
Classic bait. 1 star."

**Why we expect it.**
"No account" is a load-bearing marketing claim, and the mined trust evidence shows users punishing any gap between the listing and the first-run experience ("that's not a good first impression for an app that's advertised as 'free'", `review-mining.md`, [hn.algolia.com/api/v1/items/39991813](https://hn.algolia.com/api/v1/items/39991813)).
Any optional sign-in prompt will be read by someone as mandatory.

**Pre-written response:**
"The truth, checkable in 30 seconds: sign-in is optional.
Every workout, the difficulty adjustment, and your history work with no account, fully offline.
Sign in with Apple exists for one reason - syncing your history privately across your own devices through iCloud - and skipping it locks you out of nothing.
If the screen you saw did not make that obvious, that is a real problem with the screen, and I would like to know exactly where it appeared.
No account is the promise, and I intend to keep it literal.
- the founder"

**Product follow-up:**
Audit the sign-in prompt: the skip path must be as visible as the sign-in button, and the prompt should state what sign-in is for.
Treat any report of a blocking prompt as a ship-now bug.

### Theme 9: "Battery drain / phone gets hot"

**Predicted review (hypothetical):**
"Nice app but it eats my battery.
Twenty minutes of exercise took 15 percent off my phone."

**Why we expect it.**
Battery complaints are category-common: a Sweat reviewer wrote "you have to keep it open for your entire workout which totally drains my phone's battery" (`competitor-sweat.md`, [apps.apple.com/us/app/sweat-fitness-app-for-women/id1049234587?see-all=reviews](https://apps.apple.com/us/app/sweat-fitness-app-for-women/id1049234587?see-all=reviews)).
Any app that keeps the screen awake through a session will collect these.

**Pre-written response:**
"Thanks for the specifics, they help.
What the app does during a session: keeps the screen awake so you can follow along, and nothing else - no streaming, no network, no background work, since everything is generated on the phone before you press Start.
Screen-on time is most of what you measured, and that part is by design.
Anything beyond normal screen-on drain is a bug I want to find: your phone model and session length would let me reproduce it.
If it is on our side, the fix ships in the next update and I will reply here when it does.
- the founder"

**Product follow-up:**
Profile energy use on the oldest supported devices; if drain exceeds screen-on baseline, treat as ship-now.
Consider a dimmed in-session mode later; do not promise it in a reply.

### Theme 10: "The AI feels dumb / not personalized"

**Predicted review (hypothetical):**
"Where's the AI they talk about?
My sessions barely change and nothing feels personalized.
Feels like a random generator with AI marketing on top."

**Why we expect it.**
The category has poisoned the word: a Freeletics reviewer wrote "There is no AI or adjustments or changes...all marketing BS" (`competitor-freeletics.md`, [apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212?see-all=reviews)).
Rep Today's architecture is unusually honest, which means it will underwhelm anyone expecting a chatbot coach.

**Pre-written response:**
"You have caught the architecture, so here it is plainly.
No AI ever writes your workout.
A deterministic engine on your phone builds every session, which is why the app opens instantly and works offline.
The AI part runs in the background and only tunes your settings: how fast difficulty climbs, how much variety you get, how the three movement types are balanced.
In your first weeks it has little data on you, so sessions change slowly on purpose.
If 'AI coach' is what you wanted, we are honestly not that, and I would rather say so than fake it.
- the founder"

**Product follow-up:**
If this recurs, check where the listing and onboarding use the word AI; the copy must promise policy tuning, not a coach.

### Theme 11: "Workouts get repetitive"

**Predicted review (hypothetical):**
"Three weeks in and I keep seeing the same moves.
Getting bored. Needs a bigger library."

**Why we expect it.**
Repetitiveness is a documented complaint against Bend, the closest habit-first comparable ("repetitiveness and the paywalled free tier as the main complaints", `competitors-additional.md`), and Rep Today ships a 42-movement library, which a daily user will fully see within weeks.

**Pre-written response:**
"Straight numbers: the library is 42 movements today, and a daily user will meet all of them within a few weeks.
The constraint is deliberate - every movement must work with just a floor and a wall, no equipment ever - and that rules out most of what pads other apps' catalogs.
The engine does rotate deliberately so the same session never just repeats, but rotation cannot hide a finite list.
The library will grow, only with movements that pass the same test, and I will not pad it to inflate a number.
- the founder"

**Product follow-up:**
Growing the movement library is the one roadmap item this theme legitimately accelerates; also verify the variety window is doing its job in real histories.

### Theme 12: "No Apple Watch / no widget / where's Android"

**Predicted review (hypothetical):**
"Great idea but no Watch app in 2026? No widget?
And my partner has Android so we can't use it together."

**Why we expect it.**
Missing Apple Watch support is a fetched Freeletics complaint theme (`competitor-freeletics.md`), and platform-gap reviews are routine for iOS-first apps; the product-facts brief confirms no Watch, no widgets, and no Android at MVP.

**Pre-written response:**
"All three are real gaps, so I will not spin them.
Today Rep Today is the iPhone app, full stop: no Watch app, no widget, no Android.
Finished sessions do write to Apple Health, so your workouts land on the Watch rings that way.
I would rather make the phone app excellent than ship three thin versions, and I will not promise dates I might miss.
When any of these exist, it will be in the update notes, not hinted at in a review reply.
Thanks for wanting it on more of your screens - that is the good kind of complaint.
- the founder"

**Product follow-up:**
Tally which platform gap is requested most; that ordering is real roadmap input even though no reply should promise it.

### Theme 13: "The trial will scam me / can't cancel"

**Predicted review (hypothetical):**
"Careful with the 'free trial', these fitness apps always convert to some charge you can't cancel.
Not falling for it again."

**Why we expect it.**
Mined evidence shows deep trial distrust: "it takes you to the screen to sign up for a free trial which then will charge you 4.99/week" (`review-mining.md`, [apps.apple.com/us/app/30-day-fitness-workout-at-home/id1099771240](https://apps.apple.com/us/app/30-day-fitness-workout-at-home/id1099771240)) and Freeletics reviewers reporting "they make it impossible to cancel and get a refund" (`competitor-freeletics.md`).
Some users will pre-emptively review the pricing model, not the app.

**Pre-written response:**
"Reasonable caution, the category earned it.
Three facts you can verify without trusting me.
First: the free tier is not a trial; every workout stays free forever whether or not you ever touch premium.
Second: the 14-day trial only exists on premium, which you have to deliberately choose.
Third: billing runs entirely through Apple, so cancelling is the standard Settings > Subscriptions flow that no developer can make difficult, and refunds go through Apple directly.
If you use the app and never see a charge, that is the system working as designed.
- the founder"

**Product follow-up:**
None on mechanics; ensure the paywall screen states the trial length and price with equal visual weight, since screenshots of it will end up in reviews.

---

## 3. Escalation rules

**Ship-a-fix-now (reply, then fix before the theme compounds):**

- Any crash, data loss, or workout history wipe.
- A workout or the core loop actually gated behind the paywall (violates the product's first promise).
- A sign-in prompt that blocks or appears to block the core loop.
- The Consistency Score resetting to zero or behaving like a streak.
- The Asymmetric Ramp failing to back off after a too-hard signal.
- Battery or thermal behavior beyond screen-on baseline.
- Trial or billing behavior that does not match the stated terms.

**Update-the-listing-copy (the product is right, the expectation was wrong):**

- Repeated "where are the trainer videos" reviews: the listing is over-signaling production value.
- Repeated "the AI is fake" reviews: the listing is over-signaling AI; promise policy tuning, not a coach.
- Repeated "thought free was a trial" reviews: state "free tier, not a trial" more plainly.
- Repeated "then it asked me to sign in" reviews: say "sign-in optional, for sync only" in the listing.
- Repeated surprise about no Watch/widget/Android: state the platform scope explicitly.

**Do-nothing-it's-the-design (reply with ownership, log it, change nothing):**

- Wants streaks, badges, XP, levels, or leaderboards.
- Wants a full workout builder or to hand-pick every exercise.
- Wants social features, challenges, or community.
- Wants equipment-based workouts.
- Wants to self-select into the Strength Phase before earning it.
- Wants an AI that generates the workout itself.

If a do-nothing theme dominates review volume for a sustained period, that is a positioning conversation for the founder, not a per-review decision.

---

## 4. What we never say

- Nothing defensive: no "actually, if you read the description", no rebuttals of star counts.
- Never blame the user: no "you're using it wrong", no "most users have no trouble with this."
- No fake agreement: do not say "great idea, we'll consider it!" about things the design forbids; own the choice instead.
- No health or medical claims, ever, including in replies: no calories, weight loss, pain relief, or body-composition outcomes.
- No feature promises or dates given to soften a rating.
- No corporate filler: "we apologize for any inconvenience", "your feedback is important to us", "please reach out to support" as a brush-off.
- No streak/badge/XP language, even as praise or consolation.
- No arguing that a 1-star should have been higher, and no asking anyone to change or remove a review.
- No mocking the user's fitness level or current state, even gently.
- No em dashes, no emojis, no exclamation-point enthusiasm.
