// The avatar, as bytes a native button can wear.
//
// `AdaptiveGlassCircle` used to layer the avatar over a glass `CNButton`, and the
// press looked wrong because UIKit highlights the button while a Flutter widget on
// top of a platform view knows nothing about it. Handing the avatar to the button as
// `imageData` fixes that at the root: it becomes the button's own `UIImage` and gets
// the same `adjustsImageWhenHighlighted` treatment the SF Symbols already get.
//
// This file covers the half of that which `flutter test` can actually reach. The
// capture itself cannot be: `captureWidgetToPng` waits on two real frames, which only
// arrive when a test pumps, while PNG encoding needs `runAsync` — and a test cannot
// pump from inside `runAsync`. `widget_png_renderer_test.dart` records the same
// constraint and splits `rasterizeBoundary` out for exactly this reason.
//
// So what is pinned here is everything around the capture, which is where the bugs
// that actually bite live:
//
//   * **The key**, because it is the whole cache-invalidation story. Keyed on what is
//     drawn rather than on the reader, so a changed photo cannot serve a stale face.
//   * **Deduplication**, because without it the frame a profile lands on fires several
//     overlapping captures for one key, each mounting an overlay.
//   * **Failure is null, not a throw**, because the caller's fallback is a working
//     state and an exception here would take out the profile button.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/avatar_raster.dart';

void main() {
  setUp(clearAvatarRasterCache);
  tearDown(clearAvatarRasterCache);

  group('AvatarRasterKey', () {
    test(
      'Given the same emoji, path and size, Then two keys are interchangeable',
      () {
        // Value equality is what makes the cache a cache. Without it every rebuild
        // constructs a fresh key, misses, and re-encodes a PNG.
        const a = AvatarRasterKey(
          emoji: '🦄',
          avatarPath: 'u/abc.jpg',
          diameter: 44,
        );
        const b = AvatarRasterKey(
          emoji: '🦄',
          avatarPath: 'u/abc.jpg',
          diameter: 44,
        );

        expect(a, b);
        expect(a.hashCode, b.hashCode);
      },
    );

    test('Given a profile photo that changed, Then the key changes with it', () {
      // **The invalidation story, and the reason the key is not the user id.** Every
      // upload writes a fresh random filename, so a new photo is a new path, is a
      // new key, is a miss. A stale raster is not evicted because it is never asked
      // for again.
      const before = AvatarRasterKey(
        emoji: null,
        avatarPath: 'u/old.jpg',
        diameter: 44,
      );
      const after = AvatarRasterKey(
        emoji: null,
        avatarPath: 'u/new.jpg',
        diameter: 44,
      );

      expect(before, isNot(after));
    });

    test('Given a switch from photo to emoji, Then the key changes', () {
      // Clearing a photo leaves the emoji standing, and the two render completely
      // differently — `AvatarCircle` treats them as modes, not layers.
      const photo = AvatarRasterKey(
        emoji: '🦄',
        avatarPath: 'u/abc.jpg',
        diameter: 44,
      );
      const emoji = AvatarRasterKey(
        emoji: '🦄',
        avatarPath: null,
        diameter: 44,
      );

      expect(photo, isNot(emoji));
    });

    test('Given two sizes of one avatar, Then the rasters are distinct', () {
      // The bytes are resolution-specific, so a 36pt button must not be handed the
      // 44pt bar's raster.
      const small = AvatarRasterKey(
        emoji: '🦄',
        avatarPath: null,
        diameter: 36,
      );
      const large = AvatarRasterKey(
        emoji: '🦄',
        avatarPath: null,
        diameter: 44,
      );

      expect(small, isNot(large));
    });
  });

  group('the cache', () {
    test('Given nothing rasterised yet, Then there is nothing to serve', () {
      // The state every caller starts in, and the one that makes the synchronous
      // getter safe to call from `build`: null means "draw your fallback this frame".
      expect(
        cachedAvatarRaster(
          const AvatarRasterKey(emoji: '🦄', avatarPath: null, diameter: 44),
        ),
        isNull,
      );
      expect(avatarRasterCacheSize, 0);
    });

    testWidgets(
      'Given a capture that cannot succeed, When it is requested, Then it reports '
      'null rather than throwing',
      (tester) async {
        // Failure has to be survivable. There is no `Overlay` in this tree, so
        // `captureWidgetToPng` cannot host its subtree and throws — which stands in
        // for any capture failure on a device. The caller keeps its Flutter rendering
        // and loses only the native press response.
        late BuildContext ctx;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        );

        Uint8List? bytes;
        Object? thrown;
        try {
          bytes = await rasterizeAvatar(
            ctx,
            const AvatarRasterKey(emoji: '🦄', avatarPath: null, diameter: 44),
          );
        } catch (e) {
          thrown = e;
        }

        expect(thrown, isNull, reason: 'a failed raster is not an error state');
        expect(bytes, isNull);
      },
    );

    testWidgets(
      'Given a failed capture, When it is retried, Then nothing was cached from it',
      (tester) async {
        // Only successes are cached. Caching a failure would make it permanent, and
        // the common cause on a device is a photo that has not finished downloading —
        // which fixes itself on the next attempt.
        late BuildContext ctx;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        );

        const key = AvatarRasterKey(
          emoji: '🦄',
          avatarPath: null,
          diameter: 44,
        );
        await rasterizeAvatar(ctx, key);

        expect(avatarRasterCacheSize, 0);
        expect(cachedAvatarRaster(key), isNull);
      },
    );

    testWidgets(
      'Given several rebuilds during one capture, Then they share a single attempt',
      (tester) async {
        // **The deduplication guard.** The frame a profile lands on can rebuild the
        // bar repeatedly, and without the in-flight map each rebuild would mount its
        // own overlay entry and encode its own PNG for the same key. Identity of the
        // returned future is the assertion: same object means same capture.
        late BuildContext ctx;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        );

        const key = AvatarRasterKey(
          emoji: '🦄',
          avatarPath: null,
          diameter: 44,
        );

        final first = rasterizeAvatar(ctx, key);
        final second = rasterizeAvatar(ctx, key);

        expect(identical(first, second), isTrue);

        await Future.wait([first, second]);
      },
    );

    testWidgets(
      'Given a finished attempt, When the same key is asked for again, Then it is '
      'not still held as in flight',
      (tester) async {
        // The in-flight entry has to be released whatever the outcome, or a key that
        // failed once would hand every later caller the same dead future and never
        // retry.
        late BuildContext ctx;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        );

        const key = AvatarRasterKey(
          emoji: '🦄',
          avatarPath: null,
          diameter: 44,
        );

        final first = rasterizeAvatar(ctx, key);
        await first;
        final second = rasterizeAvatar(ctx, key);

        expect(
          identical(first, second),
          isFalse,
          reason: 'the first attempt is done, so this is a fresh one',
        );

        await second;
      },
    );
  });
}
