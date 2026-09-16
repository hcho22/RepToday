# Coach runtime authentication and production migration

The existing `reptoday-variety-language-proxy` is deployed at `https://coach.reptoday.app/coach`
with an operator-only bearer gate and the reviewed WAF boundary/rate protections. Firstmate's
2026-09-16 guarded launch reported success at source `a8b8f75`; its no-model gate probes passed.
No live model answer or shipped-client production authentication has yet been verified.

`proxy/src/coach-auth-worker.js` and `proxy/wrangler.runtime-auth.toml` prepare the captain-selected
stronger authentication migration. They are separate from the deployed legacy entry/configuration.
Ordinary iOS endpoints remain empty until that migration and genuine-device QA are accepted.
`REPTODAY_COACH_AUTH_MODE` passes through `Info.plist` to `CoachProxyClient.configured`; the approved
production origin requires `app-attest-storekit-v1` and an empty `REPTODAY_COACH_SECRET`. The app
constructs real DeviceCheck/StoreKit authentication, never a binary-embedded production credential.

## Verification boundary

For every user-triggered turn, the iOS transport obtains a verified production StoreKit 2 premium
transaction JWS. A genuine App Attest key enrolls once against a server-issued 60-second HMAC
challenge. Enrollment verifies Apple's certificate chain/current validity, nonce, public-key
identifier, app identity, initial counter and production AAGUID. The registered key obtains a fresh
one-time challenge and generates an assertion over this exact UTF-8 JSON array:

```
["reptoday-coach-auth-v1","POST","https://coach.reptoday.app/coach",
 operation,keyId,challenge,sha256(rawRequestBody),sha256(transactionJws)]
```

Hashes are lowercase hexadecimal; JSON slashes are unescaped. App Attest signs the SHA-256 hash
of those bytes. The server checks the signature/app identity, then atomically consumes the pending
challenge and advances the monotonic counter. A consumed challenge cannot be reused with a later
counter. A higher counter without the current challenge also fails. Concurrent duplicates accept
exactly once. The chosen App Attest library uses signed 32-bit counters, so values above `2^31-1`
fail closed and require a new genuine key rather than wrapping or resetting an existing counter.

Apple's official App Store Server Library verifies the supplied JWS with pinned public Apple G2/G3
roots and online certificate checks. The server independently queries **production** subscription
status and verifies the returned latest signed transaction in the same original purchase chain.
Known monthly/yearly products, active status, unexpired purchase, correct bundle/environment and no
revocation/upgrade are required. Client premium booleans, locally decoded claims, assertion-only
authentication and client-supplied status/fetch times cannot authorize a model request. Failure of
crypto, storage, Apple verification/API or configuration stops before the provider.

The exact original Coach body reaches the existing model boundary only after these checks. Purchase
proofs/App Attest data never enter the OpenAI prompt. The operator-only bearer credential is retained
for trusted administration/native QA, independently of premium/device authentication; it must never
be distributed to an app or user. Missing/wrong bearer authorization is rejected by the existing
constant-time gate before provider access.

## Bounded security storage and privacy

The migration adds one SQLite Durable Object per verified App Attest key in a production/protocol
namespace. A record is under 2 KiB and contains only:

| Field | Purpose / lifetime |
| --- | --- |
| Version, verified public key | App/key verification; up to 30 days without accepted assertion activity |
| Monotonic counter | Prevent assertion replay; same lifetime |
| Expiry timestamp and alarm | Delete inactive records after 30 days |
| One pending challenge hash and expiry | Consume exactly once within 60 seconds; replace on a new challenge |
| Deletion tombstone expiry | Replace other fields for 60 seconds after authenticated deletion |

There is no stored workout/message/reply, request/transaction hash, purchase identifier, JWS,
attestation object or receipt. Enrollment challenges for unknown keys create no stored record.
Full attestation verification occurs before enrollment writes. Duplicate enrollment cannot overwrite
a live key/counter. Expired/deleted records cannot be re-enrolled using the original captured proof
because its enrollment challenge expires; deletion's tombstone covers the remaining challenge lifetime.

Account deletion immediately unlinks the local key and invalidates pending iOS work. If the transport
is idle and supported it attempts device-authenticated server deletion within five seconds, without
requiring a current purchase. Offline/busy/failed cleanup leaves only bounded security metadata until
expiry. Local deletion and the core loop never wait for that network operation. The disclosure is
version 3 so prior acknowledgement does not silently authorize this new security-data contract.

The service is **content stateless**, rather than entirely persistence free after migration. Request
and response body logs, observability, tails, development URLs and caching remain disabled. Provider
standard abuse-monitoring retention remains as disclosed in `proxy/README.md`.

SQLite Durable Objects are supported on the [Workers Free plan](https://developers.cloudflare.com/durable-objects/platform/pricing/).
The namespace does not require a paid-plan upgrade, but quota/account availability must be confirmed
before migration. Challenge/counter/alarm updates consume Free-plan storage operations; exceeding
quotas must fail closed. The existing zone-wide `/coach` WAF rate limit remains the upstream abuse
boundary. A genuine-device farm or a copied valid Apple purchase proof used by a genuine app can
still abuse service: there is no proof of the human Apple Account and no transaction/device
exclusivity that would break legitimate restores. App Attest does not make a compromised client or
trusted operator credential impossible to abuse.

## Apple prerequisites and secure intake

The following remain captain-verified prerequisites, not assumptions from the checked-in team or
bundle settings:

1. The existing Developer account's registered `com.reptoday.app` identifier supports App Attest;
   its actual App ID prefix is confirmed and the production signing profile includes the capability.
2. The existing App Store Connect production app's numeric app ID and canonical monthly/yearly
   auto-renewable subscription products are correct. A production purchase/trial can be restored
   on a capable physical iPhone for positive QA.
3. An existing authorized App Store Connect In-App Purchase API `.p8` private key, its key ID and
   issuer ID grant the required production subscription-status operation. Do not create/search for
   credentials or a new paid account to fill an absence.
4. The existing authenticated Cloudflare account permits the SQLite namespace/migration while
   preserving the approved Worker, zone, domain and WAF controls. Missing authority blocks migration.

The prepared captain-only local command is `./tools/prepare-coach-runtime-keychain.sh`. It prompts
with hidden input for configuration identifiers and a native file picker for the **approved existing**
`.p8`; values go directly to macOS Security.framework. It preserves existing items, never searches
for a key, never prints values, never puts credentials in arguments/environment/files and performs no
deployment/API verification. `--check` checks item metadata only. Items use service
`com.reptoday.coach.production`, accounts `app-attest-app-prefix`, `app-store-app-id`,
`app-store-key-id`, `app-store-issuer-id`, and `app-store-private-key`, non-synchronizing and
device-local/unlocked. Intake is not platform authority, migration or live-QA evidence.

Those values must later become server-only `secret_text` bindings (`APP_ATTEST_APP_PREFIX`,
`APP_STORE_APP_ID`, `APP_STORE_KEY_ID`, `APP_STORE_ISSUER_ID`, `APP_STORE_PRIVATE_KEY`) through a
reviewed native Keychain boundary, preserving the provider/operator/WAF items. The migration config
contains no private values or account identifiers. Never insert them in the app, source, generated
Wrangler configuration, logs or status. The existing legacy deployment helper deliberately rejects
the new persistence binding; **do not use it to perform or roll back this migration**.

## Production, TestFlight and local QA

| Distribution | App Attest | Purchase environment | This production gateway |
| --- | --- | --- | --- |
| App Store, genuine capable device | Production | Production | Eligible after independent active-status verification |
| TestFlight | Production | Sandbox | Purchase denied; no production premium fallback |
| Xcode StoreKit configuration / Simulator | Unsupported or development attestation | Local testing | Fails closed |
| Development on a physical device | Explicit App Attest environment | Usually Sandbox | Does not prove this production purchase path |

Apple documents [production App Attest after distribution](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.devicecheck.appattest-environment)
and [Sandbox In-App Purchases in TestFlight](https://developer.apple.com/in-app-purchase/).
TestFlight positive Coach QA would need a separately reviewed isolated Sandbox service/configuration;
it must not introduce a production fallback, simulator bypass, local boolean grant or operator gate
in a binary. This is a beta compatibility limit and must be stated before release/QA scheduling.

Active introductory free trials remain eligible without positive price checks; expired transactions,
billing retry and elapsed-expiry grace remain denied, consistent with the existing
`LiveStoreKitFacade.entitlement` rule. Restore/multiple-device access is preserved. Fresh online
verification can make Coach unavailable while cached on-device premium features continue offline.

## Local validation and migration plan

Run `npm test`, `npm run typecheck` and `npm run test:runtime` inside `proxy/`, plus
`tools/test-coach-live-qa.sh`, `tools/test-coach-production-deploy.sh` and
`tools/test-coach-runtime-key-intake.sh`, `tools/test-coach-runtime-migration.sh` and
`tools/test-coach-runtime-client.sh`. Native tests use doubles and compile production entries
without executing credential/UI code. Real iOS client tests use explicit doubles; production
configuration constructs real Apple services and has no bypass switch.

The native shared-source harness executes the actual client/configuration/authentication and bounded
HTTP implementations with transport/Apple doubles. It symlinks actual AppState dependencies, rather
than replacing app behavior. It does not verify the iOS bundle's real configuration or DeviceCheck.
App-hosted Coach/view-model/context/gating/disclosure/deletion/configuration tests also run on iOS
Simulator. Follow `.github/workflows/ci.yml`: simulator app entitlements require certificate-free ad
hoc signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=`). Unsigned RepToday test hosts crash before
XCTest connects; an archived unchanged-source comparison reproduced that failure, then passed with
the CI flags. A minimal host without those entitlements passed unsigned. No app startup behavior
was changed to resolve this harness configuration issue.

Runtime tests use installed Miniflare/workerd 2025-07-18, native crypto and actual SQLite atomic
storage. Every outbound request is intercepted by a local service; no external requests are allowed. The test bundler models the installed Wrangler native-require
plugin and sets the documented `modulesRoot`; generic esbuild externalization is insufficient.
Apple's verifier dependency initializes randomness, so it imports inside a handler, never module
scope. Production configuration uses 2026-01-01; compatibility-date behavior beyond the installed
runtime's date is not proven by these tests. The earlier assertion/import/SQLite subset passed, but the subsequently added real official SDK API
JWT/status-transport test currently fails with the fixed `transport` class in this installed runtime,
including after aligning the adapter to SDK 3.1.0's `api.storekit.apple.com` production origin. Its
failing regression is retained; full runtime compatibility is **blocked**, and no migration/release
may proceed on this evidence. That correction follows [Apple's pinned SDK source](https://github.com/apple/app-store-server-library-node/blob/v3.1.0/index.ts).
Actual supported Wrangler dry-build/deployment and positive current Apple trust-chain/online checks
also remain final migration validations. Generated-key
signature tests and trusted payload/API doubles do not prove a valid Apple production enrollment.

The prepared native migration boundary is `tools/migrate-coach-runtime.sh`, with three separate
operations. **None has been launched against production during preparation.** Before any operation,
Firstmate must resolve the runtime compatibility blocker and confirm captain authorization, reviewed
committed source, Apple/account prerequisites, existing Keychain items and production-device access.
Use the installed Node 20 environment; the wrapper refuses other Node majors, dirty source or a
different task branch. Stage/release also require offline proxy unit/type/runtime checks to pass
before opening Keychain/UI or making a control-plane request; the known regression therefore
prevents launch. Hold-only rollback remains available when runtime checks fail. The coordinator
also refuses account/token overrides or OAuth expiry within
20 minutes. It never refreshes or writes the shared Wrangler authentication file.

```sh
PATH=/Users/hcho/.nvm/versions/node/v20.19.5/bin:$PATH ./tools/migrate-coach-runtime.sh --stage
PATH=/Users/hcho/.nvm/versions/node/v20.19.5/bin:$PATH ./tools/migrate-coach-runtime.sh --release
PATH=/Users/hcho/.nvm/versions/node/v20.19.5/bin:$PATH ./tools/migrate-coach-runtime.sh --hold
```

`--stage` confirms the sole authenticated account, existing active Free zone, explicit existing
Worker and already-attached approved domain before mutation. Existing hold/boundary/rate rules must
match; it never creates WAF capacity, attaches a hostname, edits DNS or purchases a plan. It enables
and verifies the hold first, then deploys through the installed supported Wrangler flow using only
public configuration. A public source revision binding pins subsequent release to the local
committed head. Only the approved SQLite class/binding/migration, server secrets, mode and public
revision are permitted. It checks the official namespace API's `class`, `script` and `use_sqlite`
fields, exact migration tag, same namespace on repeat staging, disabled observability/tails/logpush,
and disabled development/preview URLs. Unknown/missing API fields stop rather than guessing.
Namespace creation/quota authority is still unverified; an API/Free-quota refusal leaves the hold.

Only the five **missing** Apple bindings are provisioned from the approved existing local items.
Provider/operator secrets must already exist and are preserved; no existing server secret is read,
replaced or rotated. It verifies all bindings again and **leaves the hostname held closed**. It
makes no endpoint/model request and performs no genuine Apple enrollment or purchase verification.
The native reader sends the enumerated items only through an anonymous child pipe, discards child
stderr, bounds input/output and accepts only the exact complete fixed transcript. Child stdout
containing any unexpected field/value is rejected in full. Secrets/configuration identifiers never
enter argv, environment, generated configuration, artifacts or status.

`--release` reads only the operator gate/WAF items, verifies the same committed source, complete
server bindings, SQLite namespace/migration and protections, then disables only the owned hold. It
executes bounded **no-model** probes: missing/wrong bearer -> 401, authorized malformed input -> 400,
and forged runtime proof -> 401. Failure immediately re-enables/verifies the hold; a failure to
re-hold is a distinct `rehold` blocker requiring immediate captain control-plane action. Success
means the protected origin was released; genuine Apple/model/semantic/shipped-client QA is pending.

`--hold` is the fail-closed rollback: read only the WAF item, reconfirm existing target/domain/rules,
enable/verify the hold, and preserve Worker code, namespace, enrolled keys/counters, bindings and
records. It can close an invalid Worker configuration without reading/uploading secrets or making
a model call. There is no raw legacy rollback, namespace/class deletion, data export, bulk erasure,
secret rotation or automatic fallback. A future code rollback must preserve the class/migration
and be reviewed independently. The legacy helper still rejects the persistence binding.

After the reviewed migration, enable the approved `/coach` origin via per-configuration build
settings, keep the binary secret empty, and verify on a genuine production-purchase device. At most
two paid prompts should cover why squats and pistol-squat form, using supplied non-identifying context
without fabricating or altering a workout; inspect their semantics locally without recording replies.
Also test copied proof/body/challenge/counter substitution, expired/revoked premium, concurrent
duplicates, metadata deletion, redirect rejection and offline/error UI recovery. Record only fixed
outcomes. A simulator cannot supply positive App Attest evidence.

The separate prepared operator command `./tools/validate-coach-live.sh` exercises the actual
`CoachProxyClient` and synthetic PRD contexts using the native operator gate, with at most two paid
calls and fixed-output validation. Its lexical signals are smoke evidence only; semantic correctness,
real shipped authentication and UI QA remain unverified. See `proxy/README.md` for the full boundary.

Local checkpoint (2026-09-16): 151 proxy unit tests and typecheck passed; 38 actual shared-source
native client tests passed; 145 selected app-hosted simulator tests passed, including actual
configured runtime-transport construction, invalid production-host variants, view-model/core/error
behavior, context/gating/disclosure, AppState and account-deletion cleanup. 57 legacy coordinator
checks, 37 runtime migration coordinator checks, native migration/intake/live-QA doubles and
production-entry compilation passed. Debug app-host and Release simulator builds passed. Both built Info.plists have empty Coach endpoint
and binary secret and the exact runtime mode. Production App Attest is declared in the checked-in
entitlement source; signed entitlement extraction and genuine Developer account/profile authority
remain unverified. The added actual-workerd
official API test remains a blocker,
not a green check. There were no real Security/UI, control-plane, endpoint or paid model operations
in this local continuation.
