import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/friend_reading.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/notification_service.dart'
    show navigatorKey;

/// Everyone you are friends with.
///
/// One row per friendship, and the pair is stored in a canonical order
/// (`user_a < user_b`, enforced by a CHECK), so "my friends" is a match on **either**
/// column and the friend is whichever id is not mine. That asymmetry in the query is
/// the price of the symmetry in the data: a `follows` row knew which end you were, and
/// a friendship deliberately does not.
///
/// Replaces `followingListProvider`. The rename is not cosmetic — the old name recorded
/// a direction that no longer exists, and there is no longer a second list (followers)
/// for it to be distinguished from.
final friendsProvider = FutureProvider.autoDispose<List<Profile>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  // Both foreign keys are resolved in one request, and exactly one of them is the
  // other person on any given row. Filtering with `or` rather than two queries keeps
  // this a single round trip, which is what the Friends tab opens on.
  final data = await supabase
      .from('friendships')
      .select(
        'user_a, user_b, '
        'a:profiles!friendships_user_a_fkey(*), '
        'b:profiles!friendships_user_b_fkey(*)',
      )
      .or('user_a.eq.$userId,user_b.eq.$userId');

  return data.map((row) {
    final isA = row['user_a'] == userId;
    final other = (isA ? row['b'] : row['a']) as Map<String, dynamic>;
    return Profile.fromJson(other);
  }).toList();
});

/// What each friend is reading, and how many books they have read — in **one** request
/// for the whole list.
///
/// The batching is the entire point. `friends_sheet.dart` shipped in Phase 1 without
/// the row it was drawn with, and said why in its own doc: `userLibraryProvider` and
/// `userFinishedBooksProvider` are keyed by user id, so building the drawn row from
/// them means one round trip per friend, fired the moment the tab opens. One `in`
/// filter replaces all of them.
///
/// Derives its ids from [friendsProvider] instead of taking them as an argument.
/// A `family` keyed on a list would compare by identity rather than value and re-fetch
/// on every rebuild, and this provider always wants exactly the people the sheet is
/// already showing.
///
/// Filtered to the two statuses that matter server-side: fetching whole libraries to
/// count two things would trade round trips for payload rather than removing waste.
///
/// **RLS needs nothing special here.** `books` carries `Others can read visible books`
/// gated on `is_profile_visible(user_id)`, and that is applied per row — so a batched
/// query returns exactly what the per-user queries returned, and someone who has
/// removed you is simply absent from the result rather than an error. That is why
/// [groupFriendReading] is handed the id list: absent and empty have to render the
/// same.
///
/// Under mutual friendship that absence has a new cause worth naming: **they** can end
/// the friendship, so a list fetched a moment ago can contain someone whose books are
/// already unreadable. Same handling, different reason.
final friendsReadingProvider =
    FutureProvider.autoDispose<Map<String, FriendReading>>((ref) async {
      final friends = await ref.watch(friendsProvider.future);
      if (friends.isEmpty) return const {};

      final ids = friends.map((profile) => profile.id).toList();
      final data = await supabase
          .from('books')
          .select()
          .inFilter('user_id', ids)
          .inFilter('status', [bookStatusReading, bookStatusFinished])
          .order('start_date', ascending: false);

      return groupFriendReading(
        ids,
        data.map((row) => Book.fromJson(row)).toList(),
        readingStatus: bookStatusReading,
        finishedStatus: bookStatusFinished,
      );
    });

/// How many friends someone has.
///
/// **One number where there were two.** `followerCountProvider` and
/// `followingCountProvider` are gone: under a mutual model they are necessarily equal,
/// so showing both was showing the same figure twice and inviting the reader to look
/// for a difference that cannot exist.
final friendCountProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  userId,
) async {
  final result = await supabase
      .from('friendships')
      .select()
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .count();

  return result.count;
});

/// Someone else's shelves, keyed by user id.
///
/// **`keepAlive`, for the reason [userFinishedBooksProvider] states**: the Friends
/// sheet is the shell's switcher, so the same friend is visited repeatedly within a
/// session and a dropped cache turns every one of those taps into a blank pane
/// waiting on a round trip. The two are kept alive together — the pane needs both
/// before it can swap, so caching one without the other would buy nothing.
final userLibraryProvider = FutureProvider.autoDispose
    .family<List<Shelf>, String>((ref, targetUserId) async {
      ref.keepAlive();
      final data = await supabase
          .from('shelves')
          .select('*, books(*)')
          .eq('user_id', targetUserId)
          .order('position');

      final shelves = data.map((s) => Shelf.fromJson(s)).toList();
      for (final shelf in shelves) {
        shelf.books.sort((a, b) => a.position.compareTo(b.position));
      }
      return shelves;
    });

// `searchUsersProvider` and `followerListProvider` are deliberately gone.
//
// Search was the entry point that made a request queue necessary: finding a stranger by
// handle means asking, asking means a pending state, and a pending state means `status`,
// an accept RPC, a badge and a notification. An invite link is the only way in now, so
// none of that has to exist — and, critically, an invite needs no push delivery, which
// is why this could ship without the FCM v1 migration.
//
// `followerListProvider` had no meaning left to carry: a friendship has no direction, so
// there is one list and `friendsProvider` is it.

final userActionsProvider = Provider((ref) => UserActions(ref));

class UserActions {
  final Ref ref;
  UserActions(this.ref);

  /// Ends a friendship, in both directions, with one delete.
  ///
  /// There is no `follow` counterpart. Friendships are created by
  /// [InviteActions.redeem] and by nothing else — `friendships` has no INSERT policy,
  /// so even a client that tried could not write one.
  ///
  /// The pair is ordered before the delete because the table stores it that way. One
  /// row means one delete severs both sides at once, which is what lets the confirm
  /// dialog promise that access is revoked for both of you.
  Future<void> removeFriend(String targetUserId) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final a = userId.compareTo(targetUserId) < 0 ? userId : targetUserId;
    final b = userId.compareTo(targetUserId) < 0 ? targetUserId : userId;

    try {
      await supabase
          .from('friendships')
          .delete()
          .eq('user_a', a)
          .eq('user_b', b);

      ref.invalidate(friendsProvider);
      ref.invalidate(friendCountProvider(userId));
      ref.invalidate(friendCountProvider(targetUserId));
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).removeFriendFailed,
      );
    }
  }

  Future<void> pokeUser(String targetUsername) async {
    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    try {
      await supabase.rpc<void>(
        'poke_user',
        params: {'target_username': targetUsername},
      );
      EasyLoading.showSuccess(l10n.pokeSent);
    } catch (e) {
      EasyLoading.showError(l10n.pokeFailed);
    }
  }
}
