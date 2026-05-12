# Architecture

ShareCab is a monorepo of four services. They share data via the backend's REST/WebSocket API; there are no direct service-to-service calls between the clients.

## System diagram

```
                          ┌─────────────────────────┐
                          │   MongoDB Atlas (M0)    │
                          │  2dsphere geo indexes   │
                          └────────────▲────────────┘
                                       │ mongoose
                                       │
   ┌────────────────────────┐   ┌──────┴─────────┐   ┌────────────────────────┐
   │   Rider App (Flutter)  │   │   Backend      │   │  Driver App (Flutter)  │
   │   app/                 │◄──┤   backend/     ├──►│  driver/               │
   │                        │   │   Node + Exp.  │   │                        │
   │  - MSG91 OTP widget    │   │  REST + Socket │   │  - MSG91 OTP widget    │
   │  - Google Maps SDK     │   │  Matching eng. │   │  - Google Maps SDK     │
   │  - Razorpay checkout   │   │  Fare logic    │   │  - Razorpay checkout   │
   │  - AdMob rewarded ads  │   │  JWT auth      │   │  - Foreground location │
   └────────────────────────┘   └──────┬─────────┘   └────────────────────────┘
                                       │
                                       │  rest
                                       ▼
                          ┌─────────────────────────┐
                          │  Marketing site (Next)  │
                          │  website/               │
                          └─────────────────────────┘
```

## Services

| Path | Stack | What it does |
|---|---|---|
| [backend/](../backend/) | Node 20 + Express + Mongoose + socket.io | REST API, matching engine, fare calc, Razorpay verify, MSG91 verify, chat sockets. |
| [app/](../app/) | Flutter 3.19+ | Rider app: book trips, match with co-riders, unlock via ads/payment, chat, pay. |
| [driver/](../driver/) | Flutter 3.19+ | Driver app: onboard, go online, receive dispatch, run trip lifecycle, renew subscription. |
| [website/](../website/) | Next.js 14 (App Router) + Tailwind | Public marketing site. |

## Where state lives

- **MongoDB** — the only durable store. Models in [backend/src/models/](../backend/src/models/) (`User`, `Driver`, `Trip`, `MatchGroup`, `Message`, `Rating`, `Unlock`).
- **`shared_preferences`** (Flutter, both apps) — JWT session blob keyed by `sharecab.auth.session.v1` (rider) and `sharecab.driver.auth.session.v1` (driver). That's it; everything else is reloaded from the backend.
- **socket.io rooms** — ephemeral chat fan-out, no persistence (history comes from `/chat/:groupId` REST).
- **In-memory** on the backend — the dispatch timer that holds a `shareEnabled=true` trip open for 5 min before falling back. Will not survive a process restart; this is intentional for V1 because a restart cancels everything cleanly.

## Auth model

Phone + OTP only. Two paths to choose from at runtime:

1. **Production** — MSG91 widget SDK on the device sends + verifies the OTP, returns a widget access token, backend's `/auth/otp/msg91/verify` re-validates the token via MSG91's `verifyAccessToken` and issues our own JWT.
2. **Dev fallback** — when `MSG91_DEV_FALLBACK=true` on the backend, `/auth/otp/request` returns a debug OTP (`123456`) and `/auth/otp/verify` accepts only that code. Convenient for local development; **must never be set in production** — any phone can log in as anyone.

Sessions are JWTs signed by the backend (`JWT_SECRET`), 7-day lifetime, refreshed silently via `/auth/refresh`. See [api.md](api.md) for details.

## How the apps differ

Despite both being Flutter, the rider and driver apps are separate Flutter projects with separate package names. They share the *patterns* (auth service, MSG91 OTP screens, theme) but not the *code* — each was scaffolded independently so we don't pay the cross-service coupling tax. Where logic is genuinely identical (e.g. the driver-dispatch lifecycle), it was ported by copy from [app/lib/](../app/lib/) into [driver/lib/](../driver/lib/) with import paths adjusted.

## Things that look like they should be services but aren't

- **Payment** — Razorpay is a client SDK + backend webhook verifier. No separate payment service.
- **Notifications** — V1 uses `flutter_local_notifications` (foreground only). FCM is a deferred upgrade — see [app/docs/notifications.md](../app/docs/notifications.md).
- **Search** — There is no Elasticsearch / Algolia. Place autocomplete is Google Places, called from the rider client directly with `GOOGLE_MAPS_KEY`.
- **Image storage** — No S3/GCS yet. Driver document uploads are stubbed in the onboarding wizard; the file paths stay client-side. Backend wiring will land alongside the KYC integration.

## Live tracking & ETA

Once a driver is dispatched, the rider's live-ride screen polls `GET /trips/:id/driver-location` every 5 seconds to drive the map marker + ETA chip. Same data feeds both — driver position from the most recent ping, ETA computed server-side via the Directions API (haversine fallback). Driver app tightens its location-push cadence from 20s → 5s during an active trip so the rider sees ≤10 seconds of staleness.

The rider's source pin snaps to `actualPickup` GPS once the driver taps "Picked up" — distinct from the requested pickup (where the rider tapped on the map at booking), since the cab usually stops where it can pull over rather than exactly on the pin. Same model for `actualDropoff` at trip completion. Both are stored on the Trip for audit/dispute.

Full request/response shape in [api.md](api.md#live-tracking--eta).

## Cross-cutting concerns

| Concern | Where | Notes |
|---|---|---|
| Geo bounds (India-only) | [backend/src/utils/geo.js](../backend/src/utils/geo.js) `isWithinIndia` | Every endpoint that takes coords runs this check via zod refines. |
| Currency | Backend & client | Always paise (₹1 = 100 paise) on the wire. Format in INR only at render time. |
| Trip distance rails | [backend/src/config/env.js](../backend/src/config/env.js) `trip.minDistanceKm` / `maxDistanceKm` | 0.3 km – 100 km. Shorter is a misclick; longer is intercity. |
| Rider-only mode | `MATCH_RIDER_ONLY=true` | Skips driver dispatch entirely; riders coordinate via chat. Use while bootstrapping driver supply. |
