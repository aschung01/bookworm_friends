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
/// days is over a year of unbroken nightly reading — a state no account in this
/// database is within two years of reaching. The bound exists so the query has one at
/// all; the honest figure is that even a perfect four-year streak is under 1,500 rows,
/// so this could be dropped entirely the day someone gets close.
const int kReadingDaysWindow = 400;

/// The days the signed-in reader has recorded reading on.
///
/// **A set, because the table is set membership.** `reading_days` is keyed on
/// `(user_id, day)`, so a day is either in it or it is not; there is no magnitude and
/// no third state. Every consumer — the chip, the tile, the sheet's checkbox — asks
/// the same question of the same set rather than keeping its own counter, which is why
/// none of them can disagree with another.
///
/// Values are date-only, matching `readingDate`, so they are safe as `Set` keys:
/// `DateTime` equality is equality of instants, and a stray time component would make
/// every lookup miss silently and report a streak of zero to a reader who has one.
final readingDaysProvider =
    AsyncNotifierProvider.autoDispose<ReadingDaysNotifier, Set<DateTime>>(
      ReadingDaysNotifier.new,
    );

class ReadingDaysNotifier extends AutoDisposeAsyncNotifier<Set<DateTime>> {
  @override
  Future<Set<DateTime>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return {};

    final rows = await supabase
        .from('reading_days')
        .select('day')
        .eq('user_id', userId)
        .order('day', ascending: false)
        .limit(kReadingDaysWindow);

    return {
      for (final row in rows)
        // `date` arrives as `yyyy-MM-dd`, which `DateTime.parse` reads as local
        // midnight — the same value `readingDate` produces. Nothing is reformatted
        // in between, so the key a widget holds and the key a row carries are one
        // value. **Not `readingDate` of this**: pushing a midnight through the 4am
        // rollover a second time would move every day in the set back by one.
        DateTime.parse(row['day'] as String),
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
  /// Writes nothing but the day. It does **not** touch the reading position, the
  /// status, `start_date`, `finish_date` or the Reading shelf, and it posts nothing to
  /// the friends feed. That separation is the single rule the whole design rests on.
  Future<void> setRead(
    DateTime day, {
    required bool read,
    String? bookId,
  }) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final previous = state.valueOrNull ?? const <DateTime>{};
    if (previous.contains(day) == read) return;

    final next = {...previous};
    if (read) {
      next.add(day);
    } else {
      next.remove(day);
    }
    state = AsyncData(next);

    try {
      if (read) {
        await supabase.from('reading_days').upsert({
          'user_id': userId,
          'day': _wire(day),
          // What was read that night, which is what turns a tally into a history:
          // the month grid colours each day by the book's `cover_color`. Nullable,
          // and a day with two books has to pick one — the price of the primary key.
          if (bookId != null) 'book_id': bookId,
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
  /// boundary the 4am rollover exists to keep the server out of.
  static String _wire(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// Whether the reader has already recorded today.
///
/// **Its own provider rather than a widget-side `contains`**, because the answer
/// depends on `readingDate(DateTime.now())` and three surfaces ask it. Reading the
/// clock in three places is how they come to disagree across the 4am boundary.
final readTodayProvider = Provider.autoDispose<bool>((ref) {
  final days = ref.watch(readingDaysProvider).valueOrNull;
  if (days == null) return false;
  return days.contains(readingDate(DateTime.now()));
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
  return currentReadingRun(days, readingDate(DateTime.now()));
});

/// The longest run on record, which a missed night does not erase.
final longestStreakProvider = Provider.autoDispose<int>((ref) {
  final days = ref.watch(readingDaysProvider).valueOrNull;
  if (days == null) return 0;
  return longestReadingRun(days);
});
