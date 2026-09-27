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

class AuthState {
  final AuthStatus status;
  final User? user;

  const AuthState({required this.status, this.user});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.authenticated(User user)
    : this(status: AuthStatus.authenticated, user: user);
  const AuthState.unauthenticated() : this(status: AuthStatus.unauthenticated);
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
    state = AuthState.authenticated(session.user);

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
      redirectTo: 'bookworm-friends://home',
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
      redirectTo: 'bookworm-friends://home',
    );
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
