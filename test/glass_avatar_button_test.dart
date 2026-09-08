// The avatar button's raster lifecycle.
//
// `AdaptiveGlassCircle` can put its content *inside* the native button, which is the
// only way UIKit transforms it along with the glass on press. That needs PNG bytes,
// and producing them is asynchronous — an off-screen capture, preceded by a network
// fetch for photo avatars. `GlassAvatarButton` owns that: ask, draw the Flutter
// fallback meanwhile, ask again when the profile changes.
//
// **What is testable here, and what is not.** The capture itself is not:
// `captureWidgetToPng` waits on two real frames while PNG encoding needs `runAsync`,
// and a test cannot pump from inside `runAsync` — `widget_png_renderer_test.dart`
// records the same constraint. Nor is the native rendering: `useNativeGlass` is false
// under `flutter test`, so the Material fallback is what draws.
//
// So these tests pin the state machine around the capture, which is where the bugs
// that reach a reader live: showing the *previous* face after a profile change, and
// writing bytes into a widget that has moved on or gone away.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/avatar_image.dart';
import 'package:bookworm_friends/services/avatar_raster.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/glass_avatar_button.dart';

/// A provider that resolves immediately, so photo-mode avatars can be drawn without
/// a network.
///
/// The test binding stubs HTTP to 400 and the real resolver reaches for the Supabase
/// singleton, which is not initialised here — `avatar_image.dart` documents
/// [avatarImageProvider] as the seam for exactly this.
class _LoadedImage extends ImageProvider<_LoadedImage> {
  _LoadedImage(this.image);

  final ui.Image image;

  @override
  Future<_LoadedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_LoadedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _LoadedImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
  );
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

AdaptiveGlassCircle _circle(WidgetTester tester) =>
    tester.widget<AdaptiveGlassCircle>(find.byType(AdaptiveGlassCircle));

AvatarCircle _avatar(WidgetTester tester) =>
    tester.widget<AvatarCircle>(find.byType(AvatarCircle));

void main() {
  late ui.Image testImage;

  setUp(() async {
    clearAvatarRasterCache();
    testImage = await createTestImage(width: 1, height: 1);
    avatarImageProvider = (_) => _LoadedImage(testImage);
  });

  tearDown(() {
    clearAvatarRasterCache();
    // Otherwise a later test in the same process would quietly keep the fake.
    avatarImageProvider = networkAvatarImage;
  });

  testWidgets(
    'Given no raster yet, When the button first builds, Then it draws the Flutter '
    'fallback rather than a gap',
    (tester) async {
      // The first frame always looks like this, and on a machine where the capture
      // cannot run it is the only frame. A button that waited for bytes before
      // drawing anything would be a hole in the bar.
      await tester.pumpWidget(
        _wrap(
          const GlassAvatarButton(
            emoji: '🦄',
            avatarPath: null,
            semanticLabel: 'Profile',
          ),
        ),
      );

      expect(_circle(tester).imageBytes, isNull);
      expect(find.byType(AvatarCircle), findsOneWidget);
      expect(find.text('🦄'), findsOneWidget);
    },
  );

  testWidgets(
    'Given the button, When it renders, Then the tap target is the full diameter',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          GlassAvatarButton(
            emoji: '🦄',
            avatarPath: null,
            semanticLabel: 'Profile',
            onPressed: () {},
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(AdaptiveGlassCircle)),
        const Size(44, 44),
      );
    },
  );

  testWidgets(
    'Given the Material fallback, When it draws, Then the avatar is inset and filled',
    (tester) async {
      // The two `glass`-dependent choices, on the branch `flutter test` actually
      // renders. Off glass there is no disc, so the avatar takes an `IconButton`'s
      // inset and brings its own fill; the glass branch inverts both.
      await tester.pumpWidget(
        _wrap(
          const GlassAvatarButton(
            emoji: '🦄',
            avatarPath: null,
            semanticLabel: 'Profile',
          ),
        ),
      );

      expect(_avatar(tester).diameter, 32);
      expect(_avatar(tester).filled, isTrue);
    },
  );

  testWidgets(
    'Given the glass branch, When the builder is called, Then the avatar fills the '
    'disc and drops its fill',
    (tester) async {
      // Driven through the builder because the rendering cannot be reached here. The
      // builder *is* the branch, so calling it with `glass: true` is the assertion —
      // same technique `library_bar_test` uses.
      await tester.pumpWidget(
        _wrap(
          const GlassAvatarButton(
            emoji: '🦄',
            avatarPath: null,
            semanticLabel: 'Profile',
          ),
        ),
      );

      final onGlass =
          _circle(
                tester,
              ).builder(tester.element(find.byType(AdaptiveGlassCircle)), true)
              as AvatarCircle;

      expect(onGlass.diameter, 44, reason: 'the avatar is the disc');
      expect(
        onGlass.filled,
        isFalse,
        reason: 'an opaque fill at full diameter would hide the glass',
      );
    },
  );

  testWidgets('Given a profile that changes, When the new one arrives, Then the old face is '
      'not still on the button', (tester) async {
    // **The bug this exists for.** Bytes in hand belong to the *previous* avatar,
    // so a change has to drop them even though the replacement is not ready. One
    // frame of the fallback is correct; a frame of somebody else's photo is not.
    //
    // Asserted through the forwarded props rather than pixels, because the capture
    // never runs here — what matters is that the widget re-keys and re-requests.
    await tester.pumpWidget(
      _wrap(
        const GlassAvatarButton(
          emoji: '🦄',
          avatarPath: 'u/old.jpg',
          semanticLabel: 'Profile',
        ),
      ),
    );
    expect(_avatar(tester).avatarPath, 'u/old.jpg');

    await tester.pumpWidget(
      _wrap(
        const GlassAvatarButton(
          emoji: '🦄',
          avatarPath: 'u/new.jpg',
          semanticLabel: 'Profile',
        ),
      ),
    );

    expect(_circle(tester).imageBytes, isNull);
    expect(_avatar(tester).avatarPath, 'u/new.jpg');
  });

  testWidgets(
    'Given a photo cleared back to an emoji, When it rebuilds, Then the emoji is '
    'what is drawn',
    (tester) async {
      // `AvatarCircle` treats the two as modes rather than layers, so this is a
      // different rendering and a different raster key — not a smaller change than
      // swapping one photo for another.
      await tester.pumpWidget(
        _wrap(
          const GlassAvatarButton(
            emoji: '🦄',
            avatarPath: 'u/old.jpg',
            semanticLabel: 'Profile',
          ),
        ),
      );

      await tester.pumpWidget(
        _wrap(
          const GlassAvatarButton(
            emoji: '🦄',
            avatarPath: null,
            semanticLabel: 'Profile',
          ),
        ),
      );

      expect(_avatar(tester).avatarPath, isNull);
      expect(find.text('🦄'), findsOneWidget);
      expect(_circle(tester).imageBytes, isNull);
    },
  );

  testWidgets(
    'Given a rebuild with the same profile, When nothing changed, Then the button is '
    'left alone',
    (tester) async {
      // The common case, and it must not re-request: an identical key means the
      // in-flight future or the cached bytes already cover it.
      await tester.pumpWidget(
        _wrap(
          const GlassAvatarButton(
            emoji: '🦄',
            avatarPath: null,
            semanticLabel: 'Profile',
          ),
        ),
      );
      await tester.pumpWidget(
        _wrap(
          const GlassAvatarButton(
            emoji: '🦄',
            avatarPath: null,
            semanticLabel: 'Profile',
          ),
        ),
      );

      expect(find.byType(AvatarCircle), findsOneWidget);
      expect(
        avatarRasterCacheSize,
        0,
        reason: 'nothing could be captured here',
      );
    },
  );

  group('cached rasters', () {
    // **These are the only tests that reach the states *after* a capture.** Everything
    // above sees the first frame and nothing else, because a real capture cannot run
    // here. `seedAvatarRaster` puts bytes in the cache as though one had, which is what
    // makes the two behaviours below observable at all.
    //
    // They are not decoration. Both were unpinned until this group existed, and the
    // stale-bytes drop — the thing standing between a reader and somebody else's face
    // on their own profile button — survived being deliberately deleted with the whole
    // suite still green.

    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final other = Uint8List.fromList(<int>[9, 9, 9, 9]);

    const key = AvatarRasterKey(
      emoji: '\u{1F984}',
      avatarPath: null,
      diameter: 44,
    );

    testWidgets(
      'Given a raster already cached, When the button first builds, Then it is native '
      'on the very first frame',
      (tester) async {
        // The read is synchronous for this reason: an avatar rasterised earlier this
        // session should not flicker through the Flutter fallback on the way back.
        seedAvatarRaster(key, bytes);

        await tester.pumpWidget(
          _wrap(
            const GlassAvatarButton(
              emoji: '\u{1F984}',
              avatarPath: null,
              semanticLabel: 'Profile',
            ),
          ),
        );

        expect(_circle(tester).imageBytes, same(bytes));
      },
    );

    testWidgets(
      'Given cached bytes for the old profile, When the profile changes, Then the old '
      'face is dropped rather than shown again',
      (tester) async {
        // **The bug this exists to catch.** Holding the bytes for one more frame draws
        // the *previous* reader's face on a profile that has already changed. A frame
        // of the fallback is the correct answer; a frame of the wrong person is not.
        seedAvatarRaster(key, bytes);

        await tester.pumpWidget(
          _wrap(
            const GlassAvatarButton(
              emoji: '\u{1F984}',
              avatarPath: null,
              semanticLabel: 'Profile',
            ),
          ),
        );
        expect(_circle(tester).imageBytes, same(bytes));

        await tester.pumpWidget(
          _wrap(
            const GlassAvatarButton(
              emoji: '\u{1F41B}',
              avatarPath: null,
              semanticLabel: 'Profile',
            ),
          ),
        );

        expect(
          _circle(tester).imageBytes,
          isNull,
          reason:
              'the new emoji has no raster yet, so there is nothing to wear',
        );
        expect(find.text('\u{1F41B}'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the new profile was already rasterised, When it changes, Then it swaps '
      'straight to the new face',
      (tester) async {
        // The other half of the same branch: re-keying must pick up the *new* key's
        // bytes, not merely clear the old ones.
        const next = AvatarRasterKey(
          emoji: '\u{1F41B}',
          avatarPath: null,
          diameter: 44,
        );
        seedAvatarRaster(key, bytes);
        seedAvatarRaster(next, other);

        await tester.pumpWidget(
          _wrap(
            const GlassAvatarButton(
              emoji: '\u{1F984}',
              avatarPath: null,
              semanticLabel: 'Profile',
            ),
          ),
        );
        await tester.pumpWidget(
          _wrap(
            const GlassAvatarButton(
              emoji: '\u{1F41B}',
              avatarPath: null,
              semanticLabel: 'Profile',
            ),
          ),
        );

        expect(_circle(tester).imageBytes, same(other));
      },
    );
  });

  testWidgets(
    'Given no native glass, When the button builds, Then it never starts a capture',
    (tester) async {
      // **The gate that keeps this suite runnable, and it is not only an optimisation.**
      // The raster is only ever read by the native button, so off that path it is
      // waste — but it is also unfinishable here: `captureWidgetToPng` waits on two
      // real frames and then `toImage`, which needs `runAsync`, and a test cannot pump
      // from inside it. The future never completes and the pending work hangs the
      // test. Before this gate existed, mounting the button did exactly that.
      //
      // `useNativeGlass` is false under the test binding, so this is the branch every
      // test takes, and an empty cache is the proof nothing was attempted.
      await tester.pumpWidget(
        _wrap(
          const GlassAvatarButton(
            emoji: '\u{1F984}',
            avatarPath: 'u/a.jpg',
            semanticLabel: 'Profile',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(avatarRasterCacheSize, 0);
      expect(_circle(tester).imageBytes, isNull);
      expect(
        find.byType(AvatarCircle),
        findsOneWidget,
        reason:
            'and no second one off-screen, which is what an overlay capture '
            'would have mounted',
      );
    },
  );

  testWidgets(
    'Given the button is disposed mid-capture, When the frame settles, Then nothing '
    'writes to it',
    (tester) async {
      // The post-frame callback outlives the widget it was scheduled from. Without
      // the `mounted` guard this is a setState-after-dispose, which throws and takes
      // the frame with it.
      await tester.pumpWidget(
        _wrap(
          const GlassAvatarButton(
            emoji: '🦄',
            avatarPath: null,
            semanticLabel: 'Profile',
          ),
        ),
      );
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
