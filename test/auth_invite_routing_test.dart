// Where a sign-in lands when an invite is waiting.
//
// Two arrivals, and they must not collide:
//
//   * a **tapped link** held across the OAuth round trip -> straight to consent, and
//     the code screen is suppressed because the token has already been used;
//   * **no link** -> the code screen once, because the reader may have installed from
//     the landing page with a token sitting on their clipboard.
//
// Both are pushed *onto* the library rather than replacing it, so dismissing either
// leaves the reader on their own shelf instead of an empty navigator.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/invite_code_prompt_provider.dart';
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
  bool promptAlreadyShown = false,
}) async {
  SharedPreferences.setMockInitialValues(
    promptAlreadyShown ? {kInviteCodePromptPrefKey: true} : {},
  );
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
          AppRoutes.inviteCode: (_) => const Scaffold(body: Text('CODE')),
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
    'Given a token arrived by link, When consent is shown, Then the code screen is '
    'never also offered',
    (tester) async {
      final observer = await _pump(tester, pendingToken: 'K7M2QP4X');

      expect(
        observer.pushed,
        isNot(contains(AppRoutes.inviteCode)),
        reason:
            'the reader has already spent a token; asking for a code repeats it',
      );
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
    'Given no link, When a first sign-in completes, Then the code screen is offered as '
    'the clipboard handoff\'s landing point',
    (tester) async {
      final observer = await _pump(tester, pendingToken: null);

      expect(observer.pushed, contains(AppRoutes.inviteCode));
      expect(observer.pushed, isNot(contains(AppRoutes.inviteConsent)));
    },
  );

  testWidgets(
    'Given the code screen was already offered once, When signing in again, Then it is '
    'not offered a second time',
    (tester) async {
      final observer = await _pump(
        tester,
        pendingToken: null,
        promptAlreadyShown: true,
      );

      expect(observer.pushed, isNot(contains(AppRoutes.inviteCode)));
      expect(find.text('LIBRARY'), findsOneWidget);
    },
  );
}
