import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/adaptive_dialog_action.dart';

/// The horizontal strip of friend avatars, shown only inside a visit.
///
/// Named a rail rather than a bar because the shell scopes it to a visit: it
/// exists while you are in someone else's library, holds **friends only** — not
/// you — and carries the control that ends the visit at its head.
///
/// Your own avatar is deliberately absent. A permanent rail with you in it was
/// drawn on all nine states it would have to appear on and undermined itself: a
/// sheet measured from the bottom is not pushed down by a rail above it, so the
/// clearance under the bar collapsed, and the fix (hide the rail when the sheet is
/// up) makes the rail conditional again — which is the premise gone. Scoping it to
/// a visit is what made the ✕ unambiguous, because a visit is the one context
/// where a dismissal has an obvious meaning.
class FriendRail extends StatelessWidget {
  final List<Profile> following;
  final Profile? selectedFriend;

  /// Ends the visit. Rendered as the glass ✕ pinned at the rail's head, ahead of
  /// a hairline, so it stays put while the avatars scroll.
  final VoidCallback onEndVisit;

  final ValueChanged<Profile> onSelectFriend;

  const FriendRail({
    super.key,
    required this.following,
    required this.selectedFriend,
    required this.onEndVisit,
    required this.onSelectFriend,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The rail owns its own height: it is a row of 40pt avatars, and the
    // horizontal list inside needs a bounded cross axis wherever it is placed.
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 10),
            child: AdaptiveIconButton(
              symbol: 'xmark',
              icon: Icons.close,
              diameter: 36,
              symbolSize: 14,
              iconSize: 18,
              semanticLabel: l10n.endVisit,
              onPressed: onEndVisit,
            ),
          ),
          // The hairline the head is pinned ahead of: it separates "leave" from
          // "go somewhere else", which are different kinds of action.
          Container(width: 1, height: 24, color: context.colors.divider),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(left: 10, right: 10),
              itemCount: following.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final friend = following[index];
                return Center(
                  child: AvatarCircle(
                    emoji: friend.emoji ?? '📖',
                    isSelected: selectedFriend?.id == friend.id,
                    onTap: () => onSelectFriend(friend),
                    onLongPress: () => _showFriendInfoDialog(context, friend),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
