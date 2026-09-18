import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/invite_link_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final authState = ref.read(authProvider);

    if (authState.status == AuthStatus.authenticated) {
      try {
        final profile = await ref.read(profileProvider.future);
        if (!mounted) return;

        if (profile?.needsOnboarding ?? true) {
          Navigator.pushReplacementNamed(context, AppRoutes.settings);
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.home);
        }
      } catch (_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
      // **After landing, not instead of it.** Consent is pushed *onto* the
      // destination so that dismissing it leaves the reader somewhere real. An
      // earlier shape replaced the route, which meant `✕` on the consent screen
      // popped to an empty navigator.
      _pushConsentIfPending();
      // **A held token is the only invite there is**, and the line above has just
      // spent it. A typed-code screen was once offered after signup and was pointedly
      // never offered here, this branch being a reader who *already had a session*;
      // that screen is gone entirely now, so there is nothing left to withhold. See
      // `AuthPage._spendPendingInvite`.
    } else {
      // Signed out. The token stays in the provider across the whole OAuth round
      // trip and is spent by whatever lands after sign-in -- see
      // [pendingInviteTokenProvider]. Redeeming here would return
      // `not_signed_in` and burn the link for nothing.
      Navigator.pushReplacementNamed(context, AppRoutes.auth);
    }
  }

  /// Hands a link-borne token to the consent screen.
  ///
  /// The inviter is null: the token carries no name, and this app cannot read
  /// `friend_invites` to resolve one -- the table is owner-scoped by design. The
  /// consent copy already falls back to "Someone", which is what the typed-code
  /// path has always shown.
  void _pushConsentIfPending() {
    final token = ref.read(pendingInviteTokenProvider);
    if (token == null || !mounted) return;
    // Cleared before the push, so a rebuild cannot present it twice.
    ref.read(pendingInviteTokenProvider.notifier).state = null;
    Navigator.pushNamed(
      context,
      AppRoutes.inviteConsent,
      arguments: InviteConsentArgs(token: token),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}
