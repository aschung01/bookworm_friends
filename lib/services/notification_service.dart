import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:bookworm_friends/core/supabase_config.dart';

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    await _messaging.requestPermission();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(settings);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
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
    );
  }
}
