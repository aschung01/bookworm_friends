// Regression tests for the status badge in the book-details hero corner.
//
// On a *friend's* book the right-hand column carries the praise button and the
// compliment chips, so the badge ended up laid out at the bottom-right — the
// exact spot where the `Positioned` shelf label is painted over it, leaving the
// badge invisible. The badge now stacks directly above the label, so the check
// that matters is geometric: the two rects must not intersect.
//
// The owner's own book keeps the badge in the right-hand column (top-right,
// where the praise button would otherwise sit), so it is asserted separately to
// make sure the fix didn't move or duplicate it.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';

import 'support/book_details_harness.dart';

void main() {
  group('BookDetailsTabView status badge', () {
    testWidgets(
      "Given a friend's finished book, When the details page is shown, Then the status badge is not hidden behind the shelf label",
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: friendId),
          signedInAs: meId,
          // Praise from a third party: the chips' geometry is the subject here,
          // and praise of your own would also land on the button's face.
          compliments: [compliment('👏', from: otherId)],
        );

        // The layout that broke: praise button and chips own the top-right.
        expect(find.text('Praise'), findsOneWidget);
        expect(find.text('👏'), findsOneWidget);

        expect(find.byType(BookStatusBadge), findsOneWidget);
        expect(find.byType(ShelfLabel), findsOneWidget);
        expect(find.text(shelfName), findsOneWidget);

        final badge = tester.getRect(find.byType(BookStatusBadge));
        final label = tester.getRect(find.byType(ShelfLabel));

        expect(badge.isEmpty, isFalse);
        expect(label.isEmpty, isFalse);
        expect(
          badge.overlaps(label),
          isFalse,
          reason: 'badge $badge must not sit under the shelf label $label',
        );
        // Specifically: stacked above the label, sharing its right edge.
        expect(badge.bottom, lessThanOrEqualTo(label.top));
        expect(badge.right, closeTo(label.right, 0.5));
      },
    );

    testWidgets(
      "Given the owner's own finished book, When the details page is shown, Then a single badge stays clear of the shelf label",
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        // No praise button on your own book, so the column's top-right is free.
        expect(find.text('Praise'), findsNothing);
        // Rendered by the column, not duplicated into the label stack.
        expect(find.byType(BookStatusBadge), findsOneWidget);

        final badge = tester.getRect(find.byType(BookStatusBadge));
        final label = tester.getRect(find.byType(ShelfLabel));

        expect(badge.overlaps(label), isFalse);
        expect(badge.bottom, lessThanOrEqualTo(label.top));
      },
    );
  });
}
