import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    final session = supabase.auth.currentSession;
    if (session != null) {
      return AuthState.authenticated(session.user);
    }

    supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        state = AuthState.authenticated(session.user);
        NotificationService.updateTokenInProfile();
      } else if (event == AuthChangeEvent.signedOut) {
        state = const AuthState.unauthenticated();
      }
    });

    return const AuthState.unauthenticated();
  }

  Future<void> signInWithGoogle() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'bookworm-friends://home',
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
