import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

/// The Friends tab's sheet: everyone you follow, and the way into a visit.
///
/// **Not drawn as designed, deliberately.** The mockup's Everyone row carries
/// what each friend is reading and their read count. Both are per-friend queries
/// — `userLibraryProvider` and `userFinishedBooksProvider` are keyed by user id —
/// so rendering them here means one round trip per row, fired the moment the tab
/// opens. That wants a single batched query, which is a data change, and Phase 1
/// is the shell only. The row is name and avatar until that query exists; it is
/// already enough to be the entry point to a visit, which is what the shell needs
/// from it. Same reason the design puts the Activity capsule after Phase 1.
class FriendsSheet extends StatelessWidget {
  final List<Profile> following;

  /// The friend currently being looked at, ringed in the list, or `null` when you
  /// are in your own library.
  final Profile? selectedFriend;

  final ValueChanged<Profile> onSelectFriend;
  final VoidCallback onAddFriend;

  /// Springs the sheet shut and goes inert while the library is being edited.
  ///
  /// An edit can be started from any tab, so every sheet has to get out of the
  /// way — not just the read-books one. Left expanded, this sheet would sit there
  /// at full height taking room the library needs to be rearranged in.
  final bool isEditMode;

  /// See [LibrarySheet.bottomReserve].
  final double bottomReserve;

  const FriendsSheet({
    super.key,
    required this.following,
    required this.selectedFriend,
    required this.onSelectFriend,
    required this.onAddFriend,
    this.isEditMode = false,
    this.bottomReserve = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LibrarySheet(
      isEditMode: isEditMode,
      bottomReserve: bottomReserve,
      header: Row(
        children: [
          Expanded(
            child: LibrarySheetTitle(
              title: l10n.friends,
              count: following.length,
            ),
          ),
          // Icon-only: this is the home for `search_user_page`, and it is a
          // secondary action next to a list of people you already follow.
          IconButton(
            onPressed: isEditMode ? null : onAddFriend,
            tooltip: l10n.searchFriends,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.person_add_alt, size: 22),
          ),
        ],
      ),
      body: following.isEmpty
          ? _Empty(message: l10n.noFriendsYet)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final friend in following)
                  _FriendRow(
                    friend: friend,
                    isSelected: friend.id == selectedFriend?.id,
                    // Inert with the rest of the sheet: leaving an edit by
                    // paging to someone else's library is not a way out anyone
                    // asked for.
                    onTap: isEditMode ? null : () => onSelectFriend(friend),
                  ),
                const SizedBox(height: 6),
              ],
            ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final Profile friend;
  final bool isSelected;
  final VoidCallback? onTap;

  const _FriendRow({
    required this.friend,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
        child: Row(
          children: [
            AvatarCircle(
              emoji: friend.emoji ?? '',
              isSelected: isSelected,
              onTap: onTap ?? () {},
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                friend.username ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.colors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;

  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: context.colors.secondaryText, fontSize: 14),
        ),
      ),
    );
  }
}
