# Runbook

Operational tasks and recovery recipes. Add to this whenever an incident teaches you something — the next person should not have to rediscover it.

## Routine tasks

### Rotate the JWT secret

Affects every active session — users will get logged out and need to log in again. Schedule for a quiet window.

```bash
NEW=$(openssl rand -hex 64)
echo -n "$NEW" | gcloud secrets versions add jwt-secret --data-file=-
# Cloud Run auto-picks the new version on next instance start. Force it:
gcloud run services update sharecab-backend --region asia-south1 --update-secrets="JWT_SECRET=jwt-secret:latest"
```

### Rotate the MSG91 authkey

When you suspect a leak (or when MSG91 IP-blocks you).

1. msg91.com → Profile → Auth Keys → revoke old, create new.
2. `echo -n "<new key>" | gcloud secrets versions add msg91-auth-key --data-file=-`
3. Bounce Cloud Run as above.

### Approve a pending driver

No admin UI yet. Connect to the production cluster (Atlas → Browse Collections, or `mongosh` with the connection string) and:

```js
use sharecab
db.drivers.findOne({ /* match by user phone */ })  // confirm right person
db.drivers.updateOne(
  { _id: ObjectId("...") },
  { $set: { verificationStatus: "approved" } }
)
```

The driver app polls `/drivers/me` (and the Pending Review screen pulls to refresh) so the new status shows within ~10 seconds.

### Reject a driver

Same shape, `verificationStatus: "rejected"`. They lose access to the home screen and see a "contact support" message.

### Reset a driver's subscription expiry

Useful if Razorpay records the payment but our webhook missed it, leaving the driver subscribed-on-Razorpay but expired in our DB.

```js
db.drivers.updateOne(
  { _id: ObjectId("...") },
  { $set: {
    subscriptionExpiresAt: ISODate("2026-06-15T00:00:00Z"),
    subscriptionPaymentRef: "manual-fix-2026-05-12"
  }}
)
```

Always set `subscriptionPaymentRef` to something traceable so audit can find the manual override later.

### Roll back a Cloud Run deploy

```bash
gcloud run revisions list --service=sharecab-backend --region=asia-south1
gcloud run services update-traffic sharecab-backend \
  --region=asia-south1 \
  --to-revisions=sharecab-backend-00012-abc=100
```

### Tail production logs

```bash
gcloud run services logs tail sharecab-backend --region=asia-south1
```

Filter for a specific user / trip / driver:

```bash
gcloud run services logs tail sharecab-backend --region=asia-south1 \
  | grep "user=6822abc"
```

## Common failure modes

### "Forbidden" on Go Online

**Symptom:** Driver completes onboarding, taps Go Online, gets a "Forbidden" error.

**Cause:** The JWT was minted at OTP-verify time when the user was still `role: rider`. The user's role in Mongo is now `driver`, but the JWT they're holding still says `rider`. `requireRole('driver')` middleware reads role from the JWT (not Mongo) and 403s.

**Fix (already in the code):**
- [driver/lib/screens/onboarding/onboarding_screen.dart](../driver/lib/screens/onboarding/onboarding_screen.dart) calls `auth.forceRefresh()` after a successful `/drivers/onboard`, which trades the stale token for a fresh one from `/auth/refresh`.
- [driver/lib/screens/splash_screen.dart](../driver/lib/screens/splash_screen.dart) defensively calls `forceRefresh()` if `/drivers/me` returns a profile but the cached user.role isn't `driver` — heals users who onboarded on an older build.

**If a user still hits it:** ask them to sign out and back in. `/auth/otp/verify` mints a fresh JWT from the current User doc.

### MSG91 returns 408 IPBlocked

**Symptom:** OTP send fails with `IPBlocked` in the backend logs.

**Cause:** MSG91 blocks unrecognised egress IPs. Cloud Run egress IPs rotate; the easiest path is to whitelist Cloud Run's known egress ranges (Google publishes these) OR use Cloud NAT with a static IP.

**Quick fix during outage:**
1. Set `MSG91_DEV_FALLBACK=true` temporarily so logins work with `123456`.
2. ⚠️ Roll this back as soon as MSG91 is reachable again — anyone can log in as anyone with dev fallback on.

**Permanent fix:** create a Cloud NAT with a static IP, whitelist that IP in MSG91. Multi-hour setup; do it before production launch, not during.

### Razorpay dSYM upload fails for iOS archives

**Symptom:** App Store Connect upload from Xcode fails with "The archive did not include a dSYM for the Razorpay.framework with the UUIDs [...]".

**Cause:** Razorpay ships its iOS SDK as an xcframework that includes the dSYM, but Xcode's archive step doesn't auto-copy dSYMs out of xcframework slices.

**Fix (already in [app/ios/Podfile](../app/ios/Podfile) post_install):** A Run Script build phase finds the Razorpay dSYM under `Pods/` and copies it to `DWARF_DSYM_FOLDER_PATH` during the archive build. Same fix is in [driver/ios/Podfile](../driver/ios/Podfile) — if it gets dropped during a regen, re-apply by copying the post_install block from the rider app.

### Cold-start latency complaints

**Symptom:** Users report login takes 3-5 seconds.

**Cause:** Cloud Run scales to zero when idle; the first request after a quiet window cold-starts a container.

**Fix:** Set `--min-instances 1` on the Cloud Run service. ~$5/mo. Reverse with `--min-instances 0` if it's not needed.

### Mongo Atlas M0 storage warning

**Symptom:** Atlas dashboard shows >80% of the 512MB limit consumed.

**Action:**
1. Check whether old `Trip` documents are bloating the collection. Older-than-90-days trips can be archived — but we don't have an archive job yet. Manual cleanup:
   ```js
   db.trips.deleteMany({ status: "completed", completedAt: { $lt: ISODate("2026-02-01") } })
   ```
2. If that doesn't help, upgrade to M10 (~$60/mo). One-click in the Atlas console; downtime is ~3-5 minutes.

### Driver location stale

**Symptom:** Rider app shows a driver in the wrong location, or matching pairs riders with drivers who've moved away.

**Cause:** [driver/lib/services/location_push_service.dart](../driver/lib/services/location_push_service.dart) stopped ticking. Either the driver backgrounded the app (expected; OS pauses our timer), the OS killed the app for memory, or the location permission was revoked.

**Diagnostic:** check `Driver.updatedAt` in Atlas. If it's >5 minutes old while the driver is `isOnline: true`, the ping is failing.

**User-facing fix:** ask the driver to toggle offline → online. The service is idempotent on `start()` and re-requests permission if needed.

### Map renders blank on a fresh device

**Symptom:** Google Maps in the rider/driver app shows just a Google logo on a grey background.

**Cause:** Either the API key is missing the right native config, or the Maps SDK / Directions API isn't enabled on the GCP project that owns the key.

**Checks:**
1. iOS: `GMSApiKey` is in [app/ios/Runner/Info.plist](../app/ios/Runner/Info.plist) and [driver/ios/Runner/Info.plist](../driver/ios/Runner/Info.plist).
2. Android: `com.google.android.geo.API_KEY` meta-data is in [app/android/app/src/main/AndroidManifest.xml](../app/android/app/src/main/AndroidManifest.xml) and [driver/android/app/src/main/AndroidManifest.xml](../driver/android/app/src/main/AndroidManifest.xml).
3. Cloud Console → APIs & Services → Library: enable "Maps SDK for iOS," "Maps SDK for Android," AND "Directions API" (for the route polyline).
4. API key restrictions: Android requires the SHA-1 fingerprint + package name; iOS requires the bundle id.

### TestFlight "No Builds Available" for invited testers

**Symptom:** Tester accepted the invite, opened TestFlight, sees the app but no builds.

**Cause:** Two-tier invitation model. Adding someone as an Internal Tester at the app level is not enough — they also need to be added to a *Testing Group*.

**Fix:** App Store Connect → ShareCab → TestFlight → Internal Testing → "ShareCab Testers" group → Testers → "+". Builds become visible within a few minutes.

## Pre-launch checklist

Before flipping `MATCH_RIDER_ONLY=false` on production:

- [ ] `MSG91_DEV_FALLBACK=false` in Cloud Run env (NOT just unset — explicitly false).
- [ ] `JWT_SECRET` is a non-default value from Secret Manager.
- [ ] `RAZORPAY_KEY_ID` + `RAZORPAY_KEY_SECRET` are live-mode keys (not test).
- [ ] `RAZORPAY_WEBHOOK_SECRET` is set and matches the Razorpay dashboard.
- [ ] MSG91 widget is in "live" mode (not staging) and has DLT template approval.
- [ ] Google Maps API key has Android SHA-1 + iOS bundle id restrictions in place.
- [ ] Cloud Run uptime check is firing alerts to a real address.
- [ ] At least 10 drivers verified and approved in the target city.
- [ ] Driver subscription is at the agreed price (`DRIVER_SUBSCRIPTION_PRICE_PAISE`).
