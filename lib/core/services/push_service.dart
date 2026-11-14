import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../sync/sync_api_client.dart';

/// Registers this device for push notifications. The API already sends budget
/// alerts, loan and maturity reminders and the monthly digest over FCM, but the
/// app never registered a token, so none of them reached the phone.
///
/// Notification messages arriving in the background are shown by Android
/// itself; [foregroundMessages] lets the open app surface them too.
class PushService {
  PushService._();
  static final instance = PushService._();

  final _foreground = StreamController<RemoteNotification>.broadcast();
  Stream<RemoteNotification> get foregroundMessages => _foreground.stream;

  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _messageSub;

  /// Asks for permission (Android 13+ shows a prompt) and sends the token to
  /// the API. Safe to call on every sign-in; failures are logged, not thrown.
  Future<void> register(SyncApiClient api) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await _send(api, token);

      await _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen((t) => _send(api, t));

      await _messageSub?.cancel();
      _messageSub = FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) _foreground.add(n);
      });
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _send(SyncApiClient api, String token) async {
    try {
      await api.dio.patch('/users/me/fcm', data: {'fcmToken': token});
    } catch (e) {
      debugPrint('Could not register push token: $e');
    }
  }

  /// On sign-out: stop this device receiving the previous user's alerts.
  Future<void> unregister() async {
    await _refreshSub?.cancel();
    await _messageSub?.cancel();
    _refreshSub = null;
    _messageSub = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('Could not delete push token: $e');
    }
  }
}
