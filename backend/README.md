# ShareCab — Backend

Node.js + Express + MongoDB API for the ShareCab cab-sharing platform. Provides authentication, ride booking, the **cab-share matching engine**, fare estimation, realtime location via WebSockets, ratings, and an admin-ready domain model.

## Stack

- **Runtime:** Node.js 18+
- **Framework:** Express 4
- **Database:** MongoDB (with `2dsphere` indexes for geo queries)
- **Auth:** JWT (Bearer token)
- **Realtime:** Socket.IO
- **Validation:** Zod

## Quick Start

```bash
cp .env.example .env
# Edit .env (especially MONGODB_URI and JWT_SECRET)

npm install
npm run dev          # starts on http://localhost:4000
```

Health check: `GET http://localhost:4000/health`

## Project Layout

```
backend/
├── src/
│   ├── index.js              # bootstrap — connects DB, starts HTTP + Socket.IO
│   ├── app.js                # Express app, middleware, routes
│   ├── config/
│   │   ├── database.js       # Mongo connection
│   │   └── env.js            # typed env reader (with sane defaults)
│   ├── models/               # Mongoose schemas
│   │   ├── User.js
│   │   ├── Driver.js
│   │   ├── Trip.js
│   │   ├── MatchGroup.js
│   │   └── Rating.js
│   ├── routes/               # one file per resource
│   ├── controllers/          # request → service orchestration
│   ├── services/
│   │   ├── matchingService.js     # the cab-share matching engine
│   │   ├── dispatchService.js     # nearest-driver assignment
│   │   ├── fareService.js         # solo + shared fare math
│   │   └── notificationService.js # FCM/SMS/socket fan-out
│   ├── middleware/
│   │   ├── auth.js
│   │   ├── validate.js
│   │   └── errorHandler.js
│   ├── sockets/              # Socket.IO server (live location, trip updates)
│   └── utils/
│       ├── logger.js
│       └── geo.js            # haversine + GeoJSON helpers
└── docs/
    └── api.md                # full API reference
```

## Domain Model

```
User ──┬── (role=rider)──── Trip ──┐
       │                            ├── MatchGroup (2-3 trips share one cab)
       └── (role=driver)── Driver ──┘
                   │
                   └── currentLocation (2dsphere)

Rating: { trip, fromUser → toUser, stars }
```

## The Matching Engine (Short Version)

For a freshly requested trip, the engine tries — in order:

1. **Join an existing forming group** whose centroid pickup is within `MATCH_PICKUP_RADIUS_KM` (default 2 km) and whose centroid drop is within `MATCH_DESTINATION_RADIUS_KM` (default 4 km). Honors `MATCH_MAX_RIDERS_PER_CAB` (default 3).
2. **Pair with another solo `requested` trip** with compatible pickup + drop, forming a new MatchGroup.
3. **Fall back to solo dispatch** if no compatible co-rider exists.

All radii and limits are tunable via env. See [docs/api.md](./docs/api.md) for the full event flow.

## Available Scripts

```bash
npm run dev    # nodemon (auto-reload)
npm start      # production
npm run lint   # eslint
```

## API Documentation

See [docs/api.md](./docs/api.md) for the full REST + WebSocket reference.

## Environment Variables

See [.env.example](./.env.example) — every variable has a comment explaining its purpose. Key ones:

| Variable | Purpose |
|---|---|
| `MONGODB_URI` | Mongo connection string |
| `JWT_SECRET` | Sign / verify auth tokens |
| `MSG91_AUTH_KEY` | Server-side MSG91 authkey used to validate widget access tokens |
| `MSG91_WIDGET_ID` | Public MSG91 widget id served to the Flutter app when dart-defines are absent |
| `MSG91_WIDGET_AUTH_TOKEN` | Public MSG91 widget token served to the Flutter app; do not put `MSG91_AUTH_KEY` here |
| `MSG91_DEV_FALLBACK` | Local-only OTP bypass; never enable in production |
| `MATCH_DESTINATION_RADIUS_KM` | Max distance between two riders' destinations to count as "shareable" |
| `MATCH_PICKUP_RADIUS_KM` | Max distance between pickups |
| `MATCH_MAX_RIDERS_PER_CAB` | Cap on how many riders share one cab |
| `FARE_*` | Fare model parameters |

## Production Notes

This scaffold is production-ready in shape but not in everything. Before going live you should:

- Replace the in-process matching with a queue-backed worker (BullMQ / Kafka).
- Wire `notificationService` to FCM / APNS / Twilio.
- Add a routing engine (OSRM / Google Directions) to the fare and dispatch services for accurate ETAs and detour calculations.
- Add request-level idempotency keys for trip creation and payments.
- Add observability: structured logs, traces, metrics, alerting.

## License

MIT
