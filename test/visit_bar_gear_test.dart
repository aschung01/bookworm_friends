// **The gear, and why it had to exist at all.**
//
// Managing a friend was reachable only by long-pressing their row in the Friends
// sheet — a real gesture, inherited from the deleted `FriendRail`, and one that
// nothing on screen advertised. Reusing an existing gesture is not the same as
// offering an action, so the visit bar's trailing group took a second item.
//
// Three things are pinned: that it is there during a visit, that it is *not* there
// outside one, and that it sits inboard of Poke. The last is the one most likely to
// be "tidied" — Poke is the primary thing to do on this bar and the trailing edge is
// where a thumb lands, so a settings glyph in that slot would put the destructive
// path where the friendly one belongs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/pages/manage_friend_page.dart';

import 'support/home_page_harness.dart';

Profile _friend(String id, String name) => Profile(
  id: id,
  username: name,
  emoji: '🦊',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Finder _gear() => find.descendant(
  of: find.byType(AppBar),
  matching: find.byIcon(Icons.settings_outlined),
);

Future<void> _pumpShell(WidgetTester tester) => pumpHome(
  tester,
  extraOverrides: [
    friendsProvider.overrideWith((ref) async => [_friend('f1', 'jisoo')]),
    userLibraryProvider.overrideWith(
      (ref, id) async => [
        testShelf('s1', [
          testBook('b1', 's1', title: 'Clean Code'),
        ], name: 'Dev'),
      ],
    ),
    userFinishedBooksProvider.overrideWith((ref, id) async => <Book>[]),
  ],
);

void main() {
  group("the visit bar's gear", () {
    testWidgets(
      'Given your own library, When the bar renders, Then there is no gear',
      (tester) async {
        await _pumpShell(tester);

        // Nothing to manage outside a visit. The same rule Poke follows, and for the
        // same reason: neither action has a subject.
        expect(_gear(), findsNothing);
      },
    );

    testWidgets(
      "Given a visit, When the bar renders, Then the gear sits inboard of Poke",
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        expect(_gear(), findsOneWidget);
        expect(
          tester.getCenter(_gear()).dx,
          lessThan(tester.getCenter(find.text('Poke')).dx),
          reason:
              'Poke is the primary action and keeps the trailing edge; a gear '
              'there would put the way to Remove under the resting thumb',
        );
      },
    );

    testWidgets(
      'Given a visit, When the gear is tapped, Then the manage page opens for that '
      'friend',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        await tester.tap(_gear());
        await tester.pumpAndSettle();

        expect(find.byType(ManageFriendPage), findsOneWidget);
        // Carries the friend, not just the route: the page reads its subject from
        // the arguments, and a push without them throws rather than showing an empty
        // screen — but a push with the *wrong* one would look fine.
        expect(find.text('jisoo'), findsOneWidget);
      },
    );
  });
}
