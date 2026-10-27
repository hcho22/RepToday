# Coach Worker on Wrangler 4

## Scope and risk

The proxy's build tool moves from Wrangler 3.114.17 to Wrangler 4.154.0, the current release on the npm registry, pinned exactly.
Wrangler 4's `nodejs_compat` preset leaves `node:crypto` to workerd, so the crypto alias and shim added on 2026-09-29 are removed.
`nodejs_compat` and the 2026-01-01 compatibility date are unchanged.
No Coach request, reply, sign-in, App Attest, replay, Premium, clock-skew, data or privacy path changes.

Risk is medium.
A wrong bundle would break Coach sign-in exactly as it did before the 2026-09-29 fix, and the operator tools drive Wrangler in ways a unit test cannot see.
Both are contained here by proving the built bundle and by recording what Wrangler 4 actually sends.
Nothing was deployed: no staging or production deploy, no `wrangler tail`, no secret or settings change, no request to the production Coach or any model.

Recovery is reverting the change.
A deployed Worker returns to a Wrangler 3 bundle only by redeploying the reverted source through the same approved release flow; no stored data changes.

## What changed besides the version

Wrangler 4.154.0 needs Node 22 or later and refuses to start on Node 20 (observed).
The operator wrappers that pinned "the reviewed installed Node 20" (`tools/coach-staging.sh`, `tools/migrate-coach-runtime.sh`) now pin Node 24, and CI's Coach job runs Node 24.
`@cloudflare/workers-types` moves to 5.20261023.1, the peer Wrangler 4.154.0 names.
`miniflare` 4.20260730.0 is now a pinned dev dependency: Wrangler 4.154.0 ships a Miniflare 5 beta whose options API differs, and the workerd suite keeps Miniflare 4's.
The workerd suite now runs at the shipped compatibility date and flags instead of 2025-07-18, because the newer workerd supports 2026-01-01.

Recording Wrangler 4's real deploy against a local Cloudflare stand-in, and comparing it with Wrangler 3.114.17 on the same configurations, found three differences that would otherwise have surfaced only in a live run:

1. Wrangler 3 sent no Durable Object code update strategy; Wrangler 4 asks every deployment for deferred updates (old code for up to 300 seconds) unless told otherwise.
   Every Coach configuration now asks for `code_update_strategy: { mode: "immediate" }`, so a release's probes reach the code it released.
2. Wrangler 4 refuses the staging teardown configuration ("Cannot apply deleted_classes migration to non-existent class"), before any request.
   The configuration now carries the full migration history; against the deployed staging script it uploads the same single deletion step Wrangler 3 sent.
3. Wrangler 4's `tail` reconnects a lost connection with up to five new subscriptions, where Wrangler 3 exited.
   The tail adapter now sets those attempts to zero, so a capture keeps one subscription and a lost connection deletes the tail and exits.

Smaller differences, pinned by the deploy contract: version uploads name `keep_bindings` for secrets, the settings patch adds `tags: []`, the `workers.dev` and preview state is always written (to the values already configured), and Wrangler reads secret names, settings and subdomain state first.
Wrangler 4 also uploads the npm dependency list of a `package.json` beside the deployed configuration.
The operator tools write their configurations under `build/`, where there is none, so the setting that turns this off does not change their uploads; it guards a configuration that does sit beside one, which today is only a hand deploy of `proxy/wrangler.runtime-auth.toml` (beside `proxy/package.json`, and not an approved path).

Review found one more difference: Wrangler 4 picks its login per directory, so a profile bound to the configuration's directory or a parent (`wrangler auth activate`) would win over the `config/default.toml` login the operator tools check and pin.
Every Wrangler deploy and tail the tools run now passes `--profile default`.

## Offline evidence

Observed 2026-10-27 on macOS 26.7.1 with Node 24.16.0, from base revision `f274ad04c3ec4a2d5e6a1b99073f408a2226f033` plus this change.
Wrangler 4.154.0 (CLI SHA-256 `8dab269b2b490df04d1aeac0858a8d56af494b4144bcb4b66171b41d114cf88b`), `@cloudflare/unenv-preset` 2.16.2, Miniflare 4.20260730.0 with workerd 1.20260730.1.

| Requirement / scenario | Expected and observed | Result / limit |
| --- | --- | --- |
| Every deployable bundle reaches native `node:crypto` (`proxy/test/wrangler-bundles.mjs`, run first by `npm run test:runtime`) | `deploy --dry-run --outdir` of `wrangler.toml`, `wrangler.runtime-auth.toml` and the generated production, staging, staging-teardown and legacy configurations: no unenv `crypto.*` stub, no unenv crypto polyfill; Coach bundles import `createVerify` and the CommonJS module from the runtime's `crypto` | Pass |
| Reintroduced stub is refused, through the real bundler | Same run aliases `node:crypto` to unenv's polyfill; the check reports `createVerify`, `createSign`, `sign`, `verify` stubs | Pass (built-in negative control) |
| Wrangler 3's exact failure is caught twice (one-off, not committed) | `crypto` aliased to a shim with only those four APIs throwing: the bundle check fails ("createVerify is not imported from the runtime crypto module"); with the bundle check disabled, the workerd suite fails at "genuine device assertion", 401 instead of 200 | Pass; files restored byte-for-byte afterwards |
| Full workerd suite on the Wrangler-built graph | Genuine device assertion and forged-bit denial, generated-key assertions, Apple verifier negatives, official SDK JWT and transport double, proof-only gate ordering, SQLite replay, Worker/Durable Object clock skew; zero external requests | Pass at compatibility date 2026-01-01 with no alias or shim |
| Bundle-check rule (`proxy/test/wrangler-bundles.test.js`) | Accepts native imports; refuses function and class stubs, the polyfill, and a bundle whose crypto is not the runtime's | Pass |
| Deploy contract (`proxy/test/wrangler-deploy-contract.mjs`) | Real `wrangler deploy`, with the operator tools' own arguments, against a local Cloudflare stand-in: production release writes only version, deployment (100%, immediate), settings (logpush off, observability off, no tags) and subdomain (off); staging creates its SQLite class on workers.dev only; teardown sends only the deletion after `coach-security-v1`; orphan teardown sends create-then-delete | Pass; Cloudflare's acceptance of each upload is not proven offline |
| Default login despite a bound profile (deploy contract) | Each deploy runs with an OAuth login in `config/default.toml` and another profile bound to a parent of every configuration directory; every request carries the default login | Pass; with `--profile default` removed from the tools' arguments the first deploy sends the bound profile's login and fails (one-off sabotage, restored) |
| Tail contract (`proxy/test/wrangler-tail-contract.mjs`, part of `npm run test:runtime`) | The committed capture (`tools/coach-capture-guard-tail.py` spawning the adapter) through the installed Wrangler's real `tail`, from its working directory under a bound profile, against a local stand-in for the tails API and its trace-v1 WebSocket: it attaches, reaches Worker and Durable Object readiness, forwards the one guard row and stops at the deadline with exit 0; one tail, filtered to the exact version only, on the default login, then deleted; an abnormal close deletes the tail and ends the capture with no second subscription | Pass; before the adapter dropped `--sampling-rate 1` it ended `child_exit` without attaching, and removing `--profile default` or re-enabling reconnect fails it (one-off sabotage, restored); live attachment is not proven offline |
| Final-auth restoration `versions deploy` (one-off, not committed) | The documented command (`docs/coach-final-auth-diagnostics.md`, step 7) from an empty directory under a bound profile, against a local stand-in: one deployment of the exact version at 100%, on the default login, with `code_update_strategy` immediate; without `--profile default --durable-objects-code-update-mode immediate` it sends the bound login and deferred (300 s) | Pass |
| No dependency list beside a `package.json` (deploy contract) | The production configuration placed beside a `package.json` with one installed dependency uploads no `package_dependencies`; the same configuration without `dependencies_instrumentation` uploads that dependency | Pass (built-in negative control) |
| Wrangler 3 versus 4 upload comparison (scratch, not committed) | Same harness with Wrangler 3.114.17 on the same configurations; differences are those listed above | Recorded privately |
| Dry-run is offline | Wrangler 4.154.0 `deploy --dry-run` completes with all outbound network denied by a macOS sandbox profile | Pass |
| Tail adapter (`tools/coach-tail-ready.cjs --self-check`, `tools/test-coach-tail-ready.cjs`) | Hash pin, unique attachment marker and reconnect replacement, parse; the transformed module evaluates under blocked file, network, child and write capabilities and exports `coachTailMain` as a function, with zero attempts | Pass; `main` and a live tail are not invoked |
| Capture filter (`tools/test-coach-capture-guard-tail.py`) | 21 tests, stream tests now framed as Wrangler 4 prints (`JSON.stringify(event, null, 4)`) | Pass |
| Operator tool suites | `tools/coach-runtime-migrate.test.mjs` 93 tests (immediate Durable Object updates on every production configuration, shared build with no crypto alias and dependency instrumentation off), `tools/coach-staging.test.mjs` 11 tests (teardown history), native doubles and preflight tests | Pass |
| Proxy unit suite and typecheck | `npm test` 482 tests, `npm run typecheck` with workers-types 5.20261023.1 | Pass |
| Offline Coach gate | `bash tools/test-coach-final-diagnostics.sh` under Node 24 | Pass |

## Live checks for the release

None of these can be proved offline; each needs its own captain approval when the Coach server is released.

- Staging deploy (`tools/coach-staging.sh --deploy`): Wrangler 4's deploy path, immediate Durable Object update, the post-deploy settings, bindings and namespace verification, and both labelled probes.
- Staging teardown (`tools/coach-staging.sh --teardown`): the deletion migration with the full history, and the orphaned-namespace repair, which now sends create-then-delete.
- Production stage and release (`tools/migrate-coach-runtime.sh --stage` / `--release`, and `--verify-candidate` / `--verify-restored`): the version and deployment Wrangler 4 creates, `keep_bindings` keeping the existing secrets, the settings check (`tags` empty, logpush off, observability absent or off), development URLs off, and the release probes.
- Hold-only rollback (`--hold`): no Wrangler change, but it runs under the new Node 24 gate.
- Final-auth tail capture (`tools/coach-capture-guard-tail.py` through the adapter): live attachment on the default login, the attachment marker, the one-subscription behavior on a lost connection, and the JSON event shape.
  Wrangler 3.114.17 and 4.154.0 both refuse a `--sampling-rate 1` before any request ("A sampling rate must be between 0 and 1"), so the adapter now passes no sampling rate, and every event is sent; the tail contract shows the capture attaching against a local stand-in.
- One genuine-device Coach send through staging, then production: App Attest assertion and the App Store Server API signed token on the deployed Wrangler 4 bundle.
- The legacy deploy helper (`tools/deploy-coach-production.sh`) is unchanged and pinned to an old branch; under Wrangler 4 it now needs Node 22 or later.
