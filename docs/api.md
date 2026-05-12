# API Overview

The full endpoint reference is at [backend/docs/api.md](../backend/docs/api.md). This doc covers the cross-cutting bits — auth model, token lifecycle, conventions — that you need to understand before reading the endpoint list.

## Base URL

| Environment | URL |
|---|---|
| Local | `http://localhost:4000/api` (iOS sim), `http://10.0.2.2:4000/api` (Android emu) |
| Production | `https://sharecab-backend-XXX-asia-south1.run.app/api` |

All routes are under `/api`. The root path serves nothing.

## Auth model

Phone + OTP, no passwords for end-users. Two paths share the same `/auth/*` surface:

### MSG91 widget (production path)

```
┌────────────┐                ┌────────┐                  ┌────────┐
│ Flutter    │   sendOTP      │ MSG91  │                  │ Backend│
│ MSG91 SDK  ├───────────────►│ widget │                  │        │
│            │   on device    │        │                  │        │
│            │                └────────┘                  │        │
│            │                                            │        │
│            │   verifyOTP → access token                 │        │
│            │   (re-validated server-side)               │        │
│            ├──────────────────────────────────────────► │        │
│            │   POST /auth/otp/msg91/verify              │        │
│            │   { phone, accessToken }                   │        │
│            │                                            │        │
│            │              ┌─────────────────────────┐   │        │
│            │              │ MSG91 verifyAccessToken │ ◄─┤        │
│            │              └─────────────────────────┘   │        │
│            │                                            │        │
│            │   { accessToken, refreshToken, user }  ◄──┤        │
└────────────┘                                            └────────┘
```

The OTP itself never crosses our wire. We only see the JWT-style token that MSG91 hands the client *after* successful verification, and we re-validate it against MSG91's API before issuing our own session.

### Dev fallback (`MSG91_DEV_FALLBACK=true`)

`/auth/otp/request` returns `{"debugOtp": "123456"}`. `/auth/otp/verify` accepts only that exact code for any phone, auto-creates a rider account if the phone is new, and issues a session. **Never enable this in production.**

## Sessions

```jsonc
{
  "accessToken": "<JWT>",          // 7-day lifetime, signed with JWT_SECRET
  "refreshToken": "<JWT>",          // same JWT today (refresh-token rotation is a TODO)
  "accessExpiresAt": "2026-05-19T12:00:00.000Z",
  "user": { "id": "...", "name": "...", "phone": "+91...", "role": "rider", ... }
}
```

Clients persist this blob in `shared_preferences`. Both apps refresh silently via `POST /auth/refresh` when the access token is within 30 seconds of expiring; the user "stays logged in forever."

### Role baked into the JWT

The JWT payload carries `role`. Middleware (`requireRole('driver')`) reads it from the token, NOT from the database. So when the role changes (rider → driver after onboarding), the client must call `/auth/refresh` to mint a new JWT with the updated role. The driver app already does this in [driver/lib/screens/onboarding/onboarding_screen.dart](../driver/lib/screens/onboarding/onboarding_screen.dart) and as a defensive recovery in splash. See [runbook.md](runbook.md#forbidden-on-go-online).

## Conventions

| Convention | Detail |
|---|---|
| **Authorization** | `Authorization: Bearer <accessToken>` on every authenticated request. |
| **Content type** | `application/json` everywhere. No multipart yet (document upload is deferred). |
| **Phone format** | E.164 with `+91` prefix: `+919999999999`. Server normalises a few dialing variants but clients always send the canonical form. |
| **Currency** | Paise on the wire (`amountPaise: 49900` = ₹499). Format as INR at render time only. |
| **Coordinates** | `{ lat, lng }` floats; `[lng, lat]` arrays only when matching the GeoJSON Point spec on Mongo docs. Always within India — `isWithinIndia` in [backend/src/utils/geo.js](../backend/src/utils/geo.js) rejects out-of-bounds at the zod-refine layer. |
| **Errors** | `{ "error": "human-readable string" }` with the appropriate HTTP status. The Flutter clients show this verbatim to the user — keep the message actionable. |
| **Pagination** | Not implemented yet. `/rides/history` returns up to 50 most recent; revisit when that's a problem. |
| **Time** | ISO-8601 strings in UTC on the wire (`2026-05-12T14:30:00.000Z`). Render in IST on the client. |

## Endpoint surface (high level)

| Group | Mount | Purpose |
|---|---|---|
| `/auth/*` | [backend/src/routes/auth.routes.js](../backend/src/routes/auth.routes.js) | OTP send/verify, MSG91 exchange, refresh, logout. |
| `/users/*` | [backend/src/routes/user.routes.js](../backend/src/routes/user.routes.js) | Profile read/update. |
| `/trips/*` | [backend/src/routes/trip.routes.js](../backend/src/routes/trip.routes.js) | Request, match, lifecycle steps (arrive/picked-up/dropped). |
| `/drivers/*` | [backend/src/routes/driver.routes.js](../backend/src/routes/driver.routes.js) | Onboard, online/offline, location, dispatch, subscription. |
| `/unlocks/*` | [backend/src/routes/unlock.routes.js](../backend/src/routes/unlock.routes.js) | Rider ad/payment unlock flow. |
| `/payments/*` | [backend/src/routes/payment.routes.js](../backend/src/routes/payment.routes.js) | Razorpay order create + confirm + webhook. |
| `/chat/*` | [backend/src/routes/chat.routes.js](../backend/src/routes/chat.routes.js) | Group message history (live messages over socket.io). |
| `/ratings/*` | [backend/src/routes/rating.routes.js](../backend/src/routes/rating.routes.js) | Post-trip rating. |

Full request/response shapes live in [backend/docs/api.md](../backend/docs/api.md).

## Live tracking & ETA

`GET /trips/:id/driver-location` returns the assigned driver's current position + ETA to the next pending stop. Authenticated; rider must own the trip OR be a co-rider in its matchGroup. The rider app polls this every 5 seconds during `arriving` / `in_progress` to drive the driver marker + ETA chip on the live-ride screen.

Response shape:

```jsonc
{
  "driver": { "lat": 12.9716, "lng": 77.5946, "updatedAt": "2026-05-12T11:15:00.000Z" },
  "eta": {
    "toStop": "pickup",            // or "dropoff" once in_progress
    "seconds": 240,
    "distanceMeters": 1800,
    "source": "directions"         // or "haversine" when GOOGLE_MAPS_KEY unset / call failed
  }
}
```

ETA is `null` outside the active legs (no driver assigned yet, completed, cancelled). Distance + duration come from [directionsService](../backend/src/services/directionsService.js) (5-min cache by stop fingerprint); haversine fallback when the API is unavailable.

The driver app pushes its position every 20 seconds normally (matching engine's 2dsphere needs) and switches to **5 seconds** while on an active trip via [LocationPushService.useFastMode](../driver/lib/services/location_push_service.dart). Rider perceives ≤10 seconds of staleness while watching the cab approach.

**Actual pickup/drop GPS**: when the driver taps "Picked up" / "Dropped" on the active-trip screen, the app sends `{ lat, lng }` along with the lifecycle endpoint. Backend persists `trip.actualPickup` + `trip.actualDropoff` (recordedAt timestamps too). The rider's map snaps the source pin to `actualPickup` once status flips to `in_progress`. Older driver-app builds that omit coords still advance the lifecycle cleanly — the actuals field just stays empty.

## WebSockets

`socket.io` on the same Cloud Run service. Connect with the JWT in the `auth` field:

```dart
io(apiRoot.replaceAll('/api', ''), <String, dynamic>{
  'transports': ['websocket'],
  'auth': {'token': accessToken},
});
```

Events:

- `chat:message` — new message in a matched group.
- `chat:reset` — group composition changed (someone left); client should drop cached history and re-fetch.

Cloud Run supports WebSockets with a **60-minute** max session timeout. That's plenty for a chat conversation; the client reconnects automatically if disconnected.

## Rate limiting

None today. Add it before opening up to real traffic — Cloud Armor + a per-IP-per-route rule, or `express-rate-limit` if we want it in-app. Until then, the MSG91 widget's own throttling is our only protection against abuse.
