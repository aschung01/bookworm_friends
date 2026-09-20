// A compressed book takes two taps: one to bring it forward, one to open it.
//
// This is not a convenience. `BookVertical`'s own doc fixes what a spine tap means —
// it "has to match what the chassis renders at a turn of -π/2, because tapping a
// spine swaps one for the other in place" — and the read pile has behaved that way
// since it was built. A shelf spine going straight to the details page would make the
// same drawing mean two different things in one app.
//
// It also does double duty: one book face-out at a time means exactly one *face-out*
// delete badge in `spines` edit mode. The spines carry their own, centred on their heads
// and sized to them, and they do not wobble while they do — see `ShelfSpineTile` and the
// badge group below, which records both reversals.
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
import 'package:bookworm_friends/ui/widgets/wiggle.dart';

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
    testWidgets('Given spines in edit mode, When no book is forward, Then every spine '
        'carries its own badge and none of them moves', (tester) async {
      await _pump(tester, density: ShelfDensity.spines);
      await enterEditMode(tester);

      // **Inverted, and the note it replaces was right about the wrong thing.** This
      // pinned `findsNothing` for all three, reasoning that "a 44pt disc offset 22pt
      // outside a ~37pt spine would blanket the spines either side of it". True of that
      // offset — and not an argument for a row with no delete target at all, which is
      // what this was: every spine here is a `LongPressDraggable` that can be reordered
      // or sent to another shelf, so a reader who entered edit mode without first
      // turning a book out had nothing to tap and no way to make anything to tap, because
      // a spine's tap handler is null while editing. The disc is centred on the spine's
      // head now and sized to it; see `ShelfSpineTile`.
      for (final id in const ['a', 'b', 'c']) {
        expect(find.byKey(ValueKey('delete_book_$id')), findsOne);
      }

      final spines = tester.widgetList<ShelfSpineTile>(
        find.byType(ShelfSpineTile),
      );
      expect(spines, hasLength(3));
      expect(spines.every((tile) => tile.isEditMode), isTrue);

      // **And they hold still, which is a second reversal on this group.** The badge
      // arrived with a `Wiggle` around it, matching a cover on a plank, and the wobble was
      // taken back out on a report of it causing dizziness. `ShelfSpineTile` records why
      // this row is the worst case rather than an average one; what is pinned here is
      // simply that no spine is inside a running one, because the tile is where a future
      // "make it consistent with covers" change would put it back.
      expect(
        find.descendant(
          of: find.byType(ShelfSpineTile),
          matching: find.byType(Wiggle),
        ),
        findsNothing,
      );
    });

    testWidgets('Given spines in edit mode, Then the row reaches a resting frame', (
      tester,
    ) async {
      await _pump(tester, density: ShelfDensity.spines);
      await enterEditMode(tester);

      // The observable consequence of the stillness, and the reason it is worth a case
      // of its own: `pumpAndSettle` is unusable across most of this app's edit mode
      // because `Wiggle` repeats forever, and several test files carry a note saying so.
      // A compressed row has nothing repeating, so it settles — and if that ever stops
      // being true, something on this row has started animating without meaning to.
      await tester.pumpAndSettle();

      for (final id in const ['a', 'b', 'c']) {
        expect(find.byKey(ValueKey('delete_book_$id')), findsOne);
      }
    });

    testWidgets('Given spines in edit mode, Then no badge is wider than the spine it '
        'belongs to', (tester) async {
      await _pump(tester, density: ShelfDensity.spines);
      await enterEditMode(tester);

      // **This is the assertion that makes a badge per spine safe, so it is the one to
      // keep if the group is ever cut down.** Spines touch. A badge given the usual 44pt
      // of width would reach 7–15pt into each neighbour — past the left edge of the
      // neighbour's own disc — and slots are painted in row order, so that sliver goes
      // to whichever badge paints later. Aiming squarely at a disc would sometimes open
      // the confirm sheet for the book beside it, and nothing on screen would say so.
      //
      // Nothing on this row moves, so these can be exact. Elsewhere in the app the same
      // assertion needs a tolerance — see `library_delete_book_test`, where `Wiggle` takes
      // a random phase per cover and drifts a global position a couple of points between
      // runs. A tolerance creeping back in here means something has started animating.
      for (final (id, title) in const [
        ('a', 'Alpha'),
        ('b', 'Beta'),
        ('c', 'Gamma'),
      ]) {
        final spine = _spineOf(title);
        final badge = find.descendant(
          of: spine,
          matching: find.byKey(ValueKey('delete_book_$id')),
        );

        expect(badge, findsOne, reason: '$title carries no badge');
        expect(
          tester.getSize(badge).width,
          tester.getSize(spine).width,
          reason: "$title's badge is not its spine's width",
        );
        // The height is left alone: 44pt is still the reach, and there is no
        // neighbour above or below to take it from.
        expect(tester.getSize(badge).height, 44);
        expect(
          tester.getCenter(badge).dx,
          tester.getCenter(spine).dx,
          reason: "$title's disc is not centred over its own spine",
        );
      }
    });

    testWidgets(
      'Given spines in edit mode, When a spine badge is tapped, Then deletion is '
      'confirmed first',
      (tester) async {
        await _pump(tester, density: ShelfDensity.spines);
        await enterEditMode(tester);

        // Off-centre by 6pt for the reason `library_delete_book_test` does the same: the
        // row's own gesture arena sits under the middle of the badge.
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('delete_book_c'))) +
              const Offset(6, 6),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Delete this?'), findsOne);
      },
    );

    testWidgets(
      'Given spines in edit mode, Then each badge names the book it stands over',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await _pump(tester, density: ShelfDensity.spines);
          await enterEditMode(tester);

          // The other half of the targeting claim above: a disc wholly over one spine is
          // only an improvement if it is that spine's own badge. The sheet does not name
          // the book, so the label is the only place a mis-wiring would show.
          for (final (id, title) in const [
            ('a', 'Alpha'),
            ('b', 'Beta'),
            ('c', 'Gamma'),
          ]) {
            expect(
              tester.getSemantics(find.byKey(ValueKey('delete_book_$id'))),
              matchesSemantics(
                label: 'Delete $title',
                isButton: true,
                hasTapAction: true,
              ),
            );
          }
        } finally {
          // `finally` rather than `addTearDown`: the handle has to be gone before the
          // framework's end-of-test verification runs, and a tear-down is later than
          // that.
          semantics.dispose();
        }
      },
    );

    testWidgets('Given a book turned out, When edit mode is entered, Then it carries a '
        'badge centred on its cover and stays put', (tester) async {
      await _pump(tester, density: ShelfDensity.spines);
      await tester.tap(_spineOf('Beta'));
      await tester.pumpAndSettle();
      await enterEditMode(tester);

      // A turned-out book is drawn by [TurningBook] rather than by a spine tile, so its
      // badge is mounted by the row. All three are reachable either way — what the
      // two-step tap decides now is the *placement*, not whether a badge exists.
      for (final id in const ['a', 'b', 'c']) {
        expect(find.byKey(ValueKey('delete_book_$id')), findsOne);
      }
      expect(
        find.descendant(
          of: find.byType(ShelfSpineTile),
          matching: find.byKey(const ValueKey('delete_book_b')),
        ),
        findsNothing,
        reason: 'Beta is no longer a spine',
      );

      // **Centred on the cover, not pinned to its corner, and the frame in
      // `shelf_density_render_preview` is why.** A corner disc in this density lands over
      // the touching spine to the left and abuts *that* spine's badge — two discs
      // meeting, with the left one belonging to the book on the right. Nothing else on a
      // compressed row places a disc anywhere but over the book it removes.
      expect(
        tester.getCenter(find.byKey(const ValueKey('delete_book_b'))).dx,
        tester.getCenter(find.byType(TurningBook)).dx,
      );

      // And it holds still along with them. It was briefly wrapped in a `Wiggle`, to keep
      // it from being the only motionless book on a wobbling row; the row does not wobble
      // any more, so the whole density is still and there is no odd one out either way.
      expect(
        find.ancestor(
          of: find.byType(TurningBook),
          matching: find.byType(Wiggle),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'Given spines at rest, When the row is drawn, Then no spine carries a badge',
      (tester) async {
        await _pump(tester, density: ShelfDensity.spines);

        // The badge belongs to edit mode, not to the density. A read-only row keeps one
        // child per slot.
        for (final id in const ['a', 'b', 'c']) {
          expect(find.byKey(ValueKey('delete_book_$id')), findsNothing);
        }
        expect(
          tester
              .widgetList<ShelfSpineTile>(find.byType(ShelfSpineTile))
              .every((tile) => tile.isEditMode),
          isFalse,
        );
      },
    );

    testWidgets(
      'Given covers in edit mode, When the row is drawn, Then every book carries a '
      'badge',
      (tester) async {
        await _pump(tester, density: ShelfDensity.covers);
        await enterEditMode(tester);

        // Untouched, and still pinned separately: the two densities now agree that every
        // book is removable, and they are reached through different tiles to get there.
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
