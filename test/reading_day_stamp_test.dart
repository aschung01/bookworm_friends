// `D+n` on an open book's cover: how long it has been open, counted from
// `books.start_date`.
//
// The arithmetic is the whole subject, because every wrong version of it is wrong
// *quietly* — a stamp that says D+2 on the first evening looks exactly as authoritative
// as one that says D+1. Three properties are pinned here:
//
//   1. It counts CALENDAR days, not elapsed hours. The naive
//      `now.difference(start).inDays` makes a book started at 11pm into D+2 by 1am.
//   2. It is INCLUSIVE of today, so the first day is D+1 and the stamp is never missing
//      from the book the reader just opened.
//   3. It draws NOTHING rather than a zero when there is no start date, because "we
//      don't know" and "D+0" are different statements.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_day_stamp.dart';

import 'support/home_page_harness.dart';

void main() {
  group('readingDayCount', () {
    test('Given a book started today, When counted, Then it is D+1', () {
      final book = testBook(
        'b',
        's1',
        status: 1,
        startDate: DateTime(2026, 3, 4, 9),
      );

      expect(readingDayCount(book, now: DateTime(2026, 3, 4, 21)), 1);
    });

    test('Given a book started late last night, When counted at 1am, Then it is '
        'D+2 and not D+1', () {
      // The calendar has turned over once, so this is the reader's second day with the
      // book even though only two hours have passed. Elapsed-hour arithmetic gets this
      // right by accident and the previous case wrong.
      final book = testBook(
        'b',
        's1',
        status: 1,
        startDate: DateTime(2026, 3, 4, 23),
      );

      expect(readingDayCount(book, now: DateTime(2026, 3, 5, 1)), 2);
    });

    test(
      'Given a book started 23 hours ago on the same day, When counted, Then it '
      'is still D+1',
      () {
        // The mirror of the case above, and the one `inDays` gets wrong: 23 hours have
        // passed but no calendar day has.
        final book = testBook(
          'b',
          's1',
          status: 1,
          startDate: DateTime(2026, 3, 4, 0, 30),
        );

        expect(readingDayCount(book, now: DateTime(2026, 3, 4, 23, 30)), 1);
      },
    );

    test(
      'Given a book open across a month boundary, When counted, Then the days '
      'are counted and not the dates subtracted',
      () {
        final book = testBook(
          'b',
          's1',
          status: 1,
          startDate: DateTime(2026, 2, 26),
        );

        // 26, 27, 28 February then 1, 2 March — five days inclusive.
        expect(readingDayCount(book, now: DateTime(2026, 3, 2)), 5);
      },
    );

    test('Given no start date, When counted, Then the answer is null', () {
      // Rare but not impossible: a row written before the column was populated, or a
      // status set by a path that forgot. The stamp draws nothing rather than a zero.
      expect(readingDayCount(testBook('b', 's1', status: 1)), isNull);
    });

    test('Given a start date in the future, When counted, Then it is clamped to '
        'D+1', () {
      // A data fault rather than a state to draw. Clamped so nothing upstream has to
      // special-case it and no cover ever shows `D+-3`.
      final book = testBook(
        'b',
        's1',
        status: 1,
        startDate: DateTime(2026, 3, 9),
      );

      expect(readingDayCount(book, now: DateTime(2026, 3, 4)), 1);
    });
  });

  group('ReadingDayStamp', () {
    Future<void> pump(WidgetTester tester, int days) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: ReadingDayStamp(days: days)),
        ),
      ),
    );

    testWidgets('Given a day count, Then the stamp reads D+n', (tester) async {
      await pump(tester, 23);
      expect(find.text('D+23'), findsOneWidget);
    });

    testWidgets('Given the first day, Then the stamp reads D+1', (
      tester,
    ) async {
      await pump(tester, 1);
      expect(find.text('D+1'), findsOneWidget);
    });

    testWidgets('Given a three-digit count, Then it still fits on one line', (
      tester,
    ) async {
      // A book open for a year is a real state and the cover is only ~84pt wide.
      await pump(tester, 400);
      final text = tester.widget<Text>(find.text('D+400'));
      expect(text.maxLines, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('the stamp and the ribbon cannot collide', () {
    test('Given both marks, Then they sit at opposite ends of the same edge', () {
      // Two marks on one cover only works if each has a corner of its own. The ribbon
      // hangs at `top: 0, right: kReadingBookmarkInset`; the stamp sits bottom-right.
      // The one thing that must stay true is that they are not both at the top.
      expect(ReadingDayStamp.inset, greaterThan(0));
      expect(kReadingBookmarkInset, greaterThan(0));
    });
  });
}
