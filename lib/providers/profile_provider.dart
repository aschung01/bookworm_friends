import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';

final profileProvider = FutureProvider.autoDispose<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final data = await supabase
      .from('profiles')
      .select()
      .eq('id', userId)
      .single();

  return Profile.fromJson(data);
});

final updateProfileProvider = Provider((ref) => UpdateProfileNotifier(ref));

class UpdateProfileNotifier {
  final Ref ref;
  UpdateProfileNotifier(this.ref);

  Future<void> updateUsername(String username) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'username': username})
        .eq('id', userId);

    ref.invalidate(profileProvider);
  }

  Future<void> updateEmoji(String emoji) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'emoji': emoji})
        .eq('id', userId);

    ref.invalidate(profileProvider);
  }

  Future<void> updatePrivacy(bool isPrivate) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'is_private': isPrivate})
        .eq('id', userId);

    ref.invalidate(profileProvider);
  }

  Future<void> updateFcmToken(String token) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase
        .from('profiles')
        .update({'fcm_token': token})
        .eq('id', userId);
  }

  Future<bool> checkUsernameAvailable(String username) async {
    final data = await supabase
        .from('profiles')
        .select('id')
        .eq('username', username)
        .maybeSingle();

    return data == null;
  }
}
