# StoreKit 2 / Ate Plus implementation notes

Issue: [#41](https://github.com/melusi-k/ate-ios/issues/41)

## Confirmed product decision

- Offer monthly and annual subscriptions plus a lifetime, one-time purchase.
- Support a verified lifetime entitlement.
- Load localized product names/prices from StoreKit / App Store Connect. Never hard-code price amounts.
- Keep the StoreKit implementation isolated from auth/sync and other deferred platform work.

## Proposed App Store Connect product IDs

These identifiers are the app-side contract and must be created with matching types in App Store Connect before production purchase testing:

| Product ID | App Store Connect type |
| --- | --- |
| `com.melusik.ate.plus.monthly` | Auto-renewable subscription (monthly) |
| `com.melusik.ate.plus.annual` | Auto-renewable subscription (annual) |
| `com.melusik.ate.plus.lifetime` | Non-consumable (lifetime) |

The app grants access only for verified transactions in `Transaction.currentEntitlements`. Revoked transactions are ignored. StoreKit transaction updates are listened to and verified before finishing. Restore uses `AppStore.sync()` and then re-reads current entitlements.

## Scope implemented in this branch

- StoreKit 2 product loading and StoreKit-provided localized prices.
- Monthly, annual and lifetime purchase actions.
- Verified entitlement refresh and transaction update handling.
- Restore purchases, purchase cancellation/pending/error feedback.
- Settings entry point to Ate Plus and a paywall with Terms and Privacy links.

## Required setup / acceptance before release

- [ ] Create the three product records with the exact IDs and correct product types in App Store Connect.
- [ ] Set subscription durations, availability, prices, tax/banking agreements and review metadata in App Store Connect.
- [ ] Confirm lifetime benefits and the Plus feature matrix; the current app copy deliberately does not claim a specific premium feature set.
- [ ] Add a StoreKit Configuration file with these product IDs for deterministic local tests.
- [ ] Test successful, cancelled, pending, failed and restored purchases; expired/revoked subscription and lifetime transaction; no-network product loading; different storefront currencies.
- [ ] Verify restore and subscription management UX on a real device using Sandbox/TestFlight.
- [ ] Confirm subscription terms and applicable auto-renewal disclosures meet Apple's current review requirements.

## Validation status

No build, test suite, App Store Connect setup or device purchase test has been run as part of authoring these notes. Product IDs are proposed app-side contracts, not evidence that products already exist in App Store Connect.
