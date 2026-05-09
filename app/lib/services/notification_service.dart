import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications wrapper.
///
/// **Scope**: works when the app is in the foreground OR backgrounded. Does
/// NOT fire when the app process is fully killed by the user / OS — that case
/// requires Firebase Cloud Messaging (see docs/notifications.md). This is
/// intentional first-pass scope; the call sites here will keep working
/// unchanged once FCM is layered in (the FCM background handler can hand off
/// to [show] for in-app rendering).
///
/// Notification IDs are stable per-purpose so a fresh "match found" replaces
/// the prior one rather than stacking.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const int _idMatchFound = 100;
  static const int _idSearchTimedOut = 101;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    try {
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      _initialized = true;
    } catch (e) {
      // Notification init failures shouldn't crash the app — surfacing logs is enough.
      if (kDebugMode) debugPrint('NotificationService.init failed: $e');
    }
  }

  Future<void> matchFound({String? coRiderText, double? perRiderFare}) async {
    final body = [
      if (coRiderText != null) coRiderText,
      if (perRiderFare != null) 'Your share: ₹${perRiderFare.toStringAsFixed(0)}',
    ].join(' · ');
    await _show(
      id: _idMatchFound,
      title: 'Match found',
      body: body.isEmpty ? 'A driver is on the way.' : body,
      channelId: 'match',
      channelName: 'Ride matches',
    );
  }

  Future<void> searchTimedOut() async {
    await _show(
      id: _idSearchTimedOut,
      title: 'No match this round',
      body: 'We couldn\'t find a co-rider in time. You can search again or ride solo.',
      channelId: 'match',
      channelName: 'Ride matches',
    );
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
  }) async {
    if (!_initialized) await init();
    if (!_initialized) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(presentSound: true),
    );
    try {
      await _plugin.show(id, title, body, details);
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.show failed: $e');
    }
  }
}
