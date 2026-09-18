import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/invite.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/invite_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/invite/shelf_duo.dart';

/// What a redemption has to know before it can ask.
///
/// The token, and whatever is already known about the inviter. The name is optional
/// because the token does not carry one: this client cannot read `friend_invites` to
/// resolve it, so a link tapped cold arrives anonymous and the copy falls back to
/// "Someone". A landing-page payload could fill it in later.
class InviteConsentArgs {
  final String token;

  /// The inviter, when the caller already resolved them. Null for a link tapped cold,
  /// which is every link today.
  final Profile? inviter;

  const InviteConsentArgs({required this.token, this.inviter});
}

/// **The screen the whole redesign exists for.**
///
/// Full-screen, because accepting grants someone access to your library and that
/// cannot be explained on a pill in an app bar. One button.
///
/// **There is no Decline.** The `✕` is the refusal, which is Flighty's exact
/// structure and the right one: a Decline button beside Become friends makes a
/// two-way choice out of a thing that is really *do this, or leave*. Dismissing costs
/// the sender nothing either — `redeem_invite` is never called, so no use is spent.
///
/// The result of the redemption decides where this goes next: [InviteDonePage] on
/// success, [InviteDeadPage] on any of the four refusals.
class InviteConsentPage extends ConsumerStatefulWidget {
  const InviteConsentPage({super.key});

  @override
  ConsumerState<InviteConsentPage> createState() => _InviteConsentPageState();
}

class _InviteConsentPageState extends ConsumerState<InviteConsentPage> {
  /// True from the tap until the RPC answers.
  ///
  /// **Held on the button rather than swapped for a spinner screen.** Redemption
  /// writes a friendship, so there is a real wait here; replacing the screen would
  /// make the one moment the reader is actually waiting the emptiest frame in the
  /// flow, which is what the first draft of the strip did.
  bool _pending = false;

  Future<void> _accept(InviteConsentArgs args) async {
    setState(() => _pending = true);
    late final InviteRedemption redemption;
    try {
      redemption = await ref.read(inviteActionsProvider).redeem(args.token);
    } catch (_) {
      // A thrown error is the network or the session, not a refusal. Fall back to
      // the not-found copy rather than inventing a ninth outcome: the reader's next
      // move is the same either way.
      redemption = const InviteRedemption(
        InviteRedemptionResult.notFound,
        null,
      );
    }
    if (!mounted) return;
    setState(() => _pending = false);

    final inviterName = args.inviter?.username ?? '';
    if (redemption.result.isFriendNow) {
      Navigator.pushReplacementNamed(
        context,
        AppRoutesInvite.inviteDone,
        arguments: InviteDoneArgs(
          inviter: args.inviter,
          alreadyFriends:
              redemption.result == InviteRedemptionResult.alreadyFriends,
        ),
      );
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutesInvite.inviteDead,
      arguments: InviteDeadArgs(
        result: redemption.result,
        inviterName: inviterName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final args =
        ModalRoute.of(context)!.settings.arguments as InviteConsentArgs;
    final me = ref.watch(profileProvider).valueOrNull;
    final name = args.inviter?.username ?? l10n.someone;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 6, 11, 0),
              child: Row(
                children: [
                  AdaptiveIconButton(
                    symbol: 'xmark',
                    icon: Icons.close,
                    // [kIconButtonDiameter], not the library bar's 36: this is a lone
                    // control on an otherwise empty row, which is the same case the
                    // invite sheet's ✕ already argued.
                    diameter: kIconButtonDiameter,
                    symbolSize: kIconButtonSymbolSize,
                    iconSize: kIconButtonIconSize,
                    semanticLabel: l10n.close,
                    // Inert while the RPC is in flight. Leaving mid-redemption would
                    // land the reader back on their library with a friendship that
                    // did get written and nothing on screen saying so.
                    onPressed: _pending ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    ShelfDuo(
                      emoji: args.inviter?.emoji,
                      avatarPath: args.inviter?.avatarPath,
                      name: name,
                      myEmoji: me?.emoji,
                      myAvatarPath: me?.avatarPath,
                      myLabel: l10n.you,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.inviteConsentTitle(name),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.hero,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.inviteConsentBody,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
              child: Column(
                children: [
                  // The reassurance goes *above* the button, not below it. It is
                  // what the reader needs in order to press it, so it has to be read
                  // first.
                  Text(
                    l10n.inviteConsentFinePrint,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      color: colors.secondaryText,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedActionButton(
                    width: double.infinity,
                    height: 48,
                    borderRadius: 24,
                    buttonText: _pending
                        ? l10n.becomingFriends
                        : l10n.becomeFriends,
                    activated: !_pending,
                    onPressed: _pending ? null : () => _accept(args),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Route names for the three invite destinations.
///
/// Declared beside the pages rather than in `AppRoutes` for the same reason
/// [InviteConsentArgs] is: the three are one flow and only ever reached from each
/// other or from a link handler. `AppRoutes` still registers them — this is the
/// spelling, not the table.
abstract final class AppRoutesInvite {
  static const String inviteConsent = '/invite_consent';
  static const String inviteDone = '/invite_done';
  static const String inviteDead = '/invite_dead';

  // **No `inviteCode`.** There was a typed-code screen here, offered once after signup,
  // as the landing page's clipboard handoff had to land somewhere. It is gone on
  // purpose: eight characters a reader types is the shape a *referral* code will want,
  // and two schemes sharing one field would each have to reject the other's input with a
  // misleading error. A friendship is created by following a link, and by nothing else.
}

/// What the success screen needs.
class InviteDoneArgs {
  final Profile? inviter;

  /// True when the friendship already existed. Same screen, quieter headline: there
  /// is nothing new to celebrate, and saying "You're now friends" to someone who
  /// already was reads as the app having lost track.
  final bool alreadyFriends;

  const InviteDoneArgs({required this.inviter, this.alreadyFriends = false});
}

/// What the dead-link screen needs.
class InviteDeadArgs {
  final InviteRedemptionResult result;
  final String inviterName;

  const InviteDeadArgs({required this.result, required this.inviterName});
}
