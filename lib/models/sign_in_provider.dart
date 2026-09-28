/// Which sign-in doors an account actually has.
///
/// Split out of `settings_page.dart` so the rule can be tested without standing up
/// the whole settings screen, and because the field it reads is the easy one to get
/// wrong -- see [linkedSignInProviders].
library;

/// The providers linked to this account, oldest first, or empty if none can be read.
///
/// **Read `providers`, never `provider`.** GoTrue's `app_metadata.provider` names
/// whichever identity signed in *first* and then never changes, so it describes how
/// the account was opened rather than how it can be opened now: an account started on
/// Google that later links Apple still reports `"google"` for ever. `providers` is the
/// field that grows, and it is what tells the truth about a linked account.
///
/// That case is not hypothetical any more. Sign in with Apple attaches to an existing
/// account whenever Apple returns a verified email that already has one, rather than
/// opening a second -- which is the mechanism the 2022 users are being recovered
/// through -- so a single account holding both doors is now the *expected* shape, and
/// reading the singular field drew exactly one of the two.
///
/// [appMetadata] is `User.appMetadata`. Passed as a map rather than a `User` to keep
/// this file free of a Supabase import and to let a test describe an account as the
/// literal it is.
List<String> linkedSignInProviders(Map<String, dynamic>? appMetadata) {
  if (appMetadata == null) return const [];

  final providers = appMetadata['providers'];
  if (providers is List) {
    final names = providers
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isNotEmpty) return names;
  }

  // Fall back to the singular field for anything that predates `providers` or never
  // gained it. An account with one door reports it in both places, so this loses
  // nothing; it only matters for a session old enough to be missing the list.
  final single = appMetadata['provider'];
  return single is String && single.isNotEmpty ? [single] : const [];
}
