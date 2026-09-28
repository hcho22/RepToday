# Coach assertion challenge clock skew: local evidence

2026-09-28.
**Code-only fix; not deployed.**
Implementation under test: `534278adff7077a515a9969e3b7ec6db3e5c9a99`, based on `2054390`.
The subsequent evidence commit changes this report only.
The selected delivery owner is no-mistakes; its review and CI outcome are recorded separately.
Scenario linkage below is reviewable evidence, not machine-enforced Firstmate evidence import.

## Symptom and cause

Every Coach send from an enrolled device failed at the assertion challenge with `401 {"error":"unauthorized"}`.
Enrollment challenges succeeded and `key_unavailable` never appeared.

The Worker mints the challenge token with its own clock (`i` = Worker `Date.now()`), then asks the Durable Object to record it.
The Durable Object verifies the token with the clock of the machine hosting it and rejected any issue time later than that clock, with zero tolerance.
A Durable Object clock trailing the Worker by more than the Worker-to-object transit time therefore turns every fresh assertion challenge into `unauthorized`, before the record lookup that would have produced `key_unavailable`.
The enrollment challenge never calls the Durable Object, and the enrollment token is seconds old by the time either side verifies it, so enrollment is unaffected.

Other pre-lookup `unauthorized` sources were ruled out against the code:

- Key format: the Worker applies the same `keyIDValid` before minting.
- App prefix and secret format: the Worker's `ready(env)` requires the same values, and fails with `503 auth_unavailable`, not `401`.
- MAC and claim shape: the same script, secret and code mint and verify; they differ only across a mid-deploy version split, not for days.
- Worker envelope: the iOS client sends the identical `{operation, kind, keyId}` shape for enroll and assert challenges.

Live production clocks were not observed (no tail or capture was authorized for this task).
This is the only cause found that is consistent with all the device evidence and reproducible offline; it is not a captured production row.

## Accepted contract and impact

Accept an issue time up to `CHALLENGE_CLOCK_SKEW_MS` = 5000 ms ahead of the verifier's clock, in `verifyChallenge` (`proxy/src/coach-auth-crypto.js`), which every Worker and Durable Object check shares.
Preserved: MAC, claim shape, key binding, key-format and app-prefix checks, exact 60-second expiry, the single-use pending nonce, the monotonic counter, `key_unavailable` re-enrollment, public error bodies and statuses, and the token format.
Expiry keeps no tolerance: a verifier trailing within the bound lengthens real lifetime by at most 5 s, and one leading by as much still leaves 55 s, past the client's 30-second deadline.
The `token_future` guard diagnostic now fires only beyond the bound.

Why 5 s: synchronized hosts differ by milliseconds, so 5 s is orders of magnitude of headroom, and it stays small beside the 60-second lifetime.
Only the Worker can mint a token with a valid MAC, so the tolerance cannot help a forger; its only effect is an honest token living at most 5 s longer on a trailing verifier.

Risk is **high**: this loosens an authentication freshness check on a shared production service used by every enrolled client.
Impact: the Coach proxy Worker and its `CoachAuthenticationState` Durable Object; no data migration, storage schema, secret, binding or client change.
Human judgment needed: the 5 s bound, and whether to deploy.

## Scenarios

Environment: macOS 26.6.2, Node v20.19.5, installed workerd `1.20250718.0` through Miniflare `3.20250718.3`, compatibility date `2025-07-18`, `nodejs_compat`.
Time: 2026-09-28, 23:30Z-23:35Z.
Fixtures are generated P-256 keys and a trusted Premium double; zero external requests.

| Requirement | Expected | Observed | Result | Evidence |
| --- | --- | --- | --- | --- |
| Reproduction (before fix) | Durable Object 25 ms behind the Worker in separate workerd isolates reproduces the device failure | `401 {"error":"unauthorized"}`; rows `do_token_entry`/`token_future`/`deltaMs 24` then `worker_state`/`denied` | pass (reproduced) | `node test/workerd-auth.mjs` with only the constant added, before the check changed |
| Within bound | Durable Object 0, 1, 25, 250, 5000 ms behind, or 10 s ahead: challenge `200`, no guard row | as expected | pass | `proxy/test/workerd-clock-skew.mjs` |
| Beyond bound | 10 s behind: `401 unauthorized`, `do_token_entry`/`token_future` with `deltaMs` in (5000, 10000] | as expected | pass | same |
| Forged MAC, other key, expired | `401 unauthorized` inside the lagging Durable Object | as expected | pass | same |
| Send reaches the Coach handler | With a lagging Durable Object, a signed `{}` send gets the no-model `400 invalid_context`; its exact replay gets `401`; counter advances once | as expected | pass | same |
| Exact bound and expiry | Accept at exactly 5000 ms, reject at 5001 ms; expiry unchanged; tolerance never excuses MAC or key binding | as expected | pass | `proxy/test/coach-auth-crypto.test.js` |
| Diagnostics and transaction re-check | Guard rows and the in-transaction re-verification follow the same bound | as expected | pass | `coach-auth-diagnostics.test.js`, `coach-final-diagnostics.test.js` |
| Non-vacuity | Widening the bound to 60 s fails the regression | workerd `200 !== 401` beyond bound; 26 unit failures | pass | temporary sabotage, reverted |
| Enroll path and existing suites | Unchanged | `npm test` 356 passed; typecheck clean; `npm run test:runtime` validated; `bash tools/test-coach-final-diagnostics.sh` exit 0 | pass | local runs at the implementation commit |
| Live device send | Coach reply on the captain's device | not run | untested | needs an approved production deployment |
| Production clock evidence | A captured `token_future` row from production | not run | untested | no tail or capture authorized |

## Client re-enrollment on `unauthorized`

Not implemented.
Re-enrolling would not fix this cause: the new key's first assertion challenge meets the same verifier clock.
`unauthorized` is the generic proof-rejection code (forgery, replay, bad assertion), and `key_unavailable` is the explicit re-enroll signal.
Treating `unauthorized` as re-enroll would spend an Apple attestation and leave an orphan security record per failure, and would hide future server faults.
Follow-up if still wanted: at most once per app session, only for the assertion challenge, with the churn cost accepted explicitly.

## Recovery

Code-only in this task.
After a separately approved deployment, restoration is re-selecting the prior Worker version `f12edbeb-1ca1-4570-ba50-8418ae0eea46`, verified by version metadata.
The token format and stored records are unchanged, so both versions verify each other's tokens (the prior one still with zero tolerance) and rollback needs no data cleanup.
A rollback also restores the failure.
