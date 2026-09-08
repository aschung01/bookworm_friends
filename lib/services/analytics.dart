import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Where an analytics event goes.
///
/// **An interface with a swappable global, which is the seam this app already uses**
/// (`coverImageProvider`, `avatarImageProvider`). The alternative — calling
/// `FirebaseAnalytics.instance` at the call site — makes every widget test that touches
/// a logged interaction depend on Firebase being initialised, and there is no Firebase
/// under `flutter test`.
abstract interface class AnalyticsSink {
  Future<void> log(String name, Map<String, Object> parameters);
}

/// The production sink.
///
/// **Errors are swallowed, deliberately.** `FirebaseAnalytics.instance` throws when
/// Firebase has not been initialised, and nothing in this app should fail because a
/// measurement did. A share that works and is not counted is a worse dashboard; a share
/// that fails because it could not be counted is a worse product.
class FirebaseAnalyticsSink implements AnalyticsSink {
  const FirebaseAnalyticsSink();

  @override
  Future<void> log(String name, Map<String, Object> parameters) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (error) {
      // Reported once rather than silently, so a misconfigured project is findable.
      debugPrint('analytics: $name not logged ($error)');
    }
  }
}

/// Records events instead of sending them. For tests.
class RecordingAnalyticsSink implements AnalyticsSink {
  final events = <({String name, Map<String, Object> parameters})>[];

  @override
  Future<void> log(String name, Map<String, Object> parameters) async {
    events.add((name: name, parameters: parameters));
  }

  /// Every event logged under [name], in order.
  Iterable<Map<String, Object>> operator [](String name) =>
      events.where((event) => event.name == name).map((e) => e.parameters);
}

/// The app's analytics sink. Swap in a [RecordingAnalyticsSink] to assert on events.
///
/// **This is the first measurement in the app.** `firebase_analytics` has been a
/// declared dependency for a long time with zero `logEvent` calls behind it, so there is
/// no established convention to follow here and this file sets one: events are named
/// `noun_verb` in snake case, every parameter is a low-cardinality string, and nothing
/// that identifies a person or a book is ever a parameter.
AnalyticsSink analytics = const FirebaseAnalyticsSink();

/// A share was started: the image is rendered and handed off.
///
/// Logged when a destination is pressed rather than when the screen opens, because the
/// screen opening is not an intent to send anything — the whole point of `View and share`
/// is that a reader can look and change their mind.
const String kShareOpened = 'share_opened';

/// A share came back from the platform, successful or not.
///
/// **`Share.shareXFiles` returns a `ShareResult` and it was being thrown away**, which is
/// why nothing in this app has ever known whether a share landed. That return value is
/// what makes [kShareOpened] and this one a funnel rather than two counters.
const String kShareCompleted = 'share_completed';
