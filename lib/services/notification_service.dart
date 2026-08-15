import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:bookworm_friends/core/supabase_config.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    try {
      await _messaging.requestPermission().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('requestPermission'),
      );
    } catch (_) {}

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
    } catch (_) {}

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    try {
      final initialMessage = await _messaging.getInitialMessage().timeout(
        const Duration(seconds: 5),
      );
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }
    } catch (_) {}
  }

  static Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  static Future<void> updateTokenInProfile() async {
    final token = await getToken();
    if (token == null) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'fcm_token': token})
        .eq('id', userId);
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'default_channel',
          'Default',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: message.data['type'] as String?,
    );
  }

  static void _handleMessageOpenedApp(RemoteMessage message) {
    final type = message.data['type'];
    _navigateFromPayload(type is String ? type : null);
  }

  static void _onNotificationTap(NotificationResponse response) {
    _navigateFromPayload(response.payload);
  }

  static void _navigateFromPayload(String? type) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    switch (type) {
      case 'poke':
      case 'follow':
        navigator.pushNamed('/home');
        break;
      default:
        navigator.pushNamed('/home');
    }
  }
}
