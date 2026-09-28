# Final Coach authentication diagnostics and bounded operation

This is code-only preparation for a final `401 unauthorized`. It is not a Coach repair,
proof of the live cause, deployment approval, or a replacement for the
[runtime owner](coach-runtime-authentication.md#local-validation-and-migration-plan).
The completed client classification needs no repeat Instruments/LLDB work.

## Candidate and source assumptions

The candidate is based on default-branch `b333997d369fdbda470e66e2de27e502b3158b3e`.
Its existing challenge callback seam is a prerequisite of the final diagnostic.
The historically restored source `cad34528c33a960d282549db4fde31a350cca011` predates that
seam. Neither the current checkout nor the device app identifies deployed server source.
A future operation must choose the exact reviewed candidate commit and freshly verify the
baseline source, version and settings. Do not apply the scout diff directly to historical
production or assume historical version/account/namespace identifiers are current.

The four auth source changes only track fixed labels beside existing predicates and emit
from outer denial catches. Authentication, public status/error bodies, timing limits,
counters, pending nonce, stored fields, namespace/secret selection and provider routing
are preserved. Diagnostics are absent by default and only the string `"1"` enables them;
invalid/absent/off flags and successful requests emit no new row. Existing challenge-only
instrumentation is independent, including its previously documented temporal delta.

The final row schema is exactly `event`, `stage`, `reason`. Event is
`coach_final_auth_guard`; the closed pairs in
[`emitFinalAuthDiagnostic`](../proxy/src/coach-auth-diagnostics.js) are authoritative.
No IDs, values, lengths, deltas, proof/JWS, purchase fields, prompt/body, credentials or
arbitrary exception text are accepted. Compound guards intentionally have compound labels.
A DO denial may produce an inner row followed by `worker_state/denied`; the aggregate row
alone cannot identify the inner guard. `key_unavailable`, `auth_unavailable`, recognized
delete operations and challenge/enrollment operations remain silent under the new flag.

The flag is checked at emission, not cached. Local tests cover disabling while a DO read
or Premium verification is pending. Deployed versions have their own environments: changing
latest settings does not revoke a flag inside an already running old-version request.
Hold, terminate capture, restore code/configuration, and verify both metadata surfaces;
do not claim an instantaneous global log cutoff from a settings write.

## Existing guarded owners

The shell/native/coordinator chain accepts independent explicit options for stage/release:

```sh
tools/migrate-coach-runtime.sh --stage --final-auth-diagnostics
tools/migrate-coach-runtime.sh --release --final-auth-diagnostics
```

Omitting both diagnostic options produces flag-free configuration. The final option is
invalid for hold, inspection and Keychain preflight. Unknown/duplicate options and binding
values/types are rejected. The clean reviewed operational branch requirement, native custody,
source revision pin, original hold/boundary/rate checks, SQLite namespace, secret set and
privacy checks remain in place. This feature branch is not the operational branch; prepare
separate exact reviewed operational checkouts only under future authority.

The same owner adds two GET-only inspections (native reads only the existing WAF item):

```sh
tools/migrate-coach-runtime.sh --verify-candidate
tools/migrate-coach-runtime.sh --verify-restored
```

They consume, respectively, `build/coach-runtime-migration/candidate.json` and `baseline.json`
from the **candidate owner checkout**, at most 2 KiB, with exactly these fields:

| Field | Required meaning |
|---|---|
| `ownerRevision` | Exact clean HEAD of the reviewed candidate owner |
| `sourceRevision` | Exact source expected to be active and in latest settings |
| `versionId` | Exact immutable active version, alone at 100% |
| `worker` | Existing target from `TARGET.worker` in the production owner |
| `accountId`, `zoneId`, `namespaceId` | Freshly confirmed existing target identities |
| `held` | Expected existing hold state for this inspection (`true` or `false`) |

Keep these manifests private and ignored; never add credentials or publish identifiers.
Candidate inspection additionally requires source equals owner HEAD and **only** the final
diagnostic enabled. Restored inspection requires both flags absent and the baseline source.
Both independently check active version bindings and `resources.script_runtime`, latest
`/settings`, compatibility settings, secret names, namespace/class/SQLite/migration, routes,
development URLs, disabled persistent logs/traces/logpush/tail consumers, placement/tags/usage,
expected protections and zero transient tails. A second deployment read detects movement
within the inspection. A failed/partial/timeout/ambiguous read is not restoration; there are
no retries or writes in these inspections. External serialization remains necessary: an
inspection is not a distributed lock, and secret names cannot prove secret values unchanged.

## Capture readiness without a circular wait

Cloudflare documents that [Wrangler tail includes Worker and DO requests](https://developers.cloudflare.com/durable-objects/observability/troubleshooting/).
[Real-time logs contain request metadata and may drop samples](https://developers.cloudflare.com/workers/observability/logs/real-time-logs/).
The private investigation filter has therefore been ported as
[`coach-capture-guard-tail.py`](../tools/coach-capture-guard-tail.py), with a source-pinned,
in-memory adapter for installed Wrangler **3.114.17**. It changes no installed package.
Dependency drift makes the adapter refuse; review it again instead of bypassing the hash.
The adapter attaches its entrypoint to the final `module.exports` object because the
pinned bundle replaces CommonJS's original `exports` alias. The offline gate evaluates
that exact transformed module with synthetic auth and blocked IO, and checks the export
the adapter calls. `--self-check` alone checks the hash, unique replacement and parsing;
neither check invokes `main` or establishes live attachment. See the
[export regression evidence](../artifacts/reports/coach-tail-export/validation.md).

There are three different facts:

1. **Attached:** the pinned adapter has observed the WebSocket OPEN state. This alone is
   not `ready` and does not invite a device send.
2. **Pre-attempt coverage:** after attachment, two deliberately invalid, no-model probes
   exercise the actual Worker and DO paths. The filter requires matching script/version
   metadata from both entrypoints before printing `ready`. The operator also requires the
   probe command's complete success output. Neither fact depends on the captain's message.
3. **Post-attempt evidence:** final denial rows after readiness may discriminate a guard.
   Inner DO rows are still required to explain an aggregate state denial. Silence, absent
   metadata, missing coverage, a dropped/truncated event, or an unconfirmed send is inconclusive.

The probe command below performs exactly two requests: a synthetic all-zero-key enrollment
challenge, then enrollment with one-byte malformed CBOR (`AA==`). The first issues a stateless
token; the second fails CBOR validation before reading/writing security storage or calling
Apple. Neither includes a user prompt or calls a model. A DO may be activated, but no
security record, nonce, counter or alarm is written. Local Worker/DO and workerd tests prove
these control-flow properties. Future live delivery/metadata shape remains untested.
Tokens/responses are transient memory only, and any unexpected result stops without retry.

The capture has one subscription, at most 120 seconds **including readiness**, 200 input
events, 20 accepted rows, 256 KiB framing and 4 MiB total input. The first accepted row
shortens the remaining window to at most five seconds to allow the companion DO/Worker row.
No method/search/status filter excludes DO invocations. Whole events, unknown labels, extra
fields and request metadata are discarded in memory. Only fixed diagnostic rows and bounded
capture statuses/counts are printed. No raw stderr or Wrangler log file is retained.
SIGINT, SIGTERM, deadline, child failure, malformed/oversized input and version drift close
the local process group with bounded escalation. **Local exit never proves zero remote tails.**

## Exact future one-message operation (separate approval required)

This plan includes possible all-caller Coach downtime during holds and one ordinary send
that may succeed and call the model. Approve those effects, two coverage probes, the finite
window, native credential attendance, and restoration before executing any step. No step
below was executed in this preparation. Do not repeat device classification, purchases,
key resets, reinstallations, secret rotation or a speculative auth fix.

1. Reserve the existing resources through the existing operation owner. Freeze the exact
   reviewed candidate and clean original-source operational checkouts. Verify the original
   active version at 100%, exact source and latest settings, route, secret set, security
   namespace, privacy, protections, and zero tails. Populate the private manifests from
   fresh reads, not this historical document. Run the offline gate below in both relevant
   owners. Preflight the original owner's ability to stage/release and the installed,
   config-free exact-version deployment command; no force or guard bypass.
2. Use candidate `--stage --final-auth-diagnostics` under its unchanged guards; require
   complete staged/held output. Record the immutable resulting candidate version and set
   `candidate.json` to that version with `held: true`; run `--verify-candidate`. Require
   every existing secret to remain present; stop rather than allow provisioning/rotation.
3. Use candidate `--release --final-auth-diagnostics`. Require complete release/probe output;
   change the expected hold state in `candidate.json` to `false`, then `--verify-candidate`.
   Record the start and the absolute 120-second deadline in private operational evidence.
4. Start the bounded filter in the candidate checkout (the version argument is the freshly
   verified candidate version):

   ```sh
   python3 tools/coach-capture-guard-tail.py --capture-version "$candidate_version" --seconds 120
   ```

   Keep it attached under the authorized tmux continuation. After its `capture: attached`
   status, in a second pane in the **same exact checkout**, run once:

   ```sh
   node tools/coach-runtime-migrate.mjs --coverage-probes
   ```

   Require its complete `coverage: ... completed` output **and** the filter's
   `capture: ready, coverage: worker_and_do`. If readiness/metadata/probes fail or time
   expires, do not invite a send, do not reconnect, and proceed to containment/restoration.
5. Through Firstmate, invite exactly one ordinary Coach message while the original deadline
   still has time remaining. Record whether it was actually sent and its public result.
   Close on the filter's finite deadline/row bound or earlier cancellation; do not extend
   because the captain was delayed. Multiple callers have no correlation IDs: rows cannot
   establish attribution on their own, and an empty capture never disproves the failure.
6. Close capture and use existing candidate `--hold`; require verified held output. Separately
   verify zero remote tails. A lost process, nonzero exit, timeout or ambiguous mutation
   result stops dependent actions: reconcile actual deployment/settings/tail state before
   choosing any next action. Never automatically repeat an operation whose effect is unknown.
7. Restore **latest settings and original-version traffic**, retaining the hold throughout:
   - Candidate owner: `--stage` with both diagnostic options omitted. This removes the new
     flag and produces the flag-free bridge the historical original owner can inspect.
   - Original clean source owner: `--stage`, retaining all seven existing secrets and the
     exact namespace/migration. This restores baseline source/configuration to latest settings.
   - From an empty, private config-free directory, use the reviewed installed Wrangler's
     exact-version command once: `versions deploy "$baseline_version@100" --name
     reptoday-variety-language-proxy`. Noninteractive confirmation must be scoped to this
     exact deployment (Wrangler's `--yes`, **never** no-mistakes `--yes`). No `--force`,
     rollback-to-latest alias, migration deletion, settings patch or namespace reset.
   - Candidate owner: `--verify-restored` with the original metadata and `held: true`.
     Only after that passes may the unchanged original owner run `--release`.
   - Candidate owner: `--verify-restored` again with expected `held: false`. Require original
     version100%, original latest settings, absent flags, intact protections and zero tails.

This intentionally uses the existing staged bridge/original-source owners instead of a new
rollback controller. Selecting an old version alone previously left latest settings at the
diagnostic upload; this verifier reproduces and rejects that mismatch. A stage failure
keeps the hold; failed restoration is an unresolved operational incident, not completion.
Do not retry a partial stage, add a fallback release, weaken a revision check or recreate state.
[Version rollback does not restore bound resource data](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/).
Counter/nonce consumption from the attempted send is not undone. In-flight old-version
requests can finish after selection changes; source/settings restoration is not request erasure.

The runtime operation owner owns flag removal/review after the separately authorized
observation. Diagnose from the observed guard before proposing a functional change. No new
backlog or release obligation is created by this code-only preparation.

## Validation

Run `bash tools/test-coach-final-diagnostics.sh`. The same offline gate is part of existing
PR CI. It executes the full proxy/typecheck/workerd suites, native migration doubles,
strict CLI/config tests, filtered stream tests and restoration verifier fixtures. It never
executes native credential readers or a live tail. See the public-safe
[evidence and limitations](../artifacts/reports/coach-final-auth-diagnostics/validation.md).
