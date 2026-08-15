import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/notification_service.dart'
    show navigatorKey;

final followingListProvider = FutureProvider.autoDispose<List<Profile>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final data = await supabase
      .from('follows')
      .select('following_id, profiles!follows_following_id_fkey(*)')
      .eq('follower_id', userId);

  return data
      .map((row) => Profile.fromJson(row['profiles'] as Map<String, dynamic>))
      .toList();
});

final followerCountProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  userId,
) async {
  final result = await supabase
      .from('follows')
      .select()
      .eq('following_id', userId)
      .count();

  return result.count;
});

final followingCountProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  userId,
) async {
  final result = await supabase
      .from('follows')
      .select()
      .eq('follower_id', userId)
      .count();

  return result.count;
});

final isFollowingProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  targetUserId,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;

  final data = await supabase
      .from('follows')
      .select()
      .eq('follower_id', userId)
      .eq('following_id', targetUserId)
      .maybeSingle();

  return data != null;
});

final userLibraryProvider = FutureProvider.autoDispose
    .family<List<Shelf>, String>((ref, targetUserId) async {
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

final searchUsersProvider = FutureProvider.autoDispose
    .family<List<Profile>, String>((ref, query) async {
      if (query.isEmpty) return [];

      final data = await supabase
          .from('profiles')
          .select()
          .ilike('username', '%$query%')
          .limit(20);

      return data.map((p) => Profile.fromJson(p)).toList();
    });

final followerListProvider = FutureProvider.autoDispose
    .family<List<Profile>, String>((ref, userId) async {
      final data = await supabase
          .from('follows')
          .select('follower_id, profiles!follows_follower_id_fkey(*)')
          .eq('following_id', userId);

      return data
          .map(
            (row) => Profile.fromJson(row['profiles'] as Map<String, dynamic>),
          )
          .toList();
    });

final userActionsProvider = Provider((ref) => UserActions(ref));

class UserActions {
  final Ref ref;
  UserActions(this.ref);

  Future<void> follow(String targetUserId) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      await supabase.from('follows').insert({
        'follower_id': userId,
        'following_id': targetUserId,
      });

      ref.invalidate(followingListProvider);
      ref.invalidate(isFollowingProvider(targetUserId));
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).followFailed,
      );
    }
  }

  Future<void> unfollow(String targetUserId) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      await supabase
          .from('follows')
          .delete()
          .eq('follower_id', userId)
          .eq('following_id', targetUserId);

      ref.invalidate(followingListProvider);
      ref.invalidate(isFollowingProvider(targetUserId));
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).unfollowFailed,
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
