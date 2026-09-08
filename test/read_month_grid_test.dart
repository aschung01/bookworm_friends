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
//
// The last group is about the flight to the details page. The grid is the one
// surface that draws every read book at once, so a `book_<isbn>` tag here is the
// one place duplicate and missing ISBNs can put two Heroes on a route under one
// name — an assertion rather than a design problem. See `_flyableIsbns`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/read_month_grid.dart';

/// Tall enough that every group in the fixtures below is built, so a count of
/// rendered covers is a count of all of them rather than of a viewport.
const _surface = Size(400, 1000);

Book _read(
  String id,
  DateTime? finished, {
  String? isbn,
  int? pageCount,
}) => Book(
  id: id,
  userId: 'u',
  shelfId: 's',
  isbn: isbn ?? id,
  title: 'Book $id',
  thumbnail: '',
  // 2 is `bookStatusFinished`, inlined so a pure grouping test does not have to
  // import the provider library that declares it.
  status: 2,
  position: 0,
  pageCount: pageCount,
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

Future<void> _pump(
  WidgetTester tester,
  List<Book> books, {
  int filterYear = 0,
}) async {
  tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ReadMonthGrid(
          months: ReadMonthGrid.group(books),
          filterYear: filterYear,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every hero tag the grid handed its covers, in build order.
List<Object?> _tags(WidgetTester tester) => tester
    .widgetList<BookWidget>(find.byType(BookWidget))
    .map((b) => b.heroTag)
    .toList();

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
      'Given a year filter is selected, When rendered, Then each month header '
      'names the month alone, and the undated header is unaffected',
      (tester) async {
        await _pump(tester, _books(), filterYear: 2026);

        expect(find.text('March'), findsOneWidget);
        expect(find.text('February'), findsOneWidget);
        expect(find.text('November'), findsOneWidget);
        expect(find.text('No finish date'), findsOneWidget);

        expect(find.text('March 2026'), findsNothing);
        expect(find.text('February 2026'), findsNothing);
        expect(find.text('November 2025'), findsNothing);
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
      'Given a year with nothing in it, When rendered, Then the empty state names '
      'the year instead of claiming nothing was ever read',
      (tester) async {
        // The grid is handed the filtered set, so a reader with books only in
        // 2026 looking at 2023 hands it nothing — which is exactly the state the
        // capsules made reachable once they started offering empty years.
        await _pump(tester, const [], filterYear: 2023);

        expect(find.text('No books recorded for 2023'), findsOneWidget);
        expect(
          find.text('No books read yet 🥲'),
          findsNothing,
          reason:
              '"yet" is forward-looking at a year that is already over, and the '
              'reader may have read that year without ever adding the book — '
              'this view can only speak for its own records',
        );
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

  group('the fore-edge', () {
    testWidgets(
      'Given books of different lengths, When rendered, Then each is drawn at its '
      'own thickness and all of them at one height',
      (tester) async {
        // Thickness and height are separable here, and the grid wants opposite
        // answers for them: no height variation, because the cells are uniform and
        // the hashed 6% reads as misalignment; real thickness, because it is only
        // visible edge-on and a held cover in the grid turns far enough to show its
        // fore-edge. A plain `jitter: false` drew every book in the grid at
        // `minThicknessFactor`, including the long ones.
        await _pump(tester, [
          _read('short', DateTime(2026, 3, 4), pageCount: 120),
          _read('long', DateTime(2026, 3, 5), pageCount: 850),
        ]);

        final jitters = tester
            .widgetList<BookWidget>(find.byType(BookWidget))
            .map((b) => b.jitterOverride)
            .toList();

        expect(
          jitters[1]!.thicknessFactor,
          greaterThan(jitters[0]!.thicknessFactor),
          reason: 'an 850-page book has a deeper fore-edge than a 120-page one',
        );
        for (final jitter in jitters) {
          expect(jitter!.heightFactor, BookJitter.neutral.heightFactor);
        }

        // The half that has to hold in the layout: thickness contributes no
        // layout width, so giving it back must not disturb the uniform grid.
        final rects = find
            .byType(BookWidget)
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)))
            .toList();
        expect(rects[1].size, rects[0].size);
      },
    );
  });

  group('the flight to the details page', () {
    testWidgets(
      'Given read books with ISBNs of their own, When rendered, Then every cover '
      'carries the tag the details header answers to',
      (tester) async {
        // The pile's tag, on the grid's covers: `book_<isbn>` is what the details
        // header is tagged with, and a tag that stops matching fails *silently* —
        // the cover simply does not move, which is the state this replaced.
        await _pump(tester, _books());

        expect(_tags(tester), _books().map((b) => 'book_${b.isbn}').toList());
      },
    );

    testWidgets(
      'Given one ISBN finished twice, When rendered, Then neither copy carries a '
      'tag and every other book keeps one',
      (tester) async {
        // A reread, or two rows for one title. Both copies are on screen at once
        // here — unlike the pile, which only ever tags the book it has turned out —
        // so one tag would have two sources on the route.
        await _pump(tester, [
          _read('a', DateTime(2026, 3, 4), isbn: 'dup'),
          _read('b', DateTime(2025, 8, 9), isbn: 'dup'),
          _read('c', DateTime(2025, 8, 11), isbn: 'own'),
        ]);

        expect(
          _tags(tester),
          [null, null, 'book_own'],
          reason:
              'tagging the first copy would fly a cover from a cell the finger '
              'never touched, so both give the flight up rather than one lying',
        );
      },
    );

    testWidgets(
      'Given read books with no ISBN, When rendered, Then they carry no tag',
      (tester) async {
        // `book_` for every one of them. 15 of the migrated rows have no ISBN, so
        // this is the likeliest way to get a grid of identical tags.
        await _pump(tester, [
          _read('a', DateTime(2026, 3, 4), isbn: ''),
          _read('b', DateTime(2026, 3, 5), isbn: ''),
        ]);

        expect(_tags(tester), [null, null]);
      },
    );

    testWidgets(
      'Given a grid whose ISBNs repeat, When a route is pushed, Then nothing '
      'collides',
      (tester) async {
        // The assertion this guards — at most one Hero per tag on a route — is only
        // reached when a flight is *collected*, which is a route push. So the tags
        // being right is not the same claim as the flight being legal, and this is
        // the half that would throw.
        final books = [
          _read('a', DateTime(2026, 3, 4), isbn: 'dup'),
          _read('b', DateTime(2026, 3, 5), isbn: 'dup'),
          _read('c', DateTime(2026, 3, 6), isbn: 'own'),
        ];
        tester.view.physicalSize = _surface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          // The details header, standing in for the page: one
                          // Hero, tagged the way that page tags it.
                          builder: (_) => const Scaffold(
                            body: BookWidget(
                              height: 180,
                              imageUrl: '',
                              isbn: 'own',
                              title: 'Book c',
                              heroTag: 'book_own',
                            ),
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                  Expanded(
                    child: ReadMonthGrid(months: ReadMonthGrid.group(books)),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Mid-flight is where the collection happens, so this is the assertion
        // that matters. Not a count of books: both ends of a flight keep their
        // `BookWidget` element and render a placeholder inside it, so the tag is
        // on two widgets throughout and only one of them is in the air.
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
