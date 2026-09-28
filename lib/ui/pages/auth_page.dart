import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/invite_link_provider.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';
import 'package:bookworm_friends/ui/widgets/brand_mark.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';

/// The height of both sign-in buttons.
///
/// **44, which is Apple's recommended default** (their minimum is 30) and also iOS's
/// minimum touch target. It was 48, and the reason for moving is that 44 makes every
/// derived number an integer: Apple's own logo artwork is a 19-unit glyph inside a
/// 44-unit button face, so at a 44pt button the glyph is exactly 19pt and the title
/// -- 43% of the height -- is 19pt too. At 48 both came out at 20.64.
const double kSignInButtonHeight = 44;

/// How much of the button's height the title and the logo each take: **19/44**.
///
/// One constant for both, because Apple's two figures coincide. They publish 43% for
/// the title of a custom button ("the button's height would be 233% of the title's
/// font size"). They publish nothing for the logo -- the instruction is "match the
/// height of the logo file to the height of the button" and the padding inside their
/// artwork sets the proportion -- but measured out of that artwork it is 19 units of
/// glyph in a 44-unit face, which is 43.18%.
///
/// The old button asked for `height: 20` on a 56-unit canvas whose glyph was 19
/// units, which put the Apple logo at **6.8pt in a 48pt button: 14%, a third of the
/// size it should have been** -- with the asset's white plate reading as the logo at
/// 15.7pt. `assets/icons/appleLogo.svg` is cropped tight to the glyph, so this ratio
/// is applied here rather than coming from padding in the file.
///
/// Google's mark uses the same value. Their own spec is an 18dp mark in a 40dp button
/// (45%), near enough that one number serves both -- and Apple explicitly allow it:
/// "If you need to horizontally align the Apple logo with other authentication logos,
/// you can adjust the space between the logo and the button's leading edge."
const double kSignInContentRatio = 19 / 44;

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
            // The shipping mark. This drew `SmileBookwormIcon` until the logo
            // review retired the worm — the launcher has been the single chalk
            // book since `feat(branding)`, and the sign-in screen was the last
            // place still introducing the app with the old mascot.
            const BrandMark(size: 96),
            // 20, not the 48 that used to sit here. A wordmark belongs to its
            // mark: with an airy outline worm above it the gap read as breathing
            // room, but under a solid plate the same gap reads as two unrelated
            // objects. The 48 below survives, so the lockup is one unit with air
            // beneath it rather than three evenly spaced rows.
            const SizedBox(height: 20),
            Text(
              l10n.appTitle,
              // `hero` — the app's own words at a full-screen moment, which is
              // exactly this screen. It replaces a local `fontFamily:
              // 'DesignHouse'` override: that face was never part of the type
              // scale `feat(branding)` shipped, and because the override was
              // spelled at the call site it also escaped `text_style_test.dart`,
              // which checks tokens against the families `pubspec.yaml`
              // registers. DesignHouse is no longer registered at all.
              style: AppTextStyles.hero,
            ),
            const SizedBox(height: 48),
            _SignInButton(
              label: l10n.continueWithApple,
              icon: const AppleLogo(
                height: kSignInButtonHeight * kSignInContentRatio,
                // White, to match the title. Apple: "Within a button, both items
                // must be either black or white".
                color: Colors.white,
              ),
              backgroundColor: Colors.black,
              textColor: Colors.white,
              onPressed: () =>
                  ref.read(authProvider.notifier).signInWithApple(),
            ),
            const SizedBox(height: 12),
            _SignInButton(
              label: l10n.continueWithGoogle,
              icon: const GoogleIcon(
                height: kSignInButtonHeight * kSignInContentRatio,
              ),
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

  /// The provider's mark, already sized and coloured.
  ///
  /// A widget rather than an asset path, because the two marks are not
  /// interchangeable: Apple's is one tintable shape that must take the title's
  /// colour, Google's is four fixed brand colours that must not be touched. The
  /// old `String icon` field made them look like the same kind of thing, which is
  /// how a black apple on a white plate ended up on a black button.
  final Widget icon;
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
        height: kSignInButtonHeight,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: textColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            // Spelled out rather than inherited. Apple tie the title's size to the
            // button's height, and Material's default button text style does not
            // know about this button's height -- which is how the title ended up at
            // 29% of it. The size lives in the token, not here: see
            // `text_style_test.dart`, which refuses a `fontSize` at a call site.
            textStyle: AppTextStyles.signIn,
          ),
          icon: icon,
          label: Text(label),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
