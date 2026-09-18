// Where a sign-in lands when an invite is waiting.
//
// One arrival, and one only: a **tapped link** held across the OAuth round trip, which
// goes straight to consent. It is pushed *onto* the library rather than replacing it, so
// dismissing consent leaves the reader on their own shelf instead of an empty navigator.
//
// **There is no typed-code path any more**, and the last case here is the guard for that.
// A screen offered once per install used to catch the landing page's clipboard handoff;
// it is gone, because eight characters a reader types is the shape a referral code will
// want and the two must not share an input. The cost is the deferred tier: a reader who
// installs from the landing page and opens the app cold has no invite until they tap the
// link again.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/invite_link_provider.dart';
import 'package:bookworm_friends/ui/pages/auth_page.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';

/// Reports "already signed in" from the first frame.
///
/// A real sign-in cannot be driven here — it needs Supabase — and the case that matters
/// is the one `AuthPage.initState` exists for anyway: the session can complete *before*
/// the page mounts, so the state is read on mount as well as listened to.
class _SignedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(status: AuthStatus.authenticated);
}

/// Records where the app navigated, without building the real destinations —
/// `HomePage` needs Supabase and `InviteConsentPage` needs a profile.
class _Recorder extends NavigatorObserver {
  final pushed = <String?>[];
  final replaced = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) =>
      pushed.add(route.settings.name);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      replaced.add(newRoute?.settings.name);
}

Future<_Recorder> _pump(
  WidgetTester tester, {
  required String? pendingToken,
}) async {
  final observer = _Recorder();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pendingInviteTokenProvider.overrideWith((ref) => pendingToken),
        authProvider.overrideWith(_SignedIn.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [observer],
        home: const AuthPage(),
        // Stubs, so the observer can record a name without the real page's
        // dependencies being satisfied.
        routes: {
          AppRoutes.home: (_) => const Scaffold(body: Text('LIBRARY')),
          AppRoutes.inviteConsent: (_) => const Scaffold(body: Text('CONSENT')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return observer;
}

void main() {
  testWidgets(
    'Given a token held across sign-in, When the library is reached, Then consent is '
    'pushed onto it rather than replacing it',
    (tester) async {
      final observer = await _pump(tester, pendingToken: 'K7M2QP4X');

      expect(observer.replaced, contains(AppRoutes.home));
      expect(observer.pushed, contains(AppRoutes.inviteConsent));
      // Dismissing consent has to leave the reader somewhere real.
      expect(find.text('CONSENT'), findsOneWidget);
    },
  );

  testWidgets(
    'Given the token reached consent, When it is handed over, Then it is the one from '
    'the link',
    (tester) async {
      await _pump(tester, pendingToken: 'K7M2QP4X');

      final route = ModalRoute.of(tester.element(find.text('CONSENT')))!;
      final args = route.settings.arguments as InviteConsentArgs;
      expect(args.token, 'K7M2QP4X');
    },
  );

  testWidgets(
    'Given the token was spent, When the page rebuilds, Then consent is not presented '
    'a second time',
    (tester) async {
      final observer = await _pump(tester, pendingToken: 'K7M2QP4X');

      await tester.pump();
      expect(
        observer.pushed.where((r) => r == AppRoutes.inviteConsent).length,
        1,
        reason: 'the token is cleared before the push for exactly this reason',
      );
    },
  );

  testWidgets(
    'Given no link, When a sign-in completes, Then the reader is left on their library '
    'with nothing asked of them',
    (tester) async {
      final observer = await _pump(tester, pendingToken: null);

      expect(observer.replaced, contains(AppRoutes.home));
      expect(find.text('LIBRARY'), findsOneWidget);
      expect(
        observer.pushed,
        isNot(contains(AppRoutes.inviteConsent)),
        reason: 'there is no token to consent to',
      );
    },
  );

  testWidgets(
    'Given a sign-in with no link, When the landing is inspected, Then no invite-code '
    'screen exists to be pushed',
    (tester) async {
      await _pump(tester, pendingToken: null);

      // The route is gone from the table, so a regression that re-added the push would
      // throw on an unknown name rather than quietly showing a signup step. Asserting
      // the absence directly says why.
      expect(
        AppRoutes.routes.keys,
        isNot(contains('/invite_code')),
        reason: 'a typed code is the shape a referral code will want',
      );
    },
  );
}
