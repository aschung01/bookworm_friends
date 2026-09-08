// Regression tests for the reaction controls in the book-details hero.
//
// A reaction writes a row to `book_compliments`, and it is the only *persisted*
// social action in the app — a poke fires a push and stores nothing. Three
// separate defects have lived in this corner, and each has a test here:
//
// 1. Both the button and the emoji were behind the same `if (!isSelf)` guard, so
//    the person reacted to never saw it anywhere. The button stays owner-hidden
//    — you should not react to yourself — but the record does not.
// 2. The button carried a copy of your own emoji on its face while the record
//    showed the same emoji beside it, so the ordinary single-reaction case drew
//    the same glyph twice, 40pt apart, in two shapes that meant different
//    things. The button is now hidden once you hold a reaction.
// 3. Below status 2 the button returns an empty box, which used to take the only
//    route to the picker with it: a reaction on a book moved back to *Reading*
//    was visible and unreachable. The capsule belongs to the record rather than
//    to the button, so it survives.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/reaction_capsule.dart';

import 'support/book_details_harness.dart';

void main() {
  group('Book details reactions', () {
    testWidgets(
      'Given a reaction on your own finished book, When the details page is '
      'shown, Then the emoji is visible to you',
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
          reason: 'the owner must be able to see reactions they were given',
        );
        expect(find.byType(ReactionCapsule), findsOneWidget);
        // Still no way to react to your own book.
        expect(find.text('React'), findsNothing);
      },
    );

    testWidgets(
      "Given other people's reactions on a friend's book, When the details page "
      'is shown, Then the emoji and the React button are both offered',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: friendId),
          signedInAs: meId,
          // Two people, one reaction each: with `UNIQUE (book_id, from_user_id)`
          // two rows can no longer come from the same person.
          compliments: [
            compliment('👏', from: otherId),
            compliment('❤️', id: 'c2', from: 'other2'),
          ],
        );

        expect(find.text('👏'), findsOneWidget);
        expect(find.text('❤️'), findsOneWidget);
        // You hold nothing, so there is still something to add.
        expect(find.text('React'), findsOneWidget);
        expect(find.byIcon(Icons.celebration), findsOneWidget);
      },
    );

    testWidgets(
      'Given you already reacted, When the details page is shown, Then the '
      'button is gone and your emoji appears exactly once',
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

        // The reported bug: 🔥 used to be drawn twice, once as a chip and once
        // on the button's face. You may hold only one reaction, so a button
        // offering to add one is promising what it cannot do.
        expect(find.text('React'), findsNothing);
        expect(find.byIcon(Icons.celebration), findsNothing);
        expect(
          find.text('🔥'),
          findsOneWidget,
          reason: 'your reaction belongs to the record, and only to the record',
        );
        expect(find.text('👏'), findsOneWidget);
      },
    );

    testWidgets(
      'Given no reactions yet, When the details page is shown, Then nothing is '
      'drawn for them',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: meId),
          signedInAs: meId,
        );

        // Collapses rather than leaving an empty gap beside the cover.
        expect(tester.getSize(find.byType(ReactionCapsule)).height, 0);
      },
    );

    testWidgets(
      'Given a book still being read, When a visitor opens it, Then reacting is '
      'not offered but an existing reaction stays reachable',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: readingBook(ownerId: friendId),
          signedInAs: meId,
          compliments: [compliment('👏')], // yours, from before it reopened
        );

        // `_ReactButton` returns an empty box unless status == 2: you cannot
        // react to a book nobody has finished.
        expect(find.text('React'), findsNothing);
        // But the reaction is not stranded. This is the state that used to have
        // no route to the sheet at all.
        expect(find.text('👏'), findsOneWidget);
        await tester.tap(find.byType(ReactionCapsule));
        await tester.pumpAndSettle();
        expect(find.text('Reactions'), findsOneWidget);
        // And your own row is picked out inside it, which is what makes the
        // reaction changeable from here rather than merely visible. The hint that
        // used to say so in words is gone; `You` plus the row's chevron carry it.
        expect(find.text('You'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a reaction from a profile you cannot read, When the sheet is '
      'opened, Then the row says so instead of showing a blank name',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: friendId),
          signedInAs: meId,
          // The `profiles` policy withheld the row, so the embed came back null.
          compliments: [compliment('👏', from: otherId, name: null)],
        );

        await tester.tap(find.byType(ReactionCapsule));
        await tester.pumpAndSettle();

        expect(find.text("Someone you don't follow"), findsOneWidget);
        // Not yours, so not tappable and no hint about changing it.
        expect(find.text('Tap your row to change or remove it.'), findsNothing);
      },
    );

    testWidgets(
      'Given you already reacted, When the capsule is tapped, Then the sheet '
      'opens on your own row',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: finishedBook(ownerId: friendId),
          signedInAs: meId,
          compliments: [compliment('🔥', name: 'Areum')],
        );

        await tester.tap(find.byType(ReactionCapsule));
        await tester.pumpAndSettle();

        // The page's job is wiring the capsule to the sheet with the right data
        // and the right viewer. What happens when you tap your row — pop, then
        // hand over to the picker — is asserted in reactions_sheet_test.dart with
        // a spy, because following it here would pump the real emoji picker and
        // with it `SharedPreferences`.
        expect(find.text('Reactions'), findsOneWidget);
        expect(find.text('Areum'), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
      },
    );

    testWidgets(
      'Given an Interested book, When the details page is shown, Then the '
      'status badge is still on screen',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: interestedBook(ownerId: friendId),
          signedInAs: meId,
        );

        // Status 0 has no dates, so there is no reading-period card for the
        // badge to sit in. It must not vanish with the card: the badge is the
        // only thing naming the state.
        expect(find.byType(BookStatusBadge), findsOneWidget);
        expect(find.text('Interested'), findsOneWidget);
        expect(find.text('React'), findsNothing);
      },
    );
  });
}
