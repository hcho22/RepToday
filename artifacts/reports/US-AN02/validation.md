# US-AN02: Coach narrates the analytics (integration) - validation

**Story:** As a premium user, I want the coach to interpret my analytics and offer to act, so the data changes my behavior instead of being a chart I ignore.

The deterministic, testable half of this story is proved by the unit suites; the OpenAI `gpt-5.6-luna` narration prose itself is captain-verifiable manual QA (the Coach proxy is not deployed, so every shipped build is inert). These PNGs are reviewer-visible evidence that the offer surface narrates a concrete insight and routes an action through the bounded US-AC07 policy path - never a workout edit.

## What the evidence shows

### 01-coach-analytics-offer.png
The `CoachAnalyticsInsightView` card in isolation. It narrates a concrete insight ("Your push is climbing, but your hinge has been flat about 3 weeks"), offers a bounded preference nudge ("lean your sessions toward hinge"), states plainly that the app still builds every session, and offers both an **Lean into hinge** accept and a **Not now** decline - each a labeled, hittable VoiceOver element.

### 02-coach-conversation-offer.png
The offer on the **real** `CoachView`, after a premium user whose push has climbed while hinge stalled asks "how am I doing?". The turn shows the user's question, the coach's (canned) reply, and the analytics offer card at the end of the turn - exactly the production flow. The stalled-hinge count reads 4 weeks here (the real dated history), matching the classification.

## How it is pinned (no manual step required for the guarantees)

- **The insight is real, not generic** - `CoachAnalyticsInsightTests` classifies a recently-advanced pattern as `climbing` and one stuck past the threshold as `flat`, and `CoachContextBundleTests.testCarriesTheStrengthJourneyTrend` proves the derived context bundle carries that flat-hinge signal (so the model can narrate it). No new data leaves the device: `testEncodedWireCarriesOnlyTheAuditedFields` asserts the strength-journey summary is coarse (pattern / trend / weeks / advanced flag) with no date, id, or identity field.
- **The action routes through US-AC07, never a workout edit** - `CoachViewModelTests.testProgressInquiryOffersEmphasisTowardTheStalledPatternAndAcceptWrites` is the validation test: the coach offers to bias toward the stalled hinge, and *accepting* applies a bounded, clamped, coach-sourced (`.llm`) `patternEmphasis` write through `CoachSessionPolicyService`, surfacing the honest note as a coach turn. The offer's proposal can express only a preference lever (`CoachAnalyticsInsightTests.testOfferEmphasizesTheStalledPattern`), so a workout edit is inexpressible by construction.
- **Declining changes nothing** - `testDecliningAnalyticsOfferChangesNothing`.
- **The persona narrates and offers only a bounded preference** - `proxy/test/worker.test.js` pins that the `/coach` system prompt is given the strength-journey trend, is told to narrate a concrete insight, and may offer to lean the program toward a stall while never claiming to have changed anything itself.

## Manual QA (captain-verifiable, not unit-coverable)

- A real end-to-end OpenAI `gpt-5.6-luna` reply that names the climb and the stall in the app's voice (the proxy is not deployed).
- Live on-device VoiceOver focus/announcement of the offer card.
