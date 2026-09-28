# Coach tail adapter export regression

## Scope and risk

This code-only repair removes a local capture-startup blocker. It does not repair or
identify the original Coach authorization denial. The pinned Wrangler bundle replaces
`module.exports`; appending to its stale `exports` alias left the adapter's called
`m.exports.coachTailMain` undefined. The suffix now attaches to `module.exports`, inside
the shared in-memory transform so production and the regression evaluate the same bytes.

Accepted implementation scope: capture tooling only, no dependency/package edits or
upgrades. The same main invocation, hash/version pin, attachment marker, one subscription,
two-probe readiness, fixed labels, memory-only filtering, finite bounds and restoration
procedure are preserved. No app/server authentication predicate or public response changes.

Risk is medium: a small local operator-tool change with significant downstream diagnostic
importance. Only the disposable source checkout is changed. No production calls, capture,
coverage probes, native credential operations, deployment or recovery operations are part
of this repair. Code recovery is reverting this patch; it has no deployed state to undo.
Any future live operation belongs to the existing investigation and requires separately
directed attendance, fresh preflight and the unchanged restoration contract.

## Offline evidence

Observed 2026-09-28, Node 20.19.5, macOS 26.6.2, based on reviewed default-branch
`75fce3cf7b35ef6be5cb8eb2eb72dda419bb64c3`. Wrangler remains 3.114.17 with CLI SHA-256
`3ddc7ba0e400b3ad75e49a4bb18dc9b6b6727873920efe4797940b67bdbb790a`.
The commands below reproduce evidence against the revision containing this report.

| Scenario / command | Expected and observed | Result / limit |
| --- | --- | --- |
| `node tools/test-coach-tail-ready.cjs`, with the old suffix retained in the shared transform | Module evaluates, actual called export is `undefined`, exit 78; zero forbidden module attempts | Red regression reproduced the linkage defect without invoking main |
| Same command after the correction | Actual called export is `function`, exit 0; file/network/child/write/output counts all zero | Pass, only under synthetic auth and filesystem fixtures |
| Harness positive controls | Synthetic file read, fetch, child execution and write each throw at their guard, before IO | Pass; control counters are reset before recording module attempts |
| `node tools/coach-tail-ready.cjs --self-check` | Hash, unique attachment replacement and transformed JavaScript parse pass | Pass; this command alone does not evaluate export linkage |
| `bash tools/test-coach-final-diagnostics.sh` | New export regression, 21 filter tests, proxy typecheck and 349 tests, installed-workerd integration, 85 operator tests, native doubles and 9 preflight tests pass | Exit 0; existing workerd integration uses local doubles, zero external requests |

The earlier blocked non-dependency read was traced to the pinned bundle's eager
`LocalState -> getAuthTokens -> readAuthConfigFile -> readFileSync` initialization.
It attempted the Wrangler auth-config file, with contents blocked. That run is **not**
clean startup evidence merely because Wrangler caught the error and module evaluation
continued. The regression replaces the inherited environment with a clearly synthetic
token, taking Wrangler's no-file branch, and supplies a synthetic home/absent metadata.
Linux's bundled WSL detection gets only an in-memory `/proc/version` fixture.
Unexpected reads outside dependencies, network, child execution, writes and output fail
the test even if the dependency catches the exception. Only fixed results/counts print.
No real credential value or arbitrary dependency output is recorded.

## Handoff and limits

The selected delivery owner is the full no-mistakes pipeline, with automatic gate
approval disabled. This report supplies the implementation criteria and evidence apart
from captain intent; scenario linkage is for that owner's review, not machine-enforced
by the dispatch workflow. CI runs the same offline gate.

Real Wrangler main/tail execution, provider attachment, Worker/DO live coverage and a
genuine Coach send remain **untested**, outside this code-only task. The export defect
can explain pre-attachment failure but cannot exclude another live startup problem.
The original unauthorized response remains unresolved. Human operational judgment and
separate live authority remain with the existing investigation owner; no new release
obligation or permission follows from a passing offline test or merged code.
