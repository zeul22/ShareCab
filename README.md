<p align="center">
  <img src="./app/assets/appIcon.png" alt="ShareCab app icon" width="120" height="120">
</p>

# ShareCab

**ShareCab helps riders heading in the same direction share one cab, split the fare, and travel with better visibility and trust.**

The product is built for city rides where two or more people have nearby pickup and drop points. Instead of every rider booking a separate cab, ShareCab looks for compatible riders within a practical distance band, groups them into one shared trip, and gives the driver a clear pickup and trip flow.

ShareCab is not just a cheaper taxi clone. It is a cab-sharing system with rider matching, fare splitting, OTP-based pickup safety, driver dispatch, trip tracking, chat, ratings, and payment/unlock flows.

---

## What ShareCab Does

For riders:

- Find a cab-share match for short city trips and airport pickup flows.
- Match with riders whose destinations are nearby, typically within a configurable **2-4 km radius**.
- Compare shared and solo ride options before committing.
- Unlock serious matches through ads or payment so low-intent requests do not flood the system.
- Confirm pickup with an OTP, chat with the group, track trip status, and rate the experience.

For drivers:

- Go online, receive dispatches, view rider pickup details, and manage the active trip lifecycle.
- Use pickup OTP verification before starting a ride.
- Keep access controlled through driver subscription and onboarding flows.

For the platform:

- Run matching, fare calculation, dispatch, authentication, payments, realtime updates, and notifications from one backend.
- Tune matching rules such as pickup radius, destination radius, detour limits, cab capacity, and luggage constraints.

---

## Monorepo Structure

```
ShareCab/
|-- website/    # Next.js marketing and info website
|-- app/        # Flutter rider app
|-- driver/     # Flutter driver app
|-- backend/    # Node.js + Express API, matching engine, and realtime services
|-- docs/       # Cross-cutting product, architecture, deployment, and API docs
`-- README.md
```

| Part | Stack | Purpose |
|---|---|---|
| [website/](./website/) | Next.js App Router + Tailwind | Public ShareCab website. |
| [app/](./app/) | Flutter | Rider app: phone login, ride planning, matching, unlocks, chat, payment, trip status. |
| [driver/](./driver/) | Flutter | Driver app: onboarding, online status, dispatch acceptance, pickup OTP, active trip flow. |
| [backend/](./backend/) | Node.js + Express + MongoDB | REST and WebSocket API, auth, matching, dispatch, fare logic, payments, notifications. |

---

## How The Ride Flow Works

1. A rider enters pickup, destination, luggage, and sharing preferences.
2. The backend searches for compatible riders near the same route corridor.
3. ShareCab proposes a shared match when pickup distance, destination distance, detour, vehicle capacity, and luggage rules are acceptable.
4. The rider unlocks or accepts the match, then receives driver, vehicle, fare, chat, and pickup OTP details.
5. The driver verifies the pickup OTP, starts the ride, and progresses the trip through completion.
6. Riders pay, rate the trip, and keep their account session through phone OTP authentication.

---

## Documentation

Start with **[docs/](./docs/)** for cross-cutting context — architecture, deployment, API, runbook.

| If you are… | Read |
|---|---|
| A new engineer | [docs/architecture.md](./docs/architecture.md) → [docs/getting-started.md](./docs/getting-started.md) |
| Shipping to production | [docs/deployment.md](./docs/deployment.md) → [docs/runbook.md](./docs/runbook.md) |
| Integrating against the API | [docs/api.md](./docs/api.md) → [backend/docs/api.md](./backend/docs/api.md) |
| Curious about the product | [docs/product.md](./docs/product.md) |

Per-service deep dives live alongside the code: [backend/docs/api.md](./backend/docs/api.md), [app/docs/notifications.md](./app/docs/notifications.md).

---

## Quick Start

```bash
# 1. Backend
cd backend && npm install && npm run dev    # http://localhost:4000

# 2. Rider app
cd app && flutter pub get && flutter run    # iOS sim or Android emu

# 3. Driver app
cd driver && flutter pub get && flutter run

# 4. Website
cd website && npm install && npm run dev    # http://localhost:3000
```

Full setup with env vars + first-run sanity check in [docs/getting-started.md](./docs/getting-started.md).

---

## Brand & Tone

- **Name:** ShareCab
- **Voice:** simple, trustworthy, affordable, practical
- **Visual:** clean, calm, accessible — not flashy
- **Promise:** share the cab, split the fare, get there together

---

## License

MIT
