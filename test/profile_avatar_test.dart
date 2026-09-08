// `avatar_path` is the one field a client both writes and is trusted about, so
// the two pieces of logic around it are pinned here: that it survives the wire,
// and that a picked filename is normalised to something the bucket's
// `allowed_mime_types` will actually accept.
//
// The other half of the guard is not testable from Dart: the
// `profiles_avatar_path_owned` CHECK constraint, which refuses a path in someone
// else's folder. That is verified against the linked database instead — see the
// profile-photos design record.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';

Map<String, dynamic> _row({String? avatarPath}) => {
  'id': 'u1',
  'username': 'jisoo',
  'emoji': '🦊',
  'avatar_path': avatarPath,
  'fcm_token': null,
  'created_at': '2024-01-01T00:00:00Z',
  'updated_at': '2024-01-01T00:00:00Z',
};

void main() {
  group('Profile.fromJson', () {
    test('Given a row with an avatar path, When it is parsed, Then the path is '
        'carried through', () {
      final profile = Profile.fromJson(_row(avatarPath: 'u1/abc123.jpg'));

      expect(profile.avatarPath, 'u1/abc123.jpg');
      // The emoji is not displaced by the photo. It is still the fallback.
      expect(profile.emoji, '🦊');
    });

    test(
      'Given a row with no avatar path, When it is parsed, Then the profile is '
      'emoji-only',
      () {
        expect(Profile.fromJson(_row()).avatarPath, isNull);
      },
    );
  });

  group('avatarExtensionFor', () {
    test(
      'Given a filename the bucket accepts, When normalised, Then the extension '
      'is preserved and lowercased',
      () {
        // Not assumed to be JPEG: the native resizers re-encode a JPEG source as
        // JPEG but can keep PNG on Android, and a mislabelled upload is rejected
        // by the bucket outright.
        expect(avatarExtensionFor('IMG_0001.JPG'), 'jpg');
        expect(avatarExtensionFor('photo.jpeg'), 'jpeg');
        expect(avatarExtensionFor('shot.PNG'), 'png');
        expect(avatarExtensionFor('pic.webp'), 'webp');
      },
    );

    test(
      'Given a filename the bucket would reject, When normalised, Then it falls '
      'back to jpg',
      () {
        expect(avatarExtensionFor('scan.heic'), 'jpg');
        expect(avatarExtensionFor('clip.gif'), 'jpg');
      },
    );

    test('Given a filename with no usable extension, When normalised, Then it '
        'falls back to jpg', () {
      expect(avatarExtensionFor('no-extension'), 'jpg');
      expect(avatarExtensionFor('trailing.'), 'jpg');
      expect(avatarExtensionFor(''), 'jpg');
    });

    test(
      'Given a name with dots before the extension, When normalised, Then only '
      'the last segment is read',
      () {
        expect(avatarExtensionFor('my.holiday.photo.png'), 'png');
      },
    );
  });
}
