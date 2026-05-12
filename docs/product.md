# ShareCab — Product Overview

A non-technical brief for stakeholders, investors, and new joiners. For the engineering view, start at [architecture.md](architecture.md).

## What it is

ShareCab is a **short-distance ride-sharing app** for India. Riders heading roughly the same direction (within ~2-4 km radius of each other's pickup + drop) get matched into one cab, splitting the fare ~30% lower than a solo ride.

Think Uber Pool, but **purpose-built for short city trips** rather than a feature bolted onto a general-purpose ride-hail app. The platform's primary use cases:

- Office commute to a metro station / co-working hub.
- Last-mile from a metro stop to a residential cluster.
- Mall, airport pickup, college campus runs.

We're not trying to be Uber. We're not trying to do long-distance. The geographic constraint is the product.

## Why this exists

Three observations:

1. **Empty seats are the unit economic problem in ride-hailing.** A four-seater cab carrying one person at peak demand is 75% empty. Better matching → more revenue per kilometre driven → cheaper rides and higher driver earnings.

2. **Existing pool products don't work well at short distances.** Uber Pool / Ola Share are tuned for 8-15 km trips. Match rates collapse at < 5 km because the detour cost grows as a fraction of the trip. ShareCab's algorithm is built for that range — a 2 km pickup radius is *aggressive* relative to a 3 km trip.

3. **India has a unique density curve.** Tier-1 cities have neighbourhood-clusters that concentrate origin/destination pairs: tech parks, market areas, station precincts. Density makes matching tractable in a way it isn't in suburban North American sprawl.

## Market scope

**India only.** Hard-coded throughout the stack:

- Coordinate validation rejects anything outside India's bounding box.
- Phones are E.164 with `+91` prefix; SMS via MSG91 (Indian DLT-compliant).
- Currency is INR / paise.
- Payments are Razorpay (Indian rails: UPI, cards, netbanking, wallets).
- Map tiles + routing are Google Maps (best India coverage among global providers).

International expansion is out of scope for the foreseeable future. The product would need substantial re-tooling for any new geography.

## Business model (TL;DR — see [revenue.md](revenue.md) for the full version)

Two revenue streams:

### 1. Rider unlocks

Riders pay to unlock matching for one search journey:

- **Watch 2 rewarded video ads** (free to the rider, we earn AdMob CPM), OR
- **Pay a fixed fee** (₹5-15 range; pricing TBD)

The unlock is valid for 30 minutes. After that, search again → unlock again.

### 2. Driver subscriptions

Drivers pay **₹499/month** for the right to receive dispatches. New drivers get the **first month free** while we seed supply. Drivers keep 100% of the fares collected — no per-trip commission.

This is unusual for ride-hailing (most platforms take 15-30% of each fare) and a deliberate positioning choice: driver acquisition is easier when we can say "your fare is yours."

## Stage

We're pre-launch as of 2026-05-12. Status:

- ✅ Rider app: feature-complete for v1 (book, match, chat, unlock, pay, rate).
- ✅ Driver app: feature-complete for v1 (onboard, online toggle, trip lifecycle, subscription).
- ✅ Backend: matching engine, fare calc, MSG91 OTP, Razorpay, all REST + socket endpoints.
- ⏳ Driver KYC integration (Surepass) — manual approval works at small scale.
- ⏳ GCP Cloud Run deployment — using $300 free credit for the first 90 days.
- ⏳ Production launch in one tier-1 city (Bangalore likely) once driver supply reaches viability threshold.

## Differentiation

What sets ShareCab apart from Uber / Ola / Rapido:

| Lever | ShareCab | Uber Pool / Ola Share | Rapido |
|---|---|---|---|
| Trip length focus | Short (< 5 km) | Long (8-15 km) | Short (bikes) |
| Matching radius | 2 km pickup, 4 km drop | 1-2 km pickup, much wider drop | N/A — solo |
| Driver fee model | ₹499/mo flat | 20-25% per trip | 18-25% per trip |
| Rider unlock model | Ads OR ₹5-15 per search | Built into fare | N/A |
| Vehicle | 4-7 seater shared | Same | 1-passenger bike |
| Geography | India only | India + global | India only |

The matching focus + driver fee structure are the two things competitors can't easily copy without re-tooling their entire economics.

## What's NOT on the roadmap

Worth saying out loud because they come up:

- **Long-distance trips** — handled by Uber/Ola; not a fight we want to pick.
- **Bike rides** — Rapido's market; cab-only is intentional.
- **Food/grocery delivery** — different product, different ops, different fleet.
- **Subscription tiers for riders** — maybe later; for now, ads/pay-per-search is sticky enough.
- **International** — see "Market scope" above.

## Where this doc points to next

- Engineers: [architecture.md](architecture.md), [getting-started.md](getting-started.md).
- Operators: [deployment.md](deployment.md), [runbook.md](runbook.md).
- Business / finance: [revenue.md](revenue.md), [driver-verification.md](driver-verification.md) (KYC cost breakdown).
- API consumers: [api.md](api.md).
