// **The visit title's chevron, and the menu it discloses.**
//
// Managing a friend was reachable only by long-pressing their row in the Friends
// sheet — a real gesture, inherited from the deleted `FriendRail`, that nothing on
// screen advertised. Two shapes were tried in the bar's trailing group before this
// one: a gear that pushed `ManageFriendPage` (a whole screen whose only content was
// identity and one destructive action), then a glass ellipsis outboard of Poke. Both
// spent 44pt of the most contested row in the app on a control that could not say
// what it was about.
//
// The chevron sits on the title instead, which is the thing the menu acts on. Five
// things are pinned:
//
//   * it is absent outside a visit, like Poke, because neither has a subject;
//   * it sits **inboard** of Poke and immediately after the title — the assertion
//     most likely to be "corrected" by someone reading either of the old notes;
//   * the title itself is not the trigger, so a mis-aimed tap on a username does
//     nothing;
//   * it opens a menu rather than a page, which is the whole change;
//   * the confirm still gates the removal, and cancelling it is inert.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
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

/// Records the removal instead of hitting Supabase.
class _FakeUserActions extends UserActions {
  _FakeUserActions(super.ref);

  final removed = <String>[];

  @override
  Future<void> removeFriend(String targetUserId) async {
    removed.add(targetUserId);
  }
}

/// The trigger, by its accessible name.
///
/// **Not by glyph.** `Icons.keyboard_arrow_down` is a plausible thing for another
/// control to reach for, and the label is the more meaningful hold anyway: a chevron
/// says only that there is a menu, so what a screen reader needs is whose.
/// `PopupMenuButton` hands `tooltip` to Material's tooltip and to its semantics, and
/// the fallback is the only path `flutter test` takes.
Finder _chevron() => find.byTooltip('Manage friend');

/// The title, which `find.text` cannot match because it is a `Text.rich` of two spans.
Finder _title() => find.textContaining("'s Library");

Future<_FakeUserActions> _pumpShell(WidgetTester tester) async {
  await pumpHome(
    tester,
    extraOverrides: [
      userActionsProvider.overrideWith((ref) => _FakeUserActions(ref)),
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
  return shellContainer(tester).read(userActionsProvider) as _FakeUserActions;
}

/// Opens the menu and picks Remove, leaving the confirm alert up.
Future<void> _pickRemove(WidgetTester tester) async {
  await tester.tap(_chevron());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remove friend'));
  await tester.pumpAndSettle();
}

void main() {
  group("the visit title's menu", () {
    testWidgets(
      'Given your own library, When the bar renders, Then the title carries no '
      'chevron',
      (tester) async {
        await _pumpShell(tester);

        // Nothing to manage outside a visit. The same rule Poke follows, and for the
        // same reason: neither action has a subject.
        expect(_chevron(), findsNothing);
      },
    );

    testWidgets(
      'Given a visit, When the bar renders, Then the chevron follows the title and '
      'stays inboard of Poke',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        expect(_chevron(), findsOneWidget);

        // Punctuation on the phrase, so it has to sit at the end of the phrase
        // rather than anywhere else on the row. The tap target is wider than the
        // glyph, so its left edge is allowed to touch the text's right edge.
        expect(
          tester.getRect(_chevron()).left,
          greaterThanOrEqualTo(tester.getRect(_title()).right - 1),
        );
        expect(
          tester.getCenter(_chevron()).dx,
          lessThan(tester.getCenter(find.text('Poke')).dx),
          reason:
              'Poke is the one thing a reader comes here to do and keeps the '
              'trailing edge alone; the menu belongs on its subject',
        );
      },
    );

    testWidgets(
      'Given a visit, When the title itself is tapped, Then nothing opens',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        await tester.tap(_title());
        await tester.pumpAndSettle();

        // A target the width of a username would be the largest in the bar, and it
        // would fire on a mis-aimed tap at a name that reads as a label. The chevron
        // is the control; the title is the label.
        expect(find.text('Remove friend'), findsNothing);
      },
    );

    testWidgets(
      'Given a visit, When the chevron is tapped, Then Remove is offered in place '
      'rather than behind a page',
      (tester) async {
        await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');

        await tester.tap(_chevron());
        await tester.pumpAndSettle();

        expect(find.text('Remove friend'), findsOneWidget);
        // The change, stated as the thing that must not come back. Pushing a screen
        // to offer one destructive action was more ceremony than the action
        // deserved — the confirm is the ceremony.
        expect(find.byType(ManageFriendPage), findsNothing);
      },
    );

    testWidgets(
      'Given the menu, When Remove is picked, Then nothing is removed until the '
      'alert is confirmed',
      (tester) async {
        final actions = await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');
        await _pickRemove(tester);

        expect(find.text('Remove jisoo?'), findsOneWidget);
        expect(actions.removed, isEmpty);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Cancelling leaves the visit exactly as it was — still hers, still on her
        // shelves. A menu that ended the visit on the way out would be worse than
        // one that removed her.
        expect(actions.removed, isEmpty);
        expect(
          shellContainer(tester).read(selectedFriendProvider)?.username,
          'jisoo',
        );
      },
    );

    testWidgets(
      'Given the confirm alert, When Remove is tapped, Then the friendship goes and '
      'the visit ends with her',
      (tester) async {
        final actions = await _pumpShell(tester);
        await enterVisit(tester, 'jisoo');
        await _pickRemove(tester);

        await tester.tap(find.widgetWithText(TextButton, 'Remove'));
        await tester.pumpAndSettle();

        expect(actions.removed, ['f1']);
        // The shell must not be left pointed at someone who is no longer a friend:
        // her shelves are already unreadable, because RLS drops with the row.
        final container = shellContainer(tester);
        expect(container.read(selectedFriendProvider), isNull);
        expect(
          container.read(friendsSheetLevelProvider),
          FriendsSheetLevel.list,
        );
        // And the bar is back to your own library, which is the visible half of the
        // same claim.
        expect(find.text('My Library'), findsOneWidget);
      },
    );
  });
}
