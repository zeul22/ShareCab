# Matching Engine

How ShareCab pairs riders heading roughly the same direction. Implementation: [backend/src/services/matching.js](../backend/src/services/matching.js) (or wherever `match*` lives in the latest commit — search the controllers if it's moved).

## Goal

Given a new trip request `T`, find up to `maxRidersPerCab - 1` existing in-flight requests whose pickups and dropoffs are close enough to `T`'s that we can serve them in one cab without anyone losing too much time.

## Inputs

The matching pass runs per new `Trip` document. Inputs:

- `T.pickup.location` — GeoJSON Point.
- `T.dropoff.location` — GeoJSON Point.
- `T.shareEnabled` — boolean; user opted into sharing.
- `T.luggage` — affects cab capacity check.
- Tunables from [backend/src/config/env.js](../backend/src/config/env.js) under `match.*`.

## Tunables

| Key | Default | What it means |
|---|---|---|
| `MATCH_PICKUP_RADIUS_KM` | `2` | How far apart two pickups can be and still match. |
| `MATCH_DESTINATION_RADIUS_KM` | `4` | How far apart two dropoffs can be. |
| `MATCH_MAX_DETOUR_KM` | `2` | Total extra km on top of solo route for either rider. |
| `MATCH_MAX_RIDERS_PER_CAB` | `3` | Cap; 4-seater sedan minus the driver, leaving headroom for luggage. |
| `MATCH_DISPATCH_DELAY_MS` | `300000` (5 min) | Window a `shareEnabled` trip waits for a co-rider before falling back. |
| `MATCH_RIDER_ONLY` | `false` | When `true`, skip driver dispatch entirely — riders coordinate over chat. |

Tune by env var, no code change required.

## Algorithm (high level)

1. **Geo prefilter.** `Trip.find({ pickup.location: { $near: ... } })` using the 2dsphere index — fast.
2. **Candidate sieve.** For each candidate, check:
   - Pickup distance ≤ `pickupRadiusKm`.
   - Dropoff distance ≤ `destinationRadiusKm`.
   - Same `shareEnabled=true` flag.
   - Combined luggage fits the cab.
   - Detour from the optimal solo route ≤ `maxDetourKm` for both legs.
3. **Form a MatchGroup.** Up to `maxRidersPerCab` trips. The group has its own `_id`, an ordered list of trips, and a `status` (`open` → `matched` → `dispatched` → `in_progress` → `completed`).
4. **Schedule stops.** Pickups first, then dropoffs. Order: by detour minimisation. A real optimiser (OSRM / Google Directions waypoint optimization) would do better — this is the simplest order that guarantees no one is dropped before pickup, which is the only correctness constraint.
5. **Hold open.** If we found nothing, schedule a `setTimeout` for `dispatchDelayMs`. When it fires, the trip stays in `requested` state — the rider sees an empty-state UI and decides what to do (book solo, wait longer, cancel). We don't auto-fall-back to solo dispatch any more.

## Why it's simple

The naïve version reads like the academic paper version of ride-sharing matching. ShareCab's V1 deliberately avoids:

- Time-window prediction. We don't try to guess when each rider will reach pickup.
- Real-road detour math. We use straight-line haversine, which over-estimates detour on grid-pattern cities like Bangalore but under-estimates it where one-ways force long loops. Acceptable for a 2 km radius.
- ML re-ranking. With a few thousand active trips at peak, a brute-force candidate sieve is fast enough on M0.

These would matter at a different scale. They don't matter now.

## Rider-only mode

When `MATCH_RIDER_ONLY=true`:

- Trip creation works as normal.
- The matching pass still runs and pairs riders.
- The dispatch step is **skipped entirely** — no driver is assigned.
- Both matched riders see a "your match was found, coordinate via chat" screen.
- Settlement is rider-side: they take a cab together and split the fare informally.

This was the V1 launch mode. Flip to `false` once driver supply is on the platform.

## Unlock gating

The unlock check sits on `POST /trips/request`:

- In normal mode, the rider unlocks **before** the trip request goes through. No unlock token, no trip.
- In rider-only mode, the unlock moves to **match-reveal time** — rider only pays / watches ads after a match is confirmed. Reduces the perceived dead-money problem (you used to pay first, then maybe match, maybe not).

See [revenue.md](revenue.md) for the unlock economics.

## Fare calculation

See **[pricing.md](pricing.md)** for the full pricing model — vehicle classes, surge windows, distance bands, shared-fare allocation (proportional to each rider's solo leg, not flat-split), GST handling.

Implementation: [backend/src/services/fareService.js](../backend/src/services/fareService.js). All amounts are in **paise** on the wire (1 INR = 100 paise) to match Razorpay.

The matching engine itself doesn't compute fares — it pairs trips, then `tripController` calls `fareService.quoteSolo` / `quoteShared` for the breakdown that's stored on the Trip and shown to the rider.

## Where this can go wrong

- **Stale `Driver.currentLocation`** — if drivers stop pinging location (foreground push paused, OS killed the app), the 2dsphere query picks the wrong driver or no driver. Mitigation: [driver/lib/services/location_push_service.dart](../driver/lib/services/location_push_service.dart) ticks every 20s while online.
- **Match thrash** — same two riders match, one cancels, the other matches again with someone else. Worth adding a `recentMatchCooldown` if we see this in prod.
- **Stub-mode Razorpay** — the unlock flow accepts a synthetic `paymentRef` when keys aren't configured. Fine for dev; verify `RAZORPAY_KEY_SECRET` is set in prod before flipping `MSG91_DEV_FALLBACK=false`.
