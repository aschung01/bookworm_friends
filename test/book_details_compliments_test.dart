// Regression tests for who can see the praise a book has collected.
//
// "Praise" writes a row to `book_compliments` from a fixed emoji palette, and it
// is the only *persisted* social action in the app — a poke fires a push and
// stores nothing. Both the Praise button and the emoji chips were wrapped in the
// same `if (!isSelf)` guard, so the person praised never saw it anywhere: the
// push notification was the only trace. Hiding the button is right — you should
// not praise yourself — but hiding the praise defeats the point of storing it.
//
// The asymmetry is the thing to pin: the button stays owner-hidden, the chips do
// not.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/compliment_block.dart';

import 'support/book_details_harness.dart';

void main() {
  group('Book details compliments', () {
    testWidgets(
      'Given praise on your own finished book, When the details page is shown, '
      'Then the emoji are visible to you',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
          compliments: [compliment('🔥', from: friendId)],
        );

        expect(
          find.text('🔥'),
          findsOneWidget,
          reason: 'the owner must be able to see praise they were given',
        );
        expect(find.byType(ComplimentBlock), findsOneWidget);
        // Still no way to praise your own book.
        expect(find.text('Praise'), findsNothing);
        // And the badge the owner's corner already carried is untouched.
        expect(find.byType(BookStatusBadge), findsOneWidget);
      },
    );

    testWidgets(
      'Given praise on a friend\'s finished book, When the details page is '
      'shown, Then the emoji and the Praise button are both offered',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: friendId),
          signedInAs: meId,
          // Two people, one praise each: with `UNIQUE (book_id, from_user_id)`
          // two rows can no longer come from the same person.
          compliments: [
            compliment('👏', from: otherId),
            compliment('❤️', id: 'c2', from: 'other2'),
          ],
        );

        expect(find.text('👏'), findsOneWidget);
        expect(find.text('❤️'), findsOneWidget);
        expect(find.text('Praise'), findsOneWidget);
        // Nobody else's praise is mistaken for yours.
        expect(find.byIcon(Icons.celebration), findsOneWidget);
      },
    );

    testWidgets(
      'Given you already praised a friend\'s book, When the details page is '
      'shown, Then the button carries your emoji instead of the generic icon',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: friendId),
          signedInAs: meId,
          compliments: [
            compliment('🔥'), // from meId
            compliment('👏', id: 'c2', from: otherId),
          ],
        );

        // You hold one praise per book, and the chips do not say who gave what,
        // so the button is the only place that can tell you where you stand —
        // which is what makes tapping 🔥 again read as "take it back".
        expect(find.byIcon(Icons.celebration), findsNothing);
        expect(
          find.text('🔥'),
          findsNWidgets(2),
          reason: 'once as a chip on the book, once on the button as yours',
        );
        expect(find.text('👏'), findsOneWidget);
      },
    );

    testWidgets(
      'Given no praise yet, When the details page is shown, Then nothing is '
      'drawn for it',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        // The block collapses rather than leaving an empty gap by the cover.
        expect(tester.getSize(find.byType(ComplimentBlock)).height, 0);
      },
    );

    testWidgets(
      'Given a book still being read, When a visitor opens it, Then praise is '
      'not offered',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: friendId),
          signedInAs: meId,
        );

        // `_ComplimentButton` returns an empty box unless status == 2: praise is
        // for a book someone finished, not one they are partway through.
        expect(find.text('Praise'), findsNothing);
      },
    );
  });
}
