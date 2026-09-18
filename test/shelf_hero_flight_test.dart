// Guards the shelf — the plank and the name tab standing on it — flying from the
// library to the book-details page.
//
// Both are Heroes so that a tapped book carries the shelf it was standing on with
// it, instead of the shelf leaving with the outgoing page while a different one
// appears on the incoming one. Three things about that are easy to get wrong and
// invisible except in motion, or in one particular state:
//
//   1. The shape of the flight. `MaterialApp` installs `MaterialRectArcTween` as
//      the default hero rect tween, and it arcs the rect's top-left and
//      bottom-right corners along two *separate* circles — the distortion
//      `book_hero_flight_test.dart` exists because of. It happens to be harmless
//      for both of these: the plank's two rects differ only by 20pt of width and
//      share a centre x, and the tab's are the same size as each other. Which is
//      why neither widget overrides the tween — an empirical claim about the
//      layout, so it is asserted on the *painted* result rather than trusted, and
//      it is what would break if either end's geometry moved. The tab is the
//      sharper of the two: its box is squeezed onto its text, so a fraction of a
//      point of squeeze ellipsizes the name mid-flight.
//   2. That the two travel *together*. They are separate heroes with separate
//      flights, and a tab that arrives ahead of or behind its plank is worse than
//      one that never moved.
//   3. Which books are entitled to a flight at all. Finished books are kept off
//      the shelves and shown in the read view, so their shelf row is still on the
//      library route under the same tags but is not where the reader tapped.
//      Tagging the details shelf for one of those would fly a bare shelf in from
//      somewhere the cover was never standing. The *cover* of such a book does fly
//      — from the pile, and from the month grid — which is why this is keyed on the
//      book's status rather than on whether anything flew.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

import 'support/book_details_harness.dart';

/// The box a shelf part is drawing for itself, if it is drawing one.
///
/// `Hero` swaps its child for a bare `SizedBox` at both ends of a flight and draws
/// the real thing in the overlay, so "nothing under this widget has a box" and
/// "this widget is in the air" are the same statement — and it can be asked without
/// reaching into the overlay for the shuttle.
Finder _boxOf(Type part) =>
    find.descendant(of: find.byType(part), matching: find.byType(Container));

/// Width of a plank on the shelves, and of one squeezed by the details header's
/// 20pt side padding, at the 390dp width [_pumpTwoRoutes] sets up.
const _libraryWidth = 390 * 0.95;
const _detailsWidth = 390 - 40.0;

/// A library shelf and a details header, as two routes, with nothing else on
/// either.
///
/// [destinationTag] is the variable that matters: null stands for the read-pile
/// case, where the details page deliberately declines the flight. [withLabel] is
/// off by default so that the plank's shuttle is the only `Container` on screen and
/// can be measured without a finder that has to tell the two shelf parts apart.
Future<void> _pumpTwoRoutes(
  WidgetTester tester, {
  required Object? destinationTag,
  bool withLabel = false,
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // iPhone-ish, 390x844 dp
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Widget label(Object? tag) => withLabel
      ? Align(
          alignment: Alignment.centerRight,
          child: ShelfLabel(label: shelfName, heroTag: tag),
        )
      : const SizedBox.shrink();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            const SizedBox(height: 240),
                            label(
                              destinationTag == null
                                  ? null
                                  : shelfLabelHeroTag(shelfId),
                            ),
                            ShelfWidget(heroTag: destinationTag),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
              label(shelfLabelHeroTag(shelfId)),
              ShelfWidget(heroTag: shelfHeroTag(shelfId)),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the plank flies with the book', () {
    testWidgets(
      'Given both ends share a shelf tag, When the route is pushed, Then one '
      'plank is in the air and it is still a plank at every point of the flight',
      (tester) async {
        await _pumpTwoRoutes(tester, destinationTag: shelfHeroTag(shelfId));
        expect(find.byType(Container), findsOneWidget);
        expect(
          tester.getRect(find.byType(Container)).width,
          closeTo(_libraryWidth, 0.01),
        );

        await tester.tap(find.text('open'));
        await tester.pump();

        final painted = <Rect>[];
        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          // Both routes are holding a placeholder open, so the only plank being
          // drawn is the one in the overlay. This is also the assertion that the
          // flight is happening at all.
          expect(find.byType(Container), findsOneWidget);
          painted.add(tester.getRect(find.byType(Container)));
        }
        await tester.pumpAndSettle();

        for (final rect in painted) {
          expect(
            rect.height,
            closeTo(8, 0.2),
            reason: 'plank was $rect mid-flight, which is a slab, not a shelf',
          );
          expect(rect.width, lessThanOrEqualTo(_libraryWidth + 0.01));
          expect(rect.width, greaterThanOrEqualTo(_detailsWidth - 0.01));
        }
        // And it only ever narrows: a width that overshot and came back would
        // read as a wobble even with the height held.
        for (var i = 1; i < painted.length; i++) {
          expect(
            painted[i].width,
            lessThanOrEqualTo(painted[i - 1].width + 0.01),
          );
        }

        expect(
          tester.getRect(find.byType(Container)).width,
          closeTo(_detailsWidth, 0.01),
        );
      },
    );

    testWidgets(
      'Given the destination has no tag, When the route is pushed, Then the '
      'library shelf stays where it is',
      (tester) async {
        await _pumpTwoRoutes(tester, destinationTag: null);

        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        // Nobody gave up their box: the library's plank slides out with its page
        // and the destination's is simply there on arrival.
        expect(find.byType(Container), findsNWidgets(2));
      },
    );

    testWidgets('Given no tag, Then the plank is not a hero at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Center(child: ShelfWidget())),
        ),
      );
      expect(find.byType(Container), findsOneWidget);
      expect(find.byType(Hero), findsNothing);
    });
  });

  group('the name tab flies with the plank', () {
    testWidgets(
      'Given a shelf with a name, When the route is pushed, Then the tab is in '
      'the air for exactly as long as the plank is',
      (tester) async {
        await _pumpTwoRoutes(
          tester,
          destinationTag: shelfHeroTag(shelfId),
          withLabel: true,
        );
        expect(_boxOf(ShelfLabel), findsOneWidget);
        final resting = tester.getSize(_boxOf(ShelfLabel));

        await tester.tap(find.text('open'));
        await tester.pump();

        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          // Neither part is drawing its own box, so both are in flight — and
          // they start and stop together rather than one lagging the other.
          expect(_boxOf(ShelfLabel), findsNothing);
          expect(_boxOf(ShelfWidget), findsNothing);
        }

        await tester.pumpAndSettle();
        expect(_boxOf(ShelfLabel), findsOneWidget);
        expect(_boxOf(ShelfWidget), findsOneWidget);
        // The tab shrink-wraps the same name at both ends, so it lands the size
        // it left at. A tab that changed size in the air would have ellipsized
        // its own name on the way.
        expect(tester.getSize(_boxOf(ShelfLabel)), resting);
        expect(find.text(shelfName), findsOneWidget);
      },
    );

    testWidgets(
      "Given a shelf that can't be resolved, Then its empty tab is not a hero",
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                child: ShelfLabel(
                  label: '',
                  heroTag: shelfLabelHeroTag(shelfId),
                ),
              ),
            ),
          ),
        );

        // Nothing is painted, so there is nothing to fly: a hero here would take
        // the other end's tab on a flight to a zero-sized box.
        expect(find.byType(Hero), findsNothing);
        expect(_boxOf(ShelfLabel), findsNothing);
      },
    );
  });

  group('which books the details page offers a flight to', () {
    testWidgets(
      "Given a book waiting on a shelf, Then both shelf parts carry that shelf's "
      'tags',
      (tester) async {
        // Status 0 is the only status whose cover is actually standing on the plank
        // over in the library, which is what the flight's far end has to be.
        await pumpBookDetails(
          tester,
          book: interestedBook(ownerId: meId),
          signedInAs: meId,
        );

        expect(
          tester.widget<ShelfWidget>(find.byType(ShelfWidget)).heroTag,
          shelfHeroTag(shelfId),
        );
        expect(
          tester.widget<ShelfLabel>(find.byType(ShelfLabel)).heroTag,
          shelfLabelHeroTag(shelfId),
        );
      },
    );

    testWidgets(
      'Given a book in progress, Then neither is tagged, because the cover they '
      'would fly with is on the Reading shelf rather than on this one',
      (tester) async {
        // The mirror of the finished case below, and it arrived with the Reading
        // shelf: `withoutReadingBooks` takes an open book off its own plank, so that
        // plank is still on the library route under these tags but is not where the
        // reader tapped. The Reading shelf's own plank carries no tags at all, for
        // the matching reason — this page names the shelf the book *belongs* to, so
        // there is nothing here for that one to fly to either.
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: meId),
          signedInAs: meId,
        );

        expect(
          tester.widget<ShelfWidget>(find.byType(ShelfWidget)).heroTag,
          isNull,
        );
        expect(
          tester.widget<ShelfLabel>(find.byType(ShelfLabel)).heroTag,
          isNull,
        );
        // The tab is still drawn and still names the shelf: where a book belongs is
        // information the page owes the reader whether or not anything flies.
        expect(find.text(shelfName), findsOneWidget);
      },
    );

    testWidgets(
      'Given a finished book, Then neither is tagged, because the cover they '
      'would fly with is in the read pile rather than on the shelf',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        expect(
          tester.widget<ShelfWidget>(find.byType(ShelfWidget)).heroTag,
          isNull,
        );
        expect(
          tester.widget<ShelfLabel>(find.byType(ShelfLabel)).heroTag,
          isNull,
        );
      },
    );
  });
}
