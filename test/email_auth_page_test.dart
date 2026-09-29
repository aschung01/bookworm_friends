// The email form: three modes, two phases, and the things it must not say.
//
// `AuthNotifier` is replaced wholesale rather than stubbed around, for the reason
// `auth_page_navigation_test.dart` gives: its real `build()` reaches for
// `Supabase.instance`, which no widget test initialises.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/ui/pages/email_auth_page.dart';

/// Records what the page asked for, and answers however a case needs.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier({
    this.signUpOutcome = EmailSignUpOutcome.confirmationSent,
    this.throws,
  });

  final EmailSignUpOutcome signUpOutcome;
  final Object? throws;

  final signIns = <({String email, String password})>[];
  final signUps = <({String email, String password})>[];
  final resets = <String>[];

  @override
  AuthState build() => const AuthState.unauthenticated();

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    signIns.add((email: email, password: password));
    if (throws != null) throw throws!;
  }

  @override
  Future<EmailSignUpOutcome> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    signUps.add((email: email, password: password));
    if (throws != null) throw throws!;
    return signUpOutcome;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    resets.add(email);
    if (throws != null) throw throws!;
  }
}

/// A real surface size rather than `flutter_test`'s 800x600 default.
///
/// That default is **shorter than any phone the app supports**, which is the trap
/// `streak_celebration_test.dart` records. Here the point is the opposite one: this page
/// scrolls, so it has to survive a short surface *with the keyboard up* \u2014 see the last
/// group.
const Size _kPhone = Size(375, 667);

Future<_FakeAuthNotifier> _pump(
  WidgetTester tester, {
  _FakeAuthNotifier? notifier,
  double bottomInset = 0,
}) async {
  final fake = notifier ?? _FakeAuthNotifier();
  await tester.binding.setSurfaceSize(_kPhone);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(() => fake)],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: _kPhone,
            viewInsets: EdgeInsets.only(bottom: bottomInset),
          ),
          child: const EmailAuthPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

AppLocalizations get _l10n => lookupAppLocalizations(const Locale('en'));

Future<void> _fill(
  WidgetTester tester, {
  String email = 'reader@example.com',
  String? password = 'hunter2!',
}) async {
  await tester.enterText(find.byKey(kEmailFieldKey), email);
  if (password != null) {
    await tester.enterText(find.byKey(kPasswordFieldKey), password);
  }
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(kEmailAuthSubmitKey));
  await tester.pumpAndSettle();
}

void main() {
  group('signing in', () {
    testWidgets(
      'Given an email and password, When it is submitted, Then the pair reaches the '
      'notifier',
      (tester) async {
        final fake = await _pump(tester);
        await _fill(tester);
        await _submit(tester);

        expect(fake.signIns, [
          (email: 'reader@example.com', password: 'hunter2!'),
        ]);
        expect(
          fake.signUps,
          isEmpty,
          reason: 'sign-in is the mode the page opens in',
        );
      },
    );

    testWidgets(
      'Given an address with stray whitespace, When it is submitted, Then it is trimmed '
      'before it is sent',
      (tester) async {
        // A keyboard's autocapitalised space after an address is the common way this
        // happens, and gotrue answers `validation_failed` for it \u2014 an error the reader
        // cannot see the cause of, because the space is invisible.
        final fake = await _pump(tester);
        await _fill(tester, email: '  reader@example.com ');
        await _submit(tester);

        expect(fake.signIns.single.email, 'reader@example.com');
      },
    );

    testWidgets(
      'Given the page never navigates itself, When a sign-in succeeds, Then it is still '
      'showing',
      (tester) async {
        // It must not pop: a session reaches `AuthPage` underneath, which clears the whole
        // stack including this page. Popping here as well would race that, and the loser
        // would leave the reader on a dead screen.
        await _pump(tester);
        await _fill(tester);
        await _submit(tester);

        expect(find.byType(EmailAuthPage), findsOneWidget);
      },
    );
  });

  group('validation happens before the network does', () {
    testWidgets(
      'Given an address with no @, When it is submitted, Then nothing is sent and the '
      'field says why',
      (tester) async {
        final fake = await _pump(tester);
        await _fill(tester, email: 'reader.example.com');
        await _submit(tester);

        expect(fake.signIns, isEmpty);
        expect(find.text(_l10n.emailAuthEmailRequired), findsOneWidget);
      },
    );

    testWidgets(
      'Given a password under the minimum, When it is submitted, Then nothing is sent',
      (tester) async {
        // Client-side only so the reader is not sent on a round trip to be told. The server
        // still enforces it and answers `weak_password`, which is a different message.
        final fake = await _pump(tester);
        await _fill(tester, password: 'short');
        await _submit(tester);

        expect(fake.signIns, isEmpty);
        expect(find.text(_l10n.emailAuthPasswordTooShort), findsOneWidget);
      },
    );

    testWidgets(
      'Given the minimum exactly, When it is submitted, Then it is accepted',
      (tester) async {
        final fake = await _pump(tester);
        await _fill(tester, password: '123456');
        await _submit(tester);

        expect(
          fake.signIns,
          hasLength(1),
          reason: 'the bound is Supabase\'s own default, and it is inclusive',
        );
      },
    );
  });

  group('signing up', () {
    testWidgets(
      'Given the sign-up mode, When it is submitted, Then sign-up is called and sign-in '
      'is not',
      (tester) async {
        final fake = await _pump(tester);
        await tester.tap(find.text(_l10n.emailAuthToSignUp));
        await tester.pumpAndSettle();
        await _fill(tester);
        await _submit(tester);

        expect(fake.signUps, hasLength(1));
        expect(fake.signIns, isEmpty);
      },
    );

    testWidgets(
      'Given confirmation is on, When a sign-up returns no session, Then the page asks the '
      'reader to check their inbox',
      (tester) async {
        await _pump(tester);
        await tester.tap(find.text(_l10n.emailAuthToSignUp));
        await tester.pumpAndSettle();
        await _fill(tester, email: 'reader@example.com');
        await _submit(tester);

        expect(find.text(_l10n.emailAuthCheckInbox), findsOneWidget);
        // The address is named, because a typo in it is the likeliest reason no mail
        // arrives and this is the last moment it is on screen.
        expect(
          find.text(_l10n.emailAuthConfirmSent('reader@example.com')),
          findsOneWidget,
        );
        expect(find.byKey(kPasswordFieldKey), findsNothing);
      },
    );

    testWidgets('Given an address that already has an account, When it is submitted, Then the page '
        'still says check your inbox', (tester) async {
      // **The assertion that matters most on this page.** Supabase's email-enumeration
      // protection returns an indistinguishable response for an existing address, so
      // "check your inbox" is the honest answer for both. A branch that said "that email
      // is taken" would confirm who has an account — and would be easy to add in good
      // faith while making the form friendlier.
      await _pump(
        tester,
        notifier: _FakeAuthNotifier(
          signUpOutcome: EmailSignUpOutcome.confirmationSent,
        ),
      );
      await tester.tap(find.text(_l10n.emailAuthToSignUp));
      await tester.pumpAndSettle();
      await _fill(tester, email: 'someone@example.com');
      await _submit(tester);

      // Word for word what a brand-new address gets. Comparing against the same key is
      // what makes this a test about indistinguishability rather than about phrasing.
      expect(find.text(_l10n.emailAuthCheckInbox), findsOneWidget);
      expect(
        find.text(_l10n.emailAuthConfirmSent('someone@example.com')),
        findsOneWidget,
      );

      // And nothing anywhere on the page hints at the difference. Note the address must
      // not itself contain one of these words: an earlier draft used `taken@example.com`,
      // and since the sentence echoes the address back, the case failed on its own
      // fixture rather than on the behaviour.
      for (final leak in const [
        'already',
        'taken',
        'in use',
        'exists',
        'registered',
      ]) {
        expect(
          find.textContaining(leak, findRichText: true),
          findsNothing,
          reason: 'saying "$leak" would confirm which addresses have accounts',
        );
      }
    });

    testWidgets(
      'Given confirmation is off on the project, When a session arrives immediately, Then '
      'the inbox screen is not shown',
      (tester) async {
        // There is nothing to wait for, and `AuthPage` is already leaving.
        await _pump(
          tester,
          notifier: _FakeAuthNotifier(
            signUpOutcome: EmailSignUpOutcome.signedIn,
          ),
        );
        await tester.tap(find.text(_l10n.emailAuthToSignUp));
        await tester.pumpAndSettle();
        await _fill(tester);
        await _submit(tester);

        expect(find.text(_l10n.emailAuthCheckInbox), findsNothing);
      },
    );
  });

  group('asking for a reset link', () {
    testWidgets(
      'Given the reset mode, When it is entered, Then the password field is gone',
      (tester) async {
        await _pump(tester);
        await tester.tap(find.text(_l10n.emailAuthForgot));
        await tester.pumpAndSettle();

        expect(find.byKey(kEmailFieldKey), findsOneWidget);
        expect(find.byKey(kPasswordFieldKey), findsNothing);
        expect(find.text(_l10n.emailAuthSendReset), findsOneWidget);
      },
    );

    testWidgets(
      'Given an address, When a reset is requested, Then the link is sent and the page '
      'says so',
      (tester) async {
        final fake = await _pump(tester);
        await tester.tap(find.text(_l10n.emailAuthForgot));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(kEmailFieldKey),
          'reader@example.com',
        );
        await _submit(tester);

        expect(fake.resets, ['reader@example.com']);
        expect(
          find.text(_l10n.emailAuthResetSent('reader@example.com')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Given reset is reached from sign-in, When the reader backs out, Then they return to '
      'sign-in rather than to sign-up',
      (tester) async {
        await _pump(tester);
        await tester.tap(find.text(_l10n.emailAuthForgot));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_l10n.emailAuthSignIn));
        await tester.pumpAndSettle();

        expect(find.byKey(kPasswordFieldKey), findsOneWidget);
        expect(find.text(_l10n.emailAuthForgot), findsOneWidget);
      },
    );

    testWidgets(
      'Given the sign-up mode, When it is shown, Then no reset link is offered',
      (tester) async {
        // Resetting a password for an account that does not exist yet is not a thing to
        // offer; it would send a link that cannot arrive.
        await _pump(tester);
        await tester.tap(find.text(_l10n.emailAuthToSignUp));
        await tester.pumpAndSettle();

        expect(find.text(_l10n.emailAuthForgot), findsNothing);
      },
    );
  });

  group('failures', () {
    testWidgets(
      'Given the server rejected the pair, When it is reported, Then the mapped sentence '
      'is on screen',
      (tester) async {
        await _pump(
          tester,
          notifier: _FakeAuthNotifier(
            throws: const AuthException(
              'Invalid login credentials',
              statusCode: '400',
              code: 'invalid_credentials',
            ),
          ),
        );
        await _fill(tester);
        await _submit(tester);

        expect(find.text(_l10n.emailAuthInvalidCredentials), findsOneWidget);
      },
    );

    testWidgets(
      'Given a failure was shown, When the reader switches mode, Then the stale message is '
      'cleared',
      (tester) async {
        // "That email and password don't match" left standing above a lone email field
        // describes a form that is no longer on screen.
        await _pump(
          tester,
          notifier: _FakeAuthNotifier(
            throws: const AuthException(
              'Invalid login credentials',
              statusCode: '400',
              code: 'invalid_credentials',
            ),
          ),
        );
        await _fill(tester);
        await _submit(tester);
        expect(find.text(_l10n.emailAuthInvalidCredentials), findsOneWidget);

        await tester.tap(find.text(_l10n.emailAuthForgot));
        await tester.pumpAndSettle();

        expect(find.text(_l10n.emailAuthInvalidCredentials), findsNothing);
      },
    );

    testWidgets(
      'Given a failure, When it is shown, Then the form is still usable',
      (tester) async {
        // The `finally` that clears `_busy` has to run on the error path too, or one bad
        // password locks the form for good.
        final fake = _FakeAuthNotifier(
          throws: const AuthException(
            'nope',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        );
        await _pump(tester, notifier: fake);
        await _fill(tester);
        await _submit(tester);
        await _submit(tester);

        expect(fake.signIns, hasLength(2));
      },
    );
  });

  group('the keyboard', () {
    testWidgets(
      'Given the shortest supported phone with the keyboard up, When the form is shown, '
      'Then nothing overflows',
      (tester) async {
        // **This is the case that justifies the page existing at all.** Inline on
        // `AuthPage` \u2014 a centred `Column` with no scroll view \u2014 this content with a
        // keyboard raised is the `RenderFlex` overflow the streak celebration is recorded
        // hitting at exactly this size.
        await _pump(tester, bottomInset: 336);

        expect(tester.takeException(), isNull);
        expect(find.byKey(kEmailFieldKey), findsOneWidget);
      },
    );

    testWidgets(
      'Given the keyboard is up, When the submit button is reached, Then it can be '
      'scrolled to',
      (tester) async {
        await _pump(tester, bottomInset: 336);

        await tester.ensureVisible(find.byKey(kEmailAuthSubmitKey));
        await tester.pumpAndSettle();

        expect(find.byKey(kEmailAuthSubmitKey), findsOneWidget);
      },
    );
  });
}
