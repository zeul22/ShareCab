# ShareCab — Website

The public ShareCab website: home, how it works, pricing, safety, about, and contact. Built with Next.js (App Router), TypeScript, and Tailwind CSS.

## Stack

- **Framework:** Next.js 14 (App Router)
- **Language:** TypeScript
- **Styling:** Tailwind CSS
- **Deployment:** Vercel-ready (works anywhere Node 18+ runs)

## Quick Start

```bash
cp .env.example .env.local

npm install
npm run dev          # http://localhost:3000
```

## Scripts

| Command | Purpose |
|---|---|
| `npm run dev` | Local dev server |
| `npm run build` | Production build |
| `npm start` | Run production build |
| `npm run lint` | ESLint |

## Pages

- `/`               → Home (hero, value props, CTA)
- `/about`          → About ShareCab
- `/how-it-works`   → 5-step flow + matching explanation
- `/safety`         → Safety features and privacy
- `/pricing`        → Fare model, savings examples
- `/contact`        → Contact options + form

## Layout

```
website/
├── app/
│   ├── layout.tsx           # root layout, metadata, navbar + footer
│   ├── page.tsx             # home
│   ├── globals.css          # tailwind + base styles
│   ├── about/page.tsx
│   ├── how-it-works/page.tsx
│   ├── safety/page.tsx
│   ├── pricing/page.tsx
│   └── contact/page.tsx
├── components/              # Navbar, Footer, Section, FeatureCard
├── public/
├── tailwind.config.ts
├── postcss.config.js
├── tsconfig.json
└── next.config.js
```

## Design Notes

- **Tone:** simple, trustworthy, affordable, practical — not flashy.
- **Palette:** calm green (`brand-*`) on clean neutrals.
- **Type:** Inter, system-ui fallback.
- **Layout:** centered `.container-page` (max-w-6xl), generous `section` spacing.
- **Mobile-first:** all pages are responsive.

## Connecting to the backend

The marketing site is largely static. If/when you wire interactive forms (e.g. waitlist, contact), point them at `NEXT_PUBLIC_API_BASE` from `.env.local`.

## License

Source-available under the repository license. See [`../LICENSE.md`](../LICENSE.md).
