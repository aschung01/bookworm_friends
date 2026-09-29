// Recording a reading day from a book's details, and the celebration that follows.
//
// **The gap this closes.** The streak page was the only door that wrote a `reading_days`
// row and the only place the celebration could appear, so the reader most likely to have a
// run going — the one who keeps it by nudging a bookmark on the book in their hand — had
// their run grow silently and never saw the screen built for the moment. Moving the
// bookmark from the band's own door now stamps the night, and both of the details page's
// write paths raise the celebration when a write is what made today count.
//
// **The route changed under this file and the premise did not.** The band used to have a
// second door straight to the percent wheel, and `onProgressSelected` was where the night
// was stamped. The band is one card now: it opens the merged status sheet, the reader moves
// the position there (by dragging the track or through the read-out's own numerals), and
// **Save** is the single writer. So the stamp hangs on `movedPosition` — the position
// changed or was cleared — computed against the book as it was. Same assertion, one door
// further in.
//
// **The rule under test is a transition, never a state.** `readToday` is true for the rest
// of the day once a night is in, so celebrating on the state would raise the screen again on
// every subsequent nudge. What earns it is `false` becoming `true`.

// Cupertino rather than Material: the only framework widget named here is the percent
// wheel's [CupertinoPicker], and importing both makes the Material one unnecessary.
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show LibraryActions;
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_state_line.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_track.dart';
import 'package:bookworm_friends/ui/widgets/reading_period_row.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_celebration.dart';

import 'still_streak_flame.dart';
import 'support/book_details_harness.dart';

/// Serves a fixture and records what was written, instead of reaching Supabase.
class _FakeReadingDays extends ReadingDaysNotifier {
  _FakeReadingDays(this.seed);

  final Set<DateTime> seed;

  /// `(day, read, bookId)` per write, in order.
  static final List<(DateTime, bool, String?)> calls = [];

  @override
  Future<Map<DateTime, String?>> build() async => {
    for (final day in seed) day: null,
  };

  @override
  Future<void> setRead(
    DateTime day, {
    required bool read,
    String? bookId,
  }) async {
    calls.add((day, read, bookId));
    // The real notifier updates its own set before the request goes out, which is what
    // makes the page's figure answer instantly — and is what the transition rule reads
    // back. A fake that only recorded the call would make every case look like "today
    // never became recorded".
    final next = {...?state.valueOrNull};
    if (read) {
      next[day] = bookId;
    } else {
      next.remove(day);
    }
    state = AsyncValue.data(next);
  }
}

/// Swallows the column write. The position is `book_progress`'s business and is covered in
/// `book_progress_test.dart`; what this file is about is the *second* write beside it.
///
/// **The signature is the merged sheet's, and it has to be exact.** `clearProgress` and
/// `fromStatus` are the two parameters that arrived with the merge, and a `Fake` that is
/// missing either is not an override at all — the analyzer says so, which is how this file
/// found out the sheet had grown a way to *erase* a position.
class _FakeActions extends Fake implements LibraryActions {
  @override
  Future<void> updateBookStatus(
    String bookId,
    int status, {
    DateTime? startDate,
    DateTime? finishDate,
    double? progress,
    int? progressPage,
    bool clearProgress = false,
    int? fromStatus,
  }) async {}
}

/// A run of [length] days ending on [endingOn].
Set<DateTime> _run(int length, {required DateTime endingOn}) => {
  for (var back = 0; back < length; back++)
    DateTime(endingOn.year, endingOn.month, endingOn.day - back),
};

/// Opens the band's one door — the period card — and waits for the sheet.
Future<void> _openTheSheet(WidgetTester tester) async {
  await tester.tap(find.byType(ReadingPeriodRow));
  await tester.pumpAndSettle();
  expect(
    find.byType(ReadingTrack),
    findsOneWidget,
    reason: 'the band has one door, and it is the merged status sheet',
  );
}

/// Opens the sheet, drags the track off the position it opened at, and saves.
///
/// **The drag is the move, and the move is what the day-stamp hangs on.** Save computes
/// `movedPosition` against the book as it was, so a Save that changed nothing writes
/// neither the column nor the day — which is the same gate the wheel's `_touched` used to
/// be, one level up. It is also why Save is only *drawn* once the sheet is dirty: the
/// button's arrival is the sheet's whole unsaved-changes model.
///
/// Dragged from inside the thumb row rather than from the widget's centre: the control is
/// 48pt tall and only its top 24 take touches, so a gesture aimed at its centre lands in
/// the gap above the end labels and reaches no recognizer at all — a move that would look
/// like it happened and report nothing.
Future<void> _nudgeTheBookmark(WidgetTester tester) async {
  await _openTheSheet(tester);

  final track = tester.getRect(find.byType(ReadingTrack));
  await tester.dragFrom(
    Offset(track.left + track.width / 2, track.top + 12),
    const Offset(60, 0),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  // The celebration's `Idle` loop never settles, so every case here would hang on a machine
  // that has run `dart run rive_native:setup` and pass on one that has not.
  useStillStreakFlame();

  setUp(_FakeReadingDays.calls.clear);

  Future<void> pump(WidgetTester tester, {required Set<DateTime> days}) async {
    final book = readingBook(ownerId: 'me', progress: 0.2, pageCount: 300);
    await pumpBookDetails(
      tester,
      book: book,
      signedInAs: 'me',
      libraryBooks: [book],
      libraryActions: _FakeActions(),
      extraOverrides: [
        readingDaysProvider.overrideWith(() => _FakeReadingDays(days)),
      ],
    );
  }

  testWidgets('Given today is open, When the bookmark moves, Then the night is '
      'recorded and the celebration follows', (tester) async {
    final today = readingDate(DateTime.now());
    // A run of 11 ending yesterday. Tonight makes 12, which is the figure the celebration
    // must show — read back from the set rather than incremented.
    await pump(
      tester,
      days: _run(
        11,
        endingOn: DateTime(today.year, today.month, today.day - 1),
      ),
    );

    await _nudgeTheBookmark(tester);

    expect(
      _FakeReadingDays.calls,
      [(today, true, 'b1')],
      reason:
          'moving the bookmark is the shortest "I read some of this" in the app',
    );
    expect(find.byType(StreakCelebration), findsOneWidget);
    expect(find.text('12'), findsWidgets);
  });

  testWidgets('Given tonight is already in, When the bookmark moves again, Then '
      'nothing is celebrated twice', (tester) async {
    final today = readingDate(DateTime.now());
    await pump(tester, days: _run(12, endingOn: today));

    await _nudgeTheBookmark(tester);

    // The write still happens — `reading_days` is keyed on `(user_id, day)`, so it is
    // idempotent by construction and re-asserting the row is harmless. What must not
    // happen is the screen.
    expect(_FakeReadingDays.calls, [(today, true, 'b1')]);
    expect(
      find.byType(StreakCelebration),
      findsNothing,
      reason: 'today was already recorded, so tonight is not news',
    );
  });

  testWidgets(
    'Given the sheet is saved with the position untouched, Then no night is stamped',
    (tester) async {
      // The other half of the gate, from this side: agreeing with the position the sheet
      // opened at is not a claim about today.
      //
      // **There are two gates now and this exercises both.** The wheel's own `_touched`
      // still refuses to hand an answer back when the reader confirms a pre-filled value,
      // and above it the sheet only *draws* Save once something differs from what it
      // opened with — so an untouched Confirm leaves no button to press and there is
      // nothing that could write. Asserting the button's absence is asserting the write's.
      await pump(tester, days: const {});

      await _openTheSheet(tester);
      expect(
        find.text('Save'),
        findsNothing,
        reason: 'a sheet that has changed nothing has nothing to save',
      );

      // Through the read-out's percent numeral, which is where the wheel lives now that
      // the band has no second door to it. The book is at 0.2.
      await tester.tap(
        find.descendant(
          of: find.byType(ReadingStateLine),
          matching: find.text('20%'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsNothing);
      expect(_FakeReadingDays.calls, isEmpty);
      expect(find.byType(StreakCelebration), findsNothing);
    },
  );
}
