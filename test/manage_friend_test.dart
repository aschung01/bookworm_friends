// Managing a friend, and the one claim removal makes: **it is symmetric, and it is
// silent.**
//
// Both halves are asserted because both were wrong before. Removal used to be
// `unfollow`, which severed one direction and left the other standing — a
// half-friendship the schema could not even detect — and it was reachable from two
// places with two different button pairs (No/Unfollow on the deleted
// `UserLibraryPage`, Cancel/Confirm in the deleted `friend_info_dialog`). There is
// one path now, and the copy has to keep promising what the `DELETE` actually does.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';

Profile _jisoo() => Profile(
  id: 'f1',
  username: 'jisoo',
  handle: 'jisoo_reads',
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

/// The fake, plus the container backing the app — the shell state removal tears down
/// has no widget of its own, and reaching it through a pumped element does not work
/// while the page is covering the shell.
typedef _Harness = ({_FakeUserActions actions, ProviderContainer container});

Future<_Harness> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      userActionsProvider.overrideWith((ref) => _FakeUserActions(ref)),
      // Set as though a visit were in progress, so the page's teardown of it can be
      // observed. This is the state removal has to leave behind: the shell must not
      // return to a friend who is no longer in the list.
      selectedFriendProvider.overrideWith((ref) => _jisoo()),
    ],
  );
  addTearDown(container.dispose);
  final fake = container.read(userActionsProvider) as _FakeUserActions;

  // **Subscriptions, not reads.** Both shell providers are `autoDispose`, so once
  // the page pops and stops watching them they are torn down and the next read
  // rebuilds them at their initial value — which here is the override, i.e. jisoo
  // still selected. That would make this harness report the exact opposite of what
  // happened. Holding a listener keeps them alive across the pop.
  container.listen(selectedFriendProvider, (_, __) {}, fireImmediately: true);
  container.listen(
    friendsSheetLevelProvider,
    (_, __) {},
    fireImmediately: true,
  );

  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routes: {
          for (final entry in AppRoutes.routes.entries)
            if (entry.key != AppRoutes.splash) entry.key: entry.value,
        },
        home: const Scaffold(body: Text('SHELL')),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Unawaited: the route's result future does not complete until it is popped.
  navigatorKey.currentState!.pushNamed<void>(
    AppRoutes.manageFriend,
    arguments: _jisoo(),
  );
  await tester.pumpAndSettle();
  return (actions: fake, container: container);
}

void main() {
  group('the manage-friend page', () {
    testWidgets(
      'Given a friend, When the page is shown, Then it identifies her without '
      'quoting a follower count',
      (tester) async {
        await _pump(tester);

        expect(find.text('jisoo'), findsOneWidget);
        expect(find.text('@jisoo_reads'), findsOneWidget);
        // The dialog this replaces showed a Followers/Following pair, which a mutual
        // model makes one number — and one the *friend's* page has no reason to
        // report at all. "Friends since" is the fact only this model can state.
        expect(find.text('Followers'), findsNothing);
        expect(find.text('Following'), findsNothing);
        expect(find.textContaining('Friends since'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the page, When Remove is tapped, Then nothing is removed until the '
      'alert is confirmed',
      (tester) async {
        final harness = await _pump(tester);

        await tester.tap(find.text('Remove friend'));
        await tester.pumpAndSettle();

        // The alert is up and nothing has happened yet. A destructive row that acted
        // on its own tap would be the one mistake this page cannot afford.
        expect(find.text('Remove jisoo?'), findsOneWidget);
        expect(harness.actions.removed, isEmpty);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(harness.actions.removed, isEmpty);
        expect(find.text('Remove friend'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the confirm alert, When Remove is tapped, Then the friendship goes and '
      'the page leaves',
      (tester) async {
        final harness = await _pump(tester);

        await tester.tap(find.text('Remove friend'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Remove'));
        await tester.pumpAndSettle();

        expect(harness.actions.removed, ['f1']);
        expect(find.text('SHELL'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a visit is in progress, When the friend is removed, Then the visit '
      'ends with her',
      (tester) async {
        final container = (await _pump(tester)).container;

        await tester.tap(find.text('Remove friend'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Remove'));
        await tester.pumpAndSettle();

        // Without this the shell returns to a friend who is no longer in the list,
        // and her shelves are already unreadable — RLS drops with the row.
        expect(container.read(selectedFriendProvider), isNull);
        expect(
          container.read(friendsSheetLevelProvider),
          FriendsSheetLevel.list,
        );
      },
    );

    testWidgets(
      'Given the removal copy, When it is read, Then it promises both directions '
      'and no alert',
      (tester) async {
        await _pump(tester);

        // **The two claims the `DELETE` actually makes.** One row is the whole
        // friendship, so removal is symmetric by construction — and it fires no
        // push, because nothing writes one. Telling the reader removal is silent is
        // what stops them hesitating over the button; the copy may not drift from
        // either fact.
        expect(find.text('They will not get an alert.'), findsOneWidget);

        await tester.tap(find.text('Remove friend'));
        await tester.pumpAndSettle();
        expect(find.textContaining('revoked for both of you'), findsOneWidget);
      },
    );
  });
}
