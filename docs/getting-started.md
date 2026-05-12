# Getting Started

Bring up all four services locally on a fresh Mac in about 15 minutes.

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Node | ≥ 20.x | `brew install node@20` |
| Flutter | ≥ 3.19 | [flutter.dev/docs/get-started](https://docs.flutter.dev/get-started/install/macos) |
| Xcode | 15+ (for iOS sim) | App Store |
| Android Studio | latest (for emulator) | [developer.android.com/studio](https://developer.android.com/studio) |
| MongoDB | local 7.x OR Docker | `brew install mongodb-community@7.0` or use docker-compose |
| CocoaPods | latest | `sudo gem install cocoapods` |

Confirm with `flutter doctor` — fix any red Xs before proceeding.

## 1. Clone

```bash
git clone <repo> ShareCab
cd ShareCab
```

## 2. Backend — `backend/`

```bash
cd backend
npm install
cp .env.example .env       # if .env.example exists; otherwise see "Env vars" below
```

**Env vars** (`backend/.env`):

| Key | Required | Default | Notes |
|---|---|---|---|
| `PORT` | no | `4000` | |
| `MONGODB_URI` | yes | `mongodb://localhost:27017/sharecab` | Local Mongo or Atlas connection string. |
| `JWT_SECRET` | yes | `dev-only-insecure-secret` | Override in any non-local env. |
| `MSG91_DEV_FALLBACK` | dev | `false` | Set to `true` for `123456` OTP without hitting MSG91. |
| `MSG91_AUTH_KEY` | prod | — | Server-side authkey from msg91.com → API → Auth Keys. |
| `MSG91_WIDGET_ID` | prod | — | Widget ID from MSG91 OTP widget page. |
| `MSG91_WIDGET_AUTH_TOKEN` | prod | — | Public token for the widget; safe to ship to clients. |
| `MATCH_RIDER_ONLY` | dev | `false` | `true` skips driver dispatch — riders pair with each other only. |
| `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` | optional | — | Empty = stub mode (synthetic payments). |
| `RAZORPAY_WEBHOOK_SECRET` | optional | — | Needed for production webhook HMAC verification. |
| `DRIVER_SUBSCRIPTION_PRICE_PAISE` | no | `49900` | ₹499/month default. |

Start it:

```bash
npm run dev
# → listening on http://localhost:4000
```

Health check: `curl http://localhost:4000/api/health` should return `{"ok":true}`.

## 3. Rider app — `app/`

```bash
cd ../app
flutter pub get
cd ios && pod install && cd ..
```

Run on the iOS simulator:

```bash
flutter run -d "iPhone 15"
# iOS sim talks to localhost directly — no special API_BASE_URL needed
```

Run on Android emulator:

```bash
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:4000
# 10.0.2.2 is the special Android emulator alias for the host machine's localhost
```

VS Code: use the launch configs in [.vscode/launch.json](../.vscode/launch.json) — pick "ShareCab App (iOS Simulator)" or "ShareCab App (Android Emulator)".

## 4. Driver app — `driver/`

Same shape as the rider app:

```bash
cd ../driver
flutter pub get
cd ios && pod install && cd ..
flutter run -d "iPhone 15"
```

VS Code: "ShareCab Driver (iOS Simulator)". Or run rider + driver side-by-side with the compound config "ShareCab Rider + Driver (iOS Simulators)".

## 5. Marketing site — `website/`

```bash
cd ../website
npm install
npm run dev
# → http://localhost:3000
```

## 6. Sanity-check the full loop

With backend + rider + driver all running:

1. Open the rider app, log in with any 10-digit number + OTP `123456` (dev fallback) or a real number + the SMS OTP (MSG91).
2. Open the driver app, log in with a *different* number.
3. Complete onboarding in the driver app (auto-approved if `MSG91_DEV_FALLBACK=true`).
4. Set `MATCH_RIDER_ONLY=false` in `backend/.env` and restart the backend.
5. In the driver app, go online.
6. In the rider app, book a trip near the driver's location.
7. Driver app receives the dispatch within 12 seconds → tap → trip lifecycle.

If any step breaks, [runbook.md](runbook.md) has the common causes.

## Common first-run issues

- **`pod install` fails on Apple Silicon** → `sudo arch -x86_64 gem install ffi && arch -x86_64 pod install`.
- **Flutter "compileSdk not found"** → `flutter upgrade` and re-run `flutter pub get`.
- **OTP returns "Forbidden"** → see the JWT-staleness fix in [runbook.md](runbook.md#forbidden-on-go-online).
- **MSG91 returns "IPBlocked"** → your IP isn't whitelisted in the MSG91 dashboard. Either whitelist it or set `MSG91_DEV_FALLBACK=true`.
