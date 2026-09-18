// A compressed book takes two taps: one to bring it forward, one to open it.
//
// This is not a convenience. `BookVertical`'s own doc fixes what a spine tap means —
// it "has to match what the chassis renders at a turn of -π/2, because tapping a
// spine swaps one for the other in place" — and the read pile has behaved that way
// since it was built. A shelf spine going straight to the details page would make the
// same drawing mean two different things in one app.
//
// It also does double duty: one book face-out at a time means exactly one delete badge
// in `spines` edit mode, which is what stops a 44pt disc blanketing the spines either
// side of it.
//
// "One at a time" means one in the whole **library**, not one per shelf. It was one per
// shelf at first — `_surfacedBookId` was a field on `_ShelfRowState`, so a library of
// five shelves could stand five covers among its spines. The cross-shelf group below is
// what pins the difference, because every single-shelf test passes either way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/shelf_density_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/turning_book.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_spine_tile.dart';

import 'support/home_page_harness.dart';
import 'support/prefs.dart';

/// Three compressible books.
///
/// **Nothing in progress, and that is a change worth recording.** This fixture used to
/// lead with a `bookStatusReading` book, because `spines` exempted an open book from
/// compression and `enterEditMode` needed a cover to hold. Both premises are gone: an
/// open book is drawn on the Reading shelf rather than on a plank, so a shelf row is all
/// spines in this density, and the harness holds the row's draggable instead of a cover.
List<Shelf> _shelf() => [
  testShelf('s1', [
    testBook('a', 's1', position: 0, title: 'Alpha'),
    testBook('b', 's1', position: 1, title: 'Beta'),
    testBook('c', 's1', position: 2, title: 'Gamma'),
  ]),
];

/// Two shelves, three compressible books each and nothing in progress.
List<Shelf> _twoShelves() => [
  testShelf('s1', [
    testBook('a', 's1', position: 0, title: 'Alpha'),
    testBook('b', 's1', position: 1, title: 'Beta'),
    testBook('c', 's1', position: 2, title: 'Gamma'),
  ], name: 'Dev'),
  testShelf('s2', [
    testBook('d', 's2', position: 0, title: 'Delta'),
    testBook('e', 's2', position: 1, title: 'Epsilon'),
    testBook('f', 's2', position: 2, title: 'Zeta'),
  ], name: 'Fic'),
];

Future<void> _pump(
  WidgetTester tester, {
  required ShelfDensity density,
  List<Shelf>? shelves,
}) async => pumpHome(
  tester,
  shelves: shelves ?? _shelf(),
  extraOverrides: [
    await sharedPreferencesOverride({'shelf_density': density.name}),
  ],
);

/// The spine drawn for the book titled [title].
Finder _spineOf(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ShelfSpineTile));

void main() {
  group('spines', () {
    testWidgets(
      'Given a spine, When it is tapped once, Then it turns out instead of opening '
      'the book',
      (tester) async {
        await _pump(tester, density: ShelfDensity.spines);

        expect(find.byType(TurningBook), findsNothing);

        await tester.tap(_spineOf('Alpha'));
        await tester.pumpAndSettle();

        // Brought forward in place, and nothing was pushed: the details route would
        // have replaced the library.
        expect(find.byType(TurningBook), findsOne);
        expect(find.byType(ShelfSpineTile), findsNWidgets(2));
      },
    );

    testWidgets(
      'Given a book turned out, When its cover is tapped, Then the details route is '
      'pushed',
      (tester) async {
        await _pump(tester, density: ShelfDensity.spines);

        await tester.tap(_spineOf('Alpha'));
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byType(TurningBook),
                matching: find.byType(BookWidget),
              )
              .first,
        );
        await tester.pumpAndSettle();

        // The library is gone, so a route went on top of it.
        expect(find.byType(ShelfSpineTile), findsNothing);
      },
    );

    testWidgets(
      'Given one book turned out, When another spine is tapped, Then only the second '
      'is forward',
      (tester) async {
        await _pump(tester, density: ShelfDensity.spines);

        await tester.tap(_spineOf('Alpha'));
        await tester.pumpAndSettle();
        await tester.tap(_spineOf('Beta'));
        await tester.pumpAndSettle();

        // At most one at a time, as in the pile.
        expect(find.byType(TurningBook), findsOne);
        expect(_spineOf('Alpha'), findsOne);
        expect(_spineOf('Beta'), findsNothing);
      },
    );

    testWidgets(
      'Given the density changes, When the row is redrawn, Then nothing is left '
      'forward',
      (tester) async {
        await _pump(tester, density: ShelfDensity.spines);
        await tester.tap(_spineOf('Alpha'));
        await tester.pumpAndSettle();
        expect(find.byType(TurningBook), findsOne);

        await tester.tap(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.view_week),
          ),
        );
        await tester.pumpAndSettle();

        // A cover left standing among spines it no longer belongs to would be a
        // leftover, not a state.
        expect(find.byType(TurningBook), findsNothing);
      },
    );
  });

  group('one book at a time, across the whole library', () {
    testWidgets(
      'Given a spine forward on one shelf, When a spine on another shelf is tapped, '
      'Then the first goes back to a spine',
      (tester) async {
        await _pump(
          tester,
          density: ShelfDensity.spines,
          shelves: _twoShelves(),
        );

        await tester.tap(_spineOf('Beta'));
        await tester.pumpAndSettle();
        expect(find.byType(TurningBook), findsOne);

        await tester.tap(_spineOf('Epsilon'));
        await tester.pumpAndSettle();

        // **The assertion the per-shelf version failed.** Scoped to no shelf, so two
        // rows each holding their own forward book would show two.
        expect(
          find.byType(TurningBook),
          findsOne,
          reason: 'a cover among spines reads as *the* book being looked at',
        );
        expect(_spineOf('Beta'), findsOne);
        expect(_spineOf('Epsilon'), findsNothing);
      },
    );
  });

  group('reduced motion', () {
    testWidgets(
      'Given animations are disabled, When a spine is tapped, Then it is fully turned '
      'out rather than left as a spine',
      (tester) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        await _pump(tester, density: ShelfDensity.spines);
        await tester.tap(_spineOf('Alpha'));
        await tester.pumpAndSettle();

        // **The turn IS the drawing**: [TurningBook] renders a spine at 0 and a cover
        // at 1. Skipping the animation therefore does not mean leaving the controller
        // alone — that left a reader with Reduce Motion on tapping a spine, getting a
        // spine, and then a details page on the second tap.
        expect(
          tester.widget<TurningBook>(find.byType(TurningBook)).progress.value,
          1,
        );
      },
    );
  });

  group('the delete badge in spine edit mode', () {
    testWidgets('Given spines in edit mode, When no book is forward, Then no spine carries a '
        'badge', (tester) async {
      await _pump(tester, density: ShelfDensity.spines);
      await enterEditMode(tester);

      // A 44pt disc offset 22pt outside a ~37pt spine would blanket the spines
      // either side of it, and in this density they are touching. So no badge exists
      // until a book has been turned out to carry it.
      //
      // There used to be an exception here: a book in progress stood face-out among
      // the spines and kept its badge. That book is on the Reading shelf now, so
      // there is no face-out cover on this row until the reader makes one — and it
      // carries its badge up there instead, on a shelf that has one density and no
      // spines for a disc to blanket.
      expect(find.byKey(const ValueKey('delete_book_a')), findsNothing);
      expect(find.byKey(const ValueKey('delete_book_b')), findsNothing);
      expect(find.byKey(const ValueKey('delete_book_c')), findsNothing);
    });

    testWidgets('Given a book turned out, When edit mode is entered, Then only that book '
        'carries a badge', (tester) async {
      await _pump(tester, density: ShelfDensity.spines);
      await tester.tap(_spineOf('Beta'));
      await tester.pumpAndSettle();
      await enterEditMode(tester);

      // The two-step tap is what makes the badge placeable at all: one book face-out
      // at a time means exactly one badge, so nothing can collide.
      //
      // Surfaced *before* entering edit mode, deliberately, and it is the only order
      // that works: a spine's tap handler is null in edit mode and a cover's is a
      // no-op, so nothing can be turned out once the reader is editing. Which means a
      // `spines` row with nothing forward offers no delete target at all — true
      // before the Reading shelf existed too, for any shelf with no open book on it.
      expect(find.byKey(const ValueKey('delete_book_b')), findsOne);
      expect(find.byKey(const ValueKey('delete_book_a')), findsNothing);
      expect(find.byKey(const ValueKey('delete_book_c')), findsNothing);
    });

    testWidgets(
      'Given covers in edit mode, When the row is drawn, Then every book carries a '
      'badge',
      (tester) async {
        await _pump(tester, density: ShelfDensity.covers);
        await enterEditMode(tester);

        // The rule is confined to `spines`: nothing about today's edit mode changes.
        expect(find.byKey(const ValueKey('delete_book_a')), findsOne);
        expect(find.byKey(const ValueKey('delete_book_b')), findsOne);
        expect(find.byKey(const ValueKey('delete_book_c')), findsOne);
      },
    );
  });

  group('covers is untouched', () {
    testWidgets(
      'Given the covers density, When a cover is tapped once, Then the details route '
      'is pushed',
      (tester) async {
        await _pump(tester, density: ShelfDensity.covers);

        await tester.tap(
          find
              .ancestor(
                of: find.text('Alpha'),
                matching: find.byType(BookWidget),
              )
              .first,
        );
        await tester.pumpAndSettle();

        // One tap, as it always has been. The second tap only exists where a book is
        // compressed — so the library is gone and its other covers with it.
        expect(find.text('Beta'), findsNothing);
      },
    );
  });
}
