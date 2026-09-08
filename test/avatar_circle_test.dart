// Avatars have two mutually exclusive modes, not two layers: emoji mode, and
// photo mode with its own neutral placeholder. The emoji is deliberately *not*
// the fallback for a failed photo — that would flash a different identity at the
// viewer — so the assertions below are as much about what is absent as present.
//
// Two things make this file necessary rather than incidental:
//
//   1. `AvatarCircle` is now the *only* avatar in the app. Only two of the six
//      sites used to go through it, and the four that drew their own `Text` in a
//      circle disagreed about the fallback glyph. `kDefaultAvatarEmoji` is the
//      single answer, and it is pinned here.
//   2. Flutter's test binding stubs HTTP to return 400, so a real
//      `CachedNetworkImageProvider` throws under `flutter test`.
//      `avatarImageProvider` is the seam that lets an avatar be drawn without a
//      network.
//
// The three providers below exist because the first draft of this file leaned on
// `MemoryImage` and `pumpAndSettle`, and two of its tests contradicted each
// other: image decoding is real async work off the test's fake clock, so the
// frame never arrived — and `MemoryImage` keys on its bytes, so whichever test
// ran second got a *synchronous* cache hit and stopped exercising the load path
// at all. Each state is now explicit and cannot drift on timing.

import 'dart:async' show Completer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/services/avatar_image.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';

/// Resolves on the first frame, so `wasSynchronouslyLoaded` is true.
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
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
    );
  }
}

/// Never resolves, which is the loading state held still.
class _PendingImage extends ImageProvider<_PendingImage> {
  @override
  Future<_PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_PendingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
  }
}

/// Fails immediately, standing in for every non-success: dead network, expired
/// session, deleted object, a 403 from the storage read policy.
class _FailingImage extends ImageProvider<_FailingImage> {
  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FailingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(Exception('avatar unavailable')),
    );
  }
}

Future<void> pumpInApp(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  ),
);

void main() {
  late ui.Image testImage;

  setUp(() async {
    testImage = await createTestImage(width: 1, height: 1);
    avatarImageProvider = (_) => _LoadedImage(testImage);
  });

  tearDown(() {
    // Otherwise a later test in the same process would quietly keep the fake.
    avatarImageProvider = networkAvatarImage;
  });

  group('emoji mode', () {
    testWidgets(
      'Given no photo, When the avatar is drawn, Then it wears the emoji and '
      'never touches the resolver',
      (tester) async {
        var resolverCalls = 0;
        avatarImageProvider = (path) {
          resolverCalls++;
          return _LoadedImage(testImage);
        };

        await pumpInApp(tester, const AvatarCircle(emoji: '🦊'));

        expect(find.text('🦊'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        // The point of keeping the emoji: an emoji-only profile does no work.
        expect(resolverCalls, 0);
      },
    );

    testWidgets(
      'Given a profile with neither photo nor emoji, When the avatar is drawn, '
      'Then it falls back to the one default glyph',
      (tester) async {
        await pumpInApp(tester, const AvatarCircle(emoji: null));

        expect(find.text(kDefaultAvatarEmoji), findsOneWidget);
      },
    );
  });

  group('photo mode', () {
    testWidgets(
      'Given a photo that fails, When the avatar is drawn, Then it shows the '
      'neutral placeholder and never the emoji',
      (tester) async {
        avatarImageProvider = (_) => _FailingImage();

        await pumpInApp(
          tester,
          const AvatarCircle(emoji: '🦊', avatarPath: 'u/abc.jpg'),
        );
        await tester.pump();

        // The emoji is *not* the fallback. Showing it here would flash a
        // different identity at the viewer, who could not then tell an emoji
        // person from a photo person whose picture failed.
        expect(find.text('🦊'), findsNothing);
        expect(find.byIcon(Icons.person_rounded), findsOneWidget);
        // No pixels reached the screen, and nothing was thrown: `errorBuilder`
        // consumes the failure rather than reporting it to `FlutterError`, which
        // is why there is no `takeException` here to assert on.
        expect(find.byType(RawImage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Given a photo still loading, When the avatar is drawn, Then it shows the '
      'same neutral placeholder as a failure does',
      (tester) async {
        avatarImageProvider = (_) => _PendingImage();

        await pumpInApp(
          tester,
          const AvatarCircle(emoji: '🦊', avatarPath: 'u/abc.jpg'),
        );
        await tester.pump();

        // Loading and failed are deliberately identical: to a viewer they are
        // the same thing, a photo that is not on screen.
        expect(find.text('🦊'), findsNothing);
        expect(find.byIcon(Icons.person_rounded), findsOneWidget);
        expect(find.byType(RawImage), findsNothing);
      },
    );

    testWidgets(
      'Given a photo, When it has loaded, Then the image is drawn and the emoji '
      'is nowhere',
      (tester) async {
        await pumpInApp(
          tester,
          const AvatarCircle(emoji: '🦊', avatarPath: 'u/abc.jpg'),
        );

        expect(find.byType(RawImage), findsOneWidget);
        expect(find.text('🦊'), findsNothing);
        expect(find.byIcon(Icons.person_rounded), findsNothing);
      },
    );

    testWidgets(
      'Given a photo on a selected avatar, When it is drawn, Then it fills the '
      'whole circle and is clipped to it',
      (tester) async {
        await pumpInApp(
          tester,
          const AvatarCircle(
            emoji: '🦊',
            avatarPath: 'u/abc.jpg',
            diameter: 60,
            isSelected: true,
          ),
        );

        // `cover` inside a clipped circle is what replaces a crop UI, so it is
        // load-bearing rather than cosmetic.
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.fit, BoxFit.cover);

        // The full 60, *while selected*. The selection ring is a foreground
        // decoration precisely so it does not inset the photo — as a `border`
        // did, leaving a 4pt ring of background showing through. Nothing caught
        // that while avatars were emoji, because a centred glyph does not care
        // how much room it is given.
        expect(tester.getSize(find.byType(Image)), const Size(60, 60));

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(AvatarCircle),
            matching: find.byType(Container),
          ),
        );
        expect(container.clipBehavior, Clip.antiAlias);
      },
    );
  });

  group('gestures', () {
    testWidgets(
      'Given no callbacks, When the avatar is drawn, Then it adds no recogniser '
      'and a surrounding row still answers the tap',
      (tester) async {
        // Two of the six sites sit inside a row-level InkWell or ListTile. An
        // opaque recogniser on the avatar would win the arena and swallow taps
        // that land on it, which is exactly the bug this guards.
        var rowTaps = 0;
        await pumpInApp(
          tester,
          GestureDetector(
            onTap: () => rowTaps++,
            behavior: HitTestBehavior.opaque,
            child: const AvatarCircle(emoji: '🦊'),
          ),
        );

        expect(
          find.descendant(
            of: find.byType(AvatarCircle),
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
        );

        await tester.tap(find.byType(AvatarCircle));
        expect(rowTaps, 1);
      },
    );

    testWidgets(
      'Given an onTap, When the avatar is tapped, Then it answers itself',
      (tester) async {
        var taps = 0;
        await pumpInApp(tester, AvatarCircle(emoji: '🦊', onTap: () => taps++));

        await tester.tap(find.byType(AvatarCircle));
        expect(taps, 1);
      },
    );
  });
}
