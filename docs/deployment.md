# Deployment

Production target: **Google Cloud Run** (backend) + **MongoDB Atlas M0** (database), running in `asia-south1` (Mumbai). Chosen because we're on the GCP $300/90-day free credit and our user base is India-only — same region cuts latency to sub-10ms between Cloud Run and Atlas.

## Topology

```
            ┌─────────────────────────────────────────────┐
            │                Cloud Run                    │
            │   region=asia-south1, container=Node 20     │
            │   min-instances=0   max-instances=10        │
            │   memory=512Mi      cpu=1                   │
            └────────────────┬────────────────────────────┘
                             │ env vars from Secret Manager
                             │
            ┌────────────────▼────────────────────────────┐
            │           Secret Manager                    │
            │  MSG91_AUTH_KEY · JWT_SECRET · RZP_KEYS     │
            └─────────────────────────────────────────────┘
                             │ mongoose
                             ▼
            ┌─────────────────────────────────────────────┐
            │      MongoDB Atlas M0 (free tier)           │
            │  region=asia-south1   512MB                 │
            └─────────────────────────────────────────────┘
```

## What's billable, what's free

| Service | Cost at our traffic | Note |
|---|---|---|
| Cloud Run | $0–10/mo | Free tier covers ~2M requests/mo. |
| MongoDB Atlas M0 | $0 forever | 512 MB cap; upgrade to M10 (~$60/mo) when full. |
| Secret Manager | <$1/mo | First 6 secret versions per month are free. |
| Cloud Build (for deploys) | $0 | 120 build-minutes/day free. |
| Egress | usually $0 | Egress to same-region Atlas is free; egress to clients is metered but tiny per request. |

The $300 credit comfortably covers 3 months of runway for everything above, including some KYC/Razorpay-volume slack.

## One-time setup

### 1. Create the GCP project

```bash
gcloud projects create sharecab-prod --name="ShareCab"
gcloud config set project sharecab-prod
gcloud services enable run.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com
```

Enable billing in the console — credit applies automatically once a card is on file.

### 2. Create the Atlas cluster

1. [cloud.mongodb.com](https://cloud.mongodb.com) → New Project → "ShareCab".
2. Build Database → M0 Free → Provider: **Google Cloud** → Region: **Mumbai (asia-south1)**.
3. Database Access → Add user `sharecab-app` with a long random password.
4. Network Access → Add IP `0.0.0.0/0` (open; we'd ideally use VPC peering but M0 doesn't support it).
5. Connect → Drivers → copy the connection string.

### 3. Store secrets

```bash
echo -n "<mongo-uri>" | gcloud secrets create mongodb-uri --data-file=-
echo -n "<random-64-byte-hex>" | gcloud secrets create jwt-secret --data-file=-
echo -n "<msg91-authkey>" | gcloud secrets create msg91-auth-key --data-file=-
echo -n "<msg91-widget-id>" | gcloud secrets create msg91-widget-id --data-file=-
echo -n "<msg91-widget-token>" | gcloud secrets create msg91-widget-token --data-file=-
echo -n "<razorpay-key-id>" | gcloud secrets create razorpay-key-id --data-file=-
echo -n "<razorpay-key-secret>" | gcloud secrets create razorpay-key-secret --data-file=-
echo -n "<razorpay-webhook-secret>" | gcloud secrets create razorpay-webhook-secret --data-file=-
```

Generate the JWT secret with `openssl rand -hex 64`.

## Recurring deploy

### Container

Backend needs a `Dockerfile` at `backend/Dockerfile`:

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
ENV PORT=8080
EXPOSE 8080
CMD ["node", "src/server.js"]
```

Cloud Run injects `PORT` at runtime — the app must bind to `process.env.PORT` and `0.0.0.0`.

### Deploy

```bash
gcloud run deploy sharecab-backend \
  --source backend/ \
  --region asia-south1 \
  --platform managed \
  --allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --concurrency 80 \
  --min-instances 0 \
  --max-instances 10 \
  --timeout 60 \
  --set-secrets="MONGODB_URI=mongodb-uri:latest,\
JWT_SECRET=jwt-secret:latest,\
MSG91_AUTH_KEY=msg91-auth-key:latest,\
MSG91_WIDGET_ID=msg91-widget-id:latest,\
MSG91_WIDGET_AUTH_TOKEN=msg91-widget-token:latest,\
RAZORPAY_KEY_ID=razorpay-key-id:latest,\
RAZORPAY_KEY_SECRET=razorpay-key-secret:latest,\
RAZORPAY_WEBHOOK_SECRET=razorpay-webhook-secret:latest" \
  --set-env-vars="NODE_ENV=production,MATCH_RIDER_ONLY=false,MSG91_DEV_FALLBACK=false"
```

First deploy returns a `https://sharecab-backend-XXX-asia-south1.run.app` URL. That's your production `API_BASE_URL`.

### Flutter clients

Build with the production URL baked in:

```bash
# Rider app
cd app
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://sharecab-backend-XXX-asia-south1.run.app \
  --dart-define=GOOGLE_MAPS_KEY=$GOOGLE_MAPS_PROD_KEY

# Driver app — same shape from driver/
```

For TestFlight, archive in Xcode after `flutter build ipa` and upload via Transporter.

## Cold start tradeoff

Cloud Run scales to zero when idle, so the first request after a quiet window pays ~1-2s cold-start. Mitigations:

- **Acceptable as-is** — APIs are forgiving of one slow login.
- **`--min-instances 1`** — keeps one container warm. ~$5-8/mo. Use this when active user count > a few dozen.
- **Cloud Scheduler ping** — cron-curl the `/health` endpoint every 4 minutes. Hacky but free.

## Region pinning

Everything stays in `asia-south1` (Mumbai). Specifically:

- Cloud Run service region
- Atlas cluster region
- Cloud Storage buckets (if/when we add document uploads)
- Secret Manager replication policy (`automatic` is fine — secrets are tiny)

Latency to riders elsewhere in India is 20-60ms which is well within tolerance. Multi-region only becomes relevant when we have international users — out of scope for the India-only product.

## Rollback

```bash
gcloud run revisions list --service=sharecab-backend --region=asia-south1
gcloud run services update-traffic sharecab-backend \
  --region=asia-south1 \
  --to-revisions=sharecab-backend-00012-abc=100
```

Each `gcloud run deploy` creates a new revision; traffic shifts to the newest by default. Roll back by sending traffic to a prior revision id.

## Monitoring

- **Cloud Logging** — backend `console.log` lands here automatically. Filter by `resource.type="cloud_run_revision"`.
- **Cloud Monitoring** — pre-built Cloud Run dashboards show request count, error rate, latency, and instance count.
- **Uptime check** — add an HTTP uptime check on `/api/health` from the console; alerts to email/Slack are 5 lines of config.

For incidents, jump to [runbook.md](runbook.md).
