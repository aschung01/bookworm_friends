// `ShelfDensity.leaning` shingles every book that is not in progress, leaning right
// so the leftmost is frontmost.
//
// Two of these tests pin decisions rather than behaviour, and both would look like
// tidy-up candidates to someone who did not know why they are there:
//
//   - the `Stack`'s children are emitted in REVERSE index order, which is the only
//     way to get left-on-top out of a painter that draws in child order;
//   - each slot is the exposed STRIP wide, not a whole cover, because a RenderBox
//     hit-tests its full rect and the frontmost book would otherwise steal taps
//     meant for the books it overlaps.
//
// The last group is the measurement the design gated this state on: a `Stack` has no
// laziness, so it builds a tile per book where the list built about four.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/shelf_density_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_lean_metrics.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart';

import 'support/home_page_harness.dart';
import 'support/prefs.dart';

List<Book> _shelfOf(int count, {int reading = 0}) => [
  for (var i = 0; i < count; i++)
    testBook(
      'b$i',
      's1',
      position: i,
      title: 'Book $i',
      status: i < reading ? bookStatusReading : 0,
    ),
];

Future<void> _pump(
  WidgetTester tester, {
  required ShelfDensity density,
  required List<Book> books,
}) async => pumpHome(
  tester,
  shelves: [testShelf('s1', books, name: 'Dev')],
  extraOverrides: [
    await sharedPreferencesOverride({'shelf_density': density.name}),
  ],
);

/// The shelf's base book height, as the row computes it.
double _base(WidgetTester tester) =>
    (tester.view.physicalSize / tester.view.devicePixelRatio).height * 0.15;

void main() {
  group('the cascade', () {
    testWidgets(
      'Given the leaning density, When the row is drawn, Then the shingled books are '
      'emitted in reverse so the leading one is on top',
      (tester) async {
        await _pump(tester, density: ShelfDensity.leaning, books: _shelfOf(4));

        // Paint order is child order, so the LAST child painted is on top. Reversed
        // emission means child order runs b3, b2, b1, b0 — and b0 ends up in front.
        final titles = tester
            .widgetList<BookWidget>(find.byType(BookWidget))
            .map((w) => w.title)
            .where((t) => t.startsWith('Book '))
            .toList();

        expect(
          titles,
          ['Book 3', 'Book 2', 'Book 1', 'Book 0'],
          reason:
              'the cascade must be emitted highest-index-first, or the rightmost '
              'book paints in front and the emphasis lands at the wrong end',
        );
      },
    );

    testWidgets(
      'Given the leaning density, When a book is positioned, Then it sits one step '
      'along from the one in front of it',
      (tester) async {
        await _pump(tester, density: ShelfDensity.leaning, books: _shelfOf(4));

        final step = _base(tester) * kShelfLeanStep;
        final x0 = tester.getTopLeft(_coverOf('Book 0')).dx;
        final x1 = tester.getTopLeft(_coverOf('Book 1')).dx;
        final x2 = tester.getTopLeft(_coverOf('Book 2')).dx;

        expect(x1 - x0, closeTo(step, 0.5));
        expect(x2 - x1, closeTo(step, 0.5));
      },
    );

    testWidgets(
      'Given the leaning density, When a book is not the last, Then its hit area is '
      'only the strip it shows',
      (tester) async {
        await _pump(tester, density: ShelfDensity.leaning, books: _shelfOf(4));

        // The decision this pins: were the slot a full cover wide, book 0 — hit-tested
        // first because it is frontmost — would swallow taps landing on books 1..3.
        final step = _base(tester) * kShelfLeanStep;
        final slot = tester.getSize(_slotOf('Book 0'));

        expect(slot.width, closeTo(step, 0.5));
      },
    );

    testWidgets(
      'Given the leaning density, When the last book is drawn, Then all of it is '
      'tappable',
      (tester) async {
        await _pump(tester, density: ShelfDensity.leaning, books: _shelfOf(4));

        // Nothing overlaps it, so the strip rule does not apply to it.
        final slot = tester.getSize(_slotOf('Book 3'));

        expect(slot.width, closeTo(_base(tester) * kDefaultCoverAspect, 0.5));
      },
    );
  });

  group('the reading head', () {
    testWidgets(
      'Given a book in progress, When the row is drawn, Then it stands face-out '
      'before the cascade',
      (tester) async {
        await _pump(
          tester,
          density: ShelfDensity.leaning,
          books: _shelfOf(4, reading: 1),
        );

        // Book 0 is in progress, so it leads at full width and the cascade starts
        // after it.
        final readingWidth = tester.getSize(_coverOf('Book 0')).width;
        final shingledWidth = tester.getSize(_coverOf('Book 1')).width;

        // Both draw a whole cover; what differs is the room they are given. The
        // reading book's own slot is not clipped by a neighbour leaning over it.
        expect(readingWidth, closeTo(shingledWidth, 1));
        expect(
          tester.getTopLeft(_coverOf('Book 0')).dx,
          lessThan(tester.getTopLeft(_coverOf('Book 1')).dx),
        );
      },
    );

    testWidgets(
      'Given every book is in progress, When drawn as leaning, Then nothing is '
      'compressed',
      (tester) async {
        await _pump(
          tester,
          density: ShelfDensity.leaning,
          books: _shelfOf(3, reading: 3),
        );

        // Correct rather than broken: with no compressible books the density has
        // nothing to do, so the row is laid out rather than positioned. Scoped to the
        // shelf, because the shell draws `OverflowBox`es of its own.
        expect(
          find.descendant(
            of: find.byType(ShelfRow),
            matching: find.byType(OverflowBox),
          ),
          findsNothing,
        );
      },
    );
  });

  group('arithmetic', () {
    test(
      'Given a step of 0.16, When applied to a 126.6pt base, Then it is 20.3pt',
      () {
        expect(126.6 * kShelfLeanStep, closeTo(20.3, 0.05));
      },
    );

    test(
      'Given a group of books, When measured, Then only the last draws in full',
      () {
        // 84.4 for the last cover plus a step for each book in front of it — which is
        // what makes the design's ~13.6 and ~9.7 figures come out.
        const base = 126.6;
        final width = shelfLeanGroupWidth(13, base);
        expect(
          width,
          closeTo(
            12 * base * kShelfLeanStep + base * kDefaultCoverAspect,
            0.01,
          ),
        );
        // Thirteen books with nothing in progress just fit the 340.5pt usable row.
        expect(width, lessThan(341));
      },
    );

    test('Given an empty group, When measured, Then it is zero wide', () {
      expect(shelfLeanGroupWidth(0, 126.6), 0);
    });

    test('Given one book, When measured, Then it is one cover wide', () {
      expect(
        shelfLeanGroupWidth(1, 126.6),
        closeTo(126.6 * kDefaultCoverAspect, 0.01),
      );
    });
  });

  group('the build cost the design gated this state on', () {
    testWidgets(
      'Given a sixty-book shelf, When drawn as covers, Then only a handful of tiles '
      'are built',
      (tester) async {
        await _pump(tester, density: ShelfDensity.covers, books: _shelfOf(60));

        final built = tester
            .widgetList<BookWidget>(find.byType(BookWidget))
            .where((w) => w.title.startsWith('Book '))
            .length;

        // A lazy list builds the viewport and a little either side.
        expect(built, lessThan(15), reason: 'covers built $built of 60');
        debugPrint('covers, 60 books: $built tiles built');
      },
    );

    testWidgets(
      'Given a sixty-book shelf, When drawn as leaning, Then every tile is built',
      (tester) async {
        await _pump(tester, density: ShelfDensity.leaning, books: _shelfOf(60));

        final built = tester
            .widgetList<BookWidget>(find.byType(BookWidget))
            .where((w) => w.title.startsWith('Book '))
            .length;

        // **This is the cost, measured rather than argued about.** A `Stack` has no
        // laziness, so a sixty-book shelf builds sixty tiles. Accepted knowingly: the
        // density exists for shelves that fit, and a shelf that fits would have built
        // all of its tiles anyway. Recorded here so a future reader can see the
        // number rather than rediscover it.
        expect(built, 60, reason: 'leaning built $built of 60');
        debugPrint('leaning, 60 books: $built tiles built');
      },
    );
  });
}

Finder _coverOf(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(BookWidget));

/// The slot a shingled book occupies — its hit area, which is deliberately narrower
/// than the cover it draws. Scoped to the shelf, because the shell has
/// `OverflowBox`es of its own.
Finder _slotOf(String title) => find
    .ancestor(
      of: _coverOf(title),
      matching: find.descendant(
        of: find.byType(ShelfRow),
        matching: find.byType(OverflowBox),
      ),
    )
    .first;
