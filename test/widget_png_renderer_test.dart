// Tests for the rasteriser the Library Card's share depends on.
//
// This file exists because the failure mode is silent: a capture of a boundary that
// never painted returns a correctly *sized*, entirely transparent image. So every
// assertion here is about pixels, not about the call succeeding.
//
// **Everything async happens inside `runAsync`.** `toImage`, PNG encoding and
// `instantiateImageCodec` are all real async work that the fake-async zone
// `testWidgets` runs in will not drive — calling any of them outside `runAsync`
// hangs the test with no output rather than failing. That cost half an hour once.
//
// **What is deliberately not tested, and why.** `captureWidgetToPng` hosts the card
// off-screen in the overlay and waits on two real frames. Under `flutter test` those
// only arrive when the test pumps, and a test cannot pump from inside `runAsync`, so
// the two halves of that function cannot be exercised together here. That is why the
// service is split: this file mounts a boundary itself, pumps it, and tests
// `rasterizeBoundary`. The hosting half is verified on a device, which the share flow
// requires regardless.
//
// The other thing no test here can catch: `toImage` does not capture platform views,
// and the card's year capsules are a real `UIView` on iOS 26. `flutter test` reports
// Android and renders the Flutter fallback, so a capture of the live sheet would look
// perfect here and arrive holed on a phone. That is designed around — the shared
// artifact is a separate pure-Flutter tree — rather than tested for.

import 'dart:async' show Completer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/widget_png_renderer.dart';

/// Never resolves: a thumbnail whose host accepted the connection and then went
/// quiet, which is the case that would hang a share behind its spinner forever.
class _StalledImage extends ImageProvider<_StalledImage> {
  @override
  Future<_StalledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_StalledImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _StalledImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// Fails immediately: a dead cover URL.
class _FailingImage extends ImageProvider<_FailingImage> {
  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FailingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(Exception('cover unavailable')),
  );
}

/// Resolves at once, so "it waited" and "it finished" can be told apart.
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
    SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
  );
}

/// Mounts a throwaway tree and hands back a context [precacheAll] can use.
Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

/// A rasterised image, decoded back to something a test can read pixels out of.
typedef _Raster = ({int width, int height, ByteData pixels});

Color _pixelAt(_Raster raster, int x, int y) {
  final offset = (y * raster.width + x) * 4;
  return Color.fromARGB(
    raster.pixels.getUint8(offset + 3),
    raster.pixels.getUint8(offset),
    raster.pixels.getUint8(offset + 1),
    raster.pixels.getUint8(offset + 2),
  );
}

/// Mounts [child] under a repaint boundary at [size], pumps it, rasterises it to
/// PNG, and decodes it back to pixels.
///
/// The round trip through PNG is deliberate: it is what the share actually hands to
/// the platform, so encoding is part of what is under test.
Future<_Raster> _rasterize(
  WidgetTester tester, {
  required Widget child,
  required Size size,
  double pixelRatio = 1,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox.fromSize(
          size: size,
          child: RepaintBoundary(key: key, child: child),
        ),
      ),
    ),
  );

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;

  final raster = await tester.runAsync(() async {
    final bytes = await rasterizeBoundary(boundary, pixelRatio: pixelRatio);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final pixels = await image.toByteData();
    return (width: image.width, height: image.height, pixels: pixels!);
  });
  return raster!;
}

void main() {
  testWidgets('Given a boundary, When it is rasterised, '
      'Then the PNG is its logical size times the pixel ratio', (tester) async {
    final raster = await _rasterize(
      tester,
      child: const ColoredBox(color: Color(0xFF09BC8A)),
      size: const Size(200, 100),
      pixelRatio: 3,
    );

    // 3x is what keeps the shared image from looking soft next to native
    // screenshots in a chat app.
    expect(raster.width, 600);
    expect(raster.height, 300);
  });

  testWidgets(
    'Given a coloured widget, When it is rasterised, Then the pixels are that colour',
    (tester) async {
      // The assertion that matters. An unpainted boundary yields a correctly sized,
      // fully transparent image, and the size test above would pass on it.
      final raster = await _rasterize(
        tester,
        child: const ColoredBox(color: Color(0xFF09BC8A)),
        size: const Size(40, 40),
      );

      final centre = _pixelAt(raster, 20, 20);

      expect(centre, const Color(0xFF09BC8A));
      expect(
        centre.a,
        1.0,
        reason: 'a blank capture would be transparent here',
      );
    },
  );

  testWidgets(
    'Given text on a ground, When it is rasterised, Then glyphs are painted',
    (tester) async {
      final raster = await _rasterize(
        tester,
        child: const ColoredBox(
          color: Color(0xFFFFFFFF),
          child: Center(
            child: Text(
              '12',
              style: TextStyle(
                fontSize: 40,
                color: Color(0xFF000000),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        size: const Size(100, 100),
      );

      var inked = 0;
      for (var i = 0; i < raster.width * raster.height; i++) {
        // Any pixel darker than mid-grey is ink; the ground is pure white.
        if (raster.pixels.getUint8(i * 4) < 128) inked++;
      }

      // The test font draws solid boxes, so two glyphs at 40pt is a lot of ink. A
      // lower bound, because the exact figure depends on the resolved font.
      expect(
        inked,
        greaterThan(200),
        reason: 'text laid out but never painted',
      );
    },
  );

  testWidgets(
    'Given a gradient fill, When it is rasterised, Then opposite corners differ',
    (tester) async {
      // The card's tiles are gradient-filled, and a gradient is the one fill that
      // can look present while being drawn flat — which is what a collapsed or
      // mis-constrained decoration produces.
      final raster = await _rasterize(
        tester,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E7C7B), Color(0xFF07403F)],
            ),
          ),
          child: SizedBox.expand(),
        ),
        size: const Size(60, 60),
      );

      final topLeft = _pixelAt(raster, 2, 2);
      final bottomRight = _pixelAt(raster, 57, 57);

      expect(topLeft.a, 1.0);
      expect(
        topLeft.b,
        greaterThan(bottomRight.b),
        reason: 'a flat fill would make both corners identical',
      );
    },
  );

  // The other half of the "blank image" problem, and the half that ships holes
  // rather than blanks. `toImage` paints only what is decoded, so an export taken
  // while a cover is still in flight is a card with a gap in it — and the gap is
  // invisible on screen, invisible to a geometry assertion, and visible only by
  // opening the file. `precacheAll` is split out of `captureWidgetToPng` for the
  // same reason `rasterizeBoundary` is: the hosting between them cannot be pumped
  // and rasterised in one test, and both ends can.
  group('precacheAll', () {
    // Created in `setUp`, never inside a test body. Decoding is real async work off
    // the widget test's fake clock, so `await createTestImage` inside `testWidgets`
    // hangs the run with no output — the same trap `avatar_circle_test.dart` records
    // at the top of the file, and it cost ten minutes here before the penny
    // dropped.
    late ui.Image decoded;

    setUp(() async {
      decoded = await createTestImage(width: 2, height: 3);
    });

    tearDown(imageCache.clear);

    testWidgets(
      'Given an image already decoded, When the capture precaches it, '
      'Then it does not wait',
      (tester) async {
        final context = await _context(tester);

        var done = false;
        precacheAll(context, [_LoadedImage(decoded)]).then((_) => done = true);
        await tester.pump();

        expect(done, isTrue);
      },
    );

    testWidgets('Given nothing to precache, When the capture precaches, '
        'Then it returns without a frame', (tester) async {
      final context = await _context(tester);

      var done = false;
      precacheAll(context, const []).then((_) => done = true);
      await tester.pump();

      expect(done, isTrue, reason: 'an empty list must not cost a timer');
    });

    testWidgets('Given a cover that never decodes, When the capture precaches, '
        'Then it waits, and then gives up rather than hanging', (tester) async {
      // A share stuck behind a spinner with nothing to cancel is worse than a
      // card with one cover missing, so the budget exists and is asserted from
      // both sides.
      final context = await _context(tester);

      var done = false;
      precacheAll(context, [
        _StalledImage(),
      ], budget: const Duration(milliseconds: 200)).then((_) => done = true);

      await tester.pump(const Duration(milliseconds: 150));
      expect(done, isFalse, reason: 'it must actually wait for the decode');

      await tester.pump(const Duration(milliseconds: 100));
      expect(
        done,
        isTrue,
        reason: 'the budget is what stops the share hanging',
      );
    });

    testWidgets('Given a dead cover URL, When the capture precaches it, '
        'Then the share is not failed by it', (tester) async {
      // One bad thumbnail must not cost the reader their card. The hole it would
      // leave is handled where the cover is drawn, by the row\'s `errorBuilder`.
      final context = await _context(tester);

      var done = false;
      Object? thrown;
      precacheAll(context, [
        _FailingImage(),
      ]).then((_) => done = true, onError: (Object error) => thrown = error);
      await tester.pump();

      expect(thrown, isNull);
      expect(done, isTrue);
    });
  });
}
