import 'dart:async';

/// The Android notification channel every push lands in.
///
/// **Shared so the manifest and the Dart display path cannot drift apart, which is
/// exactly what they had done.** `AndroidManifest.xml` declares
/// `com.google.firebase.messaging.default_notification_channel_id` as
/// `high_importance_channel`, while the foreground handler published to a
/// `default_channel` that was never created. A channel id that does not exist is not
/// an error on Android -- the post is simply dropped -- so a foreground poke showed
/// nothing and said nothing about why.
///
/// `test/push_token_registrar_test.dart` asserts this matches the manifest.
const String kAndroidNotificationChannelId = 'high_importance_channel';

/// How long to keep asking for the APNs token before giving up, as successive waits.
///
/// **This schedule is the whole fix for the iOS case.** See [PushTokenRegistrar] for
/// why a single read is not enough. Roughly 7.75s in total, all of it off the first
/// frame, and every entry is a wait the common case never reaches: registration
/// usually completes inside the first two.
const List<Duration> kApnsRetryDelays = <Duration>[
  Duration.zero,
  Duration(milliseconds: 250),
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

/// The slice of `firebase_messaging` that token registration needs.
///
/// **A seam, for the reason `AnalyticsSink` is one:** there is no Firebase under
/// `flutter test`, so anything that reaches `FirebaseMessaging.instance` at the call
/// site drags a native dependency into every test that touches sign-in.
abstract interface class PushMessaging {
  /// Prompts for notification permission. On Android 13+ this is what asks for
  /// `POST_NOTIFICATIONS`.
  Future<void> requestPermission();

  /// The APNs device token, or null while the OS has not finished registering.
  /// Always null on platforms that do not use APNs.
  Future<String?> apnsToken();

  /// The FCM registration token.
  Future<String?> fcmToken();

  /// Fires whenever FCM rotates the token.
  Stream<String> tokenRefreshes();
}

/// Where a resolved token is persisted.
abstract interface class PushTokenSink {
  Future<void> save(String token);
}

/// Why a registration attempt ended the way it did.
///
/// Returned rather than logged so tests can assert on the outcome, and so the caller
/// can decide how loud to be. [apnsUnavailable] in particular is an ordinary result on
/// the iOS simulator, not a fault worth reporting.
enum PushTokenOutcome {
  /// A token was resolved and handed to the sink.
  saved,

  /// APNs never produced a device token within [kApnsRetryDelays].
  apnsUnavailable,

  /// APNs was fine (or not required) but FCM returned no token.
  tokenUnavailable,

  /// Something threw. The token is not registered.
  failed,
}

/// Resolves an FCM token and persists it.
///
/// **Why this is not two lines.** `profiles.fcm_token` was NULL for all 137 rows in
/// production while this code appeared to run on every sign-in, and the reason is an
/// ordering trap in `firebase_messaging` on iOS:
///
///  * `getToken()` *throws* `apns-token-not-set` until the OS has completed APNs
///    registration -- it does not return null and wait;
///  * `getAPNSToken()` returns null during that same window rather than throwing;
///  * the one moment the app ever tried to register was immediately after the
///    permission prompt on first sign-in, which is precisely when registration has
///    least likely finished.
///
/// So the only write path the app had was the one guaranteed to throw, and because the
/// call was unawaited and uncaught the throw became an unhandled async error that
/// logged nothing. Polling [PushMessaging.apnsToken] until it answers, *then* asking
/// for the FCM token, is what turns that race into a wait.
///
/// The registrar deliberately knows nothing about Firebase or Supabase; it is driven
/// entirely through [PushMessaging] and [PushTokenSink] so the retry behaviour above is
/// testable without either.
class PushTokenRegistrar {
  PushTokenRegistrar({
    required PushMessaging messaging,
    required PushTokenSink sink,
    required bool needsApnsToken,
    List<Duration> retryDelays = kApnsRetryDelays,
    Future<void> Function(Duration)? sleep,
  }) : _messaging = messaging,
       _sink = sink,
       _needsApnsToken = needsApnsToken,
       _retryDelays = retryDelays,
       _sleep = sleep ?? Future<void>.delayed;

  final PushMessaging _messaging;
  final PushTokenSink _sink;
  final bool _needsApnsToken;
  final List<Duration> _retryDelays;
  final Future<void> Function(Duration) _sleep;

  StreamSubscription<String>? _refreshes;

  /// Asks for permission. Safe to call more than once; the OS prompts once.
  ///
  /// Failure is swallowed because a refused or unanswered prompt is a legitimate
  /// choice, and [register] is still worth attempting afterwards -- a token exists
  /// whether or not the user allowed alerts, and registering it means an allow granted
  /// later in Settings needs no code to notice.
  Future<void> requestPermission() async {
    try {
      await _messaging.requestPermission();
    } catch (_) {}
  }

  /// Resolves the current token and saves it.
  ///
  /// **Writes unconditionally rather than only when the token changed.** The send path
  /// clears `profiles.fcm_token` when FCM reports a token `UNREGISTERED`, so re-writing
  /// on every authenticated launch is what lets a device that was pruned heal itself
  /// without anything having to detect that it was.
  Future<PushTokenOutcome> register() async {
    try {
      if (_needsApnsToken && await _awaitApnsToken() == null) {
        return PushTokenOutcome.apnsUnavailable;
      }

      final token = await _messaging.fcmToken();
      if (token == null || token.isEmpty) {
        return PushTokenOutcome.tokenUnavailable;
      }

      await _sink.save(token);
      return PushTokenOutcome.saved;
    } catch (_) {
      return PushTokenOutcome.failed;
    }
  }

  /// Persists rotated tokens for the rest of the process lifetime.
  ///
  /// **Nothing listened to this before, which is a slower version of the same bug.**
  /// FCM rotates a token on reinstall, restore and at its own discretion; every
  /// rotation silently stranded the row at a value that no longer addresses the device.
  void watchRefreshes() {
    _refreshes ??= _messaging.tokenRefreshes().listen((token) async {
      if (token.isEmpty) return;
      try {
        await _sink.save(token);
      } catch (_) {}
    }, onError: (Object _, StackTrace __) {});
  }

  Future<void> dispose() async {
    await _refreshes?.cancel();
    _refreshes = null;
  }

  Future<String?> _awaitApnsToken() async {
    for (final delay in _retryDelays) {
      if (delay > Duration.zero) await _sleep(delay);
      final token = await _messaging.apnsToken();
      if (token != null && token.isNotEmpty) return token;
    }
    return null;
  }
}
