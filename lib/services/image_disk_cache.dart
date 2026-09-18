import 'package:cached_network_image_ce/cached_network_image.dart';

/// Sizes the on-disk image cache that covers and avatars share.
///
/// **Call once, from `main`, before the first image resolves.** It only assigns a static;
/// [DefaultCacheManager] opens no box and touches no plugin until something actually asks
/// it for a file, so this costs nothing at startup and stays inert under `flutter test`.
///
/// **One cache, not two, and that is forced rather than chosen.** The Hive box name inside
/// `DefaultCacheManager` is a top-level constant, so a second instance would open the same
/// box as the first and the two would fight over it. Covers and avatars therefore share
/// these numbers, which is why the reasoning below has to hold for both.
void configureImageDiskCache() {
  CachedNetworkImageProvider.defaultCacheManager = DefaultCacheManager(
    // The package default is 200, which was survivable while avatars were the only
    // thing in here and is not now: one reader's own library can exceed 200 covers on
    // its own, and every friend's shelf adds more. At these sizes a cover is ~10-30KB,
    // so 800 is roughly 20MB of a temporary directory the OS may reclaim anyway.
    maxNrOfCacheObjects: 800,
    // The package default is 7 days. Long is safe here because **neither kind of URL
    // changes what it serves**: a catalogue cover URL is immutable, and an avatar gets a
    // fresh random filename on every upload — which is exactly what the profile-photos
    // record relies on to bust this cache. A short period would re-download unchanged
    // bytes and nothing else.
    stalePeriod: const Duration(days: 90),
    // **No `cleanupStrategy: LruCleanupStrategy()`, and not for want of wanting it.**
    // LRU is the right policy here — TTL evicts by expiry, and a shelf's covers are
    // fetched within seconds of each other, so their expiries are near-identical and the
    // choice of victim is effectively arbitrary. But `DefaultCacheManager` reaches this
    // file through a conditional export, and the unsupported-platform stub's constructor
    // takes only the two arguments above. Passing a third is an analyzer error even
    // though the `dart.library.io` implementation would accept it, so the portable
    // surface is the intersection. Raising the object count is the lever we do have.
  );
}
