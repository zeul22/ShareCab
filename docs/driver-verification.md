# Driver Onboarding & Verification

How a driver goes from "first OTP login" to "approved, accepting trips."

## State machine

```
   ┌──────────────────┐
   │  No Driver doc   │  → first OTP login lands here, role=rider
   └────────┬─────────┘
            │  POST /drivers/onboard
            ▼
   ┌──────────────────┐
   │  pending         │  → Pending Review screen; ops manually approves
   └────────┬─────────┘
            │  ops dashboard (or auto-approve when MSG91_DEV_FALLBACK=true)
            ▼
   ┌──────────────────┐
   │  approved        │  → Driver home; can go online + accept dispatches
   └────────┬─────────┘
            │  ops action (post-incident)
            ▼
   ┌──────────────────┐
   │  rejected        │  → blocked from going online; UX is "contact support"
   └──────────────────┘
```

Field: `Driver.verificationStatus`, enum `['pending', 'approved', 'rejected']`, default `'pending'`.

## Onboarding wizard

Four steps in [driver/lib/screens/onboarding/](../driver/lib/screens/onboarding/):

1. **Personal** — full name (matches driving licence), optional email.
2. **Vehicle** — licence number, car model, plate, colour, capacity (3/4/6 seats).
3. **Documents** — photo of driving licence, RC, selfie with car. *UX is complete but uploads are stubbed* — see [open work](#open-work) below.
4. **Review & submit** — read-only summary with "Edit" jumps to specific steps.

On submit, the driver app calls `POST /drivers/onboard`, which:
1. Validates the payload (zod).
2. Creates a `Driver` document with `verificationStatus='pending'`.
3. Promotes `User.role` from `'rider'` → `'driver'`.
4. Grants the 30-day free-trial subscription.
5. Returns the new driver profile.

The driver app then calls `/auth/refresh` to mint a fresh JWT with `role: driver` so the role-gated endpoints (`/drivers/online`, `/drivers/location`, etc.) work without a re-login. This step is critical — see [runbook.md](runbook.md#forbidden-on-go-online) for what happens when it's skipped.

## Verification today

`MSG91_DEV_FALLBACK=true` short-circuits verification — newly-onboarded drivers are immediately `approved`. This is for local development and demos.

In production, `verificationStatus` stays `'pending'` until an ops action flips it. There's no admin UI yet; an ops engineer runs:

```js
// MongoDB shell
db.drivers.updateOne(
  { _id: ObjectId("...") },
  { $set: { verificationStatus: "approved" } }
)
```

Drivers polling `/drivers/me` (or the pending-review screen pulling to refresh) will see the new status within a tick.

## KYC strategy

Manual approval is fine while volumes are low (first 50-100 drivers). Beyond that we need authoritative validation against government databases — driving licence (Parivahan/Sarathi), vehicle RC, and Aadhaar (UIDAI).

**Likely vendor: Surepass.** Indian KYC SaaS, hits the gov databases via their aggregator licence. Approximate per-driver cost:

| Check | Per-call (₹) |
|---|---|
| DL verification (Sarathi) | 3-8 |
| RC verification (Vahan) | 3-8 |
| Aadhaar OKYC | 3-10 |
| Face match against selfie | 2-5 |
| **Per-driver total** | **15-30** |

That's ~3-6% of one month's ₹499 subscription — covered on day one of the driver's lifetime.

### Integration shape (when we build it)

Backend addition in `driverController.onboardDriver`:

```js
// After Driver.create, before returning the response:
if (env.kyc.enabled) {
  const result = await surepass.verifyDriver({
    licenseNumber, vehiclePlate, aadhaar, selfieUrl,
  });
  if (result.allPassed) {
    driver.verificationStatus = 'approved';
    await driver.save();
  } else {
    // Log the failure reasons; ops reviews and either rejects or approves.
    logger.info(`KYC partial fail driver=${driver._id} reasons=${result.failedChecks.join(',')}`);
  }
}
```

Surepass returns structured results (`{ ok, name, dob, photo, validity }`) per check; we can either auto-approve on full pass, auto-reject on any fail, or — most defensible for now — auto-approve on full pass and queue partial fails for manual review.

### Why not UIDAI directly?

UIDAI's eKYC requires you to be a registered AUA/KUA (Authentication User Agency). The application process is long, paperwork-heavy, and gated on org-size criteria we don't meet yet. Surepass (and Karza, IDfy, Cashfree Verification) are aggregator licence-holders who handle that on our behalf for a per-call fee.

## Documents we collect but don't yet upload

The wizard captures local file paths in `OnboardingState.licensePhotoPath`, `rcPhotoPath`, `selfiePhotoPath` but doesn't upload them anywhere. To wire uploads when we're ready:

1. Add a multipart endpoint `POST /drivers/me/documents` on the backend.
2. Backend writes to Cloud Storage (`gs://sharecab-driver-documents/<userId>/`).
3. Store the GCS URI on the Driver doc.
4. Surepass face-match takes a URL or base64 — pass the GCS signed URL.

Until that lands, ops verifies docs by asking the driver to WhatsApp the photos — fine at 50-driver scale, breaks at 500.

## Rejected drivers

Today: no UX to re-apply. The driver sees the pending-review screen with "Rejected — contact support" copy ([driver/lib/screens/pending_review_screen.dart](../driver/lib/screens/pending_review_screen.dart)).

Future: a `/drivers/me/reapply` endpoint that resets the Driver doc and the User role, letting them go through the wizard again. Out of scope until rejections are common enough to need flow-level support.

## Open work

- **Document upload to Cloud Storage** + Surepass integration → marked here, in [matching.md](matching.md), and in [revenue.md](revenue.md) as the KYC line item.
- **Ops admin UI** — a small web view (could live in [website/](../website/) under `/admin`) for reviewing pending drivers, viewing photos, approve/reject. Today this is a Mongo shell command.
- **Reapply flow** for rejected drivers.
- **Email/SMS notification** when verification status changes — V1 relies on the driver polling.
