# TestFlight App Attest schema verification preparation

This is an **unexecuted QA-only preparation**, not TestFlight Coach enablement. The assertion
extension contract remains unresolved. The probe never admits Sandbox Premium, enrolls with the
Worker, obtains StoreKit proof, sends training content, or calls a model. Ordinary Debug/Release
Coach settings and the deployed authentication policy remain unchanged.

## Existing boundary and minimum addition

`CoachDeviceQA` and `RepTodayCoachDeviceQA` already provide the registered app identity, production
App Attest entitlement source, a dedicated Profile QA entry, empty binary secret and disabled
telemetry. See [the physical-iPhone QA runbook](coach-iphone-qa.md). The normal model runner and its
two-request budget are separate from this probe.

`Services/Coach/CoachProofSchemaProbe.swift` uses the existing `DeviceCoachAppAttester` and total
30-second deadline. It reserves one content-free attempt marker before any Apple call, generates
two independent randomized 32-byte challenges and, only on an explicit approved tap, makes one
new key, one attestation and one assertion. No retry or marker-reset control exists. The production
key identifier and model budget are neither reused nor overwritten. A new key is necessary here:
the existing enrolled-key store has no retained attestation certificate, and Apple does not allow
attesting an already-attested key again. Reinstalling does not grant a new operational budget.

The verifier validates the full, currently valid X.509 chain against the same public Apple App
Attestation root as `proxy/src/apple-trust-roots.js`, with network fetching disabled. It binds the
certificate nonce to the full attestation authenticator data and challenge hash, the P-256 public
key and credential to the key identifier, the RP hash to the approved App ID prefix and registered
bundle, counter zero and production AAGUID. The first assertion must bind that key/app, the separate
challenge and its **entire** authenticator data through the reviewed `node-app-attest` signature
algorithm, with a positive bounded counter. No extension property is shown before both proofs pass.

The small CBOR/DER consumers reject malformed, ambiguous, duplicate, trailing, over-depth and
oversized structures. The CBOR observation step does **not** select a category decoder for admission,
invent assertion aliases, authorize a distribution or validate a purchase. A trailing signed map
with ED unset can be observed as such; it is not an accepted production protocol exception.
Only these allowlisted names may be shown, with fixed `unsigned`/`bytes4`/`bytes`/`text`/`other`
types: `apple_validation_category_01`, `apple_bundle_version_01`, `validationCategory`, `bundleVersion`.
Fixed observation flags report whether a known category field matches the documented expected 2
as unsigned CBOR or either four-byte candidate order, and whether a known text version equals this
build's actual `CFBundleVersion`. These are explicit candidate observations, not alias/type/byte-order
fallbacks for admission. Comparisons require the exact unsigned value or four-byte pattern, and
version comparison requires nonempty bounded text and the actual bounded build version. More than
one recognized category or version name in a map is rejected as ambiguous; duplicate keys are
also rejected. Unknown names/values become only `unknown-properties=present`. No raw category,
bundle-version or identity values are emitted. Certificate/proof/key identifiers and the hidden
App ID prefix stay in memory, with no application logging, transcript, clipboard, export or persistent store. Late
Apple callbacks may retain their own transient memory until completion; cancellation prevents any
subsequent operation or stale result from appearing.

## Proposed genuine operation — approval still required

Availability of a device alone is insufficient. Before executing, obtain explicit approval for
the exact reviewed revision, signed TestFlight build, installation/replacement, Apple operations
and one-attempt scope. Confirm existing signing/App Store Connect authority, the registered App
Attest capability and effective **production** entitlement, an unused approved upload build number,
and the actual App ID prefix from the effective approved identity. A checked-in development team
is not evidence of that prefix. Do not create accounts, services, profiles, capabilities or a new
app identity to fill a prerequisite gap. No production deployment/helper or protected credential
read is part of this proposal.

This new diagnostic source first needs its own **reviewed diagnostic-only delivery** before a
genuine verification build is distributed. That dependency is distinct from the final Coach
enablement delivery, which remains incomplete. Neither delivery pipeline is started by this
preparation, and no signed QA build has been established.

The probe must be distributed through **genuine TestFlight** using the existing
`RepTodayCoachDeviceQA` scheme/`CoachDeviceQA` ArchiveAction, with no local StoreKit fixture and
QA telemetry unconfigured. A development install, simulator or unsigned build cannot establish
TestFlight provenance. The ordinary `tools/archive-release.sh` path is not this proposal: it
selects ordinary Release and invokes unrelated live telemetry/credential operations. Signing,
archiving for distribution, uploading through the existing app, and installing the resulting beta
are separate, currently unauthorized actions. An unsigned local compile is only preparation.

After those concrete approvals and prerequisites, the exact app action is:

1. Launch that approved TestFlight build, then open **Profile → Coach Synthetic QA**. Do not
   restore/buy Premium, acknowledge the model-run readiness toggle or send either synthetic turn.
2. Press and hold **Synthetic QA — not your workout data** for three seconds, or use its VoiceOver
   action **Open schema verification preparation**, to open the hidden schema panel. Model controls
   are disabled while it is open; it cannot open during a model send.
3. Type the approved actual App ID prefix directly into **Approved App ID prefix**, a hidden
   `SecureField`. Do not send it through chat/status, paste from a retained artifact or screenshot it.
4. Confirm the separate operation approval toggle, then tap **Verify Apple schema once** once.
   The identity input clears immediately. Wait at most 30 seconds; never retry failure or timeout.
5. Read only the fixed output locally, report its known names/types/flags and leave the screen.
   Leaving clears the displayed result. Do not export/screenshot proofs or use application logs.

Expected successful **binding validation**, still unsupported for distribution admission:

```text
result=unsupported
bindings=verified
distribution=unresolved
attestation:
flags=<bounded byte>
extensions=present|absent
unknown-properties=present|absent
<allowlisted name>=<fixed type>; <fixed candidate/version flag>
assertion:
flags=<bounded byte>
extensions=present|absent
unknown-properties=present|absent
<allowlisted name>=<fixed type>; <fixed candidate/version flag>
```

Failure produces only `result=malformed` or `result=unsupported`, followed by
`bindings=not-verified`. There is deliberately no `verified-TestFlight` success class in this
preparation: emitting it would assert the currently missing contract. A successful binding result
would establish authentic challenge-bound schema observations for that installed beta and OS.
The candidate flags would establish the observed byte-shape matches and text agreement for this
build, including which allowlisted names/types, category-2 encoding pattern and ED behavior appear
in both fresh signed proofs. This supplies empirical wire-format evidence for that exact build and
OS when the fields are present and unambiguous. It does **not** turn the candidate interpretation
or the known installation channel into cryptographic TestFlight authorization, and cannot establish
availability on every supported OS, valid Premium, server admission or a model return.

If the expected fields and comparisons all appear, that fully bound observation can supply empirical
wire-format evidence for targeted implementation after acceptance and review. An exhaustive OS
availability statement or positive hardware evidence on every supported OS is not a prerequisite
for that scoped work. Broader positive OS-support claims require their own evidence. No app OS
floor may be raised, and unknown/missing/unsupported signed properties must deny beta admission
before model access through the existing unavailable/authentication handling. If a required field
is missing, unknown, unsupported or ambiguous, the smallest further evidence dependency is primary
clarification of that precise field/encoding/OS gap, rather than decoder aliases or opaque proof
dumps. This preparation never silently resolves the proof-contract blocker.

## Offline validation

`./tools/test-coach-runtime-client.sh` executes the actual verifier and coordinator with entirely
synthetic, memory-only keys/certificates/proofs. Tests exercise the real Security chain consumer
with a synthetic root, full chain/validity failures and pinned-Apple-root rejection; exact DER nonce
handling; actual P-256 signatures and tampered full authenticator data, challenges, keys and app
hashes; ambiguous/missing/unknown/oversized structures; fixed output, prerequisite denial, one-attempt
relaunch safety and cancellation/late-callback behavior. These are not genuine Apple proofs.

Build the dedicated QA app without signing using the existing unsigned recipe, then run
`python3 tools/test-coach-qa-build-inspection.py` and the inspector in the iPhone runbook. The actual
built plist/scheme checks must still show the approved public endpoint/mode, empty binary secret,
disabled telemetry and no local StoreKit attachment. Signed-device touch/accessibility behavior
and real Apple proof availability remain pending; offline tests cannot claim either.
