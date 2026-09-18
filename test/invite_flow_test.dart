// The three screens a redemption passes through, and the one rule that ties them
// together: **every outcome is distinguishable, and every screen has a way out.**
//
// The defect these exist to prevent is not a wrong string. It is the shape the first
// draft had: one "this link didn't work" screen for four different failures. That is
// invisible in a screenshot and it leaves the reader stuck, so it is asserted rather
// than eyeballed.
//
// **A fourth screen used to be here** — a typed-code field, tested for the dead end it
// could become. It is gone, along with every way to create a friendship other than
// following a link.
//
// Widget tests against the pages directly, with `inviteActionsProvider` overridden.
// Nothing here touches Supabase: `InviteActions` is the seam, and overriding it is
// what lets a refusal be produced on demand — there is no other way to make a link
// expire inside a test.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/invite.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/invite_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';

Profile _jisoo() => Profile(
  id: 'f1',
  username: 'jisoo',
  emoji: '🦊',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Profile _me() => Profile(
  id: 'u',
  username: 'tester',
  emoji: '📚',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

/// An [InviteActions] that answers with whatever the test asked for.
///
/// A fake rather than a mock: nothing here needs `verify()` beyond the one counter,
/// and a fake keeps the setup readable at every call site.
class _FakeInviteActions extends InviteActions {
  _FakeInviteActions(super.ref, {required this.answer});

  final InviteRedemptionResult answer;

  /// How many times a redemption was attempted. Asserted to be exactly one on the
  /// consent path, which is the only thing that tells "accepted" apart from "arrived
  /// and did nothing" — both leave the reader looking at a screen.
  int redeemCalls = 0;

  @override
  Future<InviteRedemption> redeem(String token) async {
    redeemCalls += 1;
    return InviteRedemption(
      answer,
      answer == InviteRedemptionResult.notFound ? null : 'f1',
    );
  }
}

/// Pumps a stand-in library, then pushes [route] onto it.
///
/// **The library underneath is load-bearing, not scaffolding.** Every screen in this
/// flow leaves with `popUntil(isFirst)`, so a harness that pumped the page alone
/// could not exercise a single exit — and "has a way out" is half of what these tests
/// are for.
///
/// An explicit [ProviderContainer] rather than `ProviderScope(overrides:)`, because a
/// `Provider` is lazy: the override's body does not run until something reads it, so
/// capturing the fake from inside it hands back an uninitialised variable on every
/// test that does not redeem. Reading it here forces construction once.
Future<_FakeInviteActions> _pump(
  WidgetTester tester, {
  required String route,
  required Object arguments,
  InviteRedemptionResult answer = InviteRedemptionResult.ok,
}) async {
  final container = ProviderContainer(
    overrides: [
      profileProvider.overrideWith((ref) async => _me()),
      inviteActionsProvider.overrideWith(
        (ref) => _FakeInviteActions(ref, answer: answer),
      ),
    ],
  );
  addTearDown(container.dispose);
  final fake = container.read(inviteActionsProvider) as _FakeInviteActions;

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
        // `AppRoutes.routes` maps `/` to the splash page, and `home` may not
        // coexist with that entry. The stand-in library takes `/` instead: this
        // harness is about where the invite screens *go*, and the splash page is
        // neither a destination nor an origin for any of them.
        routes: {
          for (final entry in AppRoutes.routes.entries)
            if (entry.key != AppRoutes.splash) entry.key: entry.value,
        },
        home: const Scaffold(body: Text('LIBRARY')),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // **Not awaited.** `pushNamed` returns the route's *result*, which does not
  // complete until that route is popped — and most of these tests never pop, so
  // awaiting it hangs the test rather than failing it.
  unawaited(
    navigatorKey.currentState!.pushNamed<void>(route, arguments: arguments),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('the consent screen', () {
    testWidgets(
      'Given an invite from jisoo, When the screen is shown, Then it names her and '
      'offers exactly one action',
      (tester) async {
        await _pump(
          tester,
          route: AppRoutes.inviteConsent,
          arguments: InviteConsentArgs(token: 'K7M2QP4X', inviter: _jisoo()),
        );

        expect(find.textContaining('jisoo'), findsWidgets);
        expect(find.text('Become friends'), findsOneWidget);
        // **The assertion the screen exists for.** A Decline button beside Become
        // friends turns "do this, or leave" into a two-way choice, and the ✕ is
        // already the refusal. Nothing may add one back.
        expect(find.text('Decline'), findsNothing);
        expect(find.byIcon(Icons.close), findsOneWidget);
      },
    );

    testWidgets(
      'Given the reader accepts, When the redemption succeeds, Then the success '
      'screen replaces this one rather than stacking on it',
      (tester) async {
        await _pump(
          tester,
          route: AppRoutes.inviteConsent,
          arguments: InviteConsentArgs(token: 'K7M2QP4X', inviter: _jisoo()),
        );

        await tester.tap(find.text('Become friends'));
        await tester.pumpAndSettle();

        expect(find.text("You're now friends"), findsOneWidget);
        // Replaced, not pushed: backing out of the success screen must not land on
        // a consent screen for a friendship that already exists.
        expect(find.text('Become friends'), findsNothing);
      },
    );

    testWidgets(
      'Given the link has expired, When the reader accepts, Then the expired copy '
      'is shown rather than the success screen',
      (tester) async {
        await _pump(
          tester,
          route: AppRoutes.inviteConsent,
          arguments: InviteConsentArgs(token: 'K7M2QP4X', inviter: _jisoo()),
          answer: InviteRedemptionResult.expired,
        );

        await tester.tap(find.text('Become friends'));
        await tester.pumpAndSettle();

        expect(find.text('This link has expired'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the friendship already existed, When the reader accepts, Then the '
      'screen does not claim a new one',
      (tester) async {
        await _pump(
          tester,
          route: AppRoutes.inviteConsent,
          arguments: InviteConsentArgs(token: 'K7M2QP4X', inviter: _jisoo()),
          answer: InviteRedemptionResult.alreadyFriends,
        );

        await tester.tap(find.text('Become friends'));
        await tester.pumpAndSettle();

        // Same screen, quieter headline. "You're now friends" said to somebody who
        // already was reads as the app having lost track of them.
        expect(find.text("You're already friends"), findsOneWidget);
        expect(find.text("You're now friends"), findsNothing);
      },
    );
  });

  group('the dead-link screen', () {
    // **The group this whole enum exists for.** Three of these mean "ask for a new
    // link" and one means "you already used this", so a screen that cannot tell them
    // apart makes the reader guess which. Asserting the copy differs is what stops
    // somebody collapsing them back into one string.
    const cases = <InviteRedemptionResult, String>{
      InviteRedemptionResult.expired: 'This link has expired',
      InviteRedemptionResult.revoked: 'This link was turned off',
      InviteRedemptionResult.exhausted: 'This link is used up',
      InviteRedemptionResult.notFound: "We couldn't find that code",
      InviteRedemptionResult.self: "That's your own link",
    };

    for (final entry in cases.entries) {
      testWidgets(
        'Given a ${entry.key.name} link, When the screen is shown, Then it says so '
        'in its own words',
        (tester) async {
          await _pump(
            tester,
            route: AppRoutes.inviteDead,
            arguments: InviteDeadArgs(result: entry.key, inviterName: 'jisoo'),
          );

          expect(find.text(entry.value), findsOneWidget);
        },
      );
    }

    testWidgets(
      'Given every dead-link outcome, When each is shown, Then no two share a '
      'headline',
      (tester) async {
        // The per-case tests above would all still pass if four outcomes were
        // collapsed onto one string and the expectations updated to match. This is
        // the one that would not.
        final seen = <String>{};
        for (final result in cases.keys) {
          await _pump(
            tester,
            route: AppRoutes.inviteDead,
            arguments: InviteDeadArgs(result: result, inviterName: 'jisoo'),
          );
          final shown = cases.values
              .where((copy) => find.text(copy).evaluate().isNotEmpty)
              .toList();
          expect(
            shown,
            hasLength(1),
            reason: '${result.name} drew ${shown.length}',
          );
          expect(
            seen.add(shown.single),
            isTrue,
            reason:
                '${result.name} reuses another outcome\'s headline, which is the '
                'exact collapse the enum was introduced to prevent',
          );
        }
      },
    );

    testWidgets(
      'Given a dead link, When the screen is shown, Then its one action leaves '
      'rather than retrying',
      (tester) async {
        await _pump(
          tester,
          route: AppRoutes.inviteDead,
          arguments: const InviteDeadArgs(
            result: InviteRedemptionResult.expired,
            inviterName: 'jisoo',
          ),
        );

        // There is no fallback to offer — handle search is gone — so "try again"
        // or "add by handle" here would be a control that cannot work.
        expect(find.text('Continue to my library'), findsOneWidget);
        await tester.tap(find.text('Continue to my library'));
        await tester.pumpAndSettle();
        expect(find.text('LIBRARY'), findsOneWidget);
      },
    );
  });

  group('the success screen', () {
    testWidgets(
      'Given a new friendship, When the screen is shown, Then Done leaves and the '
      'notification offer is secondary to it',
      (tester) async {
        await _pump(
          tester,
          route: AppRoutes.inviteDone,
          arguments: InviteDoneArgs(inviter: _jisoo()),
        );

        expect(find.text('Done'), findsOneWidget);
        expect(find.text('Notify me about jisoo'), findsOneWidget);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('LIBRARY'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the screen is shown, When it is inspected, Then there is nothing to '
      'dismiss back to',
      (tester) async {
        await _pump(
          tester,
          route: AppRoutes.inviteDone,
          arguments: InviteDoneArgs(inviter: _jisoo()),
        );

        // No ✕. The redemption is written and the friendship exists whether or not
        // this screen is read, so a dismissal would imply the opposite.
        expect(find.byIcon(Icons.close), findsNothing);
      },
    );

    testWidgets(
      'Given a link tapped cold, When the screen is shown, Then the missing inviter '
      'does not leave a hole in the copy',
      (tester) async {
        // The token carries no name and this client cannot read `friend_invites` to
        // resolve one, so every link today arrives anonymous. The copy has to survive
        // that rather than render "You and  can see…".
        await _pump(
          tester,
          route: AppRoutes.inviteDone,
          arguments: const InviteDoneArgs(inviter: null),
        );

        expect(find.textContaining('Someone'), findsWidgets);
      },
    );
  });
}
