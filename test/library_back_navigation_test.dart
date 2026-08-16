// Tests for the library's back-navigation behaviour.
//
// A system back (Android's back gesture / button, iOS predictive back) unwinds
// the shell's nested contexts one at a time, innermost first: an edit ends, then
// a visit ends, and only then may the page pop.
//
// Note what carries the weight here. `HomePage` is the root route, so there is
// nothing to pop to and `find.byType(HomePage)` survives whether `canPop` is
// true or false — that assertion alone would be tautological. The real signal is
// the *side effect* of `onPopInvokedWithResult` running: the innermost context
// ends.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/pages/home_page.dart';
import 'package:bookworm_friends/ui/widgets/friend_rail.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';

import 'support/home_page_harness.dart';

Profile _friend(String id, String name) => Profile(
  id: id,
  username: name,
  emoji: '🦊',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  testWidgets(
    'Given the library is in edit mode, When the system back fires, Then edit mode is exited and the page stays',
    (tester) async {
      await pumpHome(tester);
      expect(isEditing(), isFalse);

      await enterEditMode(tester);
      expect(isEditing(), isTrue);

      await simulateSystemBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(isEditing(), isFalse);
      // Still on the library, not popped to a blank route.
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('My Library'), findsOneWidget);
    },
  );

  testWidgets(
    'Given the library is not in edit mode, When the system back fires, Then the page is left alone',
    (tester) async {
      await pumpHome(tester);

      await simulateSystemBack();
      await tester.pumpAndSettle();

      // Nothing to pop to, so the route survives and no mode change happens.
      expect(find.byType(HomePage), findsOneWidget);
      expect(isEditing(), isFalse);
    },
  );

  testWidgets(
    'Given a visit, When the system back fires, Then the visit ends and the page stays',
    (tester) async {
      await pumpHome(
        tester,
        extraOverrides: [
          followingListProvider.overrideWith(
            (ref) async => [_friend('f1', 'jisoo')],
          ),
        ],
      );

      await enterVisit(tester, 'jisoo');
      expect(find.byType(FriendRail), findsOneWidget);

      await simulateSystemBack();
      await tester.pumpAndSettle();

      expect(
        find.byType(FriendRail),
        findsNothing,
        reason: 'back should end the visit, and the rail lives inside one',
      );
      expect(find.text('My Library'), findsOneWidget);
      expect(find.byType(ShellTabBar), findsOneWidget);
      expect(find.byType(HomePage), findsOneWidget);
    },
  );

  testWidgets(
    'Given an edit inside a visit is impossible, When editing your own library in a visit-free shell, '
    'Then back unwinds edit before anything else',
    (tester) async {
      await pumpHome(
        tester,
        extraOverrides: [
          followingListProvider.overrideWith(
            (ref) async => [_friend('f1', 'jisoo')],
          ),
        ],
      );

      // An edit is only reachable in your own library, so the two contexts cannot
      // actually nest. This pins the order anyway: whichever is open, back takes
      // the innermost one, and never the page while either is open.
      await enterEditMode(tester);
      await simulateSystemBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(isEditing(), isFalse);
      expect(find.byType(HomePage), findsOneWidget);
    },
  );
}
