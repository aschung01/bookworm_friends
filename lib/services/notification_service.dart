import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/services/push_token_registrar.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// `firebase_messaging`, behind the seam the registrar is written against.
class _FirebasePushMessaging implements PushMessaging {
  const _FirebasePushMessaging();

  @override
  Future<void> requestPermission() =>
      FirebaseMessaging.instance.requestPermission();

  @override
  Future<String?> apnsToken() => FirebaseMessaging.instance.getAPNSToken();

  @override
  Future<String?> fcmToken() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> tokenRefreshes() => FirebaseMessaging.instance.onTokenRefresh;
}

/// Persists the token onto the signed-in reader's profile row.
///
/// Throws when nobody is signed in, which [PushTokenRegistrar.register] reports as
/// [PushTokenOutcome.failed]. That is the right shape: a token with no profile to
/// attach it to is not registered, and the next sign-in will try again.
class _ProfilePushTokenSink implements PushTokenSink {
  const _ProfilePushTokenSink();

  @override
  Future<void> save(String token) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('no signed-in user');
    await supabase
        .from('profiles')
        .update({'fcm_token': token})
        .eq('id', userId);
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Held so [PushTokenRegistrar.watchRefreshes] attaches exactly one subscription
  /// however many times [registerToken] is called.
  static PushTokenRegistrar? _registrar;

  static PushTokenRegistrar get _resolved => _registrar ??= PushTokenRegistrar(
    messaging: const _FirebasePushMessaging(),
    sink: const _ProfilePushTokenSink(),
    // APNs gates the FCM token on Apple platforms only; asking elsewhere would
    // wait out the whole retry schedule for a token that is never coming.
    needsApnsToken: Platform.isIOS || Platform.isMacOS,
  );

  static Future<void> initialize() async {
    await _resolved.requestPermission();

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
      await _createAndroidChannel();
    } catch (error) {
      debugPrint('notifications: local plugin not initialised ($error)');
    }

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    try {
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 5));
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }
    } catch (_) {}
  }

  /// **The channel has to exist before anything posts to it.** Android silently drops
  /// a notification aimed at an unknown channel id, and the manifest naming
  /// [kAndroidNotificationChannelId] only tells FCM where to put a *background*
  /// notification -- it does not create it.
  static Future<void> _createAndroidChannel() async {
    if (!Platform.isAndroid) return;
    const channel = AndroidNotificationChannel(
      kAndroidNotificationChannelId,
      'Pokes and friend activity',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  /// Resolves the FCM token and writes it to the reader's profile.
  ///
  /// Called on every authenticated session rather than only on a fresh sign-in --
  /// see `auth_provider.dart`. Cheap enough to repeat and, because the send path
  /// prunes dead tokens, repeating is what makes a pruned device recover.
  static Future<PushTokenOutcome> registerToken() async {
    final registrar = _resolved;

    // **Permission first, and from here rather than only from `initialize`.**
    // `initialize()` is fire-and-forget after `runApp`, so an auth event can reach
    // this method before it has run. That matters more than it looks: on iOS it is
    // `requestPermission()` that triggers `registerForRemoteNotifications`, so
    // calling it late means APNs registration has not merely *not finished* -- it has
    // not been asked for, and polling would burn the whole retry budget waiting for
    // something nobody started. Idempotent: the OS prompts once.
    await registrar.requestPermission();

    final outcome = await registrar.register();
    if (outcome == PushTokenOutcome.saved) {
      registrar.watchRefreshes();
    } else {
      // Reported rather than swallowed. This failing silently is why the column was
      // empty for every row in production for as long as it was.
      debugPrint('notifications: token not registered (${outcome.name})');
    }
    return outcome;
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
          kAndroidNotificationChannelId,
          'Pokes and friend activity',
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
