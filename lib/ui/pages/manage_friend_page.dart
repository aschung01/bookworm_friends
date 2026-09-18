import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/remove_friend_confirm.dart';

/// Identity, per-friend notifications, and Remove.
///
/// **Replaces `friend_info_dialog.dart` and, with it, two different confirms.** The
/// dialog was inherited from the deleted `FriendRail` and showed a follower/following
/// pair that a mutual model makes one number. Removal was reachable from two places
/// with two different button pairs — No/Unfollow on the old `UserLibraryPage`,
/// Cancel/Confirm in the dialog — which is the kind of inconsistency nobody notices
/// until they are asked to describe what the app does.
///
/// **No longer reached from the visit bar, which was its headline entry point.** The
/// gear beside Poke is an overflow menu now, and Remove is one item in it followed by
/// the same confirm this page raises — literally the same, via
/// [confirmAndRemoveFriend]. Pushing a screen to offer one destructive action was
/// more ceremony than the action deserved once the popover could offer it in place.
///
/// **What keeps the page alive is the long press and the invite hand-off**, neither of
/// which the visit bar can serve: `friends_sheet.dart` opens it from a row that may
/// not be the friend on screen, and `invite_done_page.dart` offers it as the *place*
/// per-friend notifications will live once they exist. If those two ever move, this
/// page has no remaining reason to exist.
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
      onTap: () => _confirm(context, ref),
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

  /// The app's own confirm, which this page no longer owns.
  ///
  /// It moved to [confirmAndRemoveFriend] when the visit bar's overflow menu became a
  /// second trigger for it. What is left here is the part only a *page* has to do:
  /// leave, because a screen whose whole subject has just been removed cannot stay.
  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final removed = await confirmAndRemoveFriend(
      context: context,
      ref: ref,
      friend: friend,
    );
    if (!removed || !context.mounted) return;
    Navigator.pop(context);
  }
}
