# Temporary Coach authentication guard diagnostics

Use only for the investigated assertion-challenge `401 unauthorized`, after normal source review,
validation and explicit production authority. This does not repair authentication or prove which
live guard failed. Existing generic HTTP responses, authentication predicates, namespace, security
records, secrets, and model dispatch behavior remain unchanged.

The existing native migration helper accepts an explicit optional flag:

```sh
tools/migrate-coach-runtime.sh --stage --auth-guard-diagnostics
tools/migrate-coach-runtime.sh --release --auth-guard-diagnostics
```

Both operations still require the clean reviewed branch, Node20, offline gates, existing account,
Keychain and protection checks. The flag is invalid for `--hold`. With the option omitted, ordinary
stage/release retain their prior flag-free configuration. Pre-stage inspection accepts the exact
approved diagnostic flag or its absence; post-stage and release require configuration matching the
explicit option and committed source revision. Only `COACH_AUTH_GUARD_DIAGNOSTICS=1` is permitted;
unknown values, types and bindings remain rejected.

The temporary flag permits internal console rows containing only:

- `event`: `coach_auth_guard`.
- `stage`: `worker_envelope`, `worker_state`, `do_preflight`, `do_token_entry`,
  `do_token_transaction`, or `do_state`.
- `reason`: `envelope`, `key_format`, `prefix_format`, `token_syntax`, `token_mac`,
  `token_claims`, `token_future`, `token_expired`, or `denied`.
- `deltaMs`, only for temporal failure after valid MAC and claim-shape checks: issue time minus
  verification time, bounded to [-60000,60000]. Values at the bounds may be clamped.

No keys, tokens, receipts, identifiers, messages, exception strings, secret values or app-prefix
values are emitted. Diagnostics are default-off. Logger/callback failure cannot change authorization.
A Worker denial can accompany a DO row; the Worker row alone does not identify the inner guard.

Persistent observability, traces, logpush and tail-consumer bindings remain disabled. Any explicitly
authorized transient authenticated tail must filter raw events in memory and output only the exact
allowlisted diagnostic object. It must not save or print whole events, request headers, URLs with
parameters, exception details, response bodies, or unrecognized log lines. Capture one arranged
retry and close the session; no matching row is inconclusive unless DO capture was confirmed.
There are no correlation identifiers, so unrelated concurrent requests cannot be attributed from
these rows alone. This document grants no production or temporary-capture authority.

Validation: proxy typecheck; existing auth crypto/worker/state tests; focused diagnostic privacy and
default/off/on tests; the existing full proxy gate and offline workerd runtime; migration coordinator
and native pipe tests. The local workerd version is older than the production compatibility date,
so production runtime and genuine Apple/device success remain separate evidence.

Rollback: the existing `--hold` remains the immediate fail-closed option. Source rollback must
preserve the Durable Object class, migration and namespace and be independently reviewed, as in
`coach-runtime-authentication.md`. For this investigation the known prior active version is
`f12edbeb-1ca1-4570-ba50-8418ae0eea46`; restoring it and verifying100% traffic, original flag-free
bindings and unchanged protections is a separate explicitly authorized control-plane operation.
Close any transient capture. Do not remove namespaces, reset keys, rotate secrets or use the legacy
persistence-free deployment helper. Ordinary future source deployments omit the diagnostic option.
