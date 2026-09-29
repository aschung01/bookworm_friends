// A tapped reset link, from the auth state through to the screen it presents.
//
// **The design under test is "recovery is a flag, and the screen is pushed on top".** The
// rejected alternative is the obvious one \u2014 teach `AuthPage._leaveIfSignedIn` to refuse to
// navigate while recovering \u2014 and it fails only on a cold start, where the link launches the
// app and `SplashPage` does the routing. The last group is the guard against it coming back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/ui/widgets/password_recovery_listener.dart';

const _user = User(
  id: 'u',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2024-01-01T00:00:00Z',
);

/// Lets a case drive the auth state directly.
///
/// The real `_apply` is fed by gotrue's stream, which no widget test has; what these cases
/// are about is what the rest of the app does with each resulting state, so the states are
/// produced by hand.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._initial);

  final AuthState _initial;

  @override
  AuthState build() => _initial;

  void emit(AuthState next) => state = next;

  int dismissals = 0;

  @override
  void dismissRecovery() {
    dismissals++;
    super.dismissRecovery();
  }
}

class _Log extends NavigatorObserver {
  final pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) =>
      pushed.add(route.settings.name);

  int get newPasswordPushes =>
      pushed.where((n) => n == AppRoutes.newPassword).length;
}

final _navigatorKey = GlobalKey<NavigatorState>();

/// Mounts the listener above a navigator, the way `main.dart` does.
///
/// `NewPasswordPage` is stubbed: the real one reaches `EasyLoading` and the notifier, and
/// what is under test here is only whether it gets presented.
Future<_Log> _pump(WidgetTester tester, _FakeAuthNotifier notifier) async {
  final log = _Log();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(() => notifier)],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: _navigatorKey,
        navigatorObservers: [log],
        builder: (context, child) => PasswordRecoveryListener(
          navigatorKey: _navigatorKey,
          child: child!,
        ),
        initialRoute: AppRoutes.home,
        routes: {
          AppRoutes.home: (_) => const Scaffold(body: Text('LIBRARY')),
          AppRoutes.newPassword: (_) =>
              const Scaffold(body: Text('SET PASSWORD')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return log;
}

void main() {
  group('the flag on the auth state', () {
    test(
      'Given a recovery, When the state is built, Then the reader still counts as signed in',
      () {
        // The session is real, and four places read `status == authenticated` \u2014 `auth_page`,
        // `splash_page`, `settings_page`, `invite_link_listener`. A fourth AuthStatus would
        // change the answer for all of them.
        const state = AuthState.passwordRecovery(_user);

        expect(state.status, AuthStatus.authenticated);
        expect(state.recovering, isTrue);
        expect(state.user, _user);
      },
    );

    test(
      'Given an ordinary sign-in, When the state is built, Then it is not recovering',
      () {
        expect(const AuthState.authenticated(_user).recovering, isFalse);
        expect(const AuthState.unauthenticated().recovering, isFalse);
        expect(const AuthState.unknown().recovering, isFalse);
      },
    );
  });

  group('presenting the screen', () {
    testWidgets(
      'Given a recovery arrives while the app is running, When it is seen, Then the '
      'set-password screen is pushed over the library',
      (tester) async {
        final notifier = _FakeAuthNotifier(
          const AuthState.authenticated(_user),
        );
        final log = await _pump(tester, notifier);
        expect(find.text('LIBRARY'), findsOneWidget);

        notifier.emit(const AuthState.passwordRecovery(_user));
        await tester.pumpAndSettle();

        expect(find.text('SET PASSWORD'), findsOneWidget);
        expect(log.newPasswordPushes, 1);
      },
    );

    testWidgets(
      'Given the library is underneath, When the screen is dismissed, Then the reader is '
      'left somewhere real',
      (tester) async {
        // Pushed onto the destination rather than replacing it \u2014 the rule
        // `_spendPendingInvite` and `_pushConsentIfPending` already follow.
        final notifier = _FakeAuthNotifier(
          const AuthState.authenticated(_user),
        );
        await _pump(tester, notifier);
        notifier.emit(const AuthState.passwordRecovery(_user));
        await tester.pumpAndSettle();

        _navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();

        expect(find.text('LIBRARY'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the link was exchanged before the app was built, When the listener mounts, '
      'Then it still presents',
      (tester) async {
        // **The cold-start case.** `Supabase.initialize` runs before `runApp`, so a link
        // that launches the app can emit `passwordRecovery` before any listener exists, and
        // `ref.listen` never fires for a change that already happened. This is why
        // `recovering` is persisted state and why `initState` reads it once.
        final log = await _pump(
          tester,
          _FakeAuthNotifier(const AuthState.passwordRecovery(_user)),
        );

        expect(find.text('SET PASSWORD'), findsOneWidget);
        expect(log.newPasswordPushes, 1);
      },
    );

    testWidgets(
      'Given the flag is still set, When an unrelated auth event arrives, Then a second '
      'copy is not stacked on the first',
      (tester) async {
        // `recovering` stays true for as long as the reader is on the screen, and a token
        // refresh fires roughly hourly. Without the `_presenting` guard each one would push
        // another copy.
        final notifier = _FakeAuthNotifier(
          const AuthState.authenticated(_user),
        );
        final log = await _pump(tester, notifier);

        notifier.emit(const AuthState.passwordRecovery(_user));
        await tester.pumpAndSettle();
        notifier.emit(const AuthState.passwordRecovery(_user));
        notifier.emit(const AuthState.passwordRecovery(_user));
        await tester.pumpAndSettle();

        expect(log.newPasswordPushes, 1);
      },
    );

    testWidgets(
      'Given no recovery, When the app runs, Then nothing is presented',
      (tester) async {
        // Without this the cases above would pass on a listener that pushed unconditionally.
        final notifier = _FakeAuthNotifier(
          const AuthState.authenticated(_user),
        );
        final log = await _pump(tester, notifier);

        notifier.emit(const AuthState.authenticated(_user));
        await tester.pumpAndSettle();

        expect(log.newPasswordPushes, 0);
        expect(find.text('LIBRARY'), findsOneWidget);
      },
    );

    testWidgets(
      'Given a second reset link in the same session, When it arrives after the first was '
      'dismissed, Then the screen is presented again',
      (tester) async {
        // The `_presenting` guard has to reopen, or a reader who dismissed once could never
        // reach the screen again without restarting the app.
        final notifier = _FakeAuthNotifier(
          const AuthState.authenticated(_user),
        );
        final log = await _pump(tester, notifier);

        notifier.emit(const AuthState.passwordRecovery(_user));
        await tester.pumpAndSettle();
        _navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();

        notifier.emit(const AuthState.authenticated(_user));
        notifier.emit(const AuthState.passwordRecovery(_user));
        await tester.pumpAndSettle();

        expect(log.newPasswordPushes, 2);
      },
    );
  });

  group('dismissing clears the flag', () {
    test(
      'Given a recovery, When it is dismissed, Then the reader stays signed in with their '
      'old password',
      () {
        // Which is exactly what the session is. A screen with no way out would be worse for
        // the reader who tapped the link by accident.
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              () => _FakeAuthNotifier(const AuthState.passwordRecovery(_user)),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(authProvider.notifier).dismissRecovery();
        final after = container.read(authProvider);

        expect(after.recovering, isFalse);
        expect(after.status, AuthStatus.authenticated);
        expect(after.user, _user);
      },
    );

    test(
      'Given no recovery, When dismiss is called, Then the state is left alone',
      () {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              () => _FakeAuthNotifier(const AuthState.authenticated(_user)),
            ),
          ],
        );
        addTearDown(container.dispose);

        final before = container.read(authProvider);
        container.read(authProvider.notifier).dismissRecovery();

        expect(container.read(authProvider), same(before));
      },
    );
  });
}
