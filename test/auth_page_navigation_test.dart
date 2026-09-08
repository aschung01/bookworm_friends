// The sign-in page has to leave for the library on a state change it may never
// witness.
//
// `ref.listen` alone cannot do that. An OAuth deep link is exchanged
// asynchronously, and `SplashPage` waits a fixed 500ms before it reads the auth
// state, so a sign-in can complete in the window before this page is even built.
// A listener never fires for a change that already happened, so a user with a
// valid session was left looking at the sign-in buttons until the app was
// restarted -- which is exactly the bug these tests pin. The first case is the
// regression; the second exists so the first cannot pass tautologically.
//
// `AuthNotifier` is replaced wholesale rather than stubbed around: its real
// `build()` reaches for `Supabase.instance`, which no widget test initialises.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/ui/pages/auth_page.dart';

const _user = User(
  id: 'u',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2024-01-01T00:00:00Z',
);

/// A fresh instance per call on purpose. `AuthState` does not override `==`, so
/// two `const` signed-in states would be canonicalised to one object and
/// Riverpod would collapse the second notification -- which would quietly defeat
/// the "navigates once" test below.
AuthState _signedIn() =>
    AuthState(status: AuthStatus.authenticated, user: _user);

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._initial);

  final AuthState _initial;

  @override
  AuthState build() => _initial;

  void emit(AuthState next) => state = next;
}

/// Stands in for `HomePage`, which needs the whole provider graph. Only the fact
/// that the page leaves for [AppRoutes.home] is under test.
class _Library extends StatelessWidget {
  const _Library();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('library')));
}

/// Records every route the navigator arrives at, however it got there:
/// `pushReplacementNamed` reports `didReplace`, a plain push reports `didPush`.
class _RouteLog extends NavigatorObserver {
  final names = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    names.add(route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    names.add(newRoute?.settings.name);
  }
}

Future<_RouteLog> _pumpAuthPage(
  WidgetTester tester,
  _FakeAuthNotifier notifier,
) async {
  final log = _RouteLog();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        theme: AppTheme.light,
        navigatorObservers: [log],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: AppRoutes.auth,
        routes: {
          AppRoutes.auth: (_) => const AuthPage(),
          AppRoutes.home: (_) => const _Library(),
        },
      ),
    ),
  );
  return log;
}

int _arrivalsAtHome(_RouteLog log) =>
    log.names.where((name) => name == AppRoutes.home).length;

void main() {
  group('the sign-in page leaves for the library', () {
    testWidgets(
      'Given the session already arrived before the page was built, When it '
      'mounts, Then it leaves for the library instead of offering sign-in again',
      (tester) async {
        await _pumpAuthPage(tester, _FakeAuthNotifier(_signedIn()));
        await tester.pumpAndSettle();

        expect(find.byType(_Library), findsOneWidget);
        expect(
          find.byType(AuthPage),
          findsNothing,
          reason:
              'a signed-in user stranded on the sign-in buttons is the bug; '
              'the page must not survive its own auth state',
        );
      },
    );

    testWidgets(
      'Given no session, When the page mounts, Then the sign-in buttons stay put',
      (tester) async {
        final log = await _pumpAuthPage(
          tester,
          _FakeAuthNotifier(const AuthState.unauthenticated()),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AuthPage), findsOneWidget);
        expect(find.byType(_Library), findsNothing);
        expect(
          _arrivalsAtHome(log),
          0,
          reason:
              'without this the test above would pass on any page that '
              'navigates unconditionally',
        );
      },
    );

    testWidgets(
      'Given the page is showing, When a session arrives, Then it leaves for the '
      'library',
      (tester) async {
        final notifier = _FakeAuthNotifier(const AuthState.unauthenticated());
        await _pumpAuthPage(tester, notifier);
        await tester.pumpAndSettle();
        expect(find.byType(AuthPage), findsOneWidget);

        notifier.emit(_signedIn());
        await tester.pumpAndSettle();

        expect(find.byType(_Library), findsOneWidget);
      },
    );

    testWidgets(
      'Given two sign-in notifications in a row, When they are handled, Then the '
      'library is entered once',
      (tester) async {
        // The auth stream can report the same session more than once -- an
        // exchange followed by a refresh, say. Each one reaches the page, so the
        // page, not the stream, has to be the thing that only navigates once.
        final notifier = _FakeAuthNotifier(const AuthState.unauthenticated());
        final log = await _pumpAuthPage(tester, notifier);
        await tester.pumpAndSettle();

        notifier.emit(_signedIn());
        notifier.emit(_signedIn());
        await tester.pumpAndSettle();

        expect(_arrivalsAtHome(log), 1);
      },
    );
  });
}
