# Pricing

The full picture of how a ShareCab fare is computed. Implementation: [backend/src/services/fareService.js](../backend/src/services/fareService.js). Tunables: [backend/src/config/env.js](../backend/src/config/env.js) under `fare:`.

## Headline

```
fare = (base + Σ(distance band × km in band) + perMin × min)        — per vehicle class
       × surge multiplier                                            — time-of-day
       + booking fee                                                 — flat platform charge
       + GST                                                          — visible line item, ₹0 until GSTIN
       ⇒ floored at vehicleClass.minFare
       ⇒ for shared trips, allocated proportional to each rider's solo leg
```

All amounts on the wire are in **paise** (1 INR = 100 paise) — matches Razorpay's amount field, avoids the rupees-vs-paise footgun the V1 code had.

## Vehicle classes

Classes are derived from the driver's vehicle capacity at onboarding:

| Driver vehicle capacity | Class |
|---|---|
| ≥ 6 seats | `suv` |
| ≥ 4 seats | `sedan` |
| otherwise | `hatchback` |

Each class has its own rates. Defaults (April 2026, INR):

| Class | Base | Per-min | Min fare | Distance bands |
|---|---|---|---|---|
| Hatchback | ₹25 | ₹1.00 | ₹50 | 0-3 km @ ₹12, 3-10 km @ ₹10, 10+ km @ ₹9 |
| Sedan | ₹30 | ₹1.50 | ₹70 | 0-3 km @ ₹15, 3-10 km @ ₹13, 10+ km @ ₹11 |
| SUV | ₹40 | ₹2.00 | ₹100 | 0-3 km @ ₹20, 3-10 km @ ₹17, 10+ km @ ₹15 |

Distance bands are **cumulative**: the first 3 km of any sedan trip cost ₹15/km. Kilometres 4-10 cost ₹13/km. Anything beyond 10 km is ₹11/km. Short rides cost more per km (fixed-cost amortization); long rides are cheaper per km (stays competitive on intercity-adjacent trips). Most apps don't expose this.

## Time component

Pre-pricing-rewrite we used `km / 25 km/h` as a hardcoded duration. Now [backend/src/services/directionsService.js](../backend/src/services/directionsService.js) calls Google Directions for the real ETA, accounting for traffic. Falls back to haversine + `fallbackSpeedKmph` (22 km/h default) when the key is missing or the call fails.

This matters: a 5 km trip during Bangalore rush hour can take 40 minutes — the ETA-based time component captures this, whereas the old formula priced it at the same 12 minutes a Sunday afternoon trip would take.

## Surge

Time-of-day windows, **not** demand-based (no driver-supply telemetry yet). Defined in [env.fare.surge.windows](../backend/src/config/env.js):

| Window | Days | Hours (local) | Multiplier |
|---|---|---|---|
| Weekday morning peak | Mon-Fri | 08:00, 09:00 | × 1.25 |
| Weekday evening peak | Mon-Fri | 18:00, 19:00, 20:00 | × 1.25 |
| Late night | Every day | 22:00-05:59 | × 1.20 |
| All other times | — | — | × 1.00 |

Surge applies to `(base + distance + time)`, before booking fee and GST. The breakdown shown to the rider has a separate **Surge** line, so the multiplier is transparent — no hidden upcharge.

Demand-based surge is a follow-up (needs the matching engine to emit supply/demand telemetry first).

### Global multiplier

`env.fare.surge.globalMultiplier` (default 1.0) is a knob on top of the window result — set to 1.5 during a city-wide event without re-deploying. **Capped at 2.0 by convention** — anything higher is irresponsible pricing for the Indian market.

## Booking fee

Flat ₹10 per trip (`FARE_BOOKING_FEE_PAISE=1000`). Within the typical Uber/Ola India range (₹5-25). Not subject to surge — it's a platform charge, not a fare component.

## GST

**Today: ₹0 line item.** ShareCab has no GSTIN, so we cannot legally collect GST.

When you obtain the GSTIN and set `FARE_GST_ENABLED=true`:
- 5% applied to `(subtotal + booking fee)`
- Shown as its own line in the breakdown
- Platform remits to the tax authority (section 9(5))
- Driver's take-home = total minus this GST

Keeping the line item visible-but-zero today means the UI doesn't change shape on activation. Riders see GST appear, not the whole layout shift.

## Minimum fare floor

If `(base + distance + time + surge)` is below `vehicleClass.minFare`, we floor to the minimum. Booking fee + GST get added on top. Common in India where ₹50 sedan rides would otherwise come out below the driver's break-even cost.

The breakdown sets `minimumFareApplied: true` so the rider sees a small "Minimum fare applied" line — no surprises.

## Shared-fare allocation

This is one of the three places we do better than Uber/Ola.

**The standard approach** (Uber Pool, Ola Share): combine the group's total fare and split equally. A rider whose pickup is on the way pays the same as a rider whose pickup added a 15-minute detour. Subjectively unfair; objectively encourages riders to game pickup locations.

**ShareCab approach**: each rider pays in proportion to their **own solo-leg distance**.

```
1. Compute each rider's solo subtotal independently (base + distance + time + surge)
2. Sum across the group  →  groupSum
3. groupTotal = groupSum × (1 - shareDiscount)        // default 30% off
4. Each rider's share = (their solo subtotal / groupSum) × groupTotal
5. Floor each share at the vehicle class's minFare    // hard contract
6. Add booking fee + GST per rider
```

Concrete: two-rider group, both sedan, off-peak:

| Rider | Solo distance | Solo subtotal | Group share (× 0.7) |
|---|---|---|---|
| A | 2 km | ₹62 → ₹70 floor | ₹70 floor + ₹10 booking = ₹80 |
| B | 6 km | ₹128 | ₹102 + ₹10 booking = ₹113 |
| **Driver collects** | | | **₹193** |
| **Solo equivalent total** | | | ₹70 (A) + ₹138 (B) = ₹208 |
| **Group saves vs solo** | | | ₹15 (≈ 7%) |

Rider A pays the floor; rider B pays proportionally less than their solo equivalent. The driver collects more total per km driven than they would on either solo trip alone.

## Driver take-home

Different from commission platforms. ShareCab is subscription-based — drivers pay ₹499/month and **keep 100% of the fare** they collect, minus GST passthrough when applicable:

```
driverPayout = total - GST
```

With GST disabled (today): `driverPayout == total`. Driver app's active-trip screen surfaces this as "You keep ₹X" alongside "Total to collect."

## Worked example

A sedan, 5 km, 18 min duration (Directions), weekday 9 AM (peak):

```
Components in paise:
  base                              3000   (sedan)
  distance:                         7100   (3 km × ₹15 + 2 km × ₹13)
  time (18 × ₹1.50):                2700
  --- subtotal pre-surge ---       12800
  surge × 1.25 → addition:          3200   (12800 × 0.25)
  --- subtotal post-surge ---      16000
  booking fee:                      1000
  GST (5%, disabled):                  0
  ----------------------------------------
  total:                           17000   = ₹170
```

Rider sees this exact breakdown on the [Ride Confirmation screen](../app/lib/screens/ride_confirmation_screen.dart) and again on the [Payment screen](../app/lib/screens/payment_screen.dart).

## Configuration

Hot env knobs:

| Env var | Default | Effect |
|---|---|---|
| `FARE_BOOKING_FEE_PAISE` | 1000 | Flat per-trip platform fee in paise. |
| `FARE_SHARE_DISCOUNT` | 0.30 | Off the combined solo total before allocation. |
| `FARE_GST_ENABLED` | false | Enables the 5% line item. **Requires GSTIN first.** |
| `FARE_GST_PCT` | 5 | GST rate; flip only if law changes. |
| `FARE_SURGE_GLOBAL_MULTIPLIER` | 1.0 | Stacks on top of time-window surge. Capped at 2.0. |
| `FARE_FALLBACK_SPEED_KMPH` | 22 | Used only when Directions is unavailable. |
| `GOOGLE_MAPS_KEY` | (empty) | Server-side Directions API key. Empty → haversine fallback. |

Per-class rates (base, perMin, minFare, distance bands) and surge windows live in code, not env, because changing them is a pricing-strategy decision that should land in code review.

## What's out of scope

- **Demand surge** — needs supply/demand telemetry. Post-launch.
- **Toll passthrough** — Indian roads + Google's API expose tolls inconsistently. Manual reconciliation for now.
- **Cancellation fees** — needs a cancellation policy and grace-window UX first.
- **Wait-time fees** — would need driver-side "I'm waiting" UI. Out for V1.
- **Weather / event surge** — needs external feeds.

When any of these become priorities, they slot into the fareService surface without breaking the existing breakdown shape — `components` is open-ended on the wire.

## Testing

[backend/tests/fareService.test.js](../backend/tests/fareService.test.js) covers:
- Vehicle class differences (hatch < sedan < SUV)
- Distance band boundaries (3 km, 10 km)
- Minimum fare floor on short trips
- Surge windows (off-peak / morning peak / evening peak / late night / weekend non-peak)
- Proportional shared allocation (short-leg rider pays less)
- Three-rider group totals sum to groupTotal
- GST line item: zero by default, 5% when enabled

24 tests; runs in ~200ms.
