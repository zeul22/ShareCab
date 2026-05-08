# ShareCab API Reference

Base URL: `http://localhost:4000/api`

All authenticated routes require an `Authorization: Bearer <token>` header. Tokens are returned by `/auth/signup` and `/auth/login`.

---

## Auth

### POST `/auth/signup`
Register a rider or driver.

```json
// rider
{ "name": "Asha", "phone": "9999999999", "password": "secret123", "role": "rider" }

// driver
{
  "name": "Ravi",
  "phone": "8888888888",
  "password": "secret123",
  "role": "driver",
  "driver": {
    "licenseNumber": "DL-1234",
    "vehicle": { "model": "Wagon R", "plate": "DL3CAB1234", "color": "white", "capacity": 4 }
  }
}
```
**Returns:** `{ token, user }`

### POST `/auth/login`
```json
{ "phone": "9999999999", "password": "secret123" }
```
**Returns:** `{ token, user }`

### GET `/auth/me`  (auth)
Current user.

---

## Users

### GET `/users/:id`  (auth)
Public profile.

### PATCH `/users/:id`  (auth, self or admin)
```json
{ "name": "...", "email": "...", "homeCity": "..." }
```

---

## Drivers  (auth, role=driver)

### POST `/drivers/online`
Marks the driver as available for dispatch.

### POST `/drivers/offline`
Marks the driver as unavailable.

### POST `/drivers/location`
```json
{ "lat": 28.61, "lng": 77.20 }
```
Persists the driver's current location for matching/dispatch.

> For continuous updates while driving, use the `driver:location` socket event instead of polling this endpoint.

---

## Trips

### POST `/trips/estimate`  (auth)
```json
{
  "pickup":  { "lat": 28.6315, "lng": 77.2167 },
  "dropoff": { "lat": 28.6448, "lng": 77.2167 }
}
```
**Returns:**
```json
{
  "solo":           { "total": 95, "distanceKm": 5.1, "durationMin": 12 },
  "sharedEstimate": { "perRider": 33, "groupTotal": 67 }
}
```

### POST `/trips`  (auth, rider)
Request a ride.
```json
{
  "pickup":  { "address": "Connaught Place", "lat": 28.6315, "lng": 77.2167 },
  "dropoff": { "address": "Karol Bagh",      "lat": 28.6448, "lng": 77.2167 },
  "shareEnabled": true
}
```
**Server flow:**
1. Persist trip in `requested`.
2. If `shareEnabled`, run the matching engine.
3. Assign nearest available driver (or driver for the whole match group).
4. Broadcast a `trip:update` over the socket channel.

### GET `/trips/mine`  (auth)
Last 50 trips for the authenticated rider.

### GET `/trips/:id`  (auth, participant)
Trip detail (populated with `matchGroup` and `driver`).

### POST `/trips/:id/cancel`  (auth, rider)
```json
{ "reason": "changed plans" }
```

### GET `/trips/groups/:id/fare`  (auth)
Per-rider fare breakdown for a match group.

---

## Ratings

### POST `/ratings`  (auth)
```json
{ "tripId": "...", "toUserId": "...", "stars": 5, "comment": "Good ride!" }
```
Updates the recipient's running average automatically.

---

## WebSocket (Socket.IO)

Connect to the same origin with `auth: { token }`:

```js
const socket = io('http://localhost:4000', { auth: { token } });
```

**Channels (auto-joined):**
- `user:{userId}` — private events
- `driver:{userId}` — for drivers, ride offers
- `trip:{tripId}` — explicit `socket.emit('trip:subscribe', tripId)` to join

**Events:**

| Direction | Event | Payload |
|---|---|---|
| client → server | `trip:subscribe` | `tripId` |
| client → server | `trip:unsubscribe` | `tripId` |
| client → server | `driver:location` (driver only) | `{ lat, lng, tripId? }` |
| server → client | `trip:update` | `{ id, status, driver, matchGroup }` |
| server → client | `driver:location` | `{ driverUserId, lat, lng }` |

---

## Trip Status Machine

```
requested
   │  matchingService finds group?      ┌──► matched ──► driver_assigned
   └──────────────────────────────────► │                      │
                                        └──► driver_assigned ──┘
                                                               ▼
                                                            arriving
                                                               ▼
                                                          in_progress
                                                               ▼
                                                          completed
                                                               
   any state ─► cancelled
```

---

## Errors

All errors are JSON of the form:

```json
{ "error": "Human readable message", "details": { ... }? }
```

Common codes: `400` validation, `401` auth, `403` forbidden, `404` not found, `409` conflict, `500` server.
