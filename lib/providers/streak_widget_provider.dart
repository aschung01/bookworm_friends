import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/streak.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';

/// Everything the home-screen widget needs that is not a translated string.
///
/// A record rather than a class because it is assembled in one place and consumed in one place;
/// the copy is added by [StreakWidgetSync], which has a `BuildContext` and therefore an
/// `AppLocalizations` where a provider has neither.
typedef StreakWidgetFacts = ({
  int streak,
  int longestStreak,
  DateTime? lastReadDay,
  Book? book,
});

/// The figures and the book the widget draws, or null while they are still unknown.
///
/// **Null rather than zeros while the fetch is in flight.** Writing a snapshot from an empty map
/// would publish a streak of 0 to the home screen on every cold start, so a reader with twelve
/// days would watch the widget lose them and then get them back. `readTodayProvider` makes the
/// same distinction in returning `false`, and the streak chip gates on `hasValue` for exactly
/// this reason.
///
/// **[streak] is the run ending at [lastReadDay], not the run ending today**, and that is the
/// single most important line in this file. The widget has to stay correct for days after the app
/// last ran: it decides for itself whether that run is still alive by comparing `lastReadDay`
/// against the date it is drawing. Handing it `currentStreakProvider` instead would bake in an
/// answer that expires at the next rollover, and a reader four days lapsed — the reader this
/// whole feature is for — would see a live streak that no longer exists.
final streakWidgetFactsProvider = Provider.autoDispose<StreakWidgetFacts?>((
  ref,
) {
  final days = ref.watch(readingDaysProvider).valueOrNull;
  if (days == null) return null;

  // The most recent recorded day, which anchors everything the widget derives.
  DateTime? lastReadDay;
  for (final day in days.keys) {
    if (lastReadDay == null || day.isAfter(lastReadDay)) lastReadDay = day;
  }

  // `currentReadingRun` counts back from the anchor it is given, so anchoring it on the last
  // recorded day yields the run *ending there* — which is what the widget needs and what
  // `currentStreakProvider` deliberately does not give, since it anchors on today.
  final streak = lastReadDay == null
      ? 0
      : currentReadingRun(days.keys, lastReadDay);

  // The head of the reading shelf. The shelf is reader-ordered, so "the book I am in" is a
  // question the reader has already answered by arranging it — see `readingBooksOf`.
  final reading = ref.watch(readingBooksProvider);

  return (
    streak: streak,
    longestStreak: longestReadingRun(days.keys),
    lastReadDay: lastReadDay,
    book: reading.isEmpty ? null : reading.first,
  );
});
