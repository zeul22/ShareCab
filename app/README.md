# ShareCab — Mobile App

The ShareCab rider app, built with Flutter. Helps users **share a cab** with compatible passengers headed nearby — destination-based or random-compatible matching, with first-class support for the airport pickup flow, luggage rules, and OTP-verified ride confirmation.

The app currently runs on **mock services** so the full flow (search → match → confirm → ride → pay) is demo-able without a backend. Every API call is funneled through a single `RideApi` interface — swap in `HttpRideApi` later and the UI stays unchanged.

## Stack

- **Framework:** Flutter 3.19+
- **State:** Provider (`ChangeNotifier`)
- **Networking:** `AuthApi` + `RideApi` interfaces (both mocked today)
- **Auth:** Phone + OTP, persistent sessions, rotating refresh tokens
- **Storage:** `shared_preferences` (auth session blob)
- **Location:** `geolocator`
- **Maps:** `google_maps_flutter` + `google_places_flutter` (autocomplete) + `flutter_polyline_points`

## Demo Login

Auth runs on `MockAuthApi`, so you can log in instantly with:

| Field | Value |
|-------|-------|
| **Phone** | `9999900001` |
| **OTP**   | `123456` |

In mock mode any 10-digit phone works — `123456` is always accepted. The phone-entry screen has a **Use demo number** shortcut and shows the OTP inline so reviewers don't have to remember it.

## Quick Start

```bash
# 1. Generate native folders (first run only)
flutter create . --org com.sharecab

# 2. Install dependencies
flutter pub get

# 3. Run with the API URL and your Google Maps key
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:4000 \
  --dart-define=GOOGLE_MAPS_KEY=AIzaSy...your-key
# iOS simulator? Use http://localhost:4000 for the API.
```

For MSG91 production OTP, either pass `MSG91_WIDGET_ID` and
`MSG91_WIDGET_AUTH_TOKEN` as dart-defines or configure them on the backend;
the app will fetch backend-provided widget config from
`/api/auth/otp/msg91/config` at startup.

The app's matching is **fully mocked** — you don't need the backend to demo the booking flow.

### Run from the repo root (VS Code)

The repo's [`.vscode/launch.json`](../.vscode/launch.json) ships four launch configurations so you can hit **F5** from the monorepo root without `cd`-ing into `app/`:

| Config | What it does |
|--------|--------------|
| **ShareCab App (debug)**            | Hot-reload debug build, no `--dart-define` (uses defaults from [`api_config.dart`](lib/utils/api_config.dart)) |
| **ShareCab App (profile)**          | Profile-mode build for performance testing |
| **ShareCab App (release)**          | Release-mode build |
| **ShareCab App (debug, with Maps key)** | Prompts for your Google Maps API key on launch and passes it via `--dart-define=GOOGLE_MAPS_KEY=…` |

The first three are perfect for the mock demo (the picker just won't show map tiles without a key). Pick the fourth when you actually need maps.

To bake your key in permanently, edit `.vscode/launch.json` and uncomment the `toolArgs` lines on the config you use most.

## Booking Flow

```
SplashScreen
   │  bootstrap stored session (auto-refresh access token if expired)
   │
   ├──► PhoneEntryScreen → OtpVerifyScreen   (phone + 6-digit OTP)
   ▼
HomeScreen   (Google Map + bottom sheet, two entry points)
   │
   ├──► AirportArrivalScreen   (sets airport mode + landing time)
   │           │
   │           ▼
   ▼      DestinationScreen     (pickup + drop via MapPickerScreen)
                  │
                  ▼
              LuggageScreen      (handbag / cabin / large counters)
                  │
                  ▼
       MatchPreferenceScreen     (nearby destination | random compatible)
                  │
                  ▼
             SearchingScreen    (calls MatchingEngine → MatchResult)
                  │
                  ▼
           MatchResultScreen     (Accept / Reject / Search again)
                  │  (route preview → RouteStopsScreen)
                  │
            Accept ▼
       RideConfirmationScreen   (driver, vehicle, plate, OTP)
                  │
                  ▼
          RideStatusScreen       (live map, "I've reached")
                  │
                  ▼
            PaymentScreen        (pay now / pay after; UPI / card / wallet / cash)
                  │
                  ▼
          RideCompletedScreen    (summary + Rate)
                  │
                  ▼
              RatingScreen
                  │
                  ▼
              HomeScreen
```

History, Profile, and Help & Safety are reachable from the home app bar / profile screen.

## Domain Model

All models live in [`lib/models/`](lib/models). They are intentionally framework-free — no Flutter imports — so the matching engine and tests can use them directly.

| Model           | Purpose |
|-----------------|---------|
| `User`          | Authenticated account |
| `Place`         | A `{address, lat, lng}` point |
| `LuggageProfile` | What the rider is carrying — handbag / cabin / large |
| `Vehicle`       | Car instance + `VehicleType` (hatchback / sedan / SUV) |
| `Driver`        | Driver instance + their `Vehicle` |
| `Passenger`     | A co-rider as exposed to others (first name + rating only) |
| `RouteStop`     | One stop on the sequenced route |
| `RideSearch`    | The in-progress booking request |
| `MatchProposal` | A candidate group the user can accept/reject |
| `Ride`          | Confirmed booking with OTP and status |
| `Payment`       | One rider's payment for one ride |

## Auth Architecture

Phone + OTP only — no passwords. Once a user verifies their phone, they're "logged in forever":

1. **Request OTP** → `Msg91AuthApi` calls the MSG91 Flutter widget SDK (`sendOTP`) when widget credentials are configured via dart-defines or backend public config; local dev can still use the backend `DEV_OTP` path.
2. **Verify OTP** → `Msg91AuthApi` calls the widget SDK (`verifyOTP`), sends the returned access token to the backend, and receives `{ accessToken, refreshToken, user }`. Both tokens + user are persisted as one blob in `SharedPreferences`.
3. **Access token** is short-lived (15 min). Every API call goes through `AuthService.accessTokenForApi()` which refreshes silently if expired.
4. **Refresh token rotates on every use** — each refresh issues a new pair and revokes the old one. A stolen refresh token only works until the legitimate device next refreshes.
5. **Bootstrap on launch** — if the persisted access token is expired, `AuthService.bootstrap()` refreshes silently. If refresh fails, local state clears and the user lands on the phone-entry screen.
6. **Logout** revokes the refresh token server-side and wipes local storage.

Net effect: users sign in once and stay signed in indefinitely, while every individual token has a rolling validity for security.

Files:
- [`lib/models/auth_session.dart`](lib/models/auth_session.dart) — token + user blob
- [`lib/services/api/auth_api.dart`](lib/services/api/auth_api.dart) — interface
- [`lib/services/api/msg91_auth_api.dart`](lib/services/api/msg91_auth_api.dart) — MSG91 widget integration
- [`lib/services/api/mock_auth_api.dart`](lib/services/api/mock_auth_api.dart) — demo impl
- [`lib/services/auth_service.dart`](lib/services/auth_service.dart) — token store + auto-refresh

## Matching Logic

[`lib/services/matching/matching_engine.dart`](lib/services/matching/matching_engine.dart) is a pure function over a [`RideSearch`] and a pool of concurrent passengers. It applies these constraints in order:

1. **Pickup proximity** — every rider's pickup is within ~2 km of the group centroid (small detour).
2. **Destination proximity** — for *destination-nearby* mode, every drop is within 2–4 km of the user's drop. *Random-compatible* mode skips this but keeps every other check (so "random" is still bounded).
3. **Vehicle capacity** — total riders ≤ vehicle.maxSharedRiders. 4–5 seater = max 3 riders, 7 seater = max 5.
4. **Luggage capacity** — combined luggage seats ≤ vehicle.luggageCapacity. Rules in [`luggage_rules.dart`](lib/services/matching/luggage_rules.dart): handbag/laptop = 0 seats, 2 cabin trolleys = 1 seat, each large bag = 1 seat.
5. **Active-window** — only riders who started searching recently are considered (the mock pool models this implicitly).
6. **Airport timing** — airport-mode riders only pair with other airport-mode riders whose landing time is in the same window.

Best proposal first: cheapest per-rider share, tie-broken by shorter total distance.

## Project Layout

```
app/
├── lib/
│   ├── main.dart                     # MultiProvider + named routes
│   ├── routes.dart                   # one place for every route name
│   ├── theme/app_theme.dart          # ShareCab color + component theme
│   ├── models/                       # all domain models (framework-free)
│   ├── services/
│   │   ├── auth_service.dart         # signup / login / token storage
│   │   ├── location_service.dart     # geolocator wrapper
│   │   ├── ride_flow.dart            # ChangeNotifier — booking flow state machine
│   │   ├── api/
│   │   │   ├── ride_api.dart         # interface (the swap point)
│   │   │   ├── mock_ride_api.dart    # in-memory implementation
│   │   │   └── mock_data.dart        # synthetic drivers + co-passengers
│   │   └── matching/
│   │       ├── matching_engine.dart  # pure matching logic
│   │       ├── luggage_rules.dart    # luggage seat math
│   │       ├── vehicle_rules.dart    # vehicle capacity math
│   │       └── geo.dart              # haversine helper
│   ├── screens/                      # one file per screen (see flow above)
│   └── utils/api_config.dart         # API_BASE_URL + GOOGLE_MAPS_KEY
├── pubspec.yaml
└── analysis_options.yaml
```

## Wiring a Real Backend

When the backend is ready:

1. Implement `RideApi` (e.g. `HttpRideApi`) on top of `dio`/`http`, hitting the endpoints described in [backend/docs/api.md](../backend/docs/api.md).
2. Open [`lib/main.dart`](lib/main.dart) and change one line:
   ```dart
   final RideApi rideApi = HttpRideApi(); // was MockRideApi()
   ```
3. Push live ride/driver-location updates over Socket.IO; replace the manual "I've reached" affordance in [`ride_status_screen.dart`](lib/screens/ride_status_screen.dart) with socket-driven status changes.

`RideFlowState`, every screen, and the matching engine stay untouched.

## Google Maps Setup

You need **one** Google Maps Platform API key (with `Maps SDK for Android`, `Maps SDK for iOS`, and `Places API` enabled). Plug it into three places:

### 1. Android — `android/app/src/main/AndroidManifest.xml`

Inside `<application>`:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_API_KEY_HERE"/>
```

Inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### 2. iOS — `ios/Runner/AppDelegate.swift`

```swift
import GoogleMaps
GMSServices.provideAPIKey("YOUR_API_KEY_HERE")
```

Add to `ios/Runner/Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>ShareCab uses your location to find nearby rides and drivers.</string>
```

### 3. Dart — Places autocomplete

Pass the same key via `--dart-define=GOOGLE_MAPS_KEY=...` (used by the search bar in `MapPickerScreen`).

## Branding

Color palette and typography live in [`lib/theme/app_theme.dart`](lib/theme/app_theme.dart). The brand green matches the website's `brand-600`.

## License

MIT
