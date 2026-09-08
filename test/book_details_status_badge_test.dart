// Regression tests for where the status badge lives in the book-details hero.
//
// It has been in three places. Originally the right-hand column, where it was
// laid out at the bottom-right and painted over by the `Positioned` shelf label,
// leaving it invisible. Then stacked directly above that label on a friend's
// book, but still hoisted to the top of the column on your own — two places for
// one thing, because the corner belonged to a button the owner is never shown.
//
// It is now in the reading-period card, standing in for that card's old
// "Reading period" label, with one rule for both viewers. So the checks that
// matter are: exactly one badge, below the shelf (in the band rather than the
// hero), and still present on a book that has no dates for the card to hold.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/reading_period_row.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';

import 'support/book_details_harness.dart';

void main() {
  group('BookDetailsTabView status badge', () {
    testWidgets(
      "Given a friend's finished book, When the details page is shown, Then one "
      'badge sits in the reading-period card below the shelf label',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: friendId),
          signedInAs: meId,
          // From a third party, so the react button is on screen too: the point
          // is that a busy right-hand column no longer competes with the badge.
          compliments: [compliment('👏', from: otherId)],
        );

        expect(find.text('React'), findsOneWidget);
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
        // The badge is now *below* the shelf, not above it: it left the hero for
        // the band. This is the assertion that would fail if it drifted back.
        expect(
          badge.top,
          greaterThan(label.bottom),
          reason: 'the badge belongs to the band, under the shelf',
        );
        // And it is inside the card rather than floating in the band.
        expect(
          tester.getRect(find.byType(ReadingPeriodRow)).contains(badge.center),
          isTrue,
        );
      },
    );

    testWidgets(
      "Given the owner's own finished book, When the details page is shown, "
      'Then the badge is in the same place as on a friend\'s',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        expect(find.text('React'), findsNothing);
        // One badge, and not hoisted into the column the way it used to be.
        expect(find.byType(BookStatusBadge), findsOneWidget);

        final badge = tester.getRect(find.byType(BookStatusBadge));
        final label = tester.getRect(find.byType(ShelfLabel));

        expect(badge.overlaps(label), isFalse);
        expect(badge.top, greaterThan(label.bottom));
      },
    );

    testWidgets(
      'Given a book with no dates, When the details page is shown, Then the '
      'badge survives the card it normally sits in',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: interestedBook(ownerId: friendId),
          signedInAs: meId,
        );

        // `ReadingPeriodRow` collapses to a bare badge rather than wrapping one
        // chip in a full-width card. What must not happen is the badge going
        // missing along with the dates — the guard on the call site used to be
        // `status >= 1 && startDate != null`, which would have done exactly that
        // on 133 of 472 books.
        expect(find.byType(BookStatusBadge), findsOneWidget);
        expect(find.text('Interested'), findsOneWidget);

        final badge = tester.getRect(find.byType(BookStatusBadge));
        expect(
          badge.top,
          greaterThan(tester.getRect(find.byType(ShelfLabel)).bottom),
        );
      },
    );
  });
}
