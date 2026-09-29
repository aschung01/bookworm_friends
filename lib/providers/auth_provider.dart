import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// `supabase_flutter` exports an `AuthState` of its own -- the auth stream's
// event type -- which the class below shadows. Aliased so the stream handler can
// still name it.
import 'package:supabase_flutter/supabase_flutter.dart'
    as gotrue
    show AuthState;
import 'package:url_launcher/url_launcher.dart' show closeInAppWebView;

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Where both email flows send the reader back to.
///
/// **The same URL OAuth already uses, and reusing it is a decision rather than a
/// shortcut.** A confirmation link and a recovery link are both exchanged by the observer
/// `Supabase.initialize` starts, and gotrue tells the two apart from an event name it
/// stashed beside the PKCE verifier (`resetPasswordForEmail` writes
/// `'$codeVerifier/passwordRecovery'`; the exchange replays it) -- **not** from anything
/// in the URL.
///
/// So a distinct path like `bookworm-friends://reset-password` would be the obvious
/// spelling and the wrong one: it implies something in this app parses the callback, and
/// the only component that could is a second `app_links` subscriber -- the race
/// `main.dart` and `invite_link_service.dart` both exist to warn about. It also means the
/// project's redirect allow list needs no new entry.
const String kAuthRedirect = 'bookworm-friends://home';

/// What [AuthNotifier.signUpWithEmail] found on the far side of a sign-up.
///
/// **A returned value rather than a thrown error or a bare `void`**, because with email
/// confirmation on there are *two* successes -- a session now, or a mail sent -- and an
/// exception cannot carry that distinction while `void` erases it. The page renders a
/// different phase for each.
enum EmailSignUpOutcome {
  /// No session. A confirmation link is in the reader's inbox.
  confirmationSent,

  /// A session arrived immediately, which is what happens with confirmation off.
  signedIn,
}

class AuthState {
  final AuthStatus status;
  final User? user;

  /// True between a tapped reset link and the new password being saved.
  ///
  /// **Not a fourth [AuthStatus], and that is the whole design.** A recovery session is a
  /// real session, and `status == AuthStatus.authenticated` is read in four places --
  /// `auth_page`, `splash_page`, `settings_page`, `invite_link_listener`. A new status
  /// would change the answer for all four; a flag changes it for none, so nothing
  /// downstream learns this feature exists.
  ///
  /// **State rather than a one-shot notification**, because the exchange can complete
  /// before any listener is mounted -- the same race `AuthPage.initState` documents, and
  /// the reason `InviteLinkListener` hands the cold-start case to `SplashPage`. Persisting
  /// it is what lets `PasswordRecoveryListener` catch it with a post-frame read.
  final bool recovering;

  const AuthState({required this.status, this.user, this.recovering = false});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.authenticated(User user)
    : this(status: AuthStatus.authenticated, user: user);
  const AuthState.unauthenticated() : this(status: AuthStatus.unauthenticated);

  /// Signed in, but only as far as choosing a new password.
  const AuthState.passwordRecovery(User user)
    : this(status: AuthStatus.authenticated, user: user, recovering: true);
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Registered unconditionally. Subscribing only when there was no session at
    // startup meant that whenever one *was* restored, nothing afterwards was
    // ever observed -- not a later sign-out, not a refresh.
    final subscription = supabase.auth.onAuthStateChange.listen(
      _apply,
      // gotrue pushes auth failures onto this stream (a PKCE code exchange that
      // lost a race, a refresh that could not reach the server). It has already
      // logged them; without a handler here they surface as unhandled zone
      // errors instead.
      onError: (Object _, StackTrace __) {},
    );
    ref.onDispose(subscription.cancel);

    final session = supabase.auth.currentSession;
    if (session != null) {
      // **Not left to the `initialSession` event.** `onAuthStateChange` is a plain
      // broadcast stream with no replay, and `Supabase.initialize` has already
      // recovered the session -- and emitted for it -- by the time anything first
      // reads this provider. Whether the listener above is attached before or after
      // that emission is a race decided by which widget reads `authProvider` first,
      // so the event cannot be relied on to arrive for an already-signed-in reader.
      //
      // Registering here covers the restored-session case directly. The event branch
      // in `_apply` still covers a fresh sign-in. If both happen to fire, the cost is
      // one redundant idempotent UPDATE, which is a better trade than the write being
      // skipped -- which is the bug this whole change exists to fix.
      unawaited(NotificationService.registerToken());
    }
    return session == null
        ? const AuthState.unauthenticated()
        : AuthState.authenticated(session.user);
  }

  /// Mirrors how `supabase_flutter` itself reads the stream: a session on the
  /// event means signed in, whatever the event is called. Matching on
  /// [AuthChangeEvent.signedIn] alone dropped `initialSession` (the event a
  /// session recovered during startup arrives on) and `tokenRefreshed`.
  void _apply(gotrue.AuthState data) {
    final session = data.session;

    if (session == null) {
      if (data.event == AuthChangeEvent.signedOut) {
        state = const AuthState.unauthenticated();
      }
      return;
    }

    final wasSignedOut = state.status != AuthStatus.authenticated;

    if (data.event == AuthChangeEvent.passwordRecovery) {
      // A tapped reset link. Still a full session -- see [AuthState.recovering] on why
      // this is a flag and not a status.
      state = AuthState.passwordRecovery(session.user);
    } else {
      // **`recovering` is carried across rather than cleared.** `tokenRefreshed` fires
      // roughly hourly for the life of a session, so clearing here would silently drop
      // the flag part-way through a recovery and leave `PasswordRecoveryListener` with
      // nothing to find on a later post-frame read. Only `updatePassword`,
      // `dismissRecovery` and signing out end a recovery.
      state = AuthState(
        status: AuthStatus.authenticated,
        user: session.user,
        recovering: state.recovering,
      );
    }

    // **Push registration is driven off the event, not off the state transition.**
    // `build()` returns `authenticated` when a session already exists, and the
    // recovered session's `initialSession` event arrives *after* that -- so
    // `wasSignedOut` is false for precisely the readers who were already signed in,
    // which is every returning user. Gating the token write on it meant only a
    // brand-new sign-in ever attempted one, and on iOS that is the single moment the
    // attempt is guaranteed to fail (see `PushTokenRegistrar`). Between them, those
    // two facts are why `profiles.fcm_token` was NULL for every row in production.
    //
    // `tokenRefreshed` is deliberately not in this set: it fires roughly hourly for
    // the life of the session and the token it refreshes is Supabase's, not FCM's.
    // FCM rotation is handled by `PushTokenRegistrar.watchRefreshes`.
    if (data.event == AuthChangeEvent.initialSession ||
        data.event == AuthChangeEvent.signedIn) {
      unawaited(NotificationService.registerToken());
    }

    if (!wasSignedOut) return;

    // The OAuth screen is an in-app browser (`SFSafariViewController` on iOS).
    // The provider's redirect back to `bookworm-friends://` reaches the app but
    // does not dismiss the browser, which is left sitting blank on top of it.
    closeInAppWebView();
  }

  Future<void> signInWithGoogle() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kAuthRedirect,
      // Signing out clears our session, not Google's cookie -- that lives in the
      // cookie jar the in-app browser shares with Safari. Without this, Google
      // sees one already-signed-in account with consent granted and approves
      // silently, so signing out and back in lands on the same account with no
      // chance to pick another.
      queryParams: const {'prompt': 'select_account'},
    );
  }

  Future<void> signInWithApple() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: kAuthRedirect,
    );
  }

  /// Creates an account, and reports which of the two successes happened.
  ///
  /// **Never reports that an address is already taken, and cannot.** Supabase's
  /// email-enumeration protection returns a deliberately indistinguishable response for an
  /// address that already has an account, so [EmailSignUpOutcome.confirmationSent] is the
  /// honest answer for both. Reading `user.identities.isEmpty` is the documented tell and
  /// is ambiguous by design; the page shows "check your inbox" either way.
  Future<EmailSignUpOutcome> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: kAuthRedirect,
    );
    return response.session == null
        ? EmailSignUpOutcome.confirmationSent
        : EmailSignUpOutcome.signedIn;
  }

  /// Signs in with an email and password.
  ///
  /// Throws [AuthException] on a bad pair, an unconfirmed address or a rate limit. The
  /// caller maps it -- see `emailAuthError` -- because only the caller has an
  /// [AppLocalizations] to map it into.
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await supabase.auth.signInWithPassword(email: email, password: password);
  }

  /// Mails a link that lands back here as [AuthChangeEvent.passwordRecovery].
  ///
  /// Sent for any address, including one with no account, for the same reason
  /// [signUpWithEmail] cannot report a collision: answering differently would confirm who
  /// has an account.
  Future<void> sendPasswordReset(String email) async {
    await supabase.auth.resetPasswordForEmail(email, redirectTo: kAuthRedirect);
  }

  /// Writes a new password and ends the recovery.
  ///
  /// The flag is cleared from the current state rather than by rebuilding it from the
  /// response, so a `userUpdated` event arriving first cannot resurrect it.
  Future<void> updatePassword(String password) async {
    await supabase.auth.updateUser(UserAttributes(password: password));
    state = AuthState(
      status: state.status,
      user: supabase.auth.currentUser ?? state.user,
    );
  }

  /// Ends a recovery without changing anything.
  ///
  /// The reader dismissed the screen, which leaves them signed in with their old password
  /// -- which is exactly what the session is. Without this the listener would re-present
  /// the screen on the next rebuild that read the flag.
  void dismissRecovery() {
    if (!state.recovering) return;
    state = AuthState(status: state.status, user: state.user);
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
    state = const AuthState.unauthenticated();
  }

  Future<bool> deleteAccount() async {
    try {
      await supabase.functions.invoke('delete-account');
      await supabase.auth.signOut();
      state = const AuthState.unauthenticated();
      return true;
    } catch (e) {
      return false;
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authProvider);
  return auth.user?.id;
});
