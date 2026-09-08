import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/invite_code_prompt_provider.dart';
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
    unawaited(_offerInvite());
  }

  /// The two ways an invite can be waiting at the end of a sign-in.
  ///
  /// Both are pushed **onto** the library rather than replacing it, so dismissing
  /// either leaves the reader on their own shelf rather than an empty navigator.
  Future<void> _offerInvite() async {
    // 1. A tapped link. It arrived before there was a session — `redeem_invite()`
    //    answers `not_signed_in` without one — so it was held across the whole OAuth
    //    round trip and this is the first moment it can be spent.
    final token = ref.read(pendingInviteTokenProvider);
    if (token != null) {
      ref.read(pendingInviteTokenProvider.notifier).state = null;
      // The code screen is deliberately **not** offered after this. The reader has
      // just used a link; asking whether they have a code would be asking for
      // something they have already spent.
      await ref.read(inviteCodePromptProvider).takeChance();
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.inviteConsent,
        arguments: InviteConsentArgs(token: token),
      );
      return;
    }

    // 2. No link, so this may be someone who installed from the landing page. The
    //    token is on their clipboard and `InviteCodePage` reads it back — that is the
    //    far end of the deferred tier, and without this push the copy goes nowhere.
    if (!await ref.read(inviteCodePromptProvider).takeChance()) return;
    if (!mounted) return;
    Navigator.pushNamed(context, AppRoutes.inviteCode);
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
