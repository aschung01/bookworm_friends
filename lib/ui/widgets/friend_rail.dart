import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/adaptive_dialog_action.dart';

/// The horizontal strip of friend avatars.
///
/// Named a rail rather than a bar because the decided shell scopes it to a
/// visit: it exists while you are in someone else's library, holds friends
/// only, and will carry the control that ends the visit at its head.
class FriendRail extends StatelessWidget {
  final Profile? myProfile;
  final List<Profile> following;
  final Profile? selectedFriend;
  final VoidCallback onSelectSelf;
  final ValueChanged<Profile> onSelectFriend;

  const FriendRail({
    super.key,
    required this.myProfile,
    required this.following,
    required this.selectedFriend,
    required this.onSelectSelf,
    required this.onSelectFriend,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 10),
      itemCount: following.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          final isSelected = selectedFriend == null;
          return AvatarCircle(
            emoji: myProfile?.emoji ?? '📚',
            isSelected: isSelected,
            onTap: onSelectSelf,
          );
        }
        final friend = following[index - 1];
        final isSelected = selectedFriend?.id == friend.id;
        return AvatarCircle(
          emoji: friend.emoji ?? '📖',
          isSelected: isSelected,
          onTap: () => onSelectFriend(friend),
          onLongPress: () => _showFriendInfoDialog(context, friend),
        );
      },
    );
  }
}

void _showFriendInfoDialog(BuildContext context, Profile friend) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final followerCount = ref.watch(followerCountProvider(friend.id));
        final followingCount = ref.watch(followingCountProvider(friend.id));

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(friend.emoji ?? '📖', style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text(
                friend.username ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Text(
                        followerCount.valueOrNull?.toString() ?? '-',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.followers,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Column(
                    children: [
                      Text(
                        followingCount.valueOrNull?.toString() ?? '-',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.following,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref
                          .read(userActionsProvider)
                          .pokeUser(friend.username ?? '');
                    },
                    child: Text(
                      l10n.poke,
                      style: TextStyle(color: context.colors.brandText),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showAdaptiveDialog<void>(
                        context: context,
                        builder: (confirmCtx) => AlertDialog.adaptive(
                          title: Text(l10n.unfollowConfirmTitle),
                          content: Text(l10n.unfollowConfirmMessage),
                          actions: [
                            AdaptiveDialogAction(
                              label: l10n.cancel,
                              onPressed: () => Navigator.pop(confirmCtx),
                            ),
                            AdaptiveDialogAction(
                              label: l10n.confirm,
                              isDestructive: true,
                              onPressed: () {
                                Navigator.pop(confirmCtx);
                                ref
                                    .read(userActionsProvider)
                                    .unfollow(friend.id);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                    child: Text(
                      l10n.unfollow,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}
