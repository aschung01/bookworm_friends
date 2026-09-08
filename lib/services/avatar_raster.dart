import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:bookworm_friends/services/avatar_image.dart';
import 'package:bookworm_friends/services/widget_png_renderer.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';

/// The reader's avatar, as PNG bytes a native button can wear.
///
/// **Why this exists at all.** `AdaptiveGlassCircle` used to draw the avatar as Flutter
/// content layered *over* a glass `CNButton`, and the press then looked wrong: UIKit
/// highlights the button, but a Flutter widget sitting on top of a platform view knows
/// nothing about that, so the glass reacted and the face did not. Three attempts to
/// mirror the press from Dart each shipped a worse defect — see
/// `AdaptiveGlassCircle`'s note, which records all three.
///
/// The fix is to stop layering. `CNButton` takes a [CNImageAsset] with raw
/// `imageData`, and on that path the image becomes the button's own `UIImage`, handed
/// to `setButtonContent` exactly as an SF Symbol is. `adjustsImageWhenHighlighted` is
/// set on every one of these buttons, so the avatar then gets the *same* native press
/// treatment the ✕ and share glyphs already get. Nothing is guessed.
///
/// Getting there needs the avatar as bytes, which is what this file is.
///
/// **Rasterised rather than sent as the source photo.** The stored avatar is a bare
/// image in a bucket: uncropped, unrounded, sometimes not square. What belongs on the
/// button is [AvatarCircle]'s *rendering* of it — clipped to a circle, `BoxFit.cover`,
/// with the emoji fallback when there is no photo. Rasterising the widget means the
/// button wears exactly what the rest of the app draws, from one definition, instead
/// of a second circle-cropping implementation in Swift.
class AvatarRaster {
  const AvatarRaster._();

  /// Pixel density of the raster.
  ///
  /// 3 rather than the device's own, for the same reason `shareLibraryCard` pins it:
  /// the bytes are cached and may outlive a move between displays, and an image that
  /// is too dense only costs memory where one that is too sparse cannot be repaired.
  static const double pixelRatio = 3;
}

/// Identifies the avatar a raster was made from.
///
/// **The cache key is the identity, not the reader.** Keying on user id would go stale
/// the moment a profile photo changed and hand the button the previous face; keying on
/// the rendered inputs means a change *is* a different key, so a stale entry can never
/// be served. Diameter is in it because the raster is resolution-specific.
@immutable
class AvatarRasterKey {
  final String? emoji;
  final String? avatarPath;
  final double diameter;

  const AvatarRasterKey({
    required this.emoji,
    required this.avatarPath,
    required this.diameter,
  });

  @override
  bool operator ==(Object other) =>
      other is AvatarRasterKey &&
      other.emoji == emoji &&
      other.avatarPath == avatarPath &&
      other.diameter == diameter;

  @override
  int get hashCode => Object.hash(emoji, avatarPath, diameter);

  @override
  String toString() =>
      'AvatarRasterKey(emoji: $emoji, avatarPath: $avatarPath, '
      'diameter: $diameter)';
}

/// Rasters already produced, so a rebuild does not re-encode a PNG.
///
/// A plain map rather than an `LruCache`: the entries are keyed by what is drawn, and
/// this app draws its *own* avatar in one place at one size. In practice that is one
/// entry, two while a photo change settles. [clearAvatarRasterCache] exists for tests
/// rather than for eviction.
final Map<AvatarRasterKey, Uint8List> _cache = <AvatarRasterKey, Uint8List>{};

/// In-flight rasters, so N rebuilds during one await do not start N captures.
///
/// Without this the first frame after a profile loads can fire several overlapping
/// captures for the same key — each mounting an overlay entry and encoding a PNG — and
/// they would all write the same bytes at the end. Sharing the future makes the
/// duplicate builds cheap and keeps exactly one overlay in the tree.
final Map<AvatarRasterKey, Future<Uint8List?>> _inFlight =
    <AvatarRasterKey, Future<Uint8List?>>{};

/// Bytes for [key] if they are already in hand, and null if they are not.
///
/// Synchronous by design: it is called from `build`, which cannot await. Null is the
/// caller's cue to draw its non-native fallback for this frame and try again once
/// [rasterizeAvatar] reports back.
Uint8List? cachedAvatarRaster(AvatarRasterKey key) => _cache[key];

/// Produces the PNG for [key], or null if it could not be made.
///
/// Null rather than a throw, and it is a working state: every caller has a Flutter
/// rendering of the avatar to fall back on, so a failed raster costs the native press
/// response and nothing else. The alternative — letting it throw — would take out the
/// profile button over a transient decode failure.
///
/// [context] must be under an [Overlay]; see [captureWidgetToPng], which hosts the
/// subtree off-screen there.
Future<Uint8List?> rasterizeAvatar(BuildContext context, AvatarRasterKey key) {
  final done = _cache[key];
  if (done != null) return Future<Uint8List?>.value(done);

  final running = _inFlight[key];
  if (running != null) return running;

  final future = _rasterize(context, key);
  _inFlight[key] = future;
  return future;
}

Future<Uint8List?> _rasterize(BuildContext context, AvatarRasterKey key) async {
  try {
    final bytes = await captureWidgetToPng(
      context: context,
      logicalSize: Size(key.diameter, key.diameter),
      pixelRatio: AvatarRaster.pixelRatio,
      // The photo has to be decoded *before* the boundary is captured or it exports
      // as a hole — `captureWidgetToPng` says so at length. Emoji-mode avatars draw
      // no image at all, so they precache nothing.
      precache: [
        if (key.avatarPath != null) avatarImageProvider(key.avatarPath!),
      ],
      // **No `Material` ancestor and no fill.** The overlay gives the subtree none,
      // which matters for `Text`: `MaterialApp` installs a fallback `DefaultTextStyle`
      // carrying a yellow debug underline, and an emoji drawn without a style of its
      // own would inherit it — invisible everywhere except in these bytes. `Material`
      // with a transparent type is the cheapest way to be out of that path while
      // keeping the PNG's background clear, which it must be: the glass disc is what
      // shows through behind the face.
      widget: Material(
        type: MaterialType.transparency,
        child: AvatarCircle(
          emoji: key.emoji,
          avatarPath: key.avatarPath,
          diameter: key.diameter,
          // The button's own disc is the fill. See `home_page._LibraryBar`, which
          // passes the same false on its glass path for the same reason.
          filled: false,
        ),
      ),
    );
    _cache[key] = bytes;
    return bytes;
  } catch (_) {
    // Swallowed for the reason on this function: the caller has a fallback, and a
    // profile button that disappears is worse than one without a press animation.
    return null;
  } finally {
    _inFlight.remove(key);
  }
}

/// Drops every cached raster.
///
/// For tests, which would otherwise leak one suite's bytes into the next. Production
/// has no reason to call it: a changed avatar is a changed [AvatarRasterKey], so the
/// stale entry is never looked up again.
@visibleForTesting
void clearAvatarRasterCache() {
  _cache.clear();
  _inFlight.clear();
}

/// How many rasters are held, for tests that assert the cache and the in-flight map
/// actually collapse duplicate work.
@visibleForTesting
int get avatarRasterCacheSize => _cache.length;

/// Puts [bytes] in the cache for [key] as though a capture had produced them.
///
/// **The only way to reach the post-capture states from a test.** A real capture cannot
/// run under `flutter test` — `captureWidgetToPng` needs two real frames and then
/// `runAsync`, which a test cannot pump inside — so without this seam every test sees
/// the same first frame, and the interesting behaviour (serving a cached raster
/// synchronously, and *dropping* one that has gone stale) is untestable. That gap was
/// real: a mutation which kept stale bytes across a profile change passed the whole
/// suite before this existed.
///
/// Seeding the cache rather than faking the capture keeps the seam narrow — production
/// code paths are exercised exactly as written, and only the bytes' origin differs.
@visibleForTesting
void seedAvatarRaster(AvatarRasterKey key, Uint8List bytes) {
  _cache[key] = bytes;
}
