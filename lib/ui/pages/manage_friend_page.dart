import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/adaptive_dialog_action.dart';

/// Identity, per-friend notifications, and Remove.
///
/// **Replaces `friend_info_dialog.dart` and, with it, two different confirms.** The
/// dialog was inherited from the deleted `FriendRail` and showed a follower/following
/// pair that a mutual model makes one number. Removal was reachable from two places
/// with two different button pairs — No/Unfollow on the old `UserLibraryPage`,
/// Cancel/Confirm in the dialog — which is the kind of inconsistency nobody notices
/// until they are asked to describe what the app does.
///
/// **Reached from the gear in the visit app bar**, beside Poke. It was drawn on a long
/// press of the Friends row first: a real gesture (`friends_sheet.dart`) inherited from
/// the rail, but an invisible one. Reusing an existing gesture is not the same as
/// advertising an action.
///
/// A page rather than a sheet, because it is a destination with a title and a back
/// button, and because the confirm it raises is a system alert that wants a page under
/// it rather than a sheet it would have to sit on top of.
class ManageFriendPage extends ConsumerWidget {
  const ManageFriendPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final friend = ModalRoute.of(context)!.settings.arguments as Profile;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        backgroundColor: colors.pageBackground,
        elevation: 0,
        title: Text(l10n.manageFriend, style: AppTextStyles.subtitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _Identity(friend: friend),
              const SizedBox(height: 28),

              // **The notification toggles are gone, and this is the drawings' own
              // fallback for it.** `docs/mockups/friend-requests` left it open whether
              // they ship at all: "If they slip, this screen is identity plus Remove."
              // They slipped, and shipping them anyway was the worse of the two
              // outcomes — two `Switch`es backed by nothing but local `setState`, so a
              // toggle survived until the page was popped and then silently reverted.
              // `When they finish a book` also defaulted to **on**, which told every
              // reader they would receive a notification that does not exist.
              //
              // Nothing to persist to and nothing to persist *for*: there is no
              // start/finish notification anywhere in the app. The only push is `poke`,
              // and `supabase/functions/send-notification/index.ts` still posts to the
              // decommissioned legacy FCM endpoint. A preference column would have been
              // the smallest part of the work.
              //
              // Restore them with the feature, not before — the copy
              // (`notifyOnFinish`, `notifyOnStart`, `notificationsSection`) is kept in
              // both `.arb` files for exactly that. `invite_done_page.dart`'s secondary
              // button loses its destination-with-toggles and now simply opens this
              // page, which is honest: identity and Remove are real.
              _RemoveFriendButton(friend: friend),
              const SizedBox(height: 6),

              // Flighty's line, and the better half of it. "They will not get an alert"
              // is what stops someone hesitating over the button — the fear is not that
              // removal fails, it is that the other person is told.
              Text(
                l10n.removeFriendNoAlert,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  final Profile friend;
  const _Identity({required this.friend});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return Row(
      children: [
        AvatarCircle(
          emoji: friend.emoji,
          avatarPath: friend.avatarPath,
          diameter: 56,
          emojiSize: 44,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                friend.username ?? '',
                // `titleUser`, not `title`: this is user-supplied text, and the serif
                // is reserved for the app's own voice.
                style: AppTextStyles.titleUser,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (friend.handle != null)
                Text(
                  '@${friend.handle}',
                  style: AppTextStyles.label.copyWith(
                    color: colors.secondaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              // "Friends since" replaces the follower/following pair. One fact, and one
              // that only a mutual model can state: a follow had two dates and no
              // agreed-upon start.
              Text(
                '${l10n.friendsSince} —',
                style: AppTextStyles.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RemoveFriendButton extends ConsumerWidget {
  final Profile friend;
  const _RemoveFriendButton({required this.friend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () => _confirm(context, ref, l10n),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          // A pale fill rather than a solid red one: this is the entry to a
          // destructive action, not the action itself. The alert's `Remove` is the
          // thing that does it, and that one is red text as iOS draws it.
          color: softRedColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          l10n.removeFriend,
          style: AppTextStyles.subtitle.copyWith(color: softRedColor),
        ),
      ),
    );
  }

  /// The app's own confirm.
  ///
  /// `showAdaptiveDialog` + [AdaptiveDialogAction], matching every other destructive
  /// confirm in the app. iOS orders Cancel first and the destructive action second, in
  /// red — which is what dissolves the old No/Unfollow versus Cancel/Confirm split into
  /// the platform rather than into a house style nobody wrote down.
  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.removeFriendConfirmTitle(friend.username ?? '')),
        content: Text(l10n.removeFriendConfirmMessage),
        actions: [
          AdaptiveDialogAction(
            label: l10n.cancel,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AdaptiveDialogAction(
            label: l10n.remove,
            isDestructive: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await ref.read(userActionsProvider).removeFriend(friend.id);
    if (!context.mounted) return;

    // End the visit before leaving. Without this the shell returns to a friend who is
    // no longer in the list, which `home_page.dart` would then have to evict — the same
    // eviction that now also fires when *they* remove *you*, a case a one-directional
    // model could never produce.
    ref.read(selectedFriendProvider.notifier).state = null;
    ref.read(friendsSheetLevelProvider.notifier).state = FriendsSheetLevel.list;
    Navigator.pop(context);
  }
}
