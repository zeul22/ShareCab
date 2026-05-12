# Revenue Model

ShareCab has two revenue streams: **rider unlocks** and **driver subscriptions**. Both flow through Razorpay where applicable.

## Rider unlock

Riders must "unlock" before they can be matched. They can pay this in either of two ways:

| Path | Cost to rider | We earn | Where defined |
|---|---|---|---|
| **Watch 2 rewarded ads** | ₹0 (time + attention) | AdMob CPM, typically ₹3-15 per pair of completed views in India | [app/lib/services/ad_service.dart](../app/lib/services/ad_service.dart) |
| **Pay a fixed unlock fee** | TBD (placeholder ₹5-15) | The full amount minus Razorpay fees (~2.5%) | [backend/src/controllers/unlockController.js](../backend/src/controllers/unlockController.js) |

The rider picks; we don't gate which is "preferred." Both lead to an `Unlock` document with a 30-minute TTL, after which they have to re-unlock.

### Why a TTL?

Without a TTL, a rider could unlock once and book ten trips. The TTL ties one unlock to one match search journey — long enough to complete the flow (pick locations → ads/payment → wait → confirm), short enough that hoarding doesn't work.

### Where the ad / payment sheet surfaces

| Mode | When the rider sees `MatchUnlockSheet` |
|---|---|
| **Driver-dispatch** (`MATCH_RIDER_ONLY=false`) | At trip-request time. The rider hits "Find a ride"; if there's no active `Unlock` doc, the backend returns 402 from `/trips`. The rider app catches this via `UnlockRequiredException` ([http_ride_api.dart](../app/lib/services/api/http_ride_api.dart)), opens the sheet, mints the unlock on success, and retries the trip request automatically. |
| **Rider-only** (`MATCH_RIDER_ONLY=true`) | At match-reveal time. The trip gets created free; once a co-rider matches, the rider has to unlock to see who matched and coordinate. Triggered from [match_result_screen.dart](../app/lib/screens/match_result_screen.dart). |

Same sheet, same two paths (ads OR Razorpay), different trigger point. The sheet supports both modes via a nullable `tripId` parameter — `null` means pre-trip mint (the freshly minted Unlock gets consumed by the next `/trips` call's `findOneAndUpdate`); non-null means consume against a specific matched trip.

### Rider-only mode shift

In `MATCH_RIDER_ONLY=true` mode, the unlock moves from **request time** to **match-reveal time**. Riders only commit (pay or watch ads) after seeing they were actually matched. This addresses the "dead money" problem during the early phase when match rates were low.

When `MATCH_RIDER_ONLY=false`, we revert to unlock-at-request because the match probability is high enough that pre-paying isn't a real risk.

### Ad-tier ramp by rider rating

Riders with a high rating get a cheaper unlock — fewer ads required. Implementation hook: `unlockController.adsRequiredForRating`. Encourages good rider behaviour (cancel less, rate co-riders, show up to pickup on time).

## Driver subscription

Drivers pay **₹499/month** (set via `DRIVER_SUBSCRIPTION_PRICE_PAISE=49900`) for the right to receive dispatches. Backend enforces:

- `Driver.verificationStatus === 'approved'` AND
- `Driver.subscriptionExpiresAt > now`

…before `/drivers/online` succeeds. New drivers get a **30-day free trial** at onboarding (`DRIVER_FREE_TRIAL_DAYS=30`) — set to `0` to disable once we no longer need to seed supply.

### Why subscription, not per-trip commission?

The standard ride-hailing model takes 15-30% of each trip's fare. We chose flat subscription instead because:

1. **Simpler accounting.** No GST / tax-on-services per-trip mess.
2. **Driver-friendly framing.** "Your fare is yours" beats "they take a cut" in driver acquisition.
3. **Predictable revenue.** Subscription MRR is easier to forecast than commission of variable trip volume.
4. **Lower-friction churn.** A driver who has a bad month can stay logged out and not pay; they're back the next month without owing anything.

Tradeoff: per-trip would scale revenue with usage. Subscription caps each driver at ₹499 regardless of how much they earn. We accept this — the goal is mass driver supply, not per-driver revenue optimisation.

### Driver take-home

Driver keeps **100% of the collected fare minus GST passthrough**. With the GST flag off (today), that's the full collected fare. The driver app's active-trip screen surfaces this as "You keep ₹X" alongside the total. Detail in [pricing.md](pricing.md#driver-take-home).

### Renewal flow

1. Driver app sees `daysLeft ≤ 3` and shows the urgent renewal banner.
2. Tap **Renew now** → backend creates a Razorpay order via `/drivers/subscribe`.
3. Razorpay checkout opens (or stub mode short-circuits when keys aren't configured).
4. On `payment.success`, app calls `/drivers/subscribe/confirm` with the Razorpay payment id + signature.
5. Backend verifies the HMAC, extends `subscriptionExpiresAt` by 30 days (from the *current* expiry if still active, so renewing early doesn't lose paid-up days).

Code path: [driver/lib/services/subscription_checkout.dart](../driver/lib/services/subscription_checkout.dart) → [backend/src/controllers/driverController.js](../backend/src/controllers/driverController.js) `confirmSubscription`.

### Reminders

Cron job stamps `subscriptionReminderSentAt` when a "renew soon" reminder fires for the current cycle. Cleared on successful renewal so the next cycle's reminder isn't deduped. V1 uses email-style logging only; FCM push is a follow-up.

## Cost economics (per driver, monthly)

Assuming a driver does 100 trips/month at ₹150 avg fare:

| Line item | Driver | Us |
|---|---|---|
| Fares collected from riders | ₹15,000 | — |
| Subscription paid | -₹499 | +₹499 |
| Razorpay fee (~2.5% on subscription) | — | -₹12 |
| KYC verification (one-time at onboarding) | — | -₹15-30 (amortised) |
| **Net per active driver/month** | **₹14,501** | **~₹485** |

At 10,000 active drivers, that's ~₹48.5L/month gross from subscriptions alone, before rider-side unlock revenue. Numbers are rough and pre-CAC — see investor deck for the full model.

## What's free / loss-leader

- Place autocomplete (Google Places API) — we pay Google per call.
- AdMob test ad units in development — no revenue, no cost.
- Free trial month for drivers — pure CAC.
- Cloud Run + Atlas during the GCP credit period — see [deployment.md](deployment.md).

## Future levers (not built yet)

- **Surge pricing** during peak hours. Would push `FARE_PER_KM` up dynamically.
- **Premium rider tier** — skip ads + priority matching for a monthly fee.
- **Driver tier** — higher-rated drivers get priority on shared trips.
- **B2B accounts** — corporate billing for employee daily commute.

None of these are committed; flagged here so they're in scope when the question comes up.
