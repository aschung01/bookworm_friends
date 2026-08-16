// Tests for the read view's expanded body: covers grouped by the month they were
// finished in.
//
// Two layers, tested separately. `ReadMonthGrid.group` is a pure regrouping of
// rows the app already has — no query, no new data — so it is a plain unit test.
// The widget on top of it is a widget test, and what it has to prove is narrower
// than it looks: that the numbers it draws are the books it drew.
//
// The invariant worth being blunt about is **no book is dropped**. The sheet's
// header shows a count, each month header shows a count, and the covers are the
// third telling of the same story. A finished book with no `finish_date` has no
// month to sit in, and the tempting fix — leave it out of the grid — makes all
// three disagree. Nobody reports that bug; they just stop trusting the number.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/read_month_grid.dart';

/// Tall enough that every group in the fixtures below is built, so a count of
/// rendered covers is a count of all of them rather than of a viewport.
const _surface = Size(400, 1000);

Book _read(String id, DateTime? finished) => Book(
  id: id,
  userId: 'u',
  shelfId: 's',
  isbn: id,
  title: 'Book $id',
  thumbnail: '',
  // 2 is `bookStatusFinished`, inlined so a pure grouping test does not have to
  // import the provider library that declares it.
  status: 2,
  position: 0,
  finishDate: finished,
  createdAt: DateTime(2024),
);

/// Four groups with four *different* counts, so every count in the rendered
/// headers is unambiguous: March 2026 has 3, February 2026 has 2, November 2025
/// has 1, and 4 are undated.
List<Book> _books() => [
  _read('a', DateTime(2026, 3, 4)),
  _read('b', DateTime(2026, 3, 19)),
  _read('c', DateTime(2026, 3, 28)),
  _read('d', DateTime(2026, 2, 8)),
  _read('e', DateTime(2026, 2, 21)),
  _read('f', DateTime(2025, 11, 2)),
  _read('g', null),
  _read('h', null),
  _read('i', null),
  _read('j', null),
];

Future<void> _pump(WidgetTester tester, List<Book> books) async {
  tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ReadMonthGrid(months: ReadMonthGrid.group(books))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ReadMonthGrid.group', () {
    test('Given books finished across several months, When grouped, Then the '
        'newest month leads and each group holds its own', () {
      final months = ReadMonthGrid.group(_books());

      expect(
        months.map((m) => m.month).toList(),
        [DateTime(2026, 3), DateTime(2026, 2), DateTime(2025, 11), null],
        reason:
            'newest first, which is the order the query already returns — the '
            'grouping must not become a sort',
      );
      expect(months.map((m) => m.books.length).toList(), [3, 2, 1, 4]);
    });

    test(
      'Given a finished book with no finish date, When grouped, Then it lands in '
      'a trailing group rather than being dropped',
      () {
        final months = ReadMonthGrid.group(_books());

        expect(months.last.month, isNull);
        expect(months.last.books.map((b) => b.id).toList(), [
          'g',
          'h',
          'i',
          'j',
        ]);
        expect(
          months.fold<int>(0, (sum, m) => sum + m.books.length),
          _books().length,
          reason: 'every book the header counts must be somewhere in the grid',
        );
      },
    );

    test(
      'Given the same month in different years, When grouped, Then they are two '
      'groups',
      () {
        final months = ReadMonthGrid.group([
          _read('a', DateTime(2026, 3, 4)),
          _read('b', DateTime(2025, 3, 4)),
        ]);

        expect(months.map((m) => m.month).toList(), [
          DateTime(2026, 3),
          DateTime(2025, 3),
        ]);
      },
    );

    test('Given no books, When grouped, Then there are no groups', () {
      expect(ReadMonthGrid.group(const []), isEmpty);
    });

    test(
      'Given only undated books, When grouped, Then the undated group is the '
      'only one',
      () {
        final months = ReadMonthGrid.group([_read('a', null)]);

        expect(months.length, 1);
        expect(months.single.month, isNull);
      },
    );
  });

  group('ReadMonthGrid', () {
    testWidgets(
      'Given grouped books, When rendered, Then each month shows its name and '
      'its own count',
      (tester) async {
        await _pump(tester, _books());

        expect(find.text('March 2026'), findsOneWidget);
        expect(find.text('February 2026'), findsOneWidget);
        expect(find.text('November 2025'), findsOneWidget);
        expect(find.text('No finish date'), findsOneWidget);

        // The fixture gives every group a different count, so these are each
        // exactly one header's number.
        expect(find.text('3'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the counts in the headers, When compared with the covers, Then they '
      'are the same books',
      (tester) async {
        await _pump(tester, _books());

        expect(
          find.byType(BookWidget).evaluate().length,
          _books().length,
          reason:
              'the counts and the covers are two tellings of one list; a book '
              'that has a count but no cover is a silently dropped row',
        );
      },
    );

    testWidgets(
      'Given no read books at all, When rendered, Then the empty state stands in '
      'for the grid',
      (tester) async {
        await _pump(tester, const []);

        expect(find.text('No books read yet 🥲'), findsOneWidget);
        expect(find.byType(BookWidget), findsNothing);
      },
    );

    testWidgets(
      'Given a month of covers, When laid out, Then they are four across at 2:3 '
      'and all the same size',
      (tester) async {
        // The drawings' `.mg`: four columns, portrait covers, uniform. Asserted
        // as a ratio rather than as pixels so it survives a change of gutter.
        //
        // Uniformity is the part worth pinning. `BookWidget` hashes a ±6% height
        // jitter off the ISBN so a shelf reads as physical books, and the first
        // version of this grid inherited it — on device, neighbouring covers in
        // the same row sat at visibly different heights.
        await _pump(tester, [
          for (var i = 0; i < 4; i++) _read('$i', DateTime(2026, 3, 1 + i)),
        ]);

        final rects = find
            .byType(BookWidget)
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)))
            .toList();
        expect(rects.length, 4);

        for (final rect in rects) {
          expect(rect.top, closeTo(rects.first.top, 0.5), reason: 'one row');
          expect(
            rect.height,
            closeTo(rects.first.height, 0.5),
            reason: 'no hashed jitter in a grid of uniform cells',
          );
        }
        expect(
          rects.first.width / rects.first.height,
          closeTo(2 / 3, 0.02),
          reason: 'covers are portrait at the ratio the drawings use',
        );
      },
    );
  });
}
