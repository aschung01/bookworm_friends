// The fork keeps the original's library name, so the import path is
// `cached_network_image_ce/cached_network_image.dart` rather than the doubled
// `_ce` you would expect from the package name.
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'package:bookworm_friends/core/supabase_config.dart';

/// Resolves a stored avatar path to something [Image] can draw.
///
/// The `avatars` bucket is private, so this cannot be a plain public URL. It
/// does not need to be a *signed* one either: Supabase serves
/// `GET /storage/v1/object/{bucket}/{path}` to an authenticated caller and
/// enforces the bucket's RLS policies per request. That URL carries no
/// signature, which is the whole point — it is stable and permanent, so the
/// disk cache keys on it cleanly, and authorisation lives in a header the cache
/// never sees. Signed URLs would rotate their query string and miss the cache
/// on every refresh, for no gain in access control.
typedef AvatarImageResolver = ImageProvider Function(String path);

/// Swappable so widget tests can draw an avatar without a network.
///
/// Flutter's test binding stubs HTTP to return 400, so a real
/// [CachedNetworkImageProvider] throws under `flutter test`. Tests assign a
/// [MemoryImage] factory here and restore [networkAvatarImage] afterwards.
///
/// Deliberately not `@visibleForTesting`: [AvatarCircle] reads it on every
/// build, so the annotation would be a lie that the analyzer rightly complains
/// about. It is the seam, not a back door.
AvatarImageResolver avatarImageProvider = networkAvatarImage;

/// The production resolver. Kept public so tests can restore it.
ImageProvider networkAvatarImage(String path) {
  return CachedNetworkImageProvider(
    '$supabaseUrl/storage/v1/object/$avatarBucket/$path',
    // Read at call time, never captured: `supabase_flutter` refreshes the
    // session in the background, so a token held across a refresh goes stale.
    // A disk-cache hit needs no token at all, so this only matters on a miss.
    headers: {
      'apikey': supabaseAnonKey,
      'Authorization':
          'Bearer ${supabase.auth.currentSession?.accessToken ?? ''}',
    },
    // The URL already changes with the path — every upload gets a fresh random
    // filename — so this is belt-and-braces rather than the cache-buster.
    cacheKey: path,
  );
}

/// The one bucket this app stores images in.
const String avatarBucket = 'avatars';
