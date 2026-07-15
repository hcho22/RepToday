# Pitch 1: Friction Is the Enemy

Angle: the one-tap moment is the product.
Every workout app in the field makes you do work before you can do work.
Rep Today's mechanical wedge is that it does not.

## 1. Positioning statement

For busy, desk-bound adults who keep skipping movement because starting a workout takes too many steps, Rep Today is the iOS app that opens to a complete bodyweight session with one dominant Start button.
Unlike catalog apps that make you browse (Peloton, Nike Training Club, Apple Fitness+) and configure-first generators that interview you before you can move (Down Dog, Freeletics), Rep Today never asks a single question between opening the app and starting.
It can make that promise because a deterministic engine builds every session on your phone, offline, in under 100 milliseconds, so there is no server, no login, no quiz, and no paywall standing between you and your first rep.

## 2. ICP

**"9pm Priya."**
[ASSUMPTION] The persona is a marketing construct; the product has zero users and no interview data.
Every behavioral detail below is an inference from the product brief's target ("a tired parent at 9pm, not a gym rat") and cited third-party evidence, not from real customers.

Priya is a mid-30s to mid-40s product manager or engineer with young kids and a calendar with no gym-shaped hole in it.
Her windows to move are 9pm after the kids are down, 7am in a hotel room on a work trip, and the odd 10 minutes between calls.
Each window is small, unpredictable, and easily lost: by the time she has picked a class, answered a quiz, or waited for a video to buffer, the window has closed or her will has.

What she has tried:
a class-catalog app where she scrolled instead of moving, a generated-workout app that wanted an account and settings before showing anything, and free YouTube videos that start with two minutes of talking.
There is direct demand-side evidence for exactly her ask: "I suffer from moderate ADHD and need an app that requires little decision-making. Big buttons, pre-programmed workouts ... No, I need the app to tell me exactly what to do," with offline functionality in the same requirements list ([hn.algolia.com/api/v1/items/36666806](https://hn.algolia.com/api/v1/items/36666806)).
And there is in-category evidence of the friction she is fleeing: "excessive scrolling, multiple clicks to get to something" ([Centr App Store reviews](https://apps.apple.com/us/app/centr-strength-fitness-app/id1382530817)).

When she uses Rep Today: the moment a window opens.
She opens the app, a session at her learned duration is already on screen, and she presses Start.
That is the entire interaction model, and it is why she keeps the app.

## 3. Name recommendation: keep Rep Today

Back the incumbent.
No research finding justifies paying the switching cost of a completed identifier migration, and several findings actively favor the name.

**Collision profile is the cleanest of the researched candidates.**
A US App Store search for "rep today" surfaced no app named "Rep Today" or a close variant, and only one unrelated Health & Fitness result ([iTunes Search API](https://itunes.apple.com/search?term=rep+today&entity=software&country=US&limit=15)).
The "Rep" prefix is crowded with gym-logging trackers (RepCount, RepCounter Pro, and others), but none use "Today," so the full name reads distinct ([iTunes Search API](https://itunes.apple.com/search?term=rep+count&entity=software&country=US&limit=10)).
Compare the alternatives: Cairn has a direct same-category App Store collision ("Cairn - Hiking Safety Tracker," live in Health & Fitness), and Stack is saturated, with the exact name owned by a 56k-rating game and Stack Sports owning the sports-tech web presence (all per [name-collisions.md](../../01-research/name-collisions.md) sources).

**Positioning fit is unusually strong for this angle.**
"Rep Today" is not a noun, it is an instruction, and the instruction is the product's entire UX: do a rep, today.
A friction-as-the-enemy positioning gets a name that is itself the call to action, two words, four syllables, nothing to configure.

**Domains and handles lean available.**
reptoday.app returned NXDOMAIN, a strong availability signal ([dns.google](https://dns.google/resolve?name=reptoday.app&type=NS)); github.com/reptoday returned 404 ([github.com/reptoday](https://github.com/reptoday)).
reptoday.com is a $3,895 buy-now at HugeDomains if the founder later wants it ([HugeDomains](https://www.hugedomains.com/domain_profile.cfm?d=reptoday.com)); the .app domain is sufficient at launch.

**Known risks, stated plainly.**
REP Fitness (repfitness.com) is a large home-gym equipment brand that owns "REP" mindshare in fitness web search; it sells racks and barbells, not apps, but it is the main web collision ([repfitness.com](https://www.repfitness.com)).
X/Twitter and Instagram handle status is unverified (login walls blocked checks).
**Trademark and App Store name clearance are UNVERIFIED for Rep Today and for every candidate in the research.**
A USPTO search (ideally with counsel) and an App Store Connect name reservation are required before this recommendation is final; that caveat applies equally to Cairn, Stack, or any new name, so it is not a reason to switch.

## 4. App Store listing name and subtitle

- Listing name: **Rep Today, Rest Tomorrow** (24 characters, under the 30-char limit).
- Subtitle: **Opens to a ready workout** (24 characters, under the 30-char limit).

Keep the planned listing name.
It is memorable, identity-framed, and already decided; the subtitle is where this positioning earns its keep.
"Opens to a ready workout" states the mechanical wedge in plain words, carries the "workout" keyword for search, and is a claim no researched competitor can copy truthfully: Down Dog is configure-first and login-mandatory, Freeletics front-loads a multi-question onboarding, Apple Fitness+ is a browse catalog, and even Wakeout, the lowest-friction app found in the research, still asks outcome, location, and position before starting ([competitors-additional.md](../../01-research/competitors-additional.md)).

## 5. Hero message

**Headline (8 words):**
Open the app. Your workout is already there.

**Subhead (21 words):**
A full bodyweight session, built on your phone in under 100 milliseconds. No questions, no account, no internet needed. Press Start.

## 6. Messaging hierarchy

**Pillar 1: It opens ready. Nothing to answer, nothing to pick.**
Claim: there are zero questions between opening the app and starting a session.
Proof: the app opens to a complete, pre-generated session at your learned Default Duration with one dominant Start button; it never asks "how long do you have?" before Start; the AI is never on the path between opening the app and starting (product-facts-brief.md).
Demand evidence: the verbatim ask for an app "that requires little decision-making ... tell me exactly what to do" ([hn.algolia.com/api/v1/items/36666806](https://hn.algolia.com/api/v1/items/36666806)) and the in-category complaint about "excessive scrolling, multiple clicks to get to something" ([Centr reviews](https://apps.apple.com/us/app/centr-strength-fitness-app/id1382530817)).
Sample line: "You do not pick a workout. It is on screen when the app opens."

**Pillar 2: Change one thing, in one tap, without starting over.**
Claim: the only decision that exists is optional, and it costs one tap.
Proof: duration is a non-blocking chip (5 to 60 minutes) that regenerates the whole session in under 100 milliseconds; adjusting it never blocks the Start button (product-facts-brief.md).
Sample line: "Got 20 minutes instead of 10? One tap. The new session is there before your thumb lifts."

**Pillar 3: It works where you are, with what you have. Which is nothing.**
Claim: every session runs offline and needs only a floor and a wall.
Proof: sessions are generated on-device, deterministically, offline, in under 100 milliseconds; every movement in the 42-movement library passes the hotel room test; no account is required (product-facts-brief.md).
Honesty note: review mining found no direct complaint evidence about connectivity or bloated video, so this pillar is stated as a product fact, never as a claimed market pain (review-mining.md, Theme D).
Sample line: "Airplane mode, hotel room, basement with no bars. The session builds on your phone, not on a server."

**Pillar 4: The paywall is friction too. It is not in your way.**
Claim: you will never hit a paywall between opening the app and pressing Start.
Proof: the free tier is unlimited workouts forever; premium unlocks depth (deeper analytics, Strength Phase), never the core loop (product-facts-brief.md).
Evidence this friction is real and hated in-category: "you cannot use this app unless you pay for it. You just can't." ([30 Day Fitness reviews](https://apps.apple.com/us/app/30-day-fitness-workout-at-home/id1099771240)) and "the app won't do anything until you sign up for the free trial" ([hn.algolia.com/api/v1/items/39991813](https://hn.algolia.com/api/v1/items/39991813)).
Competitive caveat kept honest: this wedge works against paywalled apps, not against Nike Training Club, whose free tier is genuinely praised (review-mining.md, Theme E).
Sample line: "Free means the workouts. All of them. Forever."

## 7. Three sample headlines for ads and social

1. "Open the app. Press Start. That was the onboarding."
2. "It never asks how long you have. A session is already on screen when you open it."
3. "No signal, no equipment, no account. Your session still builds in under 100 milliseconds."

## 8. What this positioning deliberately gives up

**It concedes the customizers.**
Zero-decision positioning will repel users who want to edit their sessions, and that objection is documented: Freeletics reviewers complain about "not being able to customize the workouts" and "no option to simply swap out or modify a specific exercise" ([Freeletics reviews](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)).
We accept losing them; they are not the ICP.

**It demotes the forgiveness story.**
The Consistency Score, the Return, and the Re-entry Ramp are genuinely differentiated mechanics, and this positioning spends almost nothing on them.
Streak-anxiety positioning is also already contested ground: HN searches show builders marketing "no streak anxiety" today (review-mining.md, Theme B), so leading with friction cedes that fight to others but also avoids a crowded claim.

**It hides the training depth.**
The three pillars, the Asymmetric Ramp, and the earned Strength Phase barely appear.
A user who converts on "it opens ready" must discover the substance inside the app, which puts weight on retention surfaces this positioning does not control.

**Its headline mechanic is partially imitable.**
"Under 100 milliseconds" is defensible only through architecture (on-device deterministic generation); a competitor could fake perceived instant-open with caching, and a judge should know we know that.
The durable moat is the full stack of the claim: instant, offline, question-free, and never paywalled at once, which the research shows no competitor currently combines (competitors-additional.md).

**It has a low emotional ceiling.**
There is no community, no transformation arc, no instructor charisma to sell.
Against Peloton-grade emotional marketing, this positioning bets everything on relief being a stronger first-session emotion than aspiration, and that bet is unproven with zero users.

**It states the offline claim without complaint-side evidence.**
Review mining ranked connectivity pain as the weakest theme, so offline appears here as a fact inside Pillar 3, never as a lead claim, and we give up whatever conversion a connectivity-pain campaign might have delivered.
