# Red team v2 - cynical target user

Persona: 41, desk job, two kids, quit four fitness apps, scrolling TikTok at 9:47pm.
I owe this package nothing.
Assets reviewed: 05-social-pmf/week-1-drafts.md, 05-social-pmf/ab-pairs.md, 02-brand/positioning.md hook bank, 03-site/screenshot-a-mobile-390x844.png, 03-site/screenshot-b-mobile-390x844.png, 04-video/frame-strip.png, 02-brand/gate-test-asset-v2.png, 09-extras/app-store-screenshots/01-ready-screen.png, 04-consistency.png, 05-free-forever.png.

One thing stated up front because the brief asked: I hunted for copy that shames me and found none.
Nothing in these drafts mocks my current state or frames a miss as my failure.
That guardrail held everywhere I looked.

---

## 1. MUST-FIX - week-1-drafts.md, Day 2, shot list items 1-2 and caption ("months of research", "I read hundreds like it")

The founder says on camera "the most common complaint about workout apps I found in months of research" and the caption says "I read hundreds like it before building."
Both are first-person factual claims the package cannot verify, and the package's own timeline undercuts them: the product PRD is dated July 2026 and the research fetches in this repo are dated 2026-07-15 to 2026-08-01, which is weeks, not months.
Under the truth policy (no invented stats, every factual claim sourced) an unverifiable "hundreds" and a probably-false "months" are exactly the kind of rounded-up founder flex I have learned to smell, and the moment I smell it I stop believing the free-forever promise that follows it.
Smallest honest fix: cut the tenure and the count - "This is the most common complaint in the App Store reviews and threads I researched before building" and "That review is real; I read a lot like it" - unless the founder can personally attest to both numbers, in which case cite where the count lives.

## 2. MUST-FIX - 03-site/screenshot-a-mobile-390x844.png and screenshot-b (first viewport at 390x844)

Positioning.md says "the hero visual is the mechanic itself" and "the demo is the proof," but on the actual 390x844 render the phone mock is cut off at the fold showing only the word "TODAY."
What I get in my 8-second skim is a good headline followed by a six-line subhead, a bold proof box that repeats half the subhead ("offline" and "no account" appear in both), and a status line - a text wall where the demo should be.
I quit four of these apps; text does not move me, the screen doing the thing might.
Smallest honest fix: tighten the subhead to two lines, deduplicate it against the proof box, and raise the phone mock so the session list and the Start button are visibly peeking inside the first viewport.

## 3. MUST-FIX - 09-extras/app-store-screenshots/04-consistency.png ("Today you showed up. That's the whole game.")

Positioning.md records that the pitch-3 headline "Showing up is the whole game" was killed by the differentiation judge for a word-level collision with a live Jillian Michaels ad ("All you have to do is show up").
This App Store screenshot ships "Today you showed up. That's the whole game." - the killed phrase, lightly rearranged, on a public marketing surface.
As a scroller I have literally seen the celebrity-trainer version of this line in an ad, so it reads borrowed, and internally it re-ships copy a judge already struck.
Smallest honest fix: reword the caption to the mechanic, e.g. "Tuesday off. Today counted in full." - the surrounding UI already carries the meaning.

## 4. SURVIVING-OBJECTION - week-1-drafts.md (all seven days) and positioning.md pillar 1: "no questions" reads as "not built for me"

Every no-questions line lands on my ear as "same generic workout for everyone," and generic is one of the four reasons I quit apps.
I am 41 with a desk body; my first question at the hook is "how does it know what I can do?" and nothing in week 1 answers it, even though the product brief has the answer (capped gentle cold start, asymmetric ramp that backs off when a session was too hard).
The day-1 pinned comment even asks me "would you use an app that never asks how long you have?" - wrong question; I never cared about being asked, I care that the workout fits me.
Carry this visibly: the no-questions promise is the strategy and should stay, but the package should admit in writing that it leaves "will this wreck my knees / bore me" unanswered for week 1, and the first "it starts easy and adjusts without asking" angle should be queued, not left implicit.

## 5. SURVIVING-OBJECTION - week-1-drafts.md Day 2 and 05-free-forever.png: "Forever" from an app that does not exist yet

"Free. All of them. Forever." from a solo developer with zero users and no App Store listing trips my nothing-is-free reflex a specific way: not "where's the catch" (the paid-depth line answers that honestly) but "you cannot promise forever, you might not exist in a year, and indie apps change their pricing the week they get traction."
No copy edit fixes this because the objection is true; it is a promise only time can verify.
Carry it visibly rather than paper over it: the strongest available move is the founder acknowledging on camera that a pre-launch promise is only a bet, which day 2 gestures at ("I want to know if that promise matters to you") but never quite says.

## 6. SURVIVING-OBJECTION - week-1-drafts.md Days 4 and 6: founder lines written like taglines, not speech

"You are someone who moves, not someone who owes," "That is the bet," "That is the whole design," "Five minutes counts as a full show-up. Coming back is the win."
No tired person talking into a phone camera at home says these sentences; they are brand poetry, and delivered verbatim they will read rehearsed, which on TikTok reads as ad.
The founder-on-camera rule exists to make first-person claims credible, and scripted slogan delivery spends exactly that credibility.
Carry it as direction: keep the meaning, let the founder paraphrase in their own broken sentences, and accept that the take where they fumble slightly is the one that posts.

## 7. SURVIVING-OBJECTION - 03-site both screenshots: the skim survives but the page is a dead end

"Rep Today is pre-launch. No waitlist, nothing to reserve." means the page ends with nothing for me to do, so I close the tab at 9:48pm and will never find this app again.
That is an honest consequence of the no-publish guardrails, but it should be carried as a known cost of the current package, not treated as a finished page.
It also sits inconsistently next to 02-brand/gate-test-asset-v2.png, which says "TestFlight beta for iOS - opening soon" and "The first TestFlight builds go out soon" - two different statuses for the same product across two assets; one of them should be made true everywhere.

## 8. SURVIVING-OBJECTION - 05-free-forever.png Premium card: "The Strength Phase, once you earn it"

To a cynic this line says I pay $7.99 a month AND still have to earn the feature, which is a worse deal than a plain paywall because I might pay and never qualify.
I understand the design intent from the product brief (earned progression is the point), but on a store screenshot with zero surrounding explanation it reads as pay-plus-homework.
Carry it, but know that this exact line will generate "so I pay to maybe get it?" comments, and decide in advance whether the answer lives in the screenshot caption or the replies.

## 9. NOTE - ab-pairs.md AB-1 / week-1-drafts.md Day 1 hook: "Most workout apps open with a question"

I disengage at roughly 0.8 seconds, on the word "Most" - "Most X do Y, ours does Z" is the oldest ad template on the platform and it flips my ad detector before the demo starts.
Leg B ("Open the app. The workout is already there.") does not trip it because it describes a thing instead of dunking on a category.
The package already tests exactly this in AB-1, which is the right move; this persona pre-registers a prediction that B wins.

## 10. NOTE - week-1-drafts.md Day 5 (airplane mode): the hook I scroll past hardest

Airplane mode means nothing to me at 9:47pm on my couch; I am not the hotel-room traveler, and "offline" sounds like a spec, not a feeling.
I disengage around second 2, while the Control Center is still on screen and no workout has appeared.
Day 2 (someone reading an angry review is drama, I stay) and Day 3 (the dip-not-reset chart is concrete, I stay) are the two that hold me; Day 4's hook loses me at "my app" in second 1 because "my app" equals promo.

## 11. NOTE - week-1-drafts.md Day 2 shot 1: the review is dated 2020 on screen

Showing "Real App Store review of a fitness app, 2020" in a 2026 video invites the top comment "you had to go back six years for that?"
The attribution honesty is right and required; consider whether a comparably brutal recent review exists in the mined set so the date works for the video instead of against it.

## 12. NOTE - 09-extras/app-store-screenshots/01-ready-screen.png next to the "no questions" copy

The hero screenshot prominently shows a "Session length, minutes" chip row with seven options directly under marketing that says the app never asks a question.
I know the chips are optional and non-blocking, but a scroller does not; expect "that's literally a question" comments wherever this screenshot and that claim appear together, and keep the "one-tap, never blocks Start, session already built" explanation ready.

## 13. NOTE - 04-video/frame-strip.png frames 2 and 4

The "Strength. Mobility. Primal." card and the closing Rep Today card are near-illegible dark-grey-on-black in the strip.
If these are mid-fade sample frames the strip is fine; if the actual title cards render at this contrast, they are invisible on a phone in a bright room and need a contrast pass before the video is cut.

---

Not manufactured to quota: I looked for bro-register, loss-framing, shame copy, invented engagement, and health claims and found none; the guardrails visibly shaped these drafts.
The "full show-up" phrase recurs five-plus times across the week and reads as invented app-speak, but it is harmless and I could not make it a real objection.
