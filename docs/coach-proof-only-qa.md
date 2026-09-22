# Coach server proof-only QA preparation

This source prepares a bounded, hidden device-to-server verification exchange. **It has not been
deployed or executed on a genuine device. It does not enable TestFlight Coach.** Ordinary
Debug/Release endpoints remain empty. Current source permits StoreKit-verified Production or
Sandbox proof and verifies the selected environment server-side; the released Worker remains
Production-only until a separately authorized deployment.

## What the exchange proves

`RuntimeAuthenticatedCoachTransport.verifyProofOnly` reuses the actual purchase, App Attest,
challenge, enrollment, assertion, HTTP, total deadline and account-reset boundaries. It signs
the exact UTF-8 body `{}` as operation `reply`, including the existing body and purchase hashes.
The reviewed gateway consumes the assertion atomically, verifies fresh active Premium with Apple,
and only then invokes the existing body validator. That validator returns
`400 {"error":"invalid_context"}` without any provider request. The client sends the **identical**
headers/body once more and requires `401 {"error":"unauthorized"}`. No new challenge, signature
or purchase read occurs for that intentional replay. Neither failure is retried.

The source gateway now denies the exact `{}` operator-bearer request with 401. An operator's
body-validation error therefore cannot produce this proof-only success. This restriction is
**new source**, not a claim about the currently deployed revision. There is no public diagnostic
route or new credential. The local integration seam in `proxy/test/workerd-auth-entry.js` is
never a Wrangler deployment entry.

A fixed success means both runtime gates passed and the exact replay was denied by the matched
reviewed server. It does not independently establish TestFlight distribution, installation channel,
the signing profile, capability readiness, or model semantics. Those facts need separate evidence.
Failure is deliberately unclassified and establishes no successful gate.

## Hidden device path and budget

The dedicated `COACH_IPHONE_QA` surface exposes this preparation only after opening the existing
hidden schema panel in **Profile → Coach Synthetic QA**. Select **Server admission preparation**
to switch panels. The ordinary model controls stay disabled while the hidden panel is open;
switching panels/leaving cancels and clears the departing probe. The server probe uses the same
configured runtime actor as model QA, so overlapping handshakes fail promptly.

The user must separately confirm the exact operation, then tap **Verify server gates once**.
`CoachRuntimeProofProbe` reserves a content-free one-attempt marker in UserDefaults before any
Apple/HTTP operation, including failures and interruptions. No reset/retry control exists.
Neither account deletion nor returning to another screen reopens the budget. Reinstalling does
not authorize a new operational budget. Schema, server-proof and model budgets are separate.

At most 30 seconds total covers the ordinary bounded authentication flow, one empty-body admission
request and, only after its exact expected response, one replay. Existing bounded key recovery
can enroll one replacement key after a stale/invalid restored key; there is no paid-request retry.
StoreKit JWS, key identifiers, assertions and response bytes remain transient in the runtime flow.
Only the spent marker persists in the probe; the normal runtime retains its usual local enrolled
key identifier and bounded server security record. No context, training summary, Coach safety
identifier, model prompt, transcript or credential is emitted. Output is limited to:

```text
runtime-gates=verified; replay=denied; model=not-requested; distribution=unresolved
```

or:

```text
runtime-gates=unverified; replay=unverified; model=not-requested; distribution=unresolved
```

## Preconditions for genuine execution

Source/offline delivery, matching newly reviewed held Worker stage/release, actual installed
build/channel, existing signing/App Attest/App Store Server API authority and exact device/Apple
operation must be established before executing. Do not use a simulator, development install,
operator bearer, local Premium boolean or fixture as genuine evidence. Do not read protected
credentials, change accounts/capabilities or spend the model budget to fill gaps.

The separately bounded [Apple-bound schema operation](coach-testflight-schema-probe.md) remains
diagnostic research, not an authorization prerequisite or input. The runtime does not parse or
trust a client distribution flag or guessed assertion extension. Instead, Apple's signed
transaction selects only Production or Sandbox after server verification, and the unchanged App
Attest boundary independently requires a production attestation/assertion. Xcode/local transaction
proof and development App Attest continue to fail closed.

Before an approved TestFlight proof-only run, deploy the reviewed Sandbox-capable Worker through the
separate guarded process and inspect the intended archive's endpoint/mode/empty gate. A Production
verifier/API failure must never trigger Sandbox; only the verified transaction environment selects
the matching Sandbox verifier and status API.

For a later approved server-proof run, use only an installed identified eligible build against the
matched server revision. The current client can submit Sandbox proof, but the older deployed
Production-only revision will deny it; no TestFlight Premium success has been observed. Existing
eligible production device/purchase QA is separate. The hidden screen cannot purchase or restore.

Record only fixed results plus public-safe build/channel/server-revision facts. Never capture proof,
JWS, identity input, credentials or raw error diagnostics. Leaving clears results. Offline workouts
remain independent of every outcome. Genuine admission, subscription and model verdicts remain
unverified until their distinct actual exchanges succeed.

## Offline verification

Use the project's Node 20 runtime for `npm test`, `npm run typecheck` and `npm run test:runtime`
inside `proxy/`. The local workerd suite exercises real P-256 signature/body/purchase binding,
SQLite nonce/counter consumption, exact replay, forged-signature denial, Premium-denial ordering
and operator exclusion; its Premium success is a trusted local double. Every egress is intercepted,
including any accidental provider dispatch. Apple SDK trust/online-verification selection and
fresh status lookup are separately tested with doubles and real verifier negative inputs.
Unsupported signed extension candidates remain denied; fixtures are not Apple evidence.

`tools/test-coach-runtime-client.sh` executes the actual client/runtime/probe sources with
Apple/transport doubles. It checks exact signed `{}` and identical replay, no bearer, unexpected
responses, absent purchase/offline failure, total deadlines, stale callbacks, persistent budget,
competing screens and disabled/unconfirmed prerequisites. Unsigned arm64 compilation and the
built-plist/scheme inspector establish compilation/configuration only. Results:
[`artifacts/reports/coach-proof-only-qa/validation.md`](../artifacts/reports/coach-proof-only-qa/validation.md).
