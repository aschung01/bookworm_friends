import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/constants/app_routes.dart';

class AuthPage extends ConsumerWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    });

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/smileBookwormIcon.svg',
              height: 120,
            ),
            const SizedBox(height: 48),
            Text(
              l10n.appTitle,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'DesignHouse',
              ),
            ),
            const SizedBox(height: 48),
            _SignInButton(
              label: l10n.continueWithApple,
              icon: 'assets/icons/appleBlackIcon.svg',
              backgroundColor: Colors.black,
              textColor: Colors.white,
              onPressed: () => ref.read(authProvider.notifier).signInWithApple(),
            ),
            const SizedBox(height: 12),
            _SignInButton(
              label: l10n.continueWithGoogle,
              icon: 'assets/icons/googleIcon.svg',
              backgroundColor: Colors.white,
              textColor: Colors.black,
              onPressed: () => ref.read(authProvider.notifier).signInWithGoogle(),
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
