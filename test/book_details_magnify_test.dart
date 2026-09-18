// Tests for the magnified book on the details page.
//
// A single tap on the hero cover lifts it to the centre of the screen at about
// two and a half times the size; a *hold* turns the book instead and must not also
// magnify it on release, or the turned pose could never be looked at. Both halves
// are asserted here, because the two gestures share one tap recogniser and the only
// thing separating them is `BookWidget.holdSuppressesTap`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_magnifier.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

import 'support/book_details_harness.dart';

/// The chassis inside the magnified copy, as opposed to the one in the header.
final _magnified = find.descendant(
  of: find.byType(MagnifiedBook),
  matching: find.byType(BookChassis),
);

void main() {
  group('BookDetailsTabView cover magnification', () {
    testWidgets(
      'Given the details page, When the cover is tapped, Then the book is held '
      'enlarged in the centre of the screen',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        final headerSize = tester.getSize(find.byType(BookChassis));
        expect(find.byType(MagnifiedBook), findsNothing);

        await tester.tap(find.byType(BookWidget));
        await tester.pumpAndSettle();

        expect(find.byType(MagnifiedBook), findsOneWidget);

        final magnifiedSize = tester.getSize(_magnified);
        expect(
          magnifiedSize.height,
          greaterThan(headerSize.height * 2),
          reason: 'the point of the gesture is that there is more to see',
        );
        // Centred on the screen, not merely somewhere else on it.
        final screen = tester.getSize(find.byType(MaterialApp));
        expect(
          tester.getCenter(_magnified).dx,
          moreOrLessEquals(screen.width / 2, epsilon: 1),
        );
        expect(
          tester.getCenter(_magnified).dy,
          moreOrLessEquals(screen.height / 2, epsilon: 1),
        );
        // Still a book: the chassis is what draws the fore-edge and the binding,
        // so this is what says the enlargement is not a flat picture of a cover.
        expect(_magnified, findsOneWidget);

        // The two properties the *flight* depends on, asserted directly because
        // breaking either one fails silently — the book would simply appear in the
        // centre instead of travelling there, with nothing thrown and no test
        // above catching it. `HeroController` starts a flight only when both
        // routes are `PageRoute`s, and the source it flies back to only survives
        // because this one is transparent.
        final route = ModalRoute.of(
          tester.element(find.byType(MagnifiedBook)),
        )!;
        expect(route, isA<PageRoute<void>>());
        expect(route.opaque, isFalse);
      },
    );

    testWidgets(
      'Given the details page, When the cover is held past the turn and '
      'released, Then nothing is magnified',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(BookWidget)),
        );
        // The turn starts at `kBookHoldDelay` and runs for `kBookTurnDuration`;
        // settling lets it *finish*, which is what marks the gesture a hold rather
        // than a slow tap.
        await tester.pump(kBookHoldDelay + const Duration(milliseconds: 1));
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.byType(MagnifiedBook), findsNothing);
      },
    );

    testWidgets(
      'Given the details page, When the cover is released before the turn '
      'finishes, Then it still magnifies',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(BookWidget)),
        );
        // Past the 140ms the turn begins at but nowhere near the end of it. A tap
        // this slow is ordinary and must not be thrown away — the whole reason
        // `holdSuppressesTap` waits for the turn to complete.
        await tester.pump(kBookHoldDelay + const Duration(milliseconds: 1));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.byType(MagnifiedBook), findsOneWidget);
      },
    );

    testWidgets(
      'Given a magnified book, When it is tapped, Then it goes back to the '
      'header',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        await tester.tap(find.byType(BookWidget));
        await tester.pumpAndSettle();
        expect(find.byType(MagnifiedBook), findsOneWidget);

        await tester.tap(_magnified);
        await tester.pumpAndSettle();

        expect(find.byType(MagnifiedBook), findsNothing);
        // The header cover is drawing again rather than being left as the hero
        // placeholder the flight replaced it with.
        expect(find.byType(BookChassis), findsOneWidget);
      },
    );

    testWidgets(
      'Given a magnified book, When the dimmed page behind it is tapped, Then '
      'it goes back',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        await tester.tap(find.byType(BookWidget));
        await tester.pumpAndSettle();

        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();

        expect(find.byType(MagnifiedBook), findsNothing);
      },
    );
  });
}
