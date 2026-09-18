import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/invite_link_provider.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // The state is checked on mount as well as listened to, because a sign-in can
    // complete before this page exists: the splash screen waits half a second
    // before it reads the auth state, and an OAuth deep link can be exchanged
    // inside that window. A change listener never fires for a change that
    // already happened, which left a signed-in user looking at the sign-in
    // buttons until the app was restarted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _leaveIfSignedIn(ref.read(authProvider));
    });
  }

  void _leaveIfSignedIn(AuthState auth) {
    if (_leaving || !mounted) return;
    if (auth.status != AuthStatus.authenticated) return;

    _leaving = true;
    Navigator.pushReplacementNamed(context, AppRoutes.home);
    _spendPendingInvite();
  }

  /// Spends an invite that was waiting when the sign-in completed.
  ///
  /// A tapped link is the only way one can be waiting. It arrived before there was a
  /// session — `redeem_invite()` answers `not_signed_in` without one — so it was held
  /// across the whole OAuth round trip and this is the first moment it can be spent.
  ///
  /// Pushed **onto** the library rather than replacing it, so dismissing consent leaves
  /// the reader on their own shelf rather than an empty navigator.
  ///
  /// **Nothing is offered when no link is waiting.** A typed-code screen used to be, once
  /// per install, to catch the landing page's clipboard handoff. Removing it costs the
  /// deferred tier: someone who installs from `libstack.app/i/<token>` and then opens the
  /// app cold has no invite until they tap the link again. That is accepted — a code a
  /// reader types is the shape a referral code will want, and the two must not share an
  /// input.
  ///
  /// Synchronous, and that is the whole method: with no `SharedPreferences` read left
  /// there is nothing to await, so the `mounted` re-checks that guarded the old async
  /// version are gone with it.
  void _spendPendingInvite() {
    final token = ref.read(pendingInviteTokenProvider);
    if (token == null) return;

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
    final l10n = AppLocalizations.of(context);
    ref.listen(authProvider, (previous, next) => _leaveIfSignedIn(next));

    return Scaffold(
      backgroundColor: context.colors.pageBackground,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SmileBookwormIcon(height: 120),
            const SizedBox(height: 48),
            Text(
              l10n.appTitle,
              // The wordmark keeps its own face and takes only its metrics from
              // the scale: DesignHouse is the logotype, so the family is the one
              // thing here that is not the token's to decide.
              style: AppTextStyles.titleUser.copyWith(
                fontFamily: 'DesignHouse',
              ),
            ),
            const SizedBox(height: 48),
            _SignInButton(
              label: l10n.continueWithApple,
              icon: 'assets/icons/appleBlackIcon.svg',
              backgroundColor: Colors.black,
              textColor: Colors.white,
              onPressed: () =>
                  ref.read(authProvider.notifier).signInWithApple(),
            ),
            const SizedBox(height: 12),
            _SignInButton(
              label: l10n.continueWithGoogle,
              icon: 'assets/icons/googleIcon.svg',
              backgroundColor: Colors.white,
              textColor: Colors.black,
              onPressed: () =>
                  ref.read(authProvider.notifier).signInWithGoogle(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  final String label;
  final String icon;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onPressed;

  const _SignInButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: textColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: SvgPicture.asset(icon, height: 20),
          label: Text(label),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
