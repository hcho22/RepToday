# ASO Keyword Landscape - Rep Today (iOS, US storefront)

Research run: 2026-07-15, fetch window 04:18-04:21 UTC.
Method: since no paid ASO tool is available, all ranking evidence comes from the public iTunes Search API (`itunes.apple.com/search`, country=US, entity=software), which returns Apple's real relevance-ranked results for a query, plus fetched `apps.apple.com` listing pages for exact titles, subtitles, ratings, and category chart positions.
Hard limitation stated up front: this method shows who ranks and what metadata they use, but gives zero search-volume data; every volume statement below is labeled [ASSUMPTION].
The iTunes Search API's relevance ranking approximates but is not guaranteed to be identical to in-app App Store search ranking.

## TL;DR

"Home workout" and "7 minute workout" are the most crowded phrases: the leaders have 118K-530K ratings, near-perfect 4.8-4.9 stars, and at least five apps carry the literal string "7 Minute Workout" in their title.
"Workout planner" is owned by gym/barbell apps (Fitbod, Hevy, Strong) and is the wrong intent for Rep Today.
"Micro workout" is near-empty whitespace: the only two apps ranking for it as a title phrase have too few ratings for the App Store to even display a score.
Recommended listing: title "Rep Today, Rest Tomorrow" (24 chars, brand-only), subtitle "No Equipment Micro Workouts" (27 chars), and a 94-char keyword field covering bodyweight, quick, daily, mobility, and minute-duration terms.
(Superseded by D-106: the listing title is now plain "Rep Today" and the subtitle is "Opens to a ready workout"; see `../02-brand/naming-decision.md`. The ranking evidence below still stands as researched.)

## Who ranks for what (all listings fetched 2026-07-15)

### "home workout" and "no equipment workout" - worst crowding

Top relevance results for "home workout" were Leap Health's portfolio plus a cluster of look-alikes ([search fetch](https://itunes.apple.com/search?term=home+workout&country=US&entity=software&limit=10)); "no equipment workout" returned largely the same apps ([search fetch](https://itunes.apple.com/search?term=no+equipment+workout&country=US&entity=software&limit=10)).

- **Home Workout - No Equipments** / subtitle "Bodyweight Fitness & Training" - 4.9 stars, 118K ratings, #60 in Health & Fitness on fetch day ([listing](https://apps.apple.com/us/app/home-workout-no-equipments/id1313192037)).
- **Workout for Women: Home & Gym** / "Workout Planner, Weight Loss" - 4.8 stars, 530K ratings ([listing](https://apps.apple.com/us/app/workout-for-women-home-gym/id839285684)).
- **Home Workout for Men** / "AI Fitness, Workout Planner" - 4.9 stars, 9.3K ratings ([listing](https://apps.apple.com/us/app/home-workout-for-men/id1323917721)).
- **JustFit: Lazy Workout & Fit** / "Female Fitness and Exercise" - 4.8 stars, 213K ratings, #139 in Health & Fitness ([listing](https://apps.apple.com/us/app/justfit-lazy-workout-fit/id1574460221)).

Note the incumbent's title uses the nonstandard plural "No Equipments"; the exact singular phrase "no equipment" is less title-saturated, though a smaller app "Home Workout No Equipment." by Shred Apps also ranked in the fetched results.

### "7 minute workout" - name-squatted to death

The query returned at least seven apps with the literal phrase in their title ([search fetch](https://itunes.apple.com/search?term=7+minute+workout&country=US&entity=software&limit=10)).

- **7 Minute Workout** (Bytesize) / "HIIT Bodyweight Home Workouts" - 4.8 stars, 14K ratings ([listing](https://apps.apple.com/us/app/7-minute-workout/id650762525)).
- **Seven: 7 Minute Workout** (Perigee) / "Daily HIIT Bodyweight Exercise" - 4.8 stars, 137K ratings, badged Editors' Choice ([listing](https://apps.apple.com/us/app/seven-7-minute-workout/id650276551)).

### "quick workout" and "daily workout"

No fetched title contains the literal phrase "quick workout"; the query resolves to the 7-minute cluster plus Sworkit and Daily Workouts ([search fetch](https://itunes.apple.com/search?term=quick+workout&country=US&entity=software&limit=10)).
"Daily workout" is effectively owned by the Daily Workout Apps, LLC portfolio ([search fetch](https://itunes.apple.com/search?term=daily+workout&country=US&entity=software&limit=10)): **Daily Workouts - Home Fitness** / "Workout Routines & Exercises", 4.7 stars, 44K ratings ([listing](https://apps.apple.com/us/app/daily-workouts-home-fitness/id469068059)).
**Sworkit Fitness & Wellness App** / "Home Workouts, Stretches, Yoga" - 4.7 stars, 30K ratings ([listing](https://apps.apple.com/us/app/sworkit-fitness-wellness-app/id527219710)).

### "bodyweight"

Ranked results mix Leap, the 7-minute apps, and big brands ([search fetch](https://itunes.apple.com/search?term=bodyweight+workout&country=US&entity=software&limit=10)).
"Bodyweight" appears in the subtitles of three leaders (Leap, Seven, Bytesize) but in the title of only niche apps (Stark Bodyweight, Bodyweight by Mark Lauren) in the fetched results.
**Nike Training Club** / "Training and Workouts" - 4.8 stars, 279K ratings, #117 in Health & Fitness, free ([listing](https://apps.apple.com/us/app/nike-training-club/id301521403)).
**Freeletics: Workouts & Fitness** / "Home & Gym AI Coach, Planner" - 4.6 stars, 22K ratings ([listing](https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212)).

### "stretching" and "mobility"

Both queries surface the same specialist cluster ([stretching fetch](https://itunes.apple.com/search?term=stretching&country=US&entity=software&limit=10), [mobility fetch](https://itunes.apple.com/search?term=mobility&country=US&entity=software&limit=10)).

- **Bend: Stretching & Flexibility** / "Daily Yoga, Stretch & Mobility" - 4.8 stars, 171K ratings, #62 in Health & Fitness ([listing](https://apps.apple.com/us/app/bend-stretching-flexibility/id1513988468)).
- **pliability: Stretch & Mobility** / "Flexibility, Recovery & Relief" - 4.8 stars, 9.7K ratings ([listing](https://apps.apple.com/us/app/pliability-stretch-mobility/id1175346453)).
- **GOWOD – Mobility & Stretching** / "Mobility For All Your Sports" - 4.8 stars, 3.3K ratings ([listing](https://apps.apple.com/us/app/gowod-mobility-stretching/id1227834875)).

Every ranked mobility app is mobility-only; none of the fetched general workout leaders put "mobility" in title or subtitle except Bend (a stretching app).

### "workout planner" - wrong intent

Results are gym-tracker apps: Fitbod, Gymverse, Strong, Hevy, Gymshark ([search fetch](https://itunes.apple.com/search?term=workout+planner&country=US&entity=software&limit=10)).
Rep Today deliberately never asks the user to plan, so competing here would misposition the app.

### "micro workout" - the whitespace

Only two apps rank with the phrase in their title ([search fetch](https://itunes.apple.com/search?term=micro+workout&country=US&entity=software&limit=10)), and both show "hasn't received enough ratings" on their listing pages:

- **Bare Minimum : Micro Workouts** / subtitle "Move 90 seconds. That's it." ([listing](https://apps.apple.com/us/app/bare-minimum-micro-workouts/id6759055696)).
- **1Hundred - micro workout** / "Your micro workout companion" ([listing](https://apps.apple.com/us/app/1hundred-micro-workout/id1538015864)).

[ASSUMPTION] "micro workout" likely has low search volume today precisely because no successful app has trained users to search it; treat it as a differentiator with growth optionality, not a traffic source.
(A fetch of the old Wakeout listing URL returned HTTP 404, so no claims are made about it.)

## Mapping Rep Today's honest attributes to underused phrasing

- **Opens to a ready workout**: no fetched competitor expresses this in metadata at all; it is a screenshot/description message, not an indexed keyword, because [ASSUMPTION] nobody searches "opens ready".
- **5-60 min sessions**: "7 minute" is saturated; "quick" and "5 minute" appear in no fetched title, so pair "quick"/"minute"/"5" from the keyword field with subtitle words.
- **No equipment**: incumbent title says "No Equipments"; the correct singular "No Equipment" in a subtitle is honest, exact-match, and less title-crowded.
- **Mobility included**: putting "mobility" in the keyword field lets Rep Today rank for a combo (workout app that includes mobility) that no fetched generalist owns.
- **Forgiving consistency**: [ASSUMPTION] "consistency" is not a fitness search term with meaningful volume; keep it for brand copy, not metadata.

## Recommended listing metadata

(This section records the 2026-07-15 recommendation; the listing name was later reduced to plain "Rep Today" by D-106, see `../02-brand/naming-decision.md`.)

**Title (24/30 chars): `Rep Today, Rest Tomorrow`**
The name already contains "Rep", a real training word, and only 6 characters remain, too few for any meaningful keyword suffix, so keep the title brand-only.

**Subtitle (27/30 chars): `No Equipment Micro Workouts`**
Reasoning: "workouts" is the indispensable head term; "no equipment" is the strongest honest differentiator with exact-singular phrasing the incumbent's title lacks; "micro" claims the whitespace category before Bare Minimum or 1Hundred can, and is truthful for 5-minute sessions.
Fallback if "micro" tests poorly: `Bodyweight Workouts, Mobility` (29 chars), which trades the whitespace bet for two proven subtitle terms.

**Keyword field (94/100 chars):**
`bodyweight,quick,daily,home,mobility,stretching,minute,hiit,exercise,routine,busy,travel,men,5`
[ASSUMPTION] Standard ASO practice (not verifiable via any page fetched in this run) holds that Apple combines title, subtitle, and keyword-field terms into phrases, so this set aims to form "quick workouts", "5 minute workouts", "daily bodyweight workouts", "home workouts no equipment", and "mobility workouts" without repeating any subtitle word.
"hiit" is included because three fetched leaders use it in subtitles; drop it if the team feels it misdescribes the product's pace.

**What not to chase**: "workout planner" (gym-tracker intent), "7 minute workout" (name-squatted, and Rep Today is not a fixed 7-minute app), "weight loss" (banned by the no-health-claims rule).

**Volume caveat, repeated**: with no ASO tool, all prioritization above is based on who ranks and how strong they are (ratings counts from 0 to 530K across fetched listings), not on measured search volume; validate with Apple Search Ads keyword popularity scores (free with an ASA account) before locking metadata.

## Sources

All URLs below were fetched successfully with WebFetch during this run (window 2026-07-15T04:18:42Z to 2026-07-15T04:20:34Z; per-URL timestamps at minute precision).

| URL | Fetched (UTC) | Substantiates |
| --- | --- | --- |
| https://itunes.apple.com/search?term=home+workout&country=US&entity=software&limit=10 | 2026-07-15T04:18Z | Ranked results for "home workout" |
| https://itunes.apple.com/search?term=no+equipment+workout&country=US&entity=software&limit=10 | 2026-07-15T04:18Z | Ranked results for "no equipment workout", incl. Shred Apps title |
| https://itunes.apple.com/search?term=bodyweight+workout&country=US&entity=software&limit=10 | 2026-07-15T04:18Z | Ranked results for "bodyweight workout" |
| https://itunes.apple.com/search?term=7+minute+workout&country=US&entity=software&limit=10 | 2026-07-15T04:18Z | Seven-plus apps titled "7 Minute Workout" |
| https://itunes.apple.com/search?term=quick+workout&country=US&entity=software&limit=10 | 2026-07-15T04:19Z | No literal "quick workout" titles in results |
| https://itunes.apple.com/search?term=stretching&country=US&entity=software&limit=10 | 2026-07-15T04:19Z | Stretching specialist cluster |
| https://itunes.apple.com/search?term=mobility&country=US&entity=software&limit=10 | 2026-07-15T04:19Z | Mobility specialist cluster |
| https://itunes.apple.com/search?term=daily+workout&country=US&entity=software&limit=10 | 2026-07-15T04:19Z | Daily Workout Apps LLC dominance |
| https://itunes.apple.com/search?term=workout+planner&country=US&entity=software&limit=10 | 2026-07-15T04:19Z | Gym-tracker intent of "workout planner" |
| https://itunes.apple.com/search?term=micro+workout&country=US&entity=software&limit=10 | 2026-07-15T04:20Z | "micro workout" whitespace |
| https://apps.apple.com/us/app/home-workout-no-equipments/id1313192037 | 2026-07-15T04:19Z | Title/subtitle, 4.9 stars, 118K ratings, #60 H&F |
| https://apps.apple.com/us/app/seven-7-minute-workout/id650276551 | 2026-07-15T04:19Z | Title/subtitle, 4.8 stars, 137K ratings, Editors' Choice |
| https://apps.apple.com/us/app/7-minute-workout/id650762525 | 2026-07-15T04:19Z | Title/subtitle, 4.8 stars, 14K ratings |
| https://apps.apple.com/us/app/justfit-lazy-workout-fit/id1574460221 | 2026-07-15T04:19Z | Title/subtitle, 4.8 stars, 213K ratings, #139 H&F |
| https://apps.apple.com/us/app/bend-stretching-flexibility/id1513988468 | 2026-07-15T04:19Z | Title/subtitle, 4.8 stars, 171K ratings, #62 H&F |
| https://apps.apple.com/us/app/pliability-stretch-mobility/id1175346453 | 2026-07-15T04:19Z | Title/subtitle, 4.8 stars, 9.7K ratings |
| https://apps.apple.com/us/app/daily-workouts-home-fitness/id469068059 | 2026-07-15T04:20Z | Title/subtitle, 4.7 stars, 44K ratings |
| https://apps.apple.com/us/app/sworkit-fitness-wellness-app/id527219710 | 2026-07-15T04:20Z | Title/subtitle, 4.7 stars, 30K ratings |
| https://apps.apple.com/us/app/nike-training-club/id301521403 | 2026-07-15T04:20Z | Title/subtitle, 4.8 stars, 279K ratings, #117 H&F, free |
| https://apps.apple.com/us/app/freeletics-workouts-fitness/id654810212 | 2026-07-15T04:20Z | Title/subtitle, 4.6 stars, 22K ratings |
| https://apps.apple.com/us/app/gowod-mobility-stretching/id1227834875 | 2026-07-15T04:20Z | Title/subtitle, 4.8 stars, 3.3K ratings |
| https://apps.apple.com/us/app/home-workout-for-men/id1323917721 | 2026-07-15T04:20Z | Title/subtitle, 4.9 stars, 9.3K ratings |
| https://apps.apple.com/us/app/workout-for-women-home-gym/id839285684 | 2026-07-15T04:20Z | Title/subtitle, 4.8 stars, 530K ratings |
| https://apps.apple.com/us/app/bare-minimum-micro-workouts/id6759055696 | 2026-07-15T04:20Z | Micro-workout entrant, no displayed rating |
| https://apps.apple.com/us/app/1hundred-micro-workout/id1538015864 | 2026-07-15T04:20Z | Micro-workout entrant, no displayed rating |

Failed fetch (no claims made from it): https://apps.apple.com/us/app/wakeout-active-breaks/id1441973160 returned HTTP 404 at 2026-07-15T04:20Z.
