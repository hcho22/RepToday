# EVERGREEN E - "The workout is decided on your phone." (how it decides)

Evergreen rotation post. The under-the-hood explainer: a deterministic engine builds
the session on the device, picks the movements by staleness and earned progression,
learns the duration you finish, and never reaches a server to do any of it.
Not pinned; re-postable whenever the rotation calls for it.

Claim discipline for this one in particular: every mechanic here is checked against the
shipped Swift engine, row by row in ../claim-verification.md. It carries no speed figure
and no movement count on any slide, by rule; the point it makes is where the deciding
happens and how, not how many milliseconds it takes.

## Caption

The workout is decided on your phone.

Something has to choose the session. Here it is a fixed engine, not a call to a server: the session is assembled by a deterministic engine that runs entirely on the phone. Give it the same day and the same history, and it builds the same session again.

It leads with the pattern you have neglected most, tracking which movement patterns you have worked and how recently, and never repeating the pattern your last session led with.

It moves you up only when you have earned it. Inside each pattern it picks the exercise that matches what you have actually done, and offers the next step up only after you clear the one you are on, one tier at a time. The count is what you already sustain, never a heroic number picked to impress you.

And it notices the length you actually finish. You tell it once how long you usually have; after that it watches the sessions you complete, not the ones you request, and drifts the default toward the length you really do.

Nothing leaves the phone to build a workout. The whole movement library ships inside the app, so the session builds with the phone offline exactly as it does online. By the time you open it, the choosing is over.

iOS, not released yet. Link in bio.

## Hashtags

#buildinpublic #indiedev #ondevice #offlinefirst #bodyweightworkout #homeworkout #indieapp

## Alt text

**Slide 1.** The Rep Today Ready Mark, a green outlined rounded square with a filled circle low inside it, sits small in the top left of a warm off-white card. Below a short green rule, large dark type reads: "The workout is decided on your phone." The word "Swipe" sits quietly at the bottom left.

**Slide 2.** A small green label at the top reads "What does the choosing". Large dark type reads: "A fixed engine, not a call to a server." Below it: "The session is assembled by a deterministic engine that runs entirely on the phone. Give it the same day and the same history and it builds the same session again. It is not fetched, not generated in the cloud, and not returned by any request."

**Slide 3.** A small green label at the top reads "How it picks the moves". Large dark type reads: "It leads with the pattern you have neglected most." Below it: "The engine tracks which movement patterns you have worked and how recently, then leads with the one you have left alone longest, and never repeats the pattern your last session led with."

**Slide 4.** A small green label at the top reads "How hard it goes". Large dark type reads: "It moves you up only when you have earned it." Below it: "Inside each pattern it picks the exercise that matches what you have actually done, and offers the next step up only after you clear the one you are on, one tier at a time. The count is what you already sustain, never a heroic number picked to impress you."

**Slide 5.** A small green label at the top reads "It learns your habit". Large dark type reads: "It notices the length you actually finish." Below it: "You tell it once how long you usually have. After that it watches the sessions you complete, not the ones you request, and drifts the default toward the length you really do. The screen opens where you tend to land."

**Slide 6.** A small green label at the top reads "What leaves the phone". Large dark type reads: "Nothing leaves the phone to build a workout." Below it: "No account, no signal, and no server sit in the path. The entire movement library ships inside the app, and the engine reads it on the device, so the session builds with the phone offline exactly as it does online."

**Slide 7.** Closing card. Large dark type reads: "By the time you open it, the choosing is over." Below it: "A session is already on the screen because the engine built it on the phone first. No menu waits for you, because the deciding already happened." At the bottom, the Ready Mark beside the words "Rep Today", then the line "iOS, not released yet.", then small grey legal type: "Pre-launch. 'Rep Today' has not been trademark-searched or registered, and the App Store name has not been reserved."
