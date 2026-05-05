import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';

final followingListProvider =
    FutureProvider.autoDispose<List<Profile>>((ref) async {
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

final followerCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, userId) async {
  final result = await supabase
      .from('follows')
      .select()
      .eq('following_id', userId)
      .count();

  return result.count;
});

final followingCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, userId) async {
  final result = await supabase
      .from('follows')
      .select()
      .eq('follower_id', userId)
      .count();

  return result.count;
});

final isFollowingProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, targetUserId) async {
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

final userLibraryProvider =
    FutureProvider.autoDispose.family<List<Shelf>, String>(
  (ref, targetUserId) async {
    final data = await supabase
        .from('shelves')
        .select('*, books(*)')
        .eq('user_id', targetUserId)
        .order('position');

    return data.map((s) => Shelf.fromJson(s)).toList();
  },
);

final searchUsersProvider =
    FutureProvider.autoDispose.family<List<Profile>, String>(
  (ref, query) async {
    if (query.isEmpty) return [];

    final data = await supabase
        .from('profiles')
        .select()
        .ilike('username', '%$query%')
        .limit(20);

    return data.map((p) => Profile.fromJson(p)).toList();
  },
);

final userActionsProvider = Provider((ref) => UserActions(ref));

class UserActions {
  final Ref ref;
  UserActions(this.ref);

  Future<void> follow(String targetUserId) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase.from('follows').insert({
      'follower_id': userId,
      'following_id': targetUserId,
    });

    ref.invalidate(followingListProvider);
    ref.invalidate(isFollowingProvider(targetUserId));
  }

  Future<void> unfollow(String targetUserId) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('follows')
        .delete()
        .eq('follower_id', userId)
        .eq('following_id', targetUserId);

    ref.invalidate(followingListProvider);
    ref.invalidate(isFollowingProvider(targetUserId));
  }
}
