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
//
// The Friends sheet's second level is deliberately **not** one of those contexts.
// It is a level of a sheet, not a context over the page, and the way back up it is a
// tap on the Friends tab. Back skips it and ends the visit outright, which is what
// makes back and the bar's ✕ agree.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/pages/home_page.dart';
import 'package:bookworm_friends/ui/widgets/friends_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';

import 'support/home_page_harness.dart';

Profile _friend(String id, String name) => Profile(
  id: id,
  username: name,
  emoji: '🦊',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

/// One followed friend, with her library stubbed: a visit draws it in the shell's
/// own pane now, so an unstubbed read leaves the pane on an error and every
/// assertion below it is about the wrong tree.
Future<void> _pumpWithFriend(WidgetTester tester) => pumpHome(
  tester,
  extraOverrides: [
    friendsProvider.overrideWith((ref) async => [_friend('f1', 'jisoo')]),
    userLibraryProvider.overrideWith(
      (ref, id) async => [
        testShelf('hers', [testBook('hb1', 'hers', title: 'Ficciones')]),
      ],
    ),
    userFinishedBooksProvider.overrideWith((ref, id) async => <Book>[]),
  ],
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
      await _pumpWithFriend(tester);

      await enterVisit(tester, 'jisoo');
      final container = shellContainer(tester);
      expect(container.read(selectedFriendProvider)?.username, 'jisoo');

      await simulateSystemBack();
      await tester.pumpAndSettle();

      expect(
        container.read(selectedFriendProvider),
        isNull,
        reason: 'back should end the visit',
      );
      expect(
        container.read(friendsSheetLevelProvider),
        FriendsSheetLevel.list,
        reason:
            'and take the sheet back to the list with it — a second level '
            'belonging to nobody is not a state the shell has',
      );
      expect(find.text('My Library'), findsOneWidget);
      expect(find.byType(FriendsSheet), findsOneWidget);
      expect(find.byType(ShellTabBar), findsOneWidget);
      expect(find.byType(HomePage), findsOneWidget);
    },
  );

  testWidgets(
    'Given a friend\'s read books, When the Friends tab is tapped, Then only the '
    'level changes',
    (tester) async {
      await _pumpWithFriend(tester);
      await enterVisit(tester, 'jisoo');
      final container = shellContainer(tester);
      expect(
        container.read(friendsSheetLevelProvider),
        FriendsSheetLevel.friend,
      );

      await backToFriendsList(tester);

      expect(container.read(friendsSheetLevelProvider), FriendsSheetLevel.list);
      expect(
        container.read(selectedFriendProvider)?.username,
        'jisoo',
        reason:
            'the two controls have different scopes: the Friends tab moves the '
            'sheet, the bar\'s ✕ ends the visit',
      );
      expect(find.byType(FriendsSheet), findsOneWidget);
    },
  );

  testWidgets(
    'Given a friend\'s read books, When the bar\'s ✕ is tapped, Then the visit '
    'ends and the level resets',
    (tester) async {
      await _pumpWithFriend(tester);
      await enterVisit(tester, 'jisoo');

      await endVisit(tester);

      final container = shellContainer(tester);
      expect(container.read(selectedFriendProvider), isNull);
      expect(container.read(friendsSheetLevelProvider), FriendsSheetLevel.list);
      expect(find.text('My Library'), findsOneWidget);
    },
  );

  testWidgets(
    'Given an edit inside a visit is impossible, When editing your own library in a visit-free shell, '
    'Then back unwinds edit before anything else',
    (tester) async {
      await _pumpWithFriend(tester);

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
