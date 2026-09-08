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
    if (!wasSignedOut) return;

    // The OAuth screen is an in-app browser (`SFSafariViewController` on iOS).
    // The provider's redirect back to `bookworm-friends://` reaches the app but
    // does not dismiss the browser, which is left sitting blank on top of it.
    closeInAppWebView();
    NotificationService.updateTokenInProfile();
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
