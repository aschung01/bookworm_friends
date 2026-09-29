// The sentence a reader gets when an email auth call fails.
//
// **These are unit tests over a pure function, with no widget pumped and no Supabase
// initialised, and that is the reason `emailAuthError` is its own file.** The interesting
// failures here are precisely the ones that are awkward to provoke against a live project:
// a send-rate limit, an unconfirmed address, and a reset link opened on the wrong device.
// Against a real backend those are a waiting game, a mailbox and a second phone; here they
// are three constructor calls.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'package:bookworm_friends/core/email_auth_error.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';

/// Real localisations rather than a stub, so a key deleted from the ARB breaks these cases
/// rather than passing against a fake that still defines it.
final _en = lookupAppLocalizations(const Locale('en'));
final _ko = lookupAppLocalizations(const Locale('ko'));

/// Most of these arrive as a 400, which is exactly why the mapper reads `code` instead.
AuthException _exception(String code) => AuthException(
  'server prose nobody should read',
  statusCode: '400',
  code: code,
);

void main() {
  group('a failure a reader can act on', () {
    test('Given a bad email/password pair, When it is mapped, Then it names the pair rather '
        'than either half', () {
      final message = emailAuthError(_exception('invalid_credentials'), _en);

      expect(message, _en.emailAuthInvalidCredentials);
      // The guard that matters here is a negative one: a sentence naming the *email*
      // specifically would confirm which addresses have accounts, which is what
      // Supabase's email-enumeration protection exists to withhold.
      expect(message.toLowerCase(), isNot(contains('no account')));
    });

    test(
      'Given gotrue used its other spelling for the same failure, When it is mapped, Then '
      'the reader sees the same sentence',
      () {
        // Both spellings have shipped. Matching only one would make the message depend on
        // a server-side rename that nothing in this app would notice.
        expect(
          emailAuthError(_exception('invalid_grant'), _en),
          emailAuthError(_exception('invalid_credentials'), _en),
        );
      },
    );

    test(
      'Given the address was never confirmed, When it is mapped, Then it points at the '
      'inbox rather than at the password',
      () {
        final message = emailAuthError(_exception('email_not_confirmed'), _en);

        expect(message, _en.emailAuthEmailNotConfirmed);
        expect(
          message,
          isNot(_en.emailAuthInvalidCredentials),
          reason:
              'both arrive as a 400, so a mapper keyed on statusCode would send a reader '
              'who only needs to tap a link off to re-check their password',
        );
      },
    );

    test(
      'Given a password the server refused, When it is mapped, Then it asks for a '
      'longer one',
      () {
        expect(
          emailAuthError(_exception('weak_password'), _en),
          _en.emailAuthWeakPassword,
        );
      },
    );

    test('Given either rate limit, When it is mapped, Then both say to wait', () {
      // Two distinct codes with one remedy. `over_email_send_rate_limit` is the one a
      // reader hits by tapping "send reset link" twice.
      expect(
        emailAuthError(_exception('over_email_send_rate_limit'), _en),
        _en.emailAuthTooManyRequests,
      );
      expect(
        emailAuthError(_exception('over_request_rate_limit'), _en),
        _en.emailAuthTooManyRequests,
      );
    });

    test('Given a malformed address, When it is mapped, Then it says so', () {
      expect(
        emailAuthError(_exception('validation_failed'), _en),
        _en.emailAuthInvalidEmail,
      );
    });
  });

  group('the failure that is not a server code', () {
    test('Given a reset link opened on another device, When it is mapped, Then it says which '
        'device to use', () {
      // Under PKCE the code verifier is written to local storage by the client that made
      // the request, so a link opened elsewhere reaches the exchange with nothing to pair
      // the code against. gotrue throws with a null `code` and this prose, so the message
      // is the only handle there is.
      const thrown = AuthException(
        'Code verifier could not be found in local storage.',
      );

      final message = emailAuthError(thrown, _en);

      expect(message, _en.emailAuthWrongDevice);
      expect(
        message,
        isNot(_en.emailAuthFailed),
        reason:
            'falling through to the generic sentence would read as a broken link rather '
            'than as a link opened in the wrong place',
      );
    });

    test('Given the prose gains punctuation or a capital, When it is mapped, Then it still '
        'lands on the device message', () {
      // Prose, not an identifier: matched as a lower-cased substring so a reworded
      // release degrades to the generic message instead of crashing, and a merely
      // re-punctuated one keeps working.
      expect(
        emailAuthError(
          const AuthException(
            'PKCE: Code Verifier could not be found -- aborting!',
          ),
          _en,
        ),
        _en.emailAuthWrongDevice,
      );
    });
  });

  group('everything else', () {
    test(
      'Given an unrecognised code, When it is mapped, Then the reader still gets a '
      'sentence',
      () {
        expect(
          emailAuthError(_exception('teapot_on_fire'), _en),
          _en.emailAuthFailed,
        );
      },
    );

    test(
      'Given a code-less exception, When it is mapped, Then the reader still gets a '
      'sentence',
      () {
        expect(
          emailAuthError(const AuthException('nothing useful'), _en),
          _en.emailAuthFailed,
        );
      },
    );

    test('Given something that is not an AuthException at all, When it is mapped, Then it '
        'does not throw', () {
      // The page hands this whatever `catch` caught, which on a dropped connection is a
      // `SocketException` and on a bug is a `TypeError`. A mapper that threw here would
      // replace a bad message with a red screen.
      expect(emailAuthError(Exception('offline'), _en), _en.emailAuthFailed);
      expect(emailAuthError('a bare string', _en), _en.emailAuthFailed);
    });
  });

  test(
    'Given the Korean locale, When a failure is mapped, Then it is answered in Korean',
    () {
      // Cheap, and it pins that every branch reads a real ARB key in both locales rather
      // than an English literal that happens to be spelled like one.
      expect(
        emailAuthError(_exception('invalid_credentials'), _ko),
        _ko.emailAuthInvalidCredentials,
      );
      expect(
        emailAuthError(_exception('invalid_credentials'), _ko),
        isNot(_en.emailAuthInvalidCredentials),
      );
    },
  );
}
