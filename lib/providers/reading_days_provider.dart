import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/models/streak.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/services/notification_service.dart'
    show navigatorKey;

/// How many trailing rows the streak is derived from.
///
/// **A ceiling, not a page.** A run longer than this would be under-reported, and 400
/// days is over a year of unbroken daily reading — a state no account in this
/// database is within two years of reaching. The bound exists so the query has one at
/// all; the honest figure is that even a perfect four-year streak is under 1,500 rows,
/// so this could be dropped entirely the day someone gets close.
const int kReadingDaysWindow = 400;

/// The days the signed-in reader has recorded reading on, and what they read.
///
/// **A map, because the table is set membership with one attribute.** `reading_days` is
/// keyed on `(user_id, day)`, so a day is either in it or it is not; there is no
/// magnitude and no third state. What the day *carries* is a nullable `book_id`, and that
/// is what turns a tally into a history: the month grid draws each recorded day in its
/// book's `cover_color`. Every consumer — the chip, the tile, the sheet's checkbox, the
/// streak page's month — asks the same question of the same map rather than keeping its
/// own counter, which is why none of them can disagree with another.
///
/// **It was a `Set<DateTime>` and the book is why it is not.** Reading the column in a
/// second provider would have meant two queries against one table and two answers that
/// can disagree about a day that was just written; membership and attribution arrive
/// together or the grid colours a day the chip has not counted. Keys are what membership
/// is asked of, so `containsKey` is the same test the `Set` answered and
/// [currentReadingRun] takes the keys directly.
///
/// Keys are date-only, matching `readingDate`, so they are safe as map keys:
/// `DateTime` equality is equality of instants, and a stray time component would make
/// every lookup miss silently and report a streak of zero to a reader who has one.
final readingDaysProvider =
    AsyncNotifierProvider.autoDispose<
      ReadingDaysNotifier,
      Map<DateTime, String?>
    >(ReadingDaysNotifier.new);

class ReadingDaysNotifier
    extends AutoDisposeAsyncNotifier<Map<DateTime, String?>> {
  @override
  Future<Map<DateTime, String?>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return {};

    final rows = await supabase
        .from('reading_days')
        .select('day, book_id')
        .eq('user_id', userId)
        .order('day', ascending: false)
        .limit(kReadingDaysWindow);

    return {
      for (final row in rows)
        // `date` arrives as `yyyy-MM-dd`, which `DateTime.parse` reads as local
        // midnight — the same value `readingDate` produces. Nothing is reformatted
        // in between, so the key a widget holds and the key a row carries are one
        // value. **Not `readingDate` of this**: these values are already reading
        // dates, and relying on today's midnight rollover to make a second pass a
        // no-op is not a bet this file should make — it was not a no-op when the
        // rollover was 4.
        DateTime.parse(row['day'] as String): row['book_id'] as String?,
    };
  }

  /// Records that the reader read on [day], or removes that record.
  ///
  /// **Optimistic, and the primary key is what makes that safe.** The set is updated
  /// before the request goes out, so the checkbox and the chip answer instantly; the
  /// write is an UPSERT on `(user_id, day)`, so a double tap, a retry, and a replayed
  /// request all produce the same one row. There is nothing to increment and therefore
  /// nothing to get out of step.
  ///
  /// **A durable offline queue is deferred, not forgotten.** This reverts and reports
  /// on failure rather than persisting the intent across a restart, because the app has
  /// no queue infrastructure to put it in and inventing one for a checkbox would be the
  /// tail wagging the dog. The table is already shaped for it: when a queue arrives it
  /// can replay its whole backlog twice with no reconciliation, which is the property
  /// `(user_id, day)` was chosen for in the first place.
  ///
  /// Writes nothing but the day and what was read on it. It does **not** touch the
  /// reading position, the status, `start_date`, `finish_date` or the Reading shelf, and
  /// it posts nothing to the friends feed. That separation is the single rule the whole
  /// design rests on — and it survives the streak page's mandatory wheel, which writes
  /// the position through `books` in a second call rather than smuggling it through this
  /// one.
  ///
  /// **Re-stamping a day with a different book is a real edit, not a no-op.** The early
  /// return used to fire on membership alone, which was right while nothing but a
  /// checkbox called this; now that recording a day names a book, a reader who records
  /// today against the wrong book and comes back has to be able to correct it. So the
  /// guard compares the attribution too, and only a write that would change nothing is
  /// dropped.
  Future<void> setRead(
    DateTime day, {
    required bool read,
    String? bookId,
  }) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final previous = state.valueOrNull ?? const <DateTime, String?>{};
    final had = previous.containsKey(day);
    if (had == read && (!read || previous[day] == bookId)) return;

    final next = {...previous};
    if (read) {
      next[day] = bookId;
    } else {
      next.remove(day);
    }
    state = AsyncData(next);

    try {
      if (read) {
        await supabase.from('reading_days').upsert({
          'user_id': userId,
          'day': _wire(day),
          // What was read that day, which is what turns a tally into a history:
          // the month grid colours each day by the book's `cover_color`. Nullable,
          // and a day with two books has to pick one — the price of the primary key.
          //
          // **Sent even when null**, unlike the first cut, which omitted the key. An
          // omitted key leaves the stored value alone on an UPSERT that lands on an
          // existing row, so a day stamped against a book could never be corrected
          // back to "no book" — and the local map above would then claim an
          // attribution the row still disagrees with.
          'book_id': bookId,
        }, onConflict: 'user_id,day');
      } else {
        await supabase
            .from('reading_days')
            .delete()
            .eq('user_id', userId)
            .eq('day', _wire(day));
      }
    } catch (_) {
      // Put the set back. The reader is looking at the control they just used, so a
      // checkbox that stayed ticked over a row that was never written is worse than
      // one that visibly springs back.
      state = AsyncData(previous);
      final context = navigatorKey.currentContext;
      if (context != null) {
        EasyLoading.showError(AppLocalizations.of(context).readTodayFailed);
      }
    }
  }

  /// `yyyy-MM-dd`, formatted by hand rather than through `DateFormat`.
  ///
  /// The value is already a date-only local midnight, so there is nothing to format
  /// *away* — and `toIso8601String` would send a time component and a `Z` for a
  /// Postgres `date` column to discard, which invites a timezone conversion at the
  /// boundary the midnight rollover exists to keep the server out of.
  static String _wire(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// Whether the reader has already recorded today.
///
/// **Its own provider rather than a widget-side `contains`**, because the answer
/// depends on `readingDate(DateTime.now())` and three surfaces ask it. Reading the
/// clock in three places is how they come to disagree across the midnight boundary.
final readTodayProvider = Provider.autoDispose<bool>((ref) {
  final days = ref.watch(readingDaysProvider).valueOrNull;
  if (days == null) return false;
  return days.containsKey(readingDate(DateTime.now()));
});

/// The run that is still alive, or 0.
///
/// Derived on read, never stored. A run ending *yesterday* still counts: today being
/// unstamped means the day is open, not that the streak is broken, and collapsing
/// those two would make every streak in the app read 0 each morning and jump back at
/// bedtime.
final currentStreakProvider = Provider.autoDispose<int>((ref) {
  final days = ref.watch(readingDaysProvider).valueOrNull;
  if (days == null) return 0;
  // `readingDate` applied here and nowhere downstream — `currentReadingRun`
  // deliberately does not re-apply the rollover, because doing it twice shifts every
  // day back by one.
  return currentReadingRun(days.keys, readingDate(DateTime.now()));
});

/// The longest run on record, which a missed day does not erase.
final longestStreakProvider = Provider.autoDispose<int>((ref) {
  final days = ref.watch(readingDaysProvider).valueOrNull;
  if (days == null) return 0;
  return longestReadingRun(days.keys);
});

/// How far through the reading day the reader is: recorded, open, or open and late.
///
/// **Derived, with no clock of its own — and that is a correction worth recording.** The first
/// cut scheduled a `Timer` to [nextReadingPhaseBoundary] in here and invalidated itself when it
/// fired, which reads well and is wrong: a provider that spawns a timer is a provider every
/// widget test has to know about. `testWidgets` fails a test that ends with a timer pending, and
/// a `ProviderContainer` disposed in a tear-down is torn down *after* that check runs — so
/// seventeen existing cases on the streak page broke at once, none of them about the clock.
///
/// **So `MyApp` owns the clock and this owns the answer.** The shell schedules one timer to the
/// next boundary and invalidates this provider when it fires, and also on resume, because a
/// suspended app's timers do not fire on schedule — a reader who backgrounds the app at 20:55
/// and returns at 22:10 would otherwise see a phase computed on the wrong side of the boundary.
/// That split leaves this provider a pure function of the map and the current moment, which is
/// what every other value in this file already is.
///
/// While the fetch is in flight the days are unknown, and this answers `open` or `openLate` from
/// the clock alone — the same choice `readTodayProvider` makes in returning `false`. It is safe
/// for the same reason: the surfaces that draw a phase are the ones that already gate on
/// `hasValue`, so nothing paints a guess.
final readingDayPhaseProvider = Provider.autoDispose<ReadingDayPhase>((ref) {
  final days = ref.watch(readingDaysProvider).valueOrNull;
  return readingDayPhase(DateTime.now(), days?.keys ?? const <DateTime>[]);
});
