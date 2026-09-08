import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/ui/pages/invite_consent_page.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/invite/shelf_duo.dart';

/// The friendship landed. Its own screen, and the one good moment for per-friend
/// notifications.
///
/// **A screen that was missing entirely until Flighty's flow was looked at properly.**
/// They confirm the connection on its own frame — two portraits with a check dropped
/// between them — and then use the moment for something useful: an outlined *Customize
/// Alerts for This Friend* beside Done. That is the best possible introduction to
/// per-friend settings, because it arrives exactly when the reader has just thought
/// about this specific person, and it is what gives the toggles on `ManageFriendPage`
/// a reason to exist rather than being a settings screen looking for content.
///
/// **The same [ShelfDuo] as the consent screen, sealed.** The two are the same moment
/// before and after; a second illustration would make them look like two unrelated
/// events.
///
/// **No app bar.** There is nothing to dismiss back to — the redemption is written,
/// the friendship exists whether or not this screen is read, and a ✕ here would imply
/// otherwise. Done is the only way out and it is unambiguous.
class InviteDonePage extends ConsumerWidget {
  const InviteDonePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final args = ModalRoute.of(context)!.settings.arguments as InviteDoneArgs;
    final me = ref.watch(profileProvider).valueOrNull;
    final name = args.inviter?.username ?? l10n.someone;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
                child: Column(
                  children: [
                    ShelfDuo(
                      emoji: args.inviter?.emoji,
                      avatarPath: args.inviter?.avatarPath,
                      name: name,
                      myEmoji: me?.emoji,
                      myAvatarPath: me?.avatarPath,
                      myLabel: l10n.you,
                      sealed: true,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      args.alreadyFriends
                          ? l10n.alreadyFriendsTitle
                          : l10n.nowFriendsTitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.hero,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.nowFriendsBody(name),
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
                  ElevatedActionButton(
                    width: double.infinity,
                    height: 48,
                    borderRadius: 24,
                    buttonText: l10n.done,
                    // Unwinds the whole invite flow. The consent screen replaced
                    // itself with this one, so there is at most a modal barrier and
                    // a link route above home — popping to the first route is what
                    // lands on the library rather than on whatever the link handler
                    // pushed this over.
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                  const SizedBox(height: 10),
                  // Outlined, and second. It is a genuinely useful offer and it is
                  // not the thing the reader came here to do, so it takes the
                  // secondary weight rather than competing with Done for the same
                  // visual priority.
                  //
                  // **Goes to `ManageFriendPage` rather than toggling anything
                  // here.** There is no per-friend notification preference in the
                  // app yet (see that page); offering the switch inline would make a
                  // promise this screen cannot keep, whereas offering the *place* it
                  // will live is honest and still useful.
                  OutlinedButton(
                    onPressed: args.inviter == null
                        ? null
                        : () {
                            Navigator.of(context).popUntil((r) => r.isFirst);
                            Navigator.pushNamed(
                              context,
                              AppRoutes.manageFriend,
                              arguments: args.inviter,
                            );
                          },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      foregroundColor: colors.primaryText,
                      side: BorderSide(color: colors.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      l10n.notifyAbout(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label,
                    ),
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
