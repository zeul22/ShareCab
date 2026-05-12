# Razorpay Setup — Walkthrough

End-to-end guide to going from "stub mode" to "real payments." Designed for a solo developer; assumes you're integrating Razorpay for the first time.

## What this gets you

After this guide:
- A Razorpay account in **test mode** (no KYC needed) with API keys.
- The driver subscription + rider unlock flows hitting real Razorpay checkout.
- A webhook that retries safely if your backend is briefly down.
- A clear path to **live mode** when you're ready for real payments.

Total time: 30-60 minutes for test mode. Live mode KYC takes 2-5 business days after you submit docs.

## 0. Pre-flight

You already have:
- ✅ Razorpay SDK on the backend ([backend/src/services/razorpayClient.js](../backend/src/services/razorpayClient.js))
- ✅ Razorpay Flutter plugin on rider + driver apps (`razorpay_flutter` in both pubspecs)
- ✅ Order create + signature verify for both **driver subscription** and **rider unlock**
- ✅ Webhook handler with HMAC verification + idempotency dedupe

What's missing is the actual Razorpay account + credentials + webhook URL registration. That's what this guide covers.

---

## 1. Create the Razorpay account (5 min)

1. Go to **[razorpay.com/dashboard](https://dashboard.razorpay.com)** → "Sign Up."
2. Use your business email. Phone OTP, password — standard signup.
3. After login you land on the dashboard in **Test Mode** automatically (top-right toggle says "Test Mode," badge is yellow).
4. **Do not** click "Activate Account" yet — that triggers KYC for live mode. We'll do that later. Test mode is fully usable for development.

That's it. You can transact in test mode immediately with no docs submitted.

---

## 2. Grab test mode API keys (2 min)

1. Dashboard → left sidebar → **Account & Settings** → **API Keys** (under "Website and app settings").
2. Click **Generate Test Key**.
3. Copy both:
   - **Key Id** — starts with `rzp_test_...` (this is the "public" key, OK to ship to clients).
   - **Key Secret** — long alphanumeric string. **Never** put this in the Flutter app or commit it.

> ⚠️ Razorpay shows the secret **once**. Copy it now to a password manager. If you lose it, you regenerate — which invalidates the old key.

---

## 3. Plug keys into the backend (3 min)

Open [backend/.env](../backend/.env) and set:

```bash
RAZORPAY_KEY_ID=rzp_test_XXXXXXXXXXXX
RAZORPAY_KEY_SECRET=XXXXXXXXXXXXXXXXXXXXXXXX
```

Restart the backend (`npm run dev`). Tail the logs — you should see no more `Razorpay stub mode` warnings on the next subscription / unlock attempt.

To verify the wiring without doing a full app flow:

```bash
curl -X POST http://localhost:4000/api/drivers/subscribe \
  -H "Authorization: Bearer <driver-jwt>" \
  -H "Content-Type: application/json"
```

You should get back a real Razorpay order id (starts with `order_...`), not a `stub_order_...`.

---

## 4. Test the end-to-end flow with test cards (10 min)

With keys plugged in, run the apps as normal and trigger a payment.

### Razorpay test cards

When Razorpay's checkout sheet appears, use these to simulate success/failure (no real money):

| Use case | Card number | CVV | Expiry | OTP |
|---|---|---|---|---|
| **Success** | `4111 1111 1111 1111` | any 3 digits | any future date | `1234` |
| **Success (Mastercard)** | `5267 3181 8797 5449` | any | any future | `1234` |
| **Insufficient funds failure** | `4000 0000 0000 0002` | any | any future | n/a |
| **Authentication failure** | `4000 0000 0000 0010` | any | any future | wrong OTP |

### Razorpay test UPI VPAs

| Use case | VPA |
|---|---|
| **Success** | `success@razorpay` |
| **Failure** | `failure@razorpay` |

Full list: [razorpay.com/docs/payments/payments/test-card-details/](https://razorpay.com/docs/payments/payments/test-card-details/).

### What to verify

1. Razorpay sheet opens with your ShareCab brand colours.
2. Enter a test card → OTP `1234` → success screen.
3. Sheet closes; app shows "Subscription renewed" / "Unlocked" snackbar.
4. Backend log shows `Subscription activated` or `Unlock minted` with the real Razorpay `pay_...` id (not `stub_...`).
5. Razorpay Dashboard → **Transactions** → **Payments** — your test payment is listed.

If any step breaks, see [Troubleshooting](#troubleshooting) below.

---

## 5. Configure the webhook (10 min)

The webhook is the safety net: if the client's `payment-confirm` call drops (network blip after Razorpay finished processing the card), Razorpay's webhook still credits the driver's subscription or mints the rider's unlock.

### Generate a webhook secret

This is separate from the API secret. Generate a strong random one:

```bash
openssl rand -hex 32
# → e.g. f3a7b9c1...
```

Add to [backend/.env](../backend/.env):

```bash
RAZORPAY_WEBHOOK_SECRET=f3a7b9c1...
```

### Expose your local backend for Razorpay to reach

Razorpay needs a public HTTPS URL. For local dev, use [ngrok](https://ngrok.com):

```bash
brew install ngrok
ngrok http 4000
# → forwards https://<random>.ngrok-free.app → localhost:4000
```

Copy the `https://` URL. (Free ngrok rotates this URL on every restart — fine for testing, annoying long-term. Upgrade to a static domain when you're tired of re-registering.)

### Register the webhook in Razorpay

1. Dashboard → **Account & Settings** → **Webhooks** → **+ Add New Webhook**.
2. **Webhook URL**: `https://<ngrok>.ngrok-free.app/api/payments/razorpay/webhook`
3. **Secret**: paste the `RAZORPAY_WEBHOOK_SECRET` you generated.
4. **Active Events** — check at minimum:
   - `payment.captured` (essential — this is what credits subscriptions + unlocks)
   - `payment.failed` (optional today; useful when you add retry logic)
   - `order.paid` (optional; we don't act on this yet)
5. **Save**.

### Test the webhook

Razorpay's dashboard has a "Test" button next to each webhook — clicking it sends a fake event so you can verify your backend responds 200.

You should see in the backend logs:

```
[info] Razorpay webhook event=payment.captured id=evt_xxx
[info] Webhook event evt_xxx already processed — skipping     ← second call
```

(The "already processed" line is the idempotency check from the [ProcessedEvent](../backend/src/models/ProcessedEvent.js) collection — proves dedupe is working.)

---

## 6. Production hardening (when ready to launch)

Before flipping anything in production:

### Complete KYC for live mode

1. Razorpay Dashboard → **Activate Account** (top-right banner).
2. Submit:
   - **PAN** card (yours, if proprietor; company's, if LLP/Pvt Ltd).
   - **GST number** (optional below ₹40L turnover but recommended).
   - **Bank account** for settlement (where Razorpay deposits your earnings — they hold for T+1 to T+5 days depending on tier).
   - **Business address proof** (Aadhaar / utility bill / lease).
   - **Website URL** (your marketing site — [sharecab.example](https://sharecab.example) when live).
3. Razorpay reviews in 2-5 business days. They may ask for clarifying docs.
4. Once approved, your dashboard switches to "Live Mode" (toggle in top-right).
5. Generate **Live Keys** (separate from test keys). Update Cloud Run secrets via Secret Manager:

```bash
echo -n "rzp_live_..." | gcloud secrets versions add razorpay-key-id --data-file=-
echo -n "<live-secret>" | gcloud secrets versions add razorpay-key-secret --data-file=-
echo -n "<live-webhook-secret>" | gcloud secrets versions add razorpay-webhook-secret --data-file=-
```

6. Update the webhook URL in Razorpay's Live Mode webhooks list to point at your Cloud Run URL (no ngrok needed once deployed):
   `https://sharecab-backend-XXX-asia-south1.run.app/api/payments/razorpay/webhook`

7. Re-deploy Cloud Run so the new secrets are picked up.

### Settlement schedule

Razorpay holds payments for T+1 to T+5 depending on your business risk tier (new accounts start at T+3). You can request faster settlement (T+1) once you have ~3 months of clean transaction history. Daily auto-settlement to your registered bank account is on by default; toggle off if you want manual.

### Refund flow (not implemented yet)

Today we don't handle refunds. When you need them:

1. `razorpay.payments.refund(paymentId)` from the backend.
2. Mark the related Driver subscription / Unlock as cancelled.
3. Email the rider/driver.

There's no UI for this — it's a manual ops task triggered from the Razorpay dashboard for now.

---

## Troubleshooting

### "Invalid Razorpay signature" on the backend

Means the HMAC didn't match. Common causes:

- **Wrong `RAZORPAY_KEY_SECRET`** in env. Double-check you copied it correctly — Razorpay's secret has no spaces but is easy to misread.
- **Webhook body parsed as JSON before HMAC check.** Already handled by [backend/src/routes/payment.routes.js](../backend/src/routes/payment.routes.js) (mounts `express.raw` for the webhook route), so this shouldn't happen — but if you ever add middleware that touches the body before the webhook handler, the HMAC will break silently.
- **Webhook secret mismatch.** The `RAZORPAY_WEBHOOK_SECRET` env var must match the Webhook Secret you set in Razorpay's dashboard (these are different from API key secrets).

### Razorpay sheet doesn't open

- **iOS**: confirm `razorpay_flutter` pod is installed (`cd ios && pod install`). The first run after adding the dep needs a fresh `flutter run`, not hot-reload.
- **Android**: confirm the minSdk is ≥ 19 (Razorpay's floor). Both apps are already at 21+.
- **Both**: tap the button while watching the Flutter console — you'll see either the SDK init failing or the order creation failing. Most issues are the latter (backend returning a stub order when you expected real).

### Webhook never fires

- **ngrok URL changed.** Free ngrok rotates the subdomain on every restart — update the URL in Razorpay's dashboard or `ngrok` will silently 404 the webhook.
- **Backend not running.** ngrok → 502 → Razorpay marks the webhook as failing. Razorpay retries 4 times over ~24 hours, so a brief outage is fine; sustained downtime means re-test after fixing.
- **Wrong path.** Must be `/api/payments/razorpay/webhook` (with `/api`). The router at [backend/src/routes/payment.routes.js](../backend/src/routes/payment.routes.js) mounts under `/payments`; the app's main router prefixes `/api`.

### "Payment failed" on a card that should succeed

- Verify you're on Test Mode (Razorpay sometimes drops you back to Live Mode after dashboard navigation — yellow vs blue badge top-right).
- The list of test cards changes occasionally — pull the current list from [razorpay.com/docs/payments/payments/test-card-details/](https://razorpay.com/docs/payments/payments/test-card-details/) if you're seeing weird failures.

### Sub-customer / refund / dispute handling

V1 doesn't implement these. When you need them, the Razorpay Node SDK has methods for each — they all follow the same `client.<resource>.create()` pattern. Add a controller per resource, mount on `/payments/*`, and you're set.

---

## What to remember

- Test mode = no KYC, real flow, no real money. Use this for all development.
- Live mode = real money, requires PAN + bank account + ~3-5 business days for KYC.
- Webhook is the safety net — don't skip it.
- Always log the order id + receipt + stub flag. Audit pays for itself the first time someone disputes a charge.
- The webhook idempotency table ([ProcessedEvent](../backend/src/models/ProcessedEvent.js)) auto-expires after 30 days. If you ever need longer audit, copy events to a separate log before they age out.

When you're stuck: [Razorpay Dashboard → Transactions](https://dashboard.razorpay.com/app/payments) shows every payment with its raw status, error code, and signature — invaluable for debugging.
