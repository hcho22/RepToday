# Trial-to-paid `subscribe` StoreKit verification

This is the re-runnable framework integration recipe for the trial-conversion observer. The unit
suite can deterministically exercise every classification and dedup branch through `StoreKitFacade`,
but it cannot manufacture an App Store-signed `VerificationResult<Transaction>` or prove when
StoreKit posts an automatic renewal to `Transaction.updates`.

## Automated decision coverage

Run:

```sh
xcodebuild \
  -project ios/RepToday/RepToday.xcodeproj \
  -scheme RepToday \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  test \
  -only-testing:RepTodayTests/StoreKitSubscriptionServiceTests
```

The tests use an isolated `UserDefaults` suite and `MockAnalyticsService`; they send no telemetry.
They cover the qualifying conversion, canonical `plan`, exact StoreKit purchase timestamp, direct
purchase, initial trial, repeat delivery, later paid renewal, ordinary paid chain, pending purchase,
current-entitlement and restore reads (including an update delivered during restore),
unverified/revoked updates, relaunch dedup, and the bounded 32-id replacement rule.

## Local StoreKit Configuration recipe

1. In Xcode, select the `RepToday` scheme and confirm Run > Options > StoreKit Configuration is
   `RepToday.storekit`. The generated scheme already points to this file.
2. Open `RepToday/Resources/RepToday.storekit`. In its StoreKit test settings, choose a fixed,
   accelerated Subscription Renewal Rate such as one renewal every 30 seconds. Leave billing retry,
   interrupted purchases, and Ask to Buy disabled for the happy-path pass.
3. Clear prior local transactions with Debug > StoreKit > Manage Transactions, uninstall the test
   app (which also clears `telemetry.trialConversionTransactionIDs`), then run a Debug build. Use
   a disposable development telemetry install; never point this recipe at production.
4. Open the paywall and buy `com.reptoday.app.premium.monthly`, whose local configuration carries
   the two-week introductory free trial. In the transaction manager, verify the initial transaction
   is an introductory free-trial purchase. Observe one `trial_started` and no `subscribe` for it.
5. Keep the app running until StoreKit Testing creates the first renewal. In the transaction manager,
   verify it is a renewal with a different transaction id, the same original transaction id, no
   free-trial offer, and the configured positive monthly price. Observe exactly one `subscribe` with
   `plan = com.reptoday.app.premium.monthly`.
6. Allow or force one more renewal. Observe no additional `subscribe`; it is an already-paid renewal.
7. Repeat from a clean transaction history with the yearly product, which has no introductory offer.
   Observe the paywall's direct-purchase `subscribe`, then confirm its first renewal produces no second
   observer event.
8. Repeat the monthly trial but refund/revoke the first renewal in the transaction manager before the
   observer handles it (use a debugger pause if needed). Confirm a revoked update emits nothing. Run
   an Ask-to-Buy/pending purchase separately and confirm it emits neither monetization event before
   approval.
9. After the first conversion is observed, quit and relaunch the app, then use the transaction
   manager to resend that renewal. Observe no second `subscribe`. Run Restore Purchases and confirm
   that neither the current-entitlement read nor any historical update delivered by the restore
   emits an event.

## What this proves—and what it does not

The manual pass proves the local StoreKit test environment supplies the offer, price, reason,
original id, transaction id, and update timing the classifier consumes, and that the real startup
listener remains active through renewal. It does not prove production App Store delivery, financial
reporting, or server-side exactly-once receipt. `AnalyticsServiceProtocol.record(_:)` remains the
delivery boundary; consent, queueing, and retries belong to that implementation. If StoreKit does not
provide a positive transaction price, the observer intentionally emits nothing rather than claiming a
paid conversion it cannot prove.

Deduplication persists only qualifying conversion transaction ids as decimal strings—never a receipt,
product, price, date, or transaction history. It retains the newest 32 and replaces the oldest on the
33rd distinct conversion. This makes ordinary StoreKit redelivery and relaunch at-most-once while an
id remains inside the documented bound; it is not a claim of server-side exactly-once delivery.
