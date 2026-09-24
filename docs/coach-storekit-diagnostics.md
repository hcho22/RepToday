# Coach QA paywall StoreKit diagnostics

In `COACH_IPHONE_QA` builds, the existing Premium paywall displays independent Products and
Restore results beside its ordinary messages. For shared recovery controls and messages, see
[Account and Premium access](../README.md#account-and-premium-access). The diagnostic rows live only with
the QA paywall view model; ordinary Debug and Release do not display them.

| Row | Meaning |
| --- | --- |
| Products: loading / loaded N plans | Initial state or catalog request in flight / usable mapped plans returned. |
| Products: lookup returned N products; 0 usable subscriptions | The live lookup returned N raw products, but none survived subscription projection. Zero means Apple returned no products; a positive N means products were filtered. Neither establishes the App Store Connect cause. |
| Products: no usable products | Empty usable catalog, including `productsUnavailable`; no transport exception is established. |
| Restore: not attempted / in progress | No restore on this model / its existing restore operation is running. |
| Restore: Premium success | The existing restore grant is Premium; the normal grant and dismissal path still applies. |
| Restore: no current entitlement | Restore completed without a current Premium grant. This differs from a thrown sync. |
| Either row: category, domain / code | The corresponding request threw. At most one underlying domain/code follows. |
| Either row: unclassified failure | The service threw without a projected diagnostic. No raw description is displayed. |

`LiveStoreKitFacade.requestFailure` projects only product-load and `AppStore.sync()` errors.
Typed StoreKit network/system errors retain one associated cause; otherwise one
`NSUnderlyingErrorKey` cause may be used. Cancellation requires a typed cancellation result,
never a matching error message. Domain labels are restricted to StoreKit, legacy StoreKit,
App Store, Apple Media Services and network domains; every other domain becomes `other`.
The value holds enums and integers, not error objects, descriptions, `userInfo`, purchase proofs
or account identifiers. It is not persisted, exported or sent to analytics.

The rows do not establish that the underlying failure
is temporary, identify a product/account configuration defect, or prove a genuine Apple restore.
Numeric codes require interpretation in their recorded domain; do not infer a cause from a code
alone or suggest account changes, repurchasing or deleting data without further evidence.

For a later authorized diagnostic-device session, record the app version/build, the two bounded
row results, and whether a restore prompt completed or was cancelled. Confirm the original
purchase environment and active status separately without collecting account identifiers or
proofs. These source changes do not update any installed app.

## Offline checks

```sh
./tools/test-storekit-paywall-diagnostics.sh
```

The macOS SwiftPM harness compiles the actual facade projection, subscription service and paywall
model with and without `COACH_IPHONE_QA`, using injected StoreKit doubles and memory-only defaults.
It does not invoke Apple services. `StoreKitPaywallDiagnosticsTests` also includes an iOS hosted
accessibility check for the two rows under QA and their absence in ordinary builds. Native macOS
execution excludes that UIKit test. See the [validation record](../artifacts/reports/coach-storekit-diagnostics/validation.md)
for exactly which checks ran and their limits.

The Premium access follow-up and its credential-only Account entry are documented in
[the current validation report](../artifacts/reports/premium-access/validation.md). The offline
runner now also tests Apple auth composition, account states, and CoreData data preservation;
it loads the real model/catalog resources into an isolated native XCTest bundle.
