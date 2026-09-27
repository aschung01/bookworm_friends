// `Uint8List` comes from here rather than from `dart:typed_data`, which `foundation` re-exports.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:bookworm_friends/models/streak_widget_snapshot.dart';

/// Writes the streak snapshot into the shared App Group and asks WidgetKit to redraw.
///
/// **A MethodChannel rather than the `home_widget` package**, and the reasoning is short: only
/// two things here need native code — put a string in `UserDefaults(suiteName:)` and call
/// `WidgetCenter.reloadAllTimelines()`. `home_widget`'s real value is its launch-URL plumbing,
/// and `app_links` already owns that path in this app (`InviteLinkService`). Its Android half
/// would be dead weight in a `pubspec.yaml` whose comments show every dependency argued for one
/// at a time.
///
/// **iOS only, and silent everywhere else.** The channel is not registered on Android, so every
/// method here is a no-op there rather than a `MissingPluginException` on a platform that has no
/// widget yet. A Glance widget would reuse the snapshot wholesale and only replace this file.
class StreakWidgetChannel {
  const StreakWidgetChannel();

  static const MethodChannel _channel = MethodChannel('bookworm/widget');

  bool get _supported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Stores [snapshot] and reloads the widget's timeline.
  ///
  /// Failures are swallowed on purpose. A widget that did not refresh is a stale number on a
  /// home screen; an error surfaced to the reader mid-session, for a surface they may not even
  /// have installed, is worse. The write is also not on any critical path — the app's own
  /// screens read the providers directly and never this.
  Future<void> write(StreakWidgetSnapshot snapshot) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('write', snapshot.encode());
    } on PlatformException catch (error) {
      debugPrint('streak widget: write failed (${error.code})');
    } on MissingPluginException {
      // A debug build running against an older Runner that has no channel registered.
    }
  }

  /// Stores [bytes] as the widget's jacket thumbnail, under [name], and reloads the timeline.
  ///
  /// **A file in the App Group container, not a value in `UserDefaults`.** A 120px PNG is tens of
  /// kilobytes; `UserDefaults` is a property list that is read whole, by both processes, on every
  /// snapshot read, and putting image data in one is the documented way to make it slow.
  ///
  /// **A second reload, and that is affordable precisely because this is rare.** The snapshot has
  /// already been written and drawn by the time this runs, so the cover arriving is a second
  /// redraw — but it only happens when the reader's book changes, where `write` is deduplicated
  /// per snapshot. The budget iOS grants a widget is spent by per-rebuild reloads, not by this.
  ///
  /// Failures are swallowed for the reason [write]'s are, and the fallback is better here: the
  /// widget draws the `coverColor` rectangle it drew before thumbnails existed.
  Future<void> writeCover(String name, Uint8List bytes) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('writeCover', <String, Object?>{
        'name': name,
        'bytes': bytes,
      });
    } on PlatformException catch (error) {
      debugPrint('streak widget: cover write failed (${error.code})');
    } on MissingPluginException {
      // A debug build running against an older Runner that has no channel registered.
    }
  }

  /// Empties the container.
  ///
  /// **Called on sign-out, and that is not housekeeping.** The snapshot outlives the session: on
  /// a shared device the next person to look at the home screen would otherwise be reading a
  /// stranger's streak and the title of a stranger's book, neither of which is behind the
  /// `reading_days` RLS that protects them everywhere else.
  ///
  /// **This now deletes the cover thumbnail too, and that raised the stakes rather than added a
  /// chore.** A hex rectangle leaked the fact of a book; a jacket leaks which book, legibly, to
  /// anyone who glances at the home screen.
  Future<void> clear() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException catch (error) {
      debugPrint('streak widget: clear failed (${error.code})');
    } on MissingPluginException {
      // As above.
    }
  }
}
