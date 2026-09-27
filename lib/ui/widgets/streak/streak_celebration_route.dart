import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/models/streak.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_celebration.dart';

/// Raises [StreakCelebration] over whatever is on screen, and returns when it is done.
///
/// **One presenter, because there are now two doors.** The celebration used to be a
/// `Positioned.fill` inside `ReadingStreakPage`'s own `Stack`, driven by two fields of that
/// page's state — which was correct while recording a night was something only that page
/// could do. It is not any more: moving a bookmark from a book's details records the night
/// too, and a reader who does that deserves the same screen. The alternatives were to
/// duplicate the overlay in `book_details_tab_view.dart`, or to hoist it into the shell and
/// give two screens a flag to raise it. Both end with one object drawn by two call sites,
/// which is the defect this feature has already been dragged through twice — see the flame
/// icon and the chip's hue in `AGENTS.md`.
///
/// **It reads the figures itself rather than taking them.** `ReadingStreakPage` used to
/// compute `streak` and `best` and pass them in, with a comment saying it did so to stay
/// "the single place that queries this feature". That reason inverts once there are two
/// callers: the query belongs wherever the celebration is raised from, and here it is
/// written once. Read rather than watched, and *after* the write — the run is arithmetic
/// over the day set, so there is no counter here that can drift from it.
///
/// **An opaque route rather than an overlay**, so the celebration is a place the reader can
/// be rather than a layer on top of a page that is still there underneath. That also makes
/// the back gesture and `onDone` the same exit, and it is what lets a book's details raise
/// it without the details page knowing anything about it. No transition: the celebration
/// opens on its own ignition beat, and a route slide in front of that is two animations
/// competing to be the arrival.
///
/// **`rootNavigator`**, because the streak page is pushed on the root table and a book's
/// details can sit inside a sheet. A celebration inside a sheet's navigator would be
/// clipped to the sheet.
Future<void> showStreakCelebration(BuildContext context, WidgetRef ref) {
  final today = readingDate(DateTime.now());
  final days = ref.read(readingDaysProvider).valueOrNull ?? const {};
  final keys = days.keys.toSet();

  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          StreakCelebration(
            streak: currentReadingRun(keys, today),
            best: longestReadingRun(keys),
            week: readingWeekEndingOn(keys, today),
            today: today,
            onDone: () => Navigator.of(routeContext).pop(),
          ),
    ),
  );
}
