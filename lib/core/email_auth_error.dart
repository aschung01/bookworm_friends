import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'package:bookworm_friends/l10n/app_localizations.dart';

/// The one gotrue failure that is not a server code.
///
/// Under PKCE the code verifier is written to local storage by the client that *made* the
/// request, so a reset link opened on a different device reaches `exchangeCodeForSession`
/// with nothing to pair the code against. gotrue throws a plain [AuthException] whose
/// `code` is null and whose message is this sentence, so matching the message is the only
/// handle there is.
///
/// Matched as a substring and lower-cased at the call site, because it is prose rather than
/// an identifier and could gain punctuation in a later release. A miss is not a crash --
/// it falls through to the generic message.
const String kMissingCodeVerifierFragment = 'code verifier could not be found';

/// Turns whatever the email auth calls threw into a sentence a reader can act on.
///
/// **Pure, and in its own file for that reason.** Every branch is reachable from a unit
/// test with no widget pumped and no Supabase initialised, which matters because the
/// interesting cases here are the ones that are awkward to provoke against a live project
/// -- a rate limit, an unconfirmed address, a reset link opened on the wrong device.
///
/// Keyed on [AuthException.code] rather than `statusCode`. The HTTP status is 400 for most
/// of these, so it cannot separate a bad password from an unconfirmed address from a
/// malformed email -- three failures with three different remedies.
///
/// **There is deliberately no "no account with that email" branch.** It would be the most
/// helpful sentence available and it is the one thing not to write: it confirms which
/// addresses have accounts, which is what Supabase's email-enumeration protection exists to
/// withhold. `invalid_credentials` names the pair instead.
String emailAuthError(Object error, AppLocalizations l10n) {
  if (error is! AuthException) return l10n.emailAuthFailed;

  if (error.message.toLowerCase().contains(kMissingCodeVerifierFragment)) {
    return l10n.emailAuthWrongDevice;
  }

  return switch (error.code) {
    'invalid_credentials' ||
    // gotrue has used both spellings; matching one would make this depend on a
    // server-side rename nothing here would notice.
    'invalid_grant' => l10n.emailAuthInvalidCredentials,
    'email_not_confirmed' => l10n.emailAuthEmailNotConfirmed,
    'weak_password' => l10n.emailAuthWeakPassword,
    // Two distinct limits with one remedy: waiting. `over_email_send_rate_limit` is the
    // one a reader hits by tapping "send reset link" twice.
    'over_email_send_rate_limit' ||
    'over_request_rate_limit' => l10n.emailAuthTooManyRequests,
    'validation_failed' => l10n.emailAuthInvalidEmail,
    _ => l10n.emailAuthFailed,
  };
}
