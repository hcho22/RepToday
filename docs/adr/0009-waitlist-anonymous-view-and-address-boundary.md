# ADR-0009: The Waitlist keeps addresses on the founder's side and gives the Marketing Engineer only an anonymous view

- Status: Accepted (decided 2026-10-19); not yet implemented.
- Date: 2026-10-19
- Deciders: captain, by approving the gr0wthlab Dispatch request for RepToday's Waitlist (item 20261016-reptoday-waitlist, decision "approve" on 2026-10-19).
- Spec: `.claude/agent/tasks/prd-waitlist_261019.md` (`US-WL##`)
- Relates to: the domain term `CONTEXT.md` -> "Waitlist"; [ADR-0005](0005-two-writer-policy-safety.md) (another place where a boundary is structural rather than conventional).
- Amended when: the captain settles the PRD's Open Questions 1-5 (storage, hosting, Source transport, view production, confirmation); this ADR then gains a "Settled choices" section rather than being superseded.

## Context

The Waitlist is the first place Rep Today holds an email address.
The app itself never asks for one, and the telemetry sink (`convex/`) is identity-free by contract.
The founder wants the Marketing Engineer (gr0wthlab's sandboxed agent, which reads the gr0wthlab, Mandu and RepToday checkouts) to count which links and which routines bring people, without any way to read an address.
One leaked email-service credential, or one export that holds addresses, would expose every sign-up at once.

## Decision

**The only Waitlist data that crosses to the Marketing Engineer is one anonymous view file, and addresses are resolved only on the founder's side.**

1. The view is one UTF-8 JSON file on the founder's Mac, format version 1, in exactly the shape the request defines: `{"view": 1, "generated_at": ..., "entries": [...]}`, each entry holding only `entry`, `source`, `fit`, `beta_opt_in` and `signed_up_on`.
   gr0wthlab's launcher reads it read-only at each weekly run, with no network.
2. The file lives outside the gr0wthlab, Mandu and RepToday checkouts and outside every git work tree, where the sandboxed agent can never open it.
   A reviewed gr0wthlab change records its path once the build lands.
3. An entry identifier is random, 1 to 64 letters, digits, `-` or `_`, unique, stable while the sign-up exists, and never derived from the address: not a hash, not an encoding.
   An address is low-entropy and guessable, so a hash of it can be reversed by testing candidate addresses.
4. An entry identifier is turned into an address only on the founder's side, at send time, in RepToday's storage or the email tool.
5. No email-service credential and no export that holds addresses is ever placed in the gr0wthlab, Mandu or RepToday checkouts.
   Credentials live in the macOS Keychain or in the hosting or email provider's own secret store, never in a file git could publish.
6. A visitor's Source comes only from the link they arrived by (`tiktok`, `youtube`, `reddit`, `network`, else `unknown`), never from a question.
   A new Source needs a new Dispatch request and a reviewed gr0wthlab change.
7. The view's format is a versioned contract with gr0wthlab's reader (`src/gr0wthlab/waitlist.py` in the gr0wthlab repository).
   A new field is a new `view` version plus a reviewed gr0wthlab change, never an in-place addition, because the reader rejects any entry whose keys are not exactly the five and any version newer than it knows.
   A new Source tag or Fit answer is a new Dispatch request plus a reviewed gr0wthlab configuration change.

## Considered options

- **Give the Marketing Engineer a read-only email-tool credential or an export** - rejected by the request: one such credential or file exposes every address, and the sandbox is the thing being protected.
- **Identify sign-ups by a hash or encoding of the address** - rejected: it is derived from the address, and a hash of a guessable value can be reversed; gr0wthlab's reader also treats an identifier that decodes to an address as a breach.
- **Count through a network API the agent calls** - rejected: the launcher reads a local file with no network, so nothing the agent runs can reach the store.
- **Put the sign-ups in the Convex telemetry sink** - not chosen here (see the PRD, Open Question 1): that sink's contract is "no identity in any event", and its schema is limited to the `events` table plus the ephemeral `rateLimits` counter table.

## Consequences

- The view cannot answer any question that needs an address or a name; that is the point.
- Field names, allowed values, the Source tags, the Fit answers, the entry identifiers and the file's path become hard to change after go-live, because gr0wthlab's configuration and Waitlist Evidence depend on them (the PRD lists each).
- A removed sign-up leaves the view on the next generation that reads the store after its removal (the PRD's US-WL07 and US-WL10 own the timing), so the view is rebuilt from the store each time rather than appended to.
- RepToday must guard its own side: a refusal to write the view anywhere inside a git work tree, a conformance check that mirrors gr0wthlab's reader, and a CI check that no credential or address list is committed.
  gr0wthlab's own address check (Guardrail G6) remains the backstop, not the plan.
- The privacy policy's Waitlist section (retention 30 days after the launch email, removal within 7 days, "only the founder ... and the service that stores it") becomes a public commitment the storage design must keep literally true.
- Storage, hosting, how the Source reaches the sign-up, how often the view is produced and whether sign-ups confirm their email are deliberately not decided here.

## Settled choices

The captain settled the PRD's Open Questions 1-5 on 2026-10-19 ("Waitlist - go with your recommendations"), accepting each marked recommendation.
The PRD's Open Questions section keeps the options and reasons.

1. Storage (OQ1): Option A - Kit stays, a first-party form posts to Kit, and a producer on the founder's Mac assigns entry identifiers.
2. Hosting (OQ2): (a) stay on Cloudflare Pages, static.
3. Source transport (OQ3): (a) per-tab last-touch among the four links; a plain path keeps an existing tag; a trailing slash counts as the same link.
4. View production (OQ4): (ii) a daily `launchd` run that also runs after each sweep, plus on demand, writing `~/Library/Application Support/RepToday/waitlist/waitlist-view.json`, owner-only.
5. Confirmation (OQ5): double opt-in; only confirmed sign-ups are in the view.
