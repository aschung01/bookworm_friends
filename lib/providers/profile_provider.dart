import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException;
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/handle.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/avatar_image.dart';
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
      EasyLoading.showSuccess(l10n.usernameChanged);
    } catch (e) {
      EasyLoading.showError(l10n.usernameChangeFailed);
    }
  }

  /// Sets `profiles.handle`: the Latin identity the exported card's strip prints.
  ///
  /// **Two failures, told apart, because they need different answers.** A handle is
  /// `UNIQUE` and format-checked in the database, so a rejected update is either "someone
  /// has that" — pick another — or "that is not a handle" — fix these characters. Reporting
  /// both as "couldn't save" is how a reader ends up retyping a name that was never going
  /// to be accepted. Postgres reports them as distinct codes: `23505` for the unique index
  /// and `23514` for the check.
  ///
  /// The format is checked client-side first, so the common mistake never becomes a round
  /// trip — but the check is not *trusted*, because the database's is the one that binds.
  Future<bool> updateHandle(String handle) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return false;

    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    if (!isValidHandle(handle)) {
      EasyLoading.showError(l10n.handleInvalid);
      return false;
    }

    EasyLoading.show();
    try {
      await supabase
          .from('profiles')
          .update({'handle': handle})
          .eq('id', userId);

      ref.invalidate(profileProvider);
      EasyLoading.showSuccess(l10n.handleChanged);
      return true;
    } on PostgrestException catch (error) {
      EasyLoading.showError(
        error.code == '23505' ? l10n.handleTaken : l10n.handleInvalid,
      );
      return false;
    } catch (_) {
      EasyLoading.showError(l10n.handleChangeFailed);
      return false;
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

  /// Replaces the photo avatar with [bytes], already resized by the picker.
  ///
  /// [extension] comes from the picked file rather than being assumed: the
  /// native resizers re-encode to JPEG for a JPEG source but can keep PNG on
  /// Android, and the bucket's `allowed_mime_types` rejects a mislabelled
  /// upload outright.
  ///
  /// The order here is load-bearing, and the failure modes are lopsided on
  /// purpose. Upload first, so a crash leaves an orphaned object that nobody can
  /// see and account deletion sweeps up. Updating the row first — or deleting the
  /// old object before the row moves — would instead leave a profile pointing at
  /// something that is not there, which the user *does* see. Prefer the orphan.
  Future<void> updateAvatar(Uint8List bytes, String extension) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    final previousPath = ref.read(profileProvider).valueOrNull?.avatarPath;

    EasyLoading.show();
    try {
      // A fresh random name every time. Nothing upserts, so Supabase's
      // "upsert needs INSERT + SELECT + UPDATE" trap never comes up, and the new
      // path is itself the cache-buster.
      final path = '$userId/${_randomFileId()}.$extension';

      await supabase.storage
          .from(avatarBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: _contentTypeFor(extension)),
          );

      await supabase
          .from('profiles')
          .update({'avatar_path': path})
          .eq('id', userId);

      // Best-effort. The read policy joins through `profiles.avatar_path`, so the
      // old object stopped being readable the moment the row moved; this only
      // reclaims the bytes.
      if (previousPath != null) {
        try {
          await supabase.storage.from(avatarBucket).remove([previousPath]);
        } catch (_) {}
      }

      ref.invalidate(profileProvider);
      EasyLoading.showSuccess(l10n.photoChanged);
    } catch (e) {
      EasyLoading.showError(l10n.photoChangeFailed);
    }
  }

  /// Drops back to the emoji avatar.
  ///
  /// Clears the row before deleting the object, for the same reason the upload
  /// writes the row last: the pointer should never outlive what it points at.
  Future<void> removeAvatar() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    final previousPath = ref.read(profileProvider).valueOrNull?.avatarPath;
    if (previousPath == null) return;

    try {
      await supabase
          .from('profiles')
          .update({'avatar_path': null})
          .eq('id', userId);

      try {
        await supabase.storage.from(avatarBucket).remove([previousPath]);
      } catch (_) {}

      ref.invalidate(profileProvider);
    } catch (e) {
      EasyLoading.showError(l10n.photoChangeFailed);
    }
  }

  // `updatePrivacy` is gone with the `is_private` column.
  //
  // Under friends-only there is nothing for it to gate: visibility is friendship, and
  // with no handle search there is no directory to be absent from. The Settings switch
  // that called this ("Allow profile search") went in the same change — it described a
  // search that no longer exists.

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

/// Extensions the `avatars` bucket accepts, mapped to the mime types its
/// `allowed_mime_types` list will let through. Anything else is normalised to
/// JPEG, which is what the picker produces in every case we have seen.
const Map<String, String> _avatarContentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

String _contentTypeFor(String extension) =>
    _avatarContentTypes[extension.toLowerCase()] ?? 'image/jpeg';

/// Normalises a picked file's extension to one the bucket accepts.
String avatarExtensionFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot == -1 || dot == fileName.length - 1) return 'jpg';
  final ext = fileName.substring(dot + 1).toLowerCase();
  return _avatarContentTypes.containsKey(ext) ? ext : 'jpg';
}

final _random = Random.secure();

/// An unguessable filename, so replacing a photo is always a new path.
///
/// Unguessable matters even in a private bucket: the read policy is the actual
/// boundary, but a predictable name would make an orphaned object trivially
/// addressable if a policy were ever loosened.
String _randomFileId() {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(
    16,
    (_) => alphabet[_random.nextInt(alphabet.length)],
  ).join();
}
