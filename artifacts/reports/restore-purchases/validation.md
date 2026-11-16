# Restore Purchases answer on the paywall - validation

Records the 2026-11-16 fix that puts the paywall's answer to a purchase or restore on screen (`docs/implementation-log.md`, "Restore Purchases says what it found on the paywall").
It names no account, email address, transaction or receipt.

## What was reported, and what was wrong

Restore Purchases did not bring Premium back on a phone signed in to an Apple Account.
The build had been installed from Xcode with the `RepToday` scheme after Premium was bought in a TestFlight build.
That scheme's Run action attaches `RepToday.storekit`, so the build used Xcode's local StoreKit test store (the system sheet reads "[Environment: Xcode]"), which holds only purchases made inside it.
Finding nothing there was correct; TestFlight and App Store builds never use the local store.
What was wrong is that the paywall showed no answer: the message was drawn below both plan cards, under the pinned Restore purchases button and off screen, so a Restore that found nothing, or failed, looked like nothing happened.

## Scenarios

Environment: iPhone 16 Simulator, iOS 18.6, Xcode 26.5, the local `RepToday.storekit` through `SKTestSession`.

| Scenario | Expected | Observed | Result | Evidence |
|---|---|---|---|---|
| Restore with an active subscription in the store | Premium unlocks, transaction linked to the account | Unlocked, one transaction linked | Pass | `RestorePurchasesStoreKitTests` |
| Restore with nothing in the store | "No active Premium subscription was found." on screen | Shown right above the Restore button | Pass | `storekit-restore-found-nothing-393x852.png` |
| Restore with a lapsed subscription | Same no-purchase answer | Same answer, nothing linked | Pass | `RestorePurchasesStoreKitTests` |
| Restore whose App Store sync fails | "We couldn't restore right now. Please try again later." on screen, nothing granted | Shown right above the Restore button | Pass | `storekit-restore-failed-393x852.png` |
| Fresh purchase | Premium unlocks | Unlocked, linked | Pass | `RestorePurchasesStoreKitTests` |
| The answer at the largest text size on a 375 x 667 phone | On screen, the plans not crowded out, the button label whole | Capped answer scrolls in place, label wraps | Pass | `*-375x667-ax5.png` |
| The original failure | The layout check fails on the old paywall | Every layout case and both on-screen StoreKit cases fail on the old `PaywallView` | Pass | `PaywallResultMessageLayoutTests` run against the previous layout |

## Not covered

A real-device restore in the App Store Sandbox or production was not run (no device was available); the StoreKit test session stands in for it.
The VoiceOver announcement and the scrolling answer at the largest text size are captain-verifiable on a device.
Recovery is an app update reverting `PaywallView`; nothing is persisted or migrated.
