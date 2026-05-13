# ShareCab Driver

ShareCab Driver — go online, accept rides, earn.

## Getting Started

The driver app is source-visible for review, UI work, and local demo testing.
In the public-source repo it should not connect to real driver dispatch unless
the backend is running with private production configuration:

```bash
ENABLE_PRODUCTION_DRIVER_OPS=true
```

For public demo/dev mode, keep backend `SHARECAB_PUBLIC_DEMO=true` and use
simulated or seeded drivers for rider-side demos.

Run locally:

```bash
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:4000 \
  --dart-define=GOOGLE_MAPS_KEY=AIzaSy...your-restricted-key
```

Android receives `GOOGLE_MAPS_KEY` from the Flutter dart-define at build time.
On iOS, set `GOOGLE_MAPS_KEY` as a local Xcode build setting or in an untracked
local xcconfig before running map screens.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
