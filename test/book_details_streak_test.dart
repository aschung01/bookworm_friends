// Recording a reading day from a book's details, and the celebration that follows.
//
// **The gap this closes.** The streak page was the only door that wrote a `reading_days`
// row and the only place the celebration could appear, so the reader most likely to have a
// run going — the one who keeps it by nudging a bookmark on the book in their hand — had
// their run grow silently and never saw the screen built for the moment. The band's percent
// wheel now stamps the night, and both of the details page's write paths raise the
// celebration when a write is what made today count.
//
// **The rule under test is a transition, never a state.** `readToday` is true for the rest
// of the day once a night is in, so celebrating on the state would raise the screen again on
// every subsequent nudge. What earns it is `false` becoming `true`.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show LibraryActions;
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/ui/widgets/band_progress_row.dart';
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
class _FakeActions extends Fake implements LibraryActions {
  @override
  Future<void> updateBookStatus(
    String bookId,
    int status, {
    DateTime? startDate,
    DateTime? finishDate,
    double? progress,
    int? progressPage,
  }) async {}
}

/// A run of [length] days ending on [endingOn].
Set<DateTime> _run(int length, {required DateTime endingOn}) => {
  for (var back = 0; back < length; back++)
    DateTime(endingOn.year, endingOn.month, endingOn.day - back),
};

/// Opens the band's wheel, moves it off the value it opened at, and confirms.
///
/// The move matters: `onProgressSelected` is gated on the sheet's own `_touched`, so
/// confirming a pre-filled position writes neither the column nor the day. That gate is
/// also what makes stamping a night here defensible — the callback firing *is* the reader
/// saying where they now are.
Future<void> _nudgeTheBookmark(WidgetTester tester) async {
  await tester.tap(find.byType(BandProgressRow));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(CupertinoPicker), const Offset(0, -120));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm'));
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
      reason: 'the wheel is the shortest "I read some of this" in the app',
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
    'Given the wheel is confirmed untouched, Then no night is stamped',
    (tester) async {
      // The other half of the `_touched` gate, from this side: agreeing with the position
      // the sheet opened at is not a claim about today.
      await pump(tester, days: const {});

      await tester.tap(find.byType(BandProgressRow));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(_FakeReadingDays.calls, isEmpty);
      expect(find.byType(StreakCelebration), findsNothing);
    },
  );
}
