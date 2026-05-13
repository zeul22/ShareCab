# ShareCab roadmap — source-available release, safety, KYC

This document is the authoritative roadmap for taking ShareCab from its current "MVP that matches riders + dispatches drivers" state to a platform that can credibly run real commercial rides AND be released as a public source-available project. It supersedes any informal notes.

The document is intentionally phased — each phase is a defensible 1–3 day chunk of work, ordered so an earlier phase doesn't block a later one. Do not skip ahead; the phases are sequenced for a reason.

## Guardrails (non-negotiable rules)

Lifted verbatim from the product brief — these are the rules every code path must respect once Phase 1 ships:

- **No verified commercial vehicle, no ride.**
- **No approved driver, no ride.**
- **No valid documents, no ride.**
- **No safety trail, no ride.**

Concretely: a driver only enters the dispatch candidate pool when their `Driver.verificationStatus === 'APPROVED'` AND every required document is currently valid AND their vehicle is flagged as commercial/yellow-plate. The matching service must enforce this server-side regardless of what the driver app sends.

## Scope choices already locked

These were resolved before this roadmap was written and apply to every phase:

- **Source-available preparation = files + boundary docs only.** No monorepo restructure into `apps/`/`packages/`/`server/` unless and until there's a concrete reason (a public mirror gating it, a code-share dependency, etc.). Restructure has zero product value and a high churn cost — see [Phase 2](#phase-2--source-available-readiness-files--boundary-docs).
- **KYC vendor = interface + stub for now.** Real vendor wiring (Surepass / IDfy / HyperVerge / etc.) is deferred to [Phase 10](#phase-10--kyc-vendor-wiring-real). The interface is designed in [Phase 3](#phase-3--kyc-provider-interface--stub) so swapping a vendor in later is a one-file change.
- **Yellow-plate validation = manual review now, RC API later.** Driver uploads plate photo + ticks "commercial" + admin reviews. Schema is shaped so an RC API can fill the fields automatically once a KYC vendor is wired (Phase 10). See [Phase 1](#phase-1--verification-state-machine--ride-eligibility-gate).

## Current state (as of this writing)

What ShareCab already has, so we don't accidentally rebuild it:

- **Phone OTP auth** for both rider and driver apps via MSG91, with a dev-OTP fallback. [`app/lib/services/auth_service.dart`](../app/lib/services/auth_service.dart), [`driver/lib/services/auth_service.dart`](../driver/lib/services/auth_service.dart).
- **Driver onboarding wizard** — 4 steps (Personal / Vehicle / Documents-stub / Review). [`driver/lib/screens/onboarding/`](../driver/lib/screens/onboarding/). The Documents step is UX-complete but uploads are stubbed.
- **Verification status** as a simple `'pending' / 'approved' / 'rejected'` enum on the Driver doc. [`backend/src/models/Driver.js:21`](../backend/src/models/Driver.js#L21). Promoted manually (no admin UI yet; a flag enables auto-approve for dev).
- **Match-then-dispatch flow** — riders match into a `MatchGroup`, both tap Find Cab, backend offers the trip to the nearest online driver with a 30s window. Driver acceptance / rejection / expiry / re-dispatch all work. [`backend/src/services/dispatchService.js`](../backend/src/services/dispatchService.js).
- **Per-rider OTP at pickup** — server-issued 4-digit code stored on the Trip, verified in `pickUpRider`. [`backend/src/controllers/tripController.js`](../backend/src/controllers/tripController.js).
- **Subscription gate** for driver online toggle — driver must have a non-expired subscription to go online. [`backend/src/controllers/driverController.js setOnline`](../backend/src/controllers/driverController.js).
- **Razorpay integration** for the ₹499/month driver sub and the rider unlock flow (test mode).
- **150+ backend tests** in `backend/tests/`.

What ShareCab does NOT yet have (and is therefore in scope for this roadmap):

- Full driver KYC: identity, DL, RC, permit, fitness, insurance, PUC, bank verification.
- Yellow-plate / commercial vehicle classification.
- Document expiry tracking + auto-block.
- KYC provider abstraction.
- Safety: SOS, share-trip-link, route-deviation detection, long-stop detection.
- Complaint / dispute / refund flow.
- Admin dashboard (any kind, backend or UI).
- Source-available/community files (LICENSE, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT).
- Rider verification beyond phone OTP.
- Audit logs for admin actions.

## What's public vs what's private

Source of truth for the public/private split. When in doubt, default to PRIVATE.

**Safe to publish (= rider/driver/web apps + non-sensitive shared code):**
- [`app/`](../app/) — rider Flutter app, UI and logic
- [`driver/`](../driver/) — driver Flutter app, UI and logic
- [`website/`](../website/) — Next.js marketing site
- [`docs/`](../docs/) — architecture, API surface, this roadmap
- Pricing engine source ([`backend/src/services/fareService.js`](../backend/src/services/fareService.js))
- Matching engine source ([`backend/src/services/matchingService.js`](../backend/src/services/matchingService.js))
- API contracts (request/response shapes) — `docs/api.md`, etc.
- Stub KYC provider ([Phase 3](#phase-3--kyc-provider-interface--stub))
- Public test suites that don't reveal fraud heuristics

**Stays private (= anything that, if leaked, gives an attacker leverage):**
- KYC vendor credentials, webhook secrets, API keys
- Payment credentials (Razorpay key/secret, webhook secret)
- Fraud detection rules + thresholds (would tell attackers what to avoid)
- Safety escalation engine internals (would tell bad actors how to evade detection)
- Admin dashboard internals (auth flow, role boundaries, internal endpoints)
- Driver / rider documents (DL scans, Aadhaar masks, selfies)
- Live GPS traces (re-identifiable PII)
- Emergency escalation playbook (police contacts, lawyer SOPs)
- Production infrastructure configs (Cloud Run YAML, Atlas connection strings, monitoring tokens)
- `.env*` files of any kind in production
- Logs (which contain PII regardless of best efforts)

The split is enforced by **what gets committed to the public repo**, not by directory structure. We do NOT restructure into `apps/`/`packages/`/`server`/`private-services/` — Phase 2 just documents the boundary and adds the public project files. Splitting public vs private repos can happen later if there's a real need.

---

## Phase plan

```
                       Phase 1   verification state machine + ride-eligibility gate
                          │
                          ▼
                       Phase 2   source-available readiness (files + boundary docs)
                          │
                          ▼
                       Phase 3   KYC provider interface + stub
                          │
                          ▼
                       Phase 4   document expiry tracking + auto-block
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
           Phase 5     Phase 6     Phase 7
         safety MVP   complaint   admin
         (SOS,        + report    backend
          share       flow        (KYC
          trip,                   review,
          route                   suspend,
          deviation)              audit)
              │           │           │
              └───────────┼───────────┘
                          ▼
                       Phase 8   rider light KYC
                          │
                          ▼
                       Phase 9   public-mirror release
                          │
                          ▼
                       Phase 10  real KYC vendor wiring
```

Phases 5, 6, 7 are independent and can run in parallel by different people. Everything else is sequential.

### Phase 1 — Verification state machine + ride-eligibility gate

**Why first**: every other phase assumes the verification state machine exists. Cheapest place to land the new shape, smallest blast radius.

**Scope:**

1. Replace `Driver.verificationStatus` enum on [`backend/src/models/Driver.js:21`](../backend/src/models/Driver.js#L21) with the fuller machine from the prompt:
   ```
   DRAFT, BASIC_PROFILE_SUBMITTED, IDENTITY_PENDING, IDENTITY_VERIFIED,
   DL_PENDING, DL_VERIFIED, VEHICLE_PENDING, VEHICLE_VERIFIED,
   BACKGROUND_CHECK_PENDING, MANUAL_REVIEW,
   APPROVED, REJECTED, SUSPENDED, EXPIRED_DOCUMENT
   ```
   Add a Mongo migration that maps existing `'pending'` → `MANUAL_REVIEW`, `'approved'` → `APPROVED`, `'rejected'` → `REJECTED` so live drivers don't get nuked.
2. Add a `Vehicle` sub-doc on Driver (or a separate `Vehicle` collection — see [Phase 4 notes](#phase-4--document-expiry-tracking--auto-block)) with `plateType: 'YELLOW' | 'WHITE' | 'UNKNOWN'`, default `UNKNOWN`. Driver onboarding form gains a "commercial vehicle?" checkbox + plate-photo upload.
3. Add `canDriverAcceptRide(driver)` helper in `backend/src/services/eligibilityService.js`. Returns true only when:
   ```js
   driver.verificationStatus === 'APPROVED'
     && driver.vehicle.plateType === 'YELLOW'
     && driver.documents.dl?.status === 'VERIFIED'
     && driver.documents.insurance?.status === 'VERIFIED'
     && driver.documents.permit?.status === 'VERIFIED'
     && driver.documents.fitness?.status === 'VERIFIED'
   ```
   The `documents.*` fields land in Phase 4 — until then the helper just checks `verificationStatus === 'APPROVED'` AND `plateType === 'YELLOW'`. Document-level checks short-circuit to `true` while their fields are absent. Phase 4 flips them live.
4. Gate `findNearestAvailableDriver` ([`dispatchService.js`](../backend/src/services/dispatchService.js)) on `canDriverAcceptRide`. Add a Mongo query clause that does the equivalent (so we don't fetch + filter every poll); the helper is the single source of truth for tests + a fallback path that re-validates the chosen driver before issuing the offer.
5. Gate `setOnline` ([`driverController.js`](../backend/src/controllers/driverController.js)) on `canDriverAcceptRide` for the same reason — a driver who's not eligible can't even flip online.
6. Update the driver app's Onboarding state machine ([`driver/lib/screens/onboarding/`](../driver/lib/screens/onboarding/)) to expose the new statuses on the Pending Review screen ("we're verifying your DL", "we're verifying your vehicle", etc.).
7. Tests: positive cases for each `canDriverAcceptRide` outcome + a regression test that an `APPROVED` driver on a `WHITE` plate vehicle is rejected by matching.

**Out of scope for this phase**: the actual KYC vendor calls (Phase 3), document expiry (Phase 4), admin UI (Phase 7).

**Deliverable**: a driver can still onboard + go online today, but the eligibility gate is in place. Existing approved drivers continue working because of the migration.

---

### Phase 2 — Source-available readiness (files + boundary docs)

**Why second**: small, additive, doesn't touch product code. Good "next chunk" for anyone helping.

**Scope:**

1. `LICENSE.md` at repo root — source-available under PolyForm Noncommercial 1.0.0, because the official ShareCab apps and services remain commercial product surfaces.
2. `CONTRIBUTING.md` at repo root — covers fork/clone setup (link to `docs/getting-started.md`), commit style, PR review expectations, test requirements.
3. `CODE_OF_CONDUCT.md` at repo root — Contributor Covenant 2.1 (industry standard, no need to invent).
4. `SECURITY.md` at repo root — how to report a vulnerability privately (a single email address) + disclosure window expectations + "what we won't pay for" (DoS, theoretical issues, etc.).
5. `docs/OPEN_SOURCE.md` — explicit list of "what's public / what's private" lifted from the [What's open vs what's private](#whats-open-vs-whats-private) section above, with rules for adding new modules to either side.
6. `.env.example` files in `backend/`, `app/` (via `--dart-define`), `driver/`, `website/`. Real `.env*` files in `.gitignore` (already are; verify).
7. Repo-wide secret scrub: `git log --all -- '**/*.env'` to confirm nothing slipped in historically. If something did, document it in `SECURITY.md` + rotate the credential.

**Out of scope**: monorepo restructure. Public-mirror release. Splitting "private services" into a separate repo. All those wait for Phase 9.

**Deliverable**: repo is presentable + has the legal/community files a public source-available project needs. Boundary is documented but not enforced (still one repo).

---

### Phase 3 — KYC provider interface + stub

**Why third**: every Phase 4+ KYC field references "what verifies this?" Defining the interface first means Phase 4 can refer to `kycProvider.verifyDl(...)` without choosing a vendor.

**Scope:**

1. Define `KycProvider` interface in `backend/src/services/kyc/kycProvider.js` matching the prompt:
   ```js
   interface KycProvider {
     verifyPan(input: PanVerificationInput): Promise<KycResult>;
     verifyAadhaar(input: AadhaarVerificationInput): Promise<KycResult>;
     verifyDrivingLicence(input: DlVerificationInput): Promise<KycResult>;
     verifyVehicleRc(input: RcVerificationInput): Promise<KycResult>;
     verifyBankAccount(input: BankVerificationInput): Promise<KycResult>;
     runFaceMatch(input: FaceMatchInput): Promise<KycResult>;
     runLivenessCheck(input: LivenessInput): Promise<KycResult>;
   }
   ```
   `KycResult` carries `{ status, providerRefId, rawResponse, verifiedFields, expiresAt? }`. Inputs are typed with required fields only — no provider-specific shape leaks here.
2. Implement `StubKycProvider` that auto-approves any input that looks structurally valid (4-letter–4-digit PAN regex, 12-digit Aadhaar, etc.) and rejects anything obviously wrong. Returns a fake `providerRefId` so the audit trail looks like the real thing. This is what dev + CI + the source-available demo all run against.
3. Wire a single env var `KYC_PROVIDER` (default `stub`) that selects the implementation. Production sets it to whatever vendor we eventually wire (Phase 10).
4. All KYC writes go through `kycService.runCheck(check)`, which:
   - Persists a `KycCheck` document (new collection) with `{ driverId, kind, status, providerRefId, requestedAt, completedAt, expiresAt }`
   - Updates the relevant `Driver.documents.*.status` field
   - Logs the action (audit log lands in Phase 7)
5. Document the contract in `docs/kyc-provider.md` so a contributor adding a real provider has one place to read.

**Out of scope**: actually calling Surepass/IDfy/anyone. Police verification (which is a different mechanism than identity checks). Webhook handlers for async verification responses.

**Deliverable**: KYC abstraction in place. `StubKycProvider` lets us write Phase 4 + Phase 7 code that calls a real-looking KYC API without needing an account anywhere.

---

### Phase 4 — Document expiry tracking + auto-block

**Why fourth**: the eligibility gate from Phase 1 needs real document state to mean anything. Until this phase, every `documents.*` field short-circuits to true; this phase makes them real.

**Scope:**

1. New `DriverDocuments` sub-doc on Driver (or a separate `DriverDocument` collection — recommendation: separate collection so each document gets its own audit/version history without bloating the Driver doc):
   ```js
   DriverDocument {
     driverId: ObjectId,
     kind: 'DL' | 'INSURANCE' | 'PERMIT' | 'FITNESS' | 'PUC' | 'POLICE_VERIFICATION',
     status: 'PENDING' | 'VERIFIED' | 'REJECTED' | 'EXPIRED',
     documentNumber: String,
     issuedOn: Date,
     expiresOn: Date,
     fileUrl: String,        // short-lived signed URL only
     verifiedBy: 'AUTO' | 'ADMIN',
     verifiedAt: Date,
     providerRefId: String,  // KycCheck cross-ref
   }
   ```
2. Background job `documentExpiryWatcher`:
   - Runs every 6 hours (or on demand).
   - Flags every document with `expiresOn < now` to `status='EXPIRED'`.
   - For each driver with one or more `EXPIRED` documents: sets `driver.verificationStatus = 'EXPIRED_DOCUMENT'`, blocks `canDriverAcceptRide`.
   - Pulls the driver out of `Driver.activeTrips` only if they're not currently on a trip; if they are, lets the current trip finish but blocks the next.
3. Expiry reminder notifications at 30 / 15 / 7 / 1 day windows. Reuses the existing `NotificationService` + cron pattern from subscription expiry reminders ([`docs/runbook.md`](runbook.md)).
4. Re-upload flow on the driver app: a re-upload of an expired document hits a new endpoint `POST /drivers/me/documents/:kind` which queues a fresh `KycCheck`. On verification, status flips back to `APPROVED` automatically (if no other docs are expired).
5. `canDriverAcceptRide` from Phase 1 now actually enforces document validity. Tests added for each per-document expiry case.

**Out of scope**: the document upload UX (UI already exists as a stub in Phase 1's onboarding wizard; this phase wires it to the backend). Police verification is a separate mechanism; treat it the same way mechanically but it's an asynchronous external process.

**Deliverable**: a driver whose insurance expired yesterday can't go online. Reminders fire before the cliff. Re-upload restores them automatically.

---

### Phase 5 — Safety MVP: SOS + share-trip-link + route deviation

**Why this phase**: regulatory ground floor. Without these the platform shouldn't carry real passengers.

**Scope:**

1. **SOS endpoint** `POST /trips/:id/sos`:
   - Freezes the current trip state (status snapshot, GPS, driver, rider, matchGroup) into a new `SafetyIncident` collection.
   - Captures the rider's live location at the moment of the tap.
   - Notifies the configured emergency contacts (Phase 8 adds this surface; until then a stub).
   - Creates an internal alert (currently: log + DB entry; later: PagerDuty / on-call rotation).
   - Returns a synchronous `incident.id` so the rider app can show "Help is on the way" with a real reference.
   - Marks the incident `WRITE_LOCKED` after creation — admin actions go through a separate audit-logged endpoint.
2. **SOS UI** in the rider app — replaces the current dummy button (if any) with a long-press confirm + auto-dialer to a configured helpline number.
3. **Share trip link** — `GET /trips/:id/share?token=…` returns a public, read-only live-tracking view. Token is a short-lived JWT with `{ tripId, sharedBy, expiresAt }`. Available only while the trip is in flight; auto-expires on completion.
4. **Route deviation detector** — a background sampler comparing actual driver GPS to the expected route's polyline. Threshold: > 500m from the route for > 60s while `status === 'in_progress'`. Emits `SafetyEvent { type: 'ROUTE_DEVIATION' }` and notifies the rider's app via socket.
5. **Long-stop detector** — driver speed < 1km/h for > 90s during `in_progress`. Same `SafetyEvent` emission.
6. **Overspeeding detector** — driver speed > urban speed limit for sustained windows. Lower priority; nice-to-have for v1.

**Out of scope**: direct police API integration, audio capture, dedicated safety team escalation workflow — all in a follow-up Phase 5.5 once the basics are in production and tested.

**Deliverable**: SOS works end-to-end (button → incident → notification → audit trail). Share-trip works. Route deviation fires alerts. None of these depend on the KYC vendor.

---

### Phase 6 — Complaint / report / refund flow

**Why this phase**: independent of safety/admin so it can run in parallel.

**Scope:**

1. New `Complaint` collection: `{ tripId, raisedBy, raisedAt, category, body, attachments, status, assignedTo, resolvedAt, resolution }`. Categories: `DRIVER_BEHAVIOR`, `OVERCHARGE`, `SAFETY`, `VEHICLE_CONDITION`, `OTHER`.
2. `POST /trips/:id/complaint` on the rider app (post-ride and during).
3. `POST /trips/:id/complaint` on the driver app (separate `raisedBy='driver'` channel for harassment by the rider).
4. Auto-suspension threshold — if a driver accumulates ≥3 `SAFETY` complaints in a 90-day window, set `verificationStatus='SUSPENDED'` (which `canDriverAcceptRide` already blocks).
5. Refund workflow — for `OVERCHARGE` category, an admin can issue a Razorpay refund through a new endpoint that wraps `razorpayClient.refundPayment`. Audit logged in Phase 7.
6. Ticketing UI on the rider/driver apps: a simple list of "your open complaints" + status.

**Out of scope**: legal escalation, lawyer-bound communication. The dispute panel itself (UI) is Phase 7.

**Deliverable**: a rider can file a complaint, the driver can see it (anonymised), repeated complaints actually suspend a driver, refunds can be issued. No human in the loop yet — Phase 7 adds the admin reviewer.

---

### Phase 7 — Admin backend (KYC review + suspension + audit)

**Why this phase**: needed to actually approve drivers + handle complaints. No UI yet; backend only.

**Scope:**

1. Admin auth — separate `AdminUser` collection with roles `'SUPER_ADMIN' | 'KYC_REVIEWER' | 'SAFETY_REVIEWER' | 'SUPPORT_AGENT' | 'FINANCE_ADMIN'`. Sign-in by email + password (NOT phone OTP; admins aren't drivers/riders). Bcrypt + a short-lived JWT.
2. Role-based middleware `requireAdminRole('KYC_REVIEWER')` on every admin endpoint.
3. Endpoints (all under `/api/admin/`):
   - `GET /drivers?status=…&q=…` — paginated, filtered list of driver applications
   - `GET /drivers/:id` — full driver detail including documents + KYC check history
   - `POST /drivers/:id/approve` — fires the verification status transition; requires `KYC_REVIEWER`
   - `POST /drivers/:id/reject` with `{ reason, notes }`
   - `POST /drivers/:id/suspend` with `{ reason, lifted_at? }`
   - `POST /drivers/:id/notes` — internal note (visible to admins, not driver)
   - `GET /incidents` — safety incident list
   - `POST /incidents/:id/notes`
   - `GET /complaints?status=…` — complaint queue
   - `POST /complaints/:id/resolve` with `{ resolution, refund_amount? }`
   - `GET /audit?actorId=…&since=…` — audit trail
4. Audit log — every admin action writes an `AuditLog { actorId, actorEmail, action, targetId, payload, ip, at }` entry. Append-only collection. Used by Phase 9's security review.
5. Document access — admin requests for KYC documents go through a signed-URL minter that emits a fresh 5-minute URL each time AND logs the access in the audit trail. Direct DB queries for `fileUrl` are blocked at the API layer for non-`SUPER_ADMIN` roles.
6. Tests covering each role's permissions and each audit-log emission.

**Out of scope**: admin UI (Next.js/React panel). That's a follow-up; the backend exposes the surface, anyone can call it via Postman / curl / a future React dashboard. Production deployment of the admin endpoints is on a separate, IP-whitelisted host (Phase 9).

**Deliverable**: a real human can review a driver, approve them, suspend them, resolve complaints, all with audit trail. The admin UI comes later.

---

### Phase 8 — Rider light KYC + emergency contacts

**Why this phase**: keep rider-side onboarding minimal. Phone OTP is the gate today; this phase adds emergency contact setup and (optionally) email verification.

**Scope:**

1. Add `emergencyContacts: [{ name, phone, relation }]` to the User doc. Max 3.
2. Onboarding flow on the rider app — first-time launch (post phone OTP) walks them through "add an emergency contact" with a "skip for now" exit. Block-list certain ride categories (late-night, long-distance) until at least one is set.
3. Optional email verification — used for receipts + future "verified rider badge" tier. Email link with a short-lived JWT.
4. Wire the SOS flow from Phase 5 to push to emergency contacts (SMS via the existing MSG91 SMS surface — `notificationService.notifyByPhone(contact.phone, 'sos_template', { riderName, location, helpline })`).
5. NO Aadhaar / PAN for riders in MVP. Document the reason in `docs/architecture.md`: heavy rider KYC is a deterrent to growth + reraisable later if regulation forces it.

**Out of scope**: corporate / student verified-rider tiers (later monetisation lever).

**Deliverable**: every active rider has a way to be reached in an emergency, and SOS notifies someone real.

---

### Phase 9 — Public-mirror release

**Why this phase**: by now Phase 2's files are in place AND the privacy-sensitive code paths are clearly separated. Time to actually open the repo (or a sanitised mirror of it).

**Scope:**

1. Decision: single public repo OR public mirror + private fork.
   - **Single public repo (recommended)**: easier to maintain, contributors see the whole stack. Risk: anything sensitive that lands in `git log` is irrecoverable. Mitigation: aggressive `.gitignore`, mandatory secret-scan in pre-commit + CI.
   - **Public mirror + private fork**: safer for sensitive code (admin internals, fraud rules). Cost: every PR has to merge into both, contributors can't fully run the stack from the public repo.
2. Choose. Document the decision in `docs/OPEN_SOURCE.md` + `README.md`.
3. CI for the public repo: secret-scan (truffleHog / gitleaks), backend tests, both Flutter app analyses, lint. Required-status checks on PRs.
4. GitHub Issues templates (bug / feature / safety report) + a public CHANGELOG.md (Keep-a-Changelog format).
5. Announcement copy — README intro, blog post, social, etc. Not a code task but plan for it here so engineering doesn't drop the ball when files go up.

**Out of scope**: turning this into a foundation / DAO / governance model — those are post-release decisions.

**Deliverable**: repo is publicly visible. Contributors can clone, run, file PRs against `main`.

---

### Phase 10 — Real KYC vendor wiring

**Why last**: every preceding phase doesn't depend on a specific vendor. Wait until we know which vendor's pricing + uptime + SLAs actually fit the business before committing.

**Scope:**

1. Procurement — sign with Surepass (or IDfy / HyperVerge / etc.). Test account credentials in dev, production credentials in production secret store. Document credential rotation in `docs/runbook.md`.
2. Implement `SurepassKycProvider` (or chosen vendor) against the `KycProvider` interface from Phase 3. Map each provider call to the interface methods.
3. Webhook handler — most vendors do RC / DL verification asynchronously. Add `/api/kyc/webhook` with HMAC verification (mirror the Razorpay webhook setup), idempotency via `ProcessedEvent` collection.
4. Cost monitoring — log every vendor call's cost (paise) so we can chart KYC cost per onboarded driver. Alert if a single driver triggers > N calls (signals a stuck retry loop or a fraud attempt).
5. Flip `KYC_PROVIDER=surepass` in production. Roll out to a canary set of drivers first; everyone else stays on stub for a week. Verify approval rates match historical manual-review rates within ±10%.
6. RC API specifically — replaces the manual yellow-plate review from Phase 1. Driver app's "commercial vehicle?" checkbox is replaced with a "we verified your RC and the vehicle is yellow-plate ✓" badge.

**Out of scope**: police verification — that's a separate mechanism (state-level + manual process) handled outside the KYC vendor.

**Deliverable**: KYC runs on a real vendor, manual review only happens for flagged edge cases.

---

## Database modules to add

Cross-reference for the schema work threaded through the phases above. Each row links to the phase it lands in:

| Collection | Purpose | Phase |
|---|---|---|
| `DriverDocument` | Per-doc state (DL/insurance/permit/fitness/PUC/police) | 4 |
| `KycCheck` | Audit trail of every KYC API call | 3 |
| `SafetyIncident` | SOS-triggered immutable snapshots | 5 |
| `SafetyEvent` | Detector outputs (route deviation, long stop, overspeeding) | 5 |
| `Complaint` | Rider/driver-raised complaints | 6 |
| `AdminUser` | Admin accounts with roles | 7 |
| `AuditLog` | Append-only admin action log | 7 |
| `EmergencyContact` | Per-user emergency contacts (embedded on User) | 8 |

Existing collections that get new fields:
- `Driver` — `verificationStatus` (full enum, Phase 1), `vehicle.plateType` (Phase 1), `documents` (references DriverDocument, Phase 4)
- `Trip` — already has `otp` from prior work; SOS reference goes into a Phase 5 sibling

## Rider eligibility rule (codified)

The final canonical check, lifted from the prompt as a target signature for Phase 1:

```js
function canDriverAcceptRide(driver) {
  return (
    driver.verificationStatus === 'APPROVED' &&
    driver.canAcceptRides === true &&
    driver.vehicle.type === 'COMMERCIAL' &&
    driver.vehicle.plateType === 'YELLOW' &&
    driver.documents.dl.status === 'VERIFIED' &&
    driver.documents.insurance.status === 'VERIFIED' &&
    driver.documents.permit.status === 'VERIFIED' &&
    driver.documents.fitness.status === 'VERIFIED'
  );
}
```

The matching engine ([`backend/src/services/matchingService.js`](../backend/src/services/matchingService.js)) + the dispatch service ([`backend/src/services/dispatchService.js`](../backend/src/services/dispatchService.js)) BOTH consult this. The driver app's `setOnline` consults it. Belt-and-suspenders, because the cost of a wrongly-matched non-commercial vehicle is hours of incident response and possibly a regulator letter.

## Open questions

These are not blockers but the team should answer them before they bite. None of them stop Phase 1 from shipping.

1. **License review**: source-available terms are now drafted around PolyForm Noncommercial 1.0.0. Have counsel review before the repository becomes public.
2. **Public mirror vs single repo** for Phase 9 — settle before going public.
3. **Police verification flow** is referenced in the prompt but the mechanism varies state to state. Recommendation: stub it as a manual admin action (upload a clearance certificate, admin marks `documents.police.status='VERIFIED'`) until volume justifies automation.
4. **Geographic scope** — the brief says "yellow-plate" which is India-specific. If we ever cross borders we'll need a per-country eligibility rule. Punt for now.
5. **Dispute timeline SLAs** — how long does a `Complaint` stay open before auto-escalating? Phase 6 picks an SLA; admin team confirms.
6. **Driver suspension thresholds** — Phase 6 hard-codes "3 safety complaints in 90 days = SUSPENDED". Real ops needs to tune this. Make it a config knob from day one.

## How to use this document

If you're picking up Phase N:
1. Re-read the [Guardrails](#guardrails-non-negotiable-rules) — they apply to every line of code you write.
2. Read the phase's "Scope" + "Out of scope" sections in full before opening any file.
3. Add tests as you go; the existing `backend/tests/` patterns are good examples.
4. When the phase is done, update [Current state (as of this writing)](#current-state-as-of-this-writing) so future contributors aren't rebuilding what you shipped.

If you're picking up something not in this document, write down what it is and which phase it slots into before starting. The roadmap is the single source of truth for sequencing.
