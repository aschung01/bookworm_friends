// A link tapped **while the app is already running**.
//
// The defect this pins: `pendingInviteTokenProvider` was written by
// `InviteLinkService` and read only by `SplashPage` and `AuthPage`, both of which run
// once at startup. A cold-start link worked; a link tapped with the app in the
// background did nothing — iOS foregrounded the app, the token landed in the provider,
// and no screen was watching. Nothing on screen said an invite had arrived.
//
// That is the *common* path, since the app is usually already running when a message is
// tapped, so the version that shipped had the frequent case broken and the rare one
// working.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/invite_link_provider.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';
import 'package:bookworm_friends/ui/widgets/invite_link_listener.dart';

/// Reports a fixed auth status. A real session needs Supabase.
class _Auth extends AuthNotifier {
  _Auth(this._status);
  final AuthStatus _status;

  @override
  AuthState build() => AuthState(status: _status);
}

/// Records pushes without building the real destinations.
class _Recorder extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) =>
      pushed.add(route);

  List<String?> get names => pushed.map((r) => r.settings.name).toList();
}

/// Builds the listener where it really lives — in `MaterialApp.builder`, above the
/// navigator — so the test exercises the same "no `Navigator` in scope" constraint the
/// production wiring has.
Future<(ProviderContainer, _Recorder)> _pump(
  WidgetTester tester, {
  AuthStatus status = AuthStatus.authenticated,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final observer = _Recorder();
  final container = ProviderContainer(
    overrides: [authProvider.overrideWith(() => _Auth(status))],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [observer],
        builder: (context, child) =>
            InviteLinkListener(navigatorKey: navigatorKey, child: child!),
        home: const Scaffold(body: Text('LIBRARY')),
        routes: {
          AppRoutes.inviteConsent: (_) => const Scaffold(body: Text('CONSENT')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, observer);
}

void main() {
  testWidgets(
    'Given the app is running and signed in, When a link arrives, Then consent is '
    'pushed without waiting for a relaunch',
    (tester) async {
      final (container, observer) = await _pump(tester);

      container.read(pendingInviteTokenProvider.notifier).state = 'K7M2QP4X';
      await tester.pumpAndSettle();

      expect(observer.names, contains(AppRoutes.inviteConsent));
      expect(find.text('CONSENT'), findsOneWidget);
    },
  );

  testWidgets(
    'Given a link arrives mid-session, When consent is pushed, Then it carries the '
    'token that arrived',
    (tester) async {
      final (container, observer) = await _pump(tester);

      container.read(pendingInviteTokenProvider.notifier).state = 'W78LKADB';
      await tester.pumpAndSettle();

      final route = observer.pushed.firstWhere(
        (r) => r.settings.name == AppRoutes.inviteConsent,
      );
      expect((route.settings.arguments as InviteConsentArgs).token, 'W78LKADB');
    },
  );

  testWidgets(
    'Given consent has been pushed, When the token is cleared, Then a rebuild does not '
    'present the same invite twice',
    (tester) async {
      final (container, observer) = await _pump(tester);

      container.read(pendingInviteTokenProvider.notifier).state = 'K7M2QP4X';
      await tester.pumpAndSettle();
      // A second frame stands in for any unrelated rebuild of the app shell.
      await tester.pump();

      expect(
        observer.names.where((n) => n == AppRoutes.inviteConsent).length,
        1,
      );
      expect(container.read(pendingInviteTokenProvider), isNull);
    },
  );

  testWidgets(
    'Given the reader is signed out, When a link arrives, Then the token is kept rather '
    'than spent',
    (tester) async {
      // `redeem_invite()` answers `not_signed_in` without a session, so redeeming here
      // would burn the sender's link for nothing. `AuthPage` picks it up on the far
      // side of sign-in — so the token must still be there.
      final (container, observer) = await _pump(
        tester,
        status: AuthStatus.unauthenticated,
      );

      container.read(pendingInviteTokenProvider.notifier).state = 'K7M2QP4X';
      await tester.pumpAndSettle();

      expect(observer.names, isNot(contains(AppRoutes.inviteConsent)));
      expect(
        container.read(pendingInviteTokenProvider),
        'K7M2QP4X',
        reason: 'the token must survive for the post-sign-in handoff',
      );
    },
  );

  testWidgets(
    'Given a token already present at first build, When the listener mounts, Then it '
    'does not fire and leaves the cold-start case to the splash page',
    (tester) async {
      // A cold start puts the token in the provider before `runApp`, and `SplashPage`
      // owns that case — it must push consent *onto* the library, which does not exist
      // yet at this point. `ref.listen` cannot fire for a pre-existing value, and this
      // asserts that the two paths therefore cannot double-present.
      final navigatorKey = GlobalKey<NavigatorState>();
      final observer = _Recorder();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _Auth(AuthStatus.authenticated)),
          pendingInviteTokenProvider.overrideWith((ref) => 'K7M2QP4X'),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: [observer],
            builder: (context, child) =>
                InviteLinkListener(navigatorKey: navigatorKey, child: child!),
            home: const Scaffold(body: Text('LIBRARY')),
            routes: {
              AppRoutes.inviteConsent: (_) =>
                  const Scaffold(body: Text('CONSENT')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(observer.names, isNot(contains(AppRoutes.inviteConsent)));
    },
  );
}
