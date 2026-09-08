import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/invite.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

/// A link that did not work, and **which kind** it was.
///
/// Expired, revoked and exhausted are told apart because the recovery differs: two of
/// them mean *ask for a new link* and one means *you already used this*. A single
/// "this link didn't work" is true for all four and useful for none — it leaves the
/// reader to guess whether to ask again or to stop.
///
/// **There is no fallback action.** An earlier draft offered "add by handle instead",
/// which no longer exists — handle search is gone, and an invite is the only way in.
/// So all this screen can honestly do is explain and get out of the way, which is why
/// its one button leaves rather than retries.
///
/// **Nothing here earns an illustration.** An error screen that draws a picture of
/// itself is asking to be admired for failing.
class InviteDeadPage extends StatelessWidget {
  const InviteDeadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final args = ModalRoute.of(context)!.settings.arguments as InviteDeadArgs;
    final (title, body) = _copy(l10n, args);

    return Scaffold(
      backgroundColor: colors.pageBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 6, 11, 0),
              child: Row(
                children: [
                  AdaptiveIconButton(
                    symbol: 'xmark',
                    icon: Icons.close,
                    // See `invite_consent_page`: a lone ✕ gets the full target.
                    diameter: kIconButtonDiameter,
                    symbolSize: kIconButtonSymbolSize,
                    iconSize: kIconButtonIconSize,
                    semanticLabel: l10n.close,
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                ],
              ),
            ),
            // **From the top, not centred, and the button is not pinned to the
            // floor.** An earlier draft did both and framed 350pt of white as though
            // the emptiness were part of the design. There is no mark here to fill
            // it, so the copy starts where the reader's eye already is.
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: AppTextStyles.hero),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    style: AppTextStyles.body.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedActionButton(
                    width: double.infinity,
                    height: 48,
                    borderRadius: 24,
                    buttonText: l10n.continueToLibrary,
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One pair of strings per outcome.
  ///
  /// A record rather than two switches, so a new outcome cannot be given a headline
  /// and left without a body — which is the failure the drawings' own verifier
  /// catches on the mockup side ("a headline must carry copy").
  ///
  /// [InviteRedemptionResult.ok] and [InviteRedemptionResult.alreadyFriends] never
  /// reach here — the consent screen routes both to the success page — but the switch
  /// is exhaustive rather than defaulting, so adding a result to the enum fails to
  /// compile instead of silently falling through to "we couldn't find that code".
  (String, String) _copy(AppLocalizations l10n, InviteDeadArgs args) {
    final name = args.inviterName.isEmpty ? l10n.someone : args.inviterName;
    return switch (args.result) {
      InviteRedemptionResult.expired => (
        l10n.inviteExpiredTitle,
        l10n.inviteExpiredBody(name),
      ),
      InviteRedemptionResult.revoked => (
        l10n.inviteRevokedTitle,
        l10n.inviteRevokedBody(name),
      ),
      InviteRedemptionResult.exhausted => (
        l10n.inviteExhaustedTitle,
        l10n.inviteExhaustedBody(name),
      ),
      InviteRedemptionResult.self => (
        l10n.inviteSelfTitle,
        l10n.inviteSelfBody,
      ),
      InviteRedemptionResult.notSignedIn => (
        l10n.inviteNotSignedInTitle,
        l10n.inviteNotSignedInBody,
      ),
      // The typed-code path's most likely landing, which is why the body names the
      // length rather than apologising: eight characters is a checkable fact.
      InviteRedemptionResult.notFound ||
      InviteRedemptionResult.ok ||
      InviteRedemptionResult.alreadyFriends => (
        l10n.inviteNotFoundTitle,
        l10n.inviteNotFoundBody,
      ),
    };
  }
}
