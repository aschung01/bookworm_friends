// `ShelfDensity.spines` draws every book that is not in progress along its spine,
// and leaves the in-progress ones face-out at the head of the row.
//
// The assertions worth understanding are the two about `slotExtent`. That number is
// measured from the rendered slot and travels to whichever shelf a book is dropped
// on as the width of the gap that shelf must open — so a density whose drawing
// changed on entering edit mode would report a gap for a book it is no longer
// drawing. `spines` is edited *as spines* precisely so that cannot happen, and the
// edit-mode test below is what pins it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/shelf_density_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_spine_tile.dart';

import 'support/home_page_harness.dart';
import 'support/prefs.dart';

/// A shelf with one book in progress and three that are not.
List<Book> _mixedShelf() => [
  testBook('reading', 's1', position: 0, status: bookStatusReading),
  testBook('a', 's1', position: 1, pageCount: 120),
  testBook('b', 's1', position: 2, pageCount: 450),
  testBook('c', 's1', position: 3, pageCount: 880),
];

Future<void> _pump(
  WidgetTester tester, {
  required ShelfDensity density,
  List<Book>? books,
}) async => pumpHome(
  tester,
  shelves: [testShelf('s1', books ?? _mixedShelf(), name: 'Dev')],
  extraOverrides: [
    await sharedPreferencesOverride({'shelf_density': density.name}),
  ],
);

void main() {
  testWidgets(
    'Given the spines density, When the library is shown, Then only the in-progress '
    'book is face-out',
    (tester) async {
      await _pump(tester, density: ShelfDensity.spines);

      // Three spines for the three books that are not in progress.
      expect(find.byType(ShelfSpineTile), findsNWidgets(3));
      // The reading book keeps its cover. `BookWidget` also appears elsewhere in the
      // shell, so scope the count to the shelf's own tiles.
      expect(
        find.descendant(
          of: find.byType(ShelfSpineTile),
          matching: find.byType(BookWidget),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Given the covers density, When the library is shown, Then nothing is a spine',
    (tester) async {
      await _pump(tester, density: ShelfDensity.covers);

      expect(find.byType(ShelfSpineTile), findsNothing);
    },
  );

  testWidgets(
    'Given the spines density, When a spine is drawn, Then its width is its own '
    'thickness and not BookVertical\'s 26pt default',
    (tester) async {
      await _pump(tester, density: ShelfDensity.spines);

      final spines = tester.widgetList<BookVertical>(
        find.descendant(
          of: find.byType(ShelfSpineTile),
          matching: find.byType(BookVertical),
        ),
      );
      expect(spines, hasLength(3));

      // **Derived from the test surface, not from the 29-47pt figure in the design.**
      // That band is for a 390x844 phone; here `bookHeight` is 0.15 of a 600pt-tall
      // view, so the same formula gives a different band. Asserting the phone's
      // numbers would pin the harness's window size rather than the behaviour.
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final base = screen.height * 0.15;
      final lo =
          base *
          BookJitter.minHeightFactor *
          kDefaultCoverAspect *
          BookJitter.minThicknessFactor;
      final hi =
          base *
          BookJitter.maxHeightFactor *
          kDefaultCoverAspect *
          BookJitter.maxThicknessFactor;

      for (final spine in spines) {
        expect(spine.width, greaterThanOrEqualTo(lo));
        expect(spine.width, lessThanOrEqualTo(hi));
        // Not the widget default, which is the mistake this guards against.
        expect(spine.width, isNot(26.0));
      }

      // Thickness follows the page count, so the 880-page book is fatter than the
      // 120-page one. This is the whole reason to use the real metric.
      final widths = spines.map((s) => s.width).toList();
      expect(widths.first, lessThan(widths.last));
    },
  );

  testWidgets(
    'Given the spines density, When a spine is drawn, Then it is measured against '
    'the library ground and not surface',
    (tester) async {
      await _pump(tester, density: ShelfDensity.spines);

      final spine = tester.widget<BookVertical>(
        find
            .descendant(
              of: find.byType(ShelfSpineTile),
              matching: find.byType(BookVertical),
            )
            .first,
      );

      // `#E9ECEF` — `surfaceVariant`, what `LibraryPane` paints. Passing the default
      // `surface` would measure a pale spine's outline against white, which clears
      // the threshold for a fill that has no edge here.
      expect(spine.background, const Color(0xffE9ECEF));
      expect(spine.separator, isTrue);
    },
  );

  testWidgets(
    'Given the spines density, When a spine is as tall as its cover would be, Then '
    'the row reserves enough for it',
    (tester) async {
      await _pump(tester, density: ShelfDensity.spines);

      final spines = tester.widgetList<BookVertical>(
        find.descendant(
          of: find.byType(ShelfSpineTile),
          matching: find.byType(BookVertical),
        ),
      );

      // `bookRowExtent` reserves `maxHeightFactor` of the base, and a spine's height
      // comes from the same `BookJitter` — so no spine can be taller than the row.
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final base = screen.height * 0.15;
      final reserved = bookRowExtent(base);
      for (final spine in spines) {
        expect(spine.height, lessThanOrEqualTo(reserved));
      }
    },
  );

  testWidgets(
    'Given the spines density, When edit mode is entered, Then the books stay '
    'spines',
    (tester) async {
      await _pump(tester, density: ShelfDensity.spines);
      await enterEditMode(tester);

      // The invariant the per-density edit rule exists for: a spine measured at lift
      // is the gap a receiving shelf opens, so the drawing must not change here.
      expect(find.byType(ShelfSpineTile), findsNWidgets(3));
    },
  );

  testWidgets(
    'Given a shelf with nothing in progress, When drawn as spines, Then every book '
    'is a spine',
    (tester) async {
      await _pump(
        tester,
        density: ShelfDensity.spines,
        books: [
          testBook('a', 's1', position: 0),
          testBook('b', 's1', position: 1),
        ],
      );

      expect(find.byType(ShelfSpineTile), findsNWidgets(2));
    },
  );

  testWidgets(
    'Given a shelf where everything is in progress, When drawn as spines, Then '
    'nothing is compressed',
    (tester) async {
      await _pump(
        tester,
        density: ShelfDensity.spines,
        books: [
          testBook('a', 's1', position: 0, status: bookStatusReading),
          testBook('b', 's1', position: 1, status: bookStatusReading),
        ],
      );

      // Correct rather than broken: nothing on the shelf is compressible, so the
      // density has nothing to do and the toggle appears to do nothing here.
      expect(find.byType(ShelfSpineTile), findsNothing);
    },
  );
}
