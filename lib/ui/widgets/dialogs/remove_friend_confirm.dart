import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/adaptive_dialog_action.dart';

/// Asks, then removes — the app's one friend-removal path.
///
/// **One function because two of them is the bug this feature already had once.**
/// Removal used to be reachable from the old `UserLibraryPage` with a No/Unfollow
/// pair and from `friend_info_dialog` with a Cancel/Confirm pair, and
/// `ManageFriendPage` was written to collapse the two. The visit bar's overflow
/// menu is a *third* entry point, so the confirm moved out of that page rather than
/// being copied beside it: an entry point is a trigger, not a licence to re-decide
/// what the confirm says.
///
/// `showAdaptiveDialog` + [AdaptiveDialogAction], as every other destructive confirm
/// in the app does. iOS orders Cancel first and the destructive action second, in
/// red, which puts the ordering in the platform rather than in a house style nobody
/// wrote down.
///
/// **Ends the visit itself, and that belongs here rather than at a call site.**
/// Without it the shell is left pointed at someone who is no longer a friend.
/// `home_page` can recover from that — it evicts a stranger's library, which it has
/// to anyway for the case where *they* remove *you* — but recovering from a state
/// this function could simply not create is the wrong division of labour.
///
/// Returns true when the friend was removed, false when the reader cancelled or the
/// context went away mid-flight. Deliberately does **not** pop anything: a page that
/// exists to host this needs to leave and a menu does not, and only the caller knows
/// which it is.
Future<bool> confirmAndRemoveFriend({
  required BuildContext context,
  required WidgetRef ref,
  required Profile friend,
}) async {
  final l10n = AppLocalizations.of(context);

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

  if (confirmed != true || !context.mounted) return false;

  await ref.read(userActionsProvider).removeFriend(friend.id);

  ref.read(selectedFriendProvider.notifier).state = null;
  ref.read(friendsSheetLevelProvider.notifier).state = FriendsSheetLevel.list;
  return true;
}
