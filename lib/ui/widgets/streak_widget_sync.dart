import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/streak_widget_snapshot.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/streak_widget_provider.dart';
import 'package:bookworm_friends/services/streak_cover_thumbnail.dart';
import 'package:bookworm_friends/services/streak_widget_channel.dart';

/// Keeps the home-screen widget's snapshot in step with the app.
///
/// **Hosted in `MaterialApp.builder` beside [InviteLinkListener], and for the same two reasons.**
/// It draws nothing, and it has to outlive every route: a night can be recorded from the streak
/// page, from the book details band, or from the finished-books sheet, and the widget has to
/// follow all of them. Sitting above the navigator also means it is still mounted while a modal
/// sheet is up, which is where the record actually happens.
///
/// **Why a widget and not a listener inside the provider.** The payload includes twelve translated
/// strings, and `AppLocalizations` needs a `BuildContext`. The alternative was reaching through
/// `navigatorKey.currentContext` from a provider — which this codebase does do for EasyLoading,
/// and which is worth avoiding here because the snapshot is written on a schedule the reader
/// cannot see: a null context would silently skip a write rather than visibly skip a toast.
///
/// The write is deduplicated on the snapshot's own equality, which excludes `writtenAt` for
/// precisely this reason — an every-rebuild `reloadAllTimelines` is how a widget exhausts the
/// refresh budget iOS grants it and then stops updating at all.
class StreakWidgetSync extends ConsumerStatefulWidget {
  const StreakWidgetSync({
    super.key,
    required this.child,
    this.thumbnail = const StreakCoverThumbnail(),
  });

  final Widget child;

  /// Injected so a test can pump this widget without a socket. See [StreakCoverThumbnail].
  final StreakCoverThumbnail thumbnail;

  @override
  ConsumerState<StreakWidgetSync> createState() => _StreakWidgetSyncState();
}

class _StreakWidgetSyncState extends ConsumerState<StreakWidgetSync> {
  static const StreakWidgetChannel _channel = StreakWidgetChannel();

  /// The last payload actually handed to the platform, so an unchanged one is not re-sent.
  StreakWidgetSnapshot? _written;

  /// The cover URL whose thumbnail has been fetched, so a book that has not changed does not
  /// cost a request per rebuild. **Separate from [_written] rather than folded into it**, because
  /// the snapshot's equality deliberately ignores most of the book and the two answer different
  /// questions: whether to re-publish the figures, and whether to re-fetch an image.
  String? _coverFetched;

  /// True while a fetch is in flight, so a rebuild during it does not start a second one.
  bool _fetching = false;

  @override
  Widget build(BuildContext context) {
    // **Sign-out clears rather than rewrites.** The snapshot outlives the session, so on a
    // shared device the next person to glance at the home screen would otherwise read a
    // stranger's streak and the title of a stranger's book — neither of which is behind the
    // owner-only RLS that protects them everywhere else in the app.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (next == null && previous != null) {
        _written = null;
        _coverFetched = null;
        _channel.clear();
      }
    });

    ref.listen(streakWidgetFactsProvider, (_, facts) {
      if (facts == null) return;
      _publish(facts);
    });

    // Also read on build, not only listened for: the facts can settle before this widget is
    // first mounted — `readingDaysProvider` is warmed by the library shell — and a listener
    // alone would then wait for a second change that may not come until tomorrow.
    final facts = ref.watch(streakWidgetFactsProvider);
    if (facts != null) {
      // Deferred off the build phase. `invokeMethod` during build is a platform call inside a
      // frame, and the dedupe below means the common case does nothing at all.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _publish(facts);
      });
    }

    return widget.child;
  }

  void _publish(StreakWidgetFacts facts) {
    final l10n = AppLocalizations.of(context);
    final snapshot = StreakWidgetSnapshot(
      streak: facts.streak,
      longestStreak: facts.longestStreak,
      lastReadDay: facts.lastReadDay,
      book: facts.book,
      // The five strings the widget prints. All count-free in both locales, which is what makes
      // passing them cheaper than a second copy of the ARB inside the extension.
      copy: StreakWidgetCopy(
        // **Empty at zero, not the plural's own zero case.** `streakDays(0)` is the sentence
        // "No streak yet", which is a label for a screen and not for the slot beside a numeral:
        // passing it through rendered "0 No streak yet" on the widget. For any live run the
        // string is attributive and count-free in both locales, which is the property that lets
        // it be passed at all. Empty is the honest value at zero, because there the widget draws
        // the nothingYet line instead, exactly as the streak page does.
        dayStreak: facts.streak == 0 ? '' : l10n.streakDays(facts.streak),
        todayOpen: l10n.streakTodayOpen,
        todayLate: l10n.streakTodayLate,
        todayDone: l10n.streakTodayDone,
        nothingYet: l10n.streakNothingYet,
      ),
      // The copy ladder. Seven sentences and no choice among them: which one is drawn is the
      // widget's to derive from the hour of the entry it is rendering, exactly as the phase is.
      lines: StreakWidgetLines(
        dawn: l10n.streakWidgetLineDawn,
        morning: l10n.streakWidgetLineMorning,
        afternoon: l10n.streakWidgetLineAfternoon,
        evening: l10n.streakWidgetLineEvening,
        late: l10n.streakWidgetLineLate,
        last: l10n.streakWidgetLineFinal,
        none: l10n.streakWidgetLineNone,
      ),
    );

    if (snapshot == _written) return;
    _written = snapshot;
    _channel.write(snapshot);
    _publishCover(facts);
  }

  /// Fetch and store the jacket, after the snapshot has gone.
  ///
  /// **Deliberately not awaited by [_publish], and the order is the point.** The figures are
  /// already on the home screen before this starts; making the streak wait on a network call
  /// would mean a recorded night does not appear until a cover downloads. The widget draws
  /// `coverColor` in the meantime, which is what it drew before thumbnails existed.
  void _publishCover(StreakWidgetFacts facts) {
    final book = facts.book;
    if (book == null) return;
    final url = book.thumbnail;
    if (url.isEmpty || url == _coverFetched || _fetching) return;

    _fetching = true;
    // Marked fetched up front, so a failure is not retried on every rebuild for the rest of the
    // session. A reader who was offline gets their jacket the next time the book changes or the
    // app restarts, which is the right trade against hammering a dead URL from a `build`.
    _coverFetched = url;
    widget.thumbnail
        .build(url)
        .then((bytes) {
          if (bytes == null) return;
          _channel.writeCover(
            StreakWidgetSnapshot.coverFileName(book.id),
            bytes,
          );
        })
        .whenComplete(() => _fetching = false);
  }
}
