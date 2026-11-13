# ADR-0017: The Coach is a Convex-hosted agent that writes user-accepted Custom Workouts

- Status: Accepted (decided 2026-11-10), diet scope amended by [ADR-0019](0019-coach-answers-general-health-and-fitness.md) (2026-11-13); implemented in M4 (`US-CA01`...`US-CA08`, 2026-11-11) against the development Clerk instance and Convex deployment. The device exit criteria (a sandbox subscription, notifications on hardware) and the release steps are owed (`artifacts/reports/coach-agent-m4/validation.md`).
- Date: 2026-11-10
- Deciders: captain, via the Push/Pull/Legs design grill (2026-11-09 to 2026-11-10)
- Spec: `.claude/agent/tasks/prd-ppl-rest-accounts-coach-agent_261110.md`
- Supersedes: the Cloudflare Worker Coach route with per-request App Attest and StoreKit-receipt authentication (`docs/coach-runtime-authentication.md`).
- Relates to: [ADR-0005](0005-two-writer-policy-safety.md) (safety-owned engine moves stay out of the Coach's reach); ADR-0016; `CONTEXT.md` -> "Coach", "Custom Workout".

## Context

Today the Coach is a stateless chat: each turn sends only the current message and a de-identified context bundle to OpenAI through a Cloudflare Worker, and the model itself takes no actions.
The captain wants a premium Coach that remembers the user, acts on their behalf, writes workouts from their history, gives diet guidance and sets reminders.

## Decision

**The Coach runs as Convex actions authenticated by Clerk, with persistent memory, tools, and free-form Custom Workouts the user must accept.**

- Premium is a per-user entitlement in Convex kept current by App Store Server Notifications and checked every turn.
- Tools: log an Outside Activity, rest today or train anyway, change today's length, swap a movement, set Focus Areas, schedule an on-device reminder. Each action is confirmed with Undo. De-load, Re-entry and cold start stay engine-owned.
- A Custom Workout is written freely by the model from the user's workout history, status and injury history. It is a proposal: the user reviews, edits and accepts it before it plays. Any movement is allowed; catalog movements show Trainer art, others are text-only and untracked. A played Custom Workout counts like an Outside Activity and never advances progression.
- Diet guidance is general (protein, hydration, low carb, low sugar, vegetables), for adults only, and never medical. (Amended by [ADR-0019](0019-coach-answers-general-health-and-fitness.md): the Coach now answers general health and fitness questions, adults get sample meals, weight-management principles and the evidence on common supplements, and plain hydration is open to every age.)
- The Coach becomes the fourth tab.

## Considered Options

- Coach steers the deterministic engine through closed tools only - rejected by the captain in favor of free-form writing with user review as the safety rail.
- Keeping the Cloudflare proxy and shipping history in each request - rejected once user data lives in Convex.

## Consequences

- Workout and injury history now reach the LLM provider; the Coach data disclosure and privacy policy must say so.
- Custom Workouts are a separate artifact, not a `SessionPolicy` write, so ADR-0005's safety-over-preference structure is unchanged.

## Implementation decisions (M4, 2026-11-11)

These settle what the decision above left to implementation.
The captain chose the retirement in the last item on 2026-11-11; the rest are recorded here as built.

- **Model (Open Question 3).** The provider is unchanged: OpenAI, now called from a Convex action through the Responses API with `store: false`.
  The model is `gpt-5.6-luna` at low reasoning effort (`convex/coachModel.ts`); `COACH_MODEL` on a deployment overrides it without a code change.
  A short evaluation on the dev deployment (`convex/coachEval.ts`, twelve synthetic turns covering each tool, a form question, an adult diet question and a de-load request) had `gpt-5.6-luna` and `gpt-5.6-terra` both pick the expected tool on all twelve turns.
  Luna was chosen: it kept the load off the synthetic user's flagged wrists in its Custom Workout, gave the general adult diet guidance decision 29 asks for where Terra declined it, and costs about a tenth as much per turn (about 3,000 input tokens, most of them cached, and under 400 output tokens), with a median latency under two seconds.
  Both models often answer a tool call without text, so the server adds one plain line per kind of proposal (`proposalReply`).
- **Tools are proposals.** The model's tool calls are never executed on the server: each is validated and clamped into a proposal (`convex/coachTools.ts`) that the app shows as a card.
  The user confirms or declines it; a confirmed one is applied on the phone through the same paths the user's own controls take (`CoachProposalApplier`), so it is saved locally first and syncs through M3's outbox, and it can be undone.
  "Every action shows a confirmation with Undo" is therefore read as confirm-first, then Undo.
  Because a proposal's result is the user's later tap, a turn is one model call; the outcome (applied, declined, undone) is written to the conversation memory so the next turn knows it.
- **Safety moves are unreachable by construction.** The tool list and the app's `CoachProposal.Action` are closed: there is no tool or case for a de-load, a Return, the cold start, the progression pace, the earned phase or an injury flag, and any other tool name the model sends is dropped.
- **Context.** The server reads the user's own synced records (profile and injury areas, recent sessions, Outside Activities, accepted Custom Workouts, Focus Areas) and the conversation, and writes them out in the app's words (`convex/coachPrompt.ts`); the phone adds only today's plan, which only its engine can compute.
  The model is never sent the user's name, email, height, weight or an account identifier; its abuse-monitoring id is a one-way hash of the account.
- **Entitlement.** App Store Server Notifications V2 reach `POST /appStore/notifications`; every signed payload is verified against the pinned Apple roots (full chain, Apple's marker extensions, validity at the signed date, the ES256 signature), then checked for the bundle id, an accepted environment and a Premium product (`convex/appStoreJws.ts`, `convex/appStore.ts`).
  The app passes the account's `appAccountToken` with every purchase, and sends a purchase's signed transaction after it completes and on Restore Purchases (`entitlements:linkTransaction`).
  A subscription is linked to one live account; a restore never moves it from another account that still exists.
  Accepted environments are deployment configuration (`APPSTORE_ENVIRONMENTS`); a development deployment may also accept unsigned Xcode StoreKit test transactions (`APPSTORE_ALLOW_XCODE`), as Apple's own verifier does, so a Simulator purchase can be walked end to end.
- **Diet age rail.** The server reads the onboarding age from the user's own profile; a user not known to be 18 or over gets a fixed decline for a diet question without a model call, and a model reply that drifts into diet is replaced before it is stored (`convex/coachSafety.ts`).
  ADR-0019 keeps the rail, takes plain hydration off its word lists and adds a crisis rail ahead of it at every age.
- **Custom Workouts and FR-8.** Only an accepted Custom Workout is saved or played (FR-11).
  A played one is recorded as an Outside Activity, never a session, so it never advances progression, Earned Reps or a Foundation.
  Its group is the one with strictly the most sets among its catalog steps (squat and hinge count as Legs); a tie, or no grouped catalog step, names no group, so the Rotation is left alone as an "other" Outside Activity leaves it.
- **Today's choices.** Resting today, training anyway, today's length and movements swapped out are kept for the day on the device (`TodayChoices`), and Today's own controls write the same record, so the two never disagree.
  Resting on a Training Day is a session-free day: it skips no group.
- **Reminders** are local notifications only; permission is asked the first time one is set, and they are listed, edited and deleted in Settings.
- **Retired with the agent.** The Coach's keyword-driven `SessionPolicy` tuning (US-AC07) and its strength-journey stall offer (US-AN02) were removed: the agent's confirmed tools replace them, and the offer's pattern-emphasis lever no longer reaches the engine under the fixed rotation.
  The injury routing offer (US-AC08) stays: it still points the user to their own injury control and writes nothing.

