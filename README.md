# ShareCab

ShareCab is a cab-sharing platform that helps individuals share rides when their destinations are nearby — usually within a **2–4 km radius**. Inspired by Uber, Ola, and Rapido, but focused specifically on short-distance route matching and shared cab usage.

The goal: make everyday cab rides cheaper and more convenient by intelligently matching nearby riders heading in the same direction.

---

## Monorepo Structure

```
ShareCab/
├── website/    # Next.js marketing & info website
├── app/        # Flutter mobile app (rider + driver)
├── backend/    # Node.js + Express API + matching engine
└── README.md
```

| Part        | Stack                          | Purpose                                              |
|-------------|--------------------------------|------------------------------------------------------|
| `website/`  | Next.js (App Router) + Tailwind | Public-facing site: home, how it works, pricing, etc.|
| `app/`      | Flutter                        | Mobile app for riders and drivers                    |
| `backend/`  | Node.js + Express + MongoDB    | REST + WebSocket API, matching engine, fare logic    |

---

## Quick Start

Each part has its own README with detailed run instructions:

- [website/README.md](./website/README.md)
- [app/README.md](./app/README.md)
- [backend/README.md](./backend/README.md)

```bash
# 1. Backend
cd backend && cp .env.example .env && npm install && npm run dev

# 2. Website
cd website && npm install && npm run dev

# 3. Flutter app
cd app && flutter pub get && flutter run
```

---

## Architecture Overview

```
   ┌─────────────┐         ┌─────────────┐
   │  Flutter    │         │  Next.js    │
   │   App       │         │  Website    │
   └──────┬──────┘         └──────┬──────┘
          │                       │
          │   REST + WebSockets   │
          └───────────┬───────────┘
                      ▼
              ┌───────────────┐
              │  Node.js API  │
              │  + Socket.IO  │
              └───────┬───────┘
                      │
        ┌─────────────┼──────────────┐
        ▼             ▼              ▼
  ┌──────────┐  ┌───────────┐  ┌────────────┐
  │ MongoDB  │  │ Matching  │  │ Notif. /   │
  │ (geo 2dsphere) │ Engine │  │ Fare svc   │
  └──────────┘  └───────────┘  └────────────┘
```

Core domain entities: **Rider**, **Driver**, **Trip**, **MatchGroup**, **Rating**.

---

## Brand & Tone

- **Name:** ShareCab
- **Voice:** simple, trustworthy, affordable, practical
- **Visual:** clean, calm, accessible — not flashy
- **Promise:** share the cab, split the fare, get there together

---

## License

MIT
