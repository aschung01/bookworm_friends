// Token registration, which had never once succeeded in production: `fcm_token` was
// NULL for all 137 profile rows while this code path appeared to run on every sign-in.
//
// **The bug these tests exist to pin down is an ordering trap, not a logic error.** On
// iOS `FirebaseMessaging.getToken()` throws `apns-token-not-set` until APNs
// registration completes, while `getAPNSToken()` returns null through that same window.
// The app asked for the FCM token immediately after the permission prompt on first
// sign-in -- the one moment registration is least likely to have finished -- from an
// unawaited call whose throw became an unhandled async error that logged nothing.
//
// So the cases below are mostly about *waiting*: that the registrar retries APNs rather
// than reading it once, that it gives up rather than hanging, that a rotation is
// persisted, and that a failure is reported as an outcome instead of vanishing.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/push_token_registrar.dart';

/// A scripted `firebase_messaging`. `apnsAnswers` is consumed one entry per poll, so a
/// test can say "null twice, then a token" and describe the real race exactly.
class _FakeMessaging implements PushMessaging {
  _FakeMessaging({
    List<String?> apnsAnswers = const <String?>['apns-token'],
    this.fcmTokenValue = 'fcm-token',
    this.throwOnFcmToken = false,
  }) : _apnsAnswers = List<String?>.of(apnsAnswers);

  final List<String?> _apnsAnswers;
  final String? fcmTokenValue;
  final bool throwOnFcmToken;

  final _refreshes = StreamController<String>.broadcast();
  int apnsReads = 0;
  int fcmReads = 0;
  int permissionRequests = 0;

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<String?> apnsToken() async {
    apnsReads++;
    if (_apnsAnswers.isEmpty) return null;
    return _apnsAnswers.removeAt(0);
  }

  @override
  Future<String?> fcmToken() async {
    fcmReads++;
    if (throwOnFcmToken) {
      throw Exception('[firebase_messaging/apns-token-not-set]');
    }
    return fcmTokenValue;
  }

  @override
  Stream<String> tokenRefreshes() => _refreshes.stream;

  void rotate(String token) => _refreshes.add(token);
  Future<void> close() => _refreshes.close();
}

class _RecordingSink implements PushTokenSink {
  final saved = <String>[];
  bool throwOnSave = false;

  @override
  Future<void> save(String token) async {
    if (throwOnSave) throw StateError('no signed-in user');
    saved.add(token);
  }
}

/// Collapses the retry waits so the schedule is exercised without real time passing.
Future<void> _noSleep(Duration _) async {}

PushTokenRegistrar _registrar(
  _FakeMessaging messaging,
  _RecordingSink sink, {
  bool needsApnsToken = true,
}) => PushTokenRegistrar(
  messaging: messaging,
  sink: sink,
  needsApnsToken: needsApnsToken,
  retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
  sleep: _noSleep,
);

void main() {
  group('waiting out APNs registration', () {
    test(
      'Given APNs answers on the first read, When registering, Then the token is saved',
      () async {
        final messaging = _FakeMessaging();
        final sink = _RecordingSink();

        final outcome = await _registrar(messaging, sink).register();

        expect(outcome, PushTokenOutcome.saved);
        expect(sink.saved, ['fcm-token']);
        await messaging.close();
      },
    );

    test('Given APNs is not ready yet, When registering, Then it is polled until it '
        'answers and the token is still saved', () async {
      // The production failure in one case: the first reads come back null because
      // the OS has not finished registering. Reading once -- which is what asking
      // for the FCM token straight away effectively does -- is what broke this.
      final messaging = _FakeMessaging(apnsAnswers: [null, null, 'apns-token']);
      final sink = _RecordingSink();

      final outcome = await _registrar(messaging, sink).register();

      expect(outcome, PushTokenOutcome.saved);
      expect(messaging.apnsReads, 3);
      expect(sink.saved, ['fcm-token']);
      await messaging.close();
    });

    test(
      'Given APNs never answers, When registering, Then it gives up and never asks '
      'FCM for a token',
      () async {
        // The simulator case, and the reason this is an outcome rather than a throw.
        // Asking FCM anyway is what raised `apns-token-not-set`.
        final messaging = _FakeMessaging(apnsAnswers: const <String?>[]);
        final sink = _RecordingSink();

        final outcome = await _registrar(messaging, sink).register();

        expect(outcome, PushTokenOutcome.apnsUnavailable);
        expect(messaging.fcmReads, 0);
        expect(sink.saved, isEmpty);
        await messaging.close();
      },
    );

    test(
      'Given a platform without APNs, When registering, Then APNs is never consulted',
      () async {
        // Android must not wait out the whole schedule for a token that is never coming.
        final messaging = _FakeMessaging(apnsAnswers: const <String?>[]);
        final sink = _RecordingSink();

        final outcome = await _registrar(
          messaging,
          sink,
          needsApnsToken: false,
        ).register();

        expect(outcome, PushTokenOutcome.saved);
        expect(messaging.apnsReads, 0);
        await messaging.close();
      },
    );
  });

  group('reporting failure instead of losing it', () {
    test(
      'Given FCM throws, When registering, Then the failure comes back as an outcome',
      () async {
        final messaging = _FakeMessaging(throwOnFcmToken: true);
        final sink = _RecordingSink();

        final outcome = await _registrar(messaging, sink).register();

        expect(outcome, PushTokenOutcome.failed);
        expect(sink.saved, isEmpty);
        await messaging.close();
      },
    );

    test(
      'Given nobody is signed in, When registering, Then the save failure is reported',
      () async {
        final messaging = _FakeMessaging();
        final sink = _RecordingSink()..throwOnSave = true;

        final outcome = await _registrar(messaging, sink).register();

        expect(outcome, PushTokenOutcome.failed);
        await messaging.close();
      },
    );

    test(
      'Given FCM returns no token, When registering, Then nothing is saved',
      () async {
        final messaging = _FakeMessaging(fcmTokenValue: null);
        final sink = _RecordingSink();

        final outcome = await _registrar(messaging, sink).register();

        expect(outcome, PushTokenOutcome.tokenUnavailable);
        expect(sink.saved, isEmpty);
        await messaging.close();
      },
    );
  });

  group('keeping up with rotation', () {
    test(
      'Given a rotated token, When it arrives, Then it is persisted',
      () async {
        // Nothing listened to `onTokenRefresh` before. FCM rotates on reinstall and
        // restore, and every rotation stranded the row at a stale value.
        final messaging = _FakeMessaging();
        final sink = _RecordingSink();
        final registrar = _registrar(messaging, sink)..watchRefreshes();

        messaging.rotate('rotated-token');
        await pumpEventQueue();

        expect(sink.saved, ['rotated-token']);
        await registrar.dispose();
        await messaging.close();
      },
    );

    test('Given watchRefreshes is called repeatedly, When a token rotates, Then it is '
        'saved once', () async {
      // `registerToken` runs on every authenticated session, so this is called more
      // than once per process; duplicate subscriptions would multiply every write.
      final messaging = _FakeMessaging();
      final sink = _RecordingSink();
      final registrar = _registrar(messaging, sink)
        ..watchRefreshes()
        ..watchRefreshes()
        ..watchRefreshes();

      messaging.rotate('rotated-token');
      await pumpEventQueue();

      expect(sink.saved, ['rotated-token']);
      await registrar.dispose();
      await messaging.close();
    });

    test(
      'Given a refusal, When permission is requested, Then it does not throw',
      () async {
        final messaging = _FakeMessaging();
        final sink = _RecordingSink();

        await _registrar(messaging, sink).requestPermission();

        expect(messaging.permissionRequests, 1);
        await messaging.close();
      },
    );
  });

  group('the channel the manifest and Dart must agree on', () {
    test('Given the Android manifest, When its default channel is read, Then it matches '
        'the id Dart posts to', () {
      // **These had drifted, and Android says nothing when they do.** The manifest
      // declared `high_importance_channel` while the foreground handler published to
      // a `default_channel` that was never created; a post to an unknown channel is
      // dropped, so a foreground poke showed nothing and reported no error. Asserting
      // the pair here is cheaper than rediscovering that.
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      final declared = RegExp(
        r'default_notification_channel_id"\s*\n?\s*android:value="([^"]+)"',
      ).firstMatch(manifest);

      expect(
        declared?.group(1),
        kAndroidNotificationChannelId,
        reason:
            'AndroidManifest.xml and kAndroidNotificationChannelId must name the '
            'same channel, or foreground notifications are silently dropped.',
      );
    });

    test(
      'Given the Android manifest, When permissions are read, Then POST_NOTIFICATIONS '
      'is declared',
      () {
        // Required from API 33. Without it the OS drops every notification and the
        // runtime prompt has nothing to ask for.
        expect(
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
          contains('android.permission.POST_NOTIFICATIONS'),
        );
      },
    );
  });
}
