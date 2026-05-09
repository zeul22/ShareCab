# Notifications — current state and the FCM upgrade path

## What's wired up today

[`NotificationService`](../lib/services/notification_service.dart) uses
`flutter_local_notifications` to show system notifications from inside the
running app process.

Trigger points:

| Event                       | Where                                                   |
|-----------------------------|---------------------------------------------------------|
| Match found                 | `RideFlowState.startSearch` after proposals arrive      |
| Search window timed out     | `SearchingScreen` AnimationController completes empty   |

**Coverage**:

- ✅ App in foreground — notification rendered (banner depending on OS settings).
- ✅ App backgrounded but process alive — notification rendered.
- ❌ App fully killed (force-stop / OS evicted) — **no Dart code runs, no notification**.

This last gap is the bit that needs Firebase Cloud Messaging.

## Why local notifications can't cover "app fully closed"

`flutter_local_notifications` schedules through the OS notification system,
but the **trigger** is a Dart call inside the app. When the app process is
gone, no Dart runs, so the trigger never fires. To deliver a notification to
a fully-killed app you need a **server-pushed** message that the OS itself
delivers — that's FCM (Android + iOS) or APNs (iOS native).

## FCM upgrade — concrete steps

Estimated effort: 3–5 hours of focused work + Firebase project setup.

### 1. Firebase project setup (~30 min)

1. Create a Firebase project at <https://console.firebase.google.com>.
2. **Android**: register the package `com.example.sharecab` (or your final
   id), download `google-services.json` → drop into
   `app/android/app/google-services.json`. Add the `google-services` Gradle
   plugin in `android/build.gradle` and `android/app/build.gradle`.
3. **iOS**: register the bundle id, download `GoogleService-Info.plist` →
   drop into `app/ios/Runner/`. APNs requires an Apple Developer account
   and an APNs auth key uploaded to Firebase Cloud Messaging settings.
4. Generate a service-account JSON key (Project Settings → Service accounts
   → Generate new private key). Store as `backend/.fcm-service-account.json`
   (gitignored).

### 2. Flutter side (~1 hour)

Add deps to `pubspec.yaml`:

```yaml
firebase_core: ^3.6.0
firebase_messaging: ^15.1.3
```

In `lib/main.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handoff to the same NotificationService.show used by foreground.
  // Or rely on FCM's `notification:` payload to be auto-rendered by the OS.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.instance.init();

  // After auth, register the device token with the backend.
  final token = await FirebaseMessaging.instance.getToken();
  // POST it to /api/users/me/push-token with the bearer token.

  runApp(const ShareCabApp());
}
```

### 3. Backend side (~1.5 hours)

```bash
npm install firebase-admin
```

Add a `User.pushTokens: [String]` field. New endpoint
`POST /api/users/me/push-token` to register/upsert.

In `tripController.requestTrip` (after deferred dispatch resolves) and in
`scheduleDeferredDispatch` callback, call a new `notificationService.send`
that uses `firebase-admin` to push to the matched riders' tokens:

```js
const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require(env.fcmServiceAccountPath)) });

async function sendMatchFound(userId, payload) {
  const user = await User.findById(userId);
  if (!user?.pushTokens?.length) return;
  await admin.messaging().sendEachForMulticast({
    tokens: user.pushTokens,
    notification: {
      title: 'Match found',
      body: `Co-rider · ₹${payload.perRiderFare} share`,
    },
    data: { tripId: payload.tripId, kind: 'match_found' },
  });
}
```

### 4. iOS-only extras (~30 min)

- Enable Push Notifications + Background Modes (Remote notifications) in
  the Runner target's Capabilities.
- The first-run `requestPermission()` prompt is fine via
  `firebase_messaging`'s own API.

### 5. Verify

- Background the app, fire a match → notification appears (works today
  with local notifications).
- **Force-stop** the app, fire a match from another device → notification
  appears (only works after FCM is wired).

## When to do this

The local-notification path covers the most common case (rider has the app
in their recent-apps stack while waiting). FCM becomes meaningful when
either (a) ride wait windows extend beyond a few minutes, or (b) you start
sending notifications for events the rider isn't actively waiting for
(driver arriving, ride starting, payment due).
