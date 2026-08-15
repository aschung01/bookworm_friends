import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/notification_service.dart'
    show navigatorKey;

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

    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    EasyLoading.show();
    try {
      await supabase
          .from('profiles')
          .update({'username': username})
          .eq('id', userId);

      ref.invalidate(profileProvider);
      EasyLoading.showSuccess(l10n.nicknameChanged);
    } catch (e) {
      EasyLoading.showError(l10n.nicknameChangeFailed);
    }
  }

  Future<void> updateEmoji(String emoji) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      await supabase.from('profiles').update({'emoji': emoji}).eq('id', userId);

      ref.invalidate(profileProvider);
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).emojiChangeFailed,
      );
    }
  }

  Future<void> updatePrivacy(bool isPrivate) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      await supabase
          .from('profiles')
          .update({'is_private': isPrivate})
          .eq('id', userId);

      ref.invalidate(profileProvider);
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).settingChangeFailed,
      );
    }
  }

  Future<void> updateFcmToken(String token) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      await supabase
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
    } catch (_) {}
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
