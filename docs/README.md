# ShareCab Documentation

Cross-cutting docs for the ShareCab monorepo. Per-service deep dives live alongside the code (e.g. [backend/docs/api.md](../backend/docs/api.md)) — this folder covers the seams between services and the things every contributor needs to know.

## Contents

### Start here
- [Architecture](architecture.md) — what the four services are, how they fit together, where state lives.
- [Getting Started](getting-started.md) — clone, install, and run everything locally in 15 minutes.

### Building & shipping
- [Deployment](deployment.md) — GCP Cloud Run + MongoDB Atlas; the production target.
- [Razorpay setup](razorpay-setup.md) — end-to-end walkthrough from test-mode signup to live-mode KYC.
- [Runbook](runbook.md) — operational tasks, common failure modes, and recovery recipes.

### Reference
- [API](api.md) — auth model + endpoint overview (full reference in [backend/docs/api.md](../backend/docs/api.md)).
- [Matching engine](matching.md) — how the geo + detour algorithm pairs riders.
- [Pricing](pricing.md) — vehicle classes, surge, distance bands, GST, shared-fare allocation.
- [Revenue model](revenue.md) — rider ad/payment unlock + driver subscription.
- [Driver verification](driver-verification.md) — onboarding, KYC strategy, verification states.

### Non-technical
- [Product overview](product.md) — what ShareCab is, market scope, pricing.

## Conventions

- All code examples assume macOS — most of us develop on it. Linux is fine; Windows is untested.
- Indian-context defaults run throughout: phones in `+91XXXXXXXXXX`, currency in paise (`₹1 = 100 paise`), coordinates bounded to India.
- When a doc cites a file:line, the link is clickable in IDE-aware viewers. Code moves fast — verify before relying on a specific line number.

## When to update these docs

- A new service or major dependency joins the stack → update [architecture.md](architecture.md).
- A new env var or secret → update [deployment.md](deployment.md) AND [getting-started.md](getting-started.md).
- A new monetisation lever → update [revenue.md](revenue.md).
- An incident → write the recovery into [runbook.md](runbook.md) so the next person doesn't rediscover it.
