# Public Release Boundary Plan

ShareCab should be public-source/source-available with a usable demo path, but
not a turnkey clone of the official commercial service.

The public repository should let contributors understand, run, test, and improve
the core product mechanics. Production operations, real driver supply, live
provider credentials, and sensitive safety/fraud logic stay private.

## Release Modes

ShareCab should support two clearly separated modes.

| Mode | Audience | Purpose | Production credentials |
|---|---|---|---|
| Public demo/dev | Contributors, reviewers, students, auditors | Run the rider flow, matching, pricing, ad unlock, and payment simulations locally or against test providers. | Never required |
| Official production | ShareCab maintainers | Operate the real ShareCab rider and driver apps. | Required and private |

The public repo must default to public demo/dev mode. Production mode should
require explicit private configuration that is never committed.

## Public and Functional

These areas should work in the public repository with local services, test
provider accounts, or stubs:

| Area | Public behavior |
|---|---|
| Rider app | Phone login with dev OTP fallback, trip planning, place search with a user-supplied maps key, matching preferences, unlock choices, ride confirmation UI, and localized platform UI. |
| Matching engine | Real matching, radius, destination proximity, vehicle capacity, luggage, and detour rules using local/test data. |
| Pricing | Fare calculation, shared fare split, taxes/fees, unlock pricing, and testable pricing rules. |
| Ad-watch unlock | Rewarded-ad flow using test ad unit IDs or a stubbed "mark ad watched" provider in local demo mode. |
| Rider payment unlock | Razorpay test-mode flow or a stub payment provider that exercises the same backend state transitions without live money. |
| Backend API | Auth, matching, trip lifecycle, fare calculation, unlock ledger, payment state machine, and websocket events that do not require production secrets. |
| Website | Public product pages, docs links, support links, pricing explanation, and local build. |
| Tests | Backend tests, Flutter analyzer checks, and focused unit/widget tests around public behavior. |

These features may use fake users, fake drivers, fake payment references, and
fake ad rewards, but they should preserve the real state transitions so bugs are
meaningful.

## Public but Intentionally Limited

These areas can be visible in source but should not operate as real production
systems from the public repo:

| Area | Public boundary |
|---|---|
| Driver app | Source can remain public for review and UI development, but it should run only in demo/stub mode unless private production configuration is present. It should not connect public builds to real driver dispatch. |
| Driver onboarding | Public UI and validation are fine; real KYC, document review, and production approval stay private or stubbed. |
| Driver online/dispatch | Public demo may use simulated drivers. Real driver availability, acceptance, pickup sequencing, and route assignment for live rides require private production mode. |
| Admin operations | Public docs can describe roles and high-level workflows. Real admin dashboard, internal review tools, and audit operations remain private until explicitly cleared. |
| Safety escalation | Public app UX can show SOS/share-trip concepts. Real escalation contacts, law-enforcement playbooks, detection thresholds, and incident ops stay private. |

## Private Only

Never publish these in the public repository:

- Production `.env` files or derived build configuration.
- MSG91 production auth keys, backend auth keys, or server-side OTP provider
  credentials.
- Razorpay live keys, webhook secrets, settlement configuration, or live
  payment dashboards.
- Google Maps production keys, signing restrictions, or billing configuration.
- AdMob production ad unit IDs if they are tied to official monetization.
- App signing keys, keystores, certificates, provisioning profiles, App Store
  Connect credentials, or Play Console credentials.
- KYC provider credentials, webhook secrets, vendor-specific fraud responses, or
  real document verification payloads.
- Real rider, driver, trip, GPS, payment, support, complaint, or KYC data.
- Fraud heuristics, abuse thresholds, safety escalation rules, and internal
  enforcement playbooks that would help attackers bypass controls.
- Production infrastructure config that exposes project IDs, service accounts,
  private networks, database URLs, or observability tokens.

## Provider Boundary

Every external provider should have a public interface and at least one public
stub/test implementation:

| Provider | Public implementation | Private production implementation |
|---|---|---|
| OTP | Dev OTP or documented client widget setup without server secrets | MSG91 production server verification credentials |
| Ads | Test rewarded ads or stub rewarded-ad completion | Official AdMob units and revenue configuration |
| Payments | Razorpay test mode or stub payment confirmation | Razorpay live keys, webhook secrets, settlement config |
| Maps | User-supplied restricted key for local dev | Official production key and restrictions |
| KYC | Stub provider and public interface | Surepass/IDfy/HyperVerge credentials and webhook handling |
| Dispatch | Simulated drivers for demo trips | Real driver fleet availability and production dispatch |

This keeps the architecture reviewable without publishing production leverage.

## Required Code Changes Before Public Release

1. Add a single public demo switch, for example `SHARECAB_PUBLIC_DEMO=true`, that
   defaults to safe stub providers.
2. Make the backend refuse production driver dispatch unless an explicit private
   flag such as `ENABLE_PRODUCTION_DRIVER_OPS=true` is present.
3. Add demo driver seeding or simulated-driver dispatch so rider matching and
   ride confirmation can still be exercised without the real driver app.
4. Ensure ad-watch unlock can run with AdMob test IDs or a local stub.
5. Ensure rider payment unlock can run with Razorpay test mode or a local stub.
6. Keep provider interfaces public and production adapters secret/config-gated.
7. Add `.env.example` files that document only safe test/demo values.
8. Add CI for secret scanning, backend tests, Flutter analyze for rider/driver,
   and website lint/build.
9. Run a repository history secret audit before making the repo public. Rotate
   any credential that ever appeared in git history, even if the current file no
   longer contains it.
10. Keep support/security/conduct contacts pointed at a monitored project
    address.

## Public README Positioning

The public README should say:

- ShareCab is source-available for learning, review, and non-competing
  collaboration.
- The public demo supports rider planning, matching, ad-watch unlock, payment
  test/stub flows, pricing, and backend state transitions.
- The driver app is visible but not connected to official production driver
  operations from the public repo.
- Commercial or production use requires written permission.

## Decision Log

- The rider-side funnel is the primary public functional path.
- Matching, pricing, ad-watch unlock, and user payment state transitions should
  stay public because they are central to understanding ShareCab.
- Real driver operations are not public-functional at launch because they depend
  on KYC, fleet quality, safety operations, support, and compliance controls.
- Production provider credentials and sensitive operational logic stay private.
