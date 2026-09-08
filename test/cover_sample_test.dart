// Tests for the four functions in `cover_sample.dart`, and for the policy that picks
// between them.
//
// `averageCoverColor` was a 1x1 `drawImageRect` that let the rasteriser do the
// averaging, and on the device it did not average at all — Impeller returns roughly a
// single texel at a 1x1 destination, so a mostly-white jacket with black type was
// stored as near-white while its mean was a mid grey. Every back board in the app was
// tinted from an arbitrary pixel of its cover, and **no test noticed**, because the
// only test of it used a solid-colour image: a single texel of a solid colour and the
// mean of a solid colour are the same number.
//
// So the load-bearing test in the first group is the second one. A half-black,
// half-white image is the smallest input that tells an average apart from a sample.
//
// The `coverToneColor` group is newer and answers a different question: not "is this
// the mean" but "is the mean the right thing to want". It is not — a bright yellow
// jacket with black type has a mean of olive, a colour that is nowhere on the book.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book/cover_sample.dart';

/// Builds an image from explicit pixels, straight-alpha RGBA.
///
/// `decodeImageFromPixels` rather than a `PictureRecorder`, so no rasteriser is
/// involved in constructing the input either — the test is then measuring the
/// function and nothing else.
Future<ui.Image> _image(
  int width,
  int height,
  List<int> Function(int x, int y) at,
) {
  final bytes = Uint8List(width * height * 4);
  var i = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final rgba = at(x, y);
      bytes[i++] = rgba[0];
      bytes[i++] = rgba[1];
      bytes[i++] = rgba[2];
      bytes[i++] = rgba.length > 3 ? rgba[3] : 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Runs [body] outside the fake-async zone, which `decodeImageFromPixels` and
/// `toByteData` both need.
Future<void> _real(WidgetTester tester, Future<void> Function() body) =>
    tester.runAsync(body).then((_) {});

void main() {
  testWidgets('Given a solid cover, Then its average is that colour', (
    tester,
  ) async {
    await _real(tester, () async {
      final image = await _image(8, 12, (_, __) => [200, 30, 100]);
      expect(await averageCoverColor(image), const Color(0xFFC81E64));
    });
  });

  testWidgets(
    'Given a cover that is half black and half white, Then its average is the '
    'midpoint',
    (tester) async {
      // **The test the old implementation would have failed.** A sampler that
      // returns one texel returns black or white here; only an average returns the
      // middle. Everything about the stored colour rests on this: a book's spine is
      // this value, sitting beside the cover it came from.
      await _real(tester, () async {
        final image = await _image(
          10,
          10,
          (x, y) => y < 5 ? [0, 0, 0] : [255, 255, 255],
        );
        final avg = await averageCoverColor(image);
        expect(avg, isNotNull);
        expect((avg!.r * 255).round(), closeTo(128, 1));
        expect((avg.g * 255).round(), closeTo(128, 1));
        expect((avg.b * 255).round(), closeTo(128, 1));
      });
    },
  );

  testWidgets(
    'Given a cover that is one fifth red on white, Then the average is weighted '
    'by area',
    (tester) async {
      // Not just "somewhere between": the weights have to be right, or a cover with
      // a small band of strong colour reads as that colour.
      await _real(tester, () async {
        final image = await _image(
          10,
          10,
          (x, y) => y < 2 ? [255, 0, 0] : [255, 255, 255],
        );
        final avg = await averageCoverColor(image);
        expect((avg!.r * 255).round(), 255);
        // Four fifths white: 0.8 * 255 = 204.
        expect((avg.g * 255).round(), closeTo(204, 1));
        expect((avg.b * 255).round(), closeTo(204, 1));
      });
    },
  );

  testWidgets(
    'Given a cover with a transparent half, Then only the pixels it has are '
    'averaged',
    (tester) async {
      // Averaged over the pixels the cover actually has, rather than dragged toward
      // black by the ones it does not. `rawRgba` is premultiplied, so a naive mean
      // counts a transparent pixel as black and a jacket with a cut-out background
      // comes out muddy.
      await _real(tester, () async {
        final image = await _image(
          10,
          10,
          (x, y) => y < 5 ? [200, 30, 100, 255] : [0, 0, 0, 0],
        );
        expect(await averageCoverColor(image), const Color(0xFFC81E64));
      });
    },
  );

  testWidgets(
    'Given a fully transparent cover, Then there is no colour to report',
    (tester) async {
      // Null rather than black. The caller treats it as "not known yet", which is
      // the honest answer and the one that leaves the fallback in place.
      await _real(tester, () async {
        final image = await _image(4, 4, (_, __) => [0, 0, 0, 0]);
        expect(await averageCoverColor(image), isNull);
      });
    },
  );

  testWidgets(
    'Given a cover of one strong colour and one pale one, Then the average is '
    'not either of them',
    (tester) async {
      // The property that makes this a *tone* rather than a swatch, and the one the
      // doc comment admits is muddy: a cover split between two strong colours
      // averages to something that is neither. Pinned so the trade is deliberate.
      await _real(tester, () async {
        final image = await _image(
          10,
          10,
          (x, y) => x < 5 ? [0, 0, 255] : [255, 255, 0],
        );
        final avg = await averageCoverColor(image);
        expect((avg!.r * 255).round(), closeTo(128, 1));
        expect((avg.g * 255).round(), closeTo(128, 1));
        expect((avg.b * 255).round(), closeTo(128, 1));
      });
    },
  );

  group('coverBackgroundColor', () {
    testWidgets('Given a block of type in the middle, Then it is not counted', (
      tester,
    ) async {
      // The whole reason this looks at a ring rather than at the whole cover. A
      // 5-bit histogram of the *entire* image gives black a huge advantage: near-black
      // type collapses into a handful of bins while a real background spreads across
      // many of them, so on real covers the mode was `#020101` on 21% of the pixels
      // of a brown jacket and the white of a margin on 13% of a pink one.
      await _real(tester, () async {
        final result = await coverBackgroundColor(
          await _flatCoverWithType([254, 238, 2]),
        );
        expect(result, isNotNull);
        expect(result!.colour.toARGB32(), 0xFFFEEE02);
        expect(
          result.share,
          1.0,
          reason:
              'the ring is entirely background, so nothing should dilute it',
        );
      });
    });

    testWidgets('Given a two-tone border, Then the share reports the majority honestly', (
      tester,
    ) async {
      // `share` is the caller's only evidence, so it has to be a real measurement
      // rather than a formality — it is the number `kCoverBackgroundMinShare` is
      // compared against.
      //
      // The expected value is worked out rather than eyeballed, and the arithmetic
      // is worth writing down because it is counter-intuitive: **the ring is not
      // uniformly weighted in x.** On a 100x150 cover the ring is 8px, so it is 800
      // pixels of top band, 800 of bottom band, and 134 rows x 16 columns = 2144 of
      // side strip — 3744 in all, well over half of it in the two narrow strips. A
      // colour split at x = 70 therefore takes 560 + 560 from the bands and the
      // whole 1072-pixel left strip: 2192 / 3744 = 0.585, not the 0.70 its share of
      // the cover's *width* would suggest.
      await _real(tester, () async {
        final result = await coverBackgroundColor(
          await _image(
            100,
            150,
            (x, y) => x < 70 ? [10, 20, 200] : [250, 250, 250],
          ),
        );
        expect(result, isNotNull);
        expect(
          result!.colour.toARGB32(),
          0xFF0A14C8,
          reason: 'the minority colour won the ring',
        );
        expect(result.share, closeTo(0.585, 0.01));
      });
    });

    testWidgets(
      'Given a fully transparent cover, Then there is no background',
      (tester) async {
        await _real(tester, () async {
          expect(
            await coverBackgroundColor(
              await _image(20, 30, (_, __) => [0, 0, 0, 0]),
            ),
            isNull,
          );
        });
      },
    );
  });

  group('coverToneColor', () {
    testWidgets(
      'Given a flat yellow cover with black type, Then the tone is the yellow '
      'rather than the olive mean',
      (tester) async {
        // **The headline case, and the one a person can check by looking.** The mean
        // of this image is about `#9F9501`, a colour that is nowhere on the cover;
        // the yellow is 100% of its border. The real book this mimics stored
        // `#979015` and rendered a dark olive spine beside its own bright yellow
        // jacket.
        await _real(tester, () async {
          final image = await _flatCoverWithType([254, 238, 2]);
          _expectHex(await coverToneColor(image), 0xFFFEEE02);

          final mean = await averageCoverColor(image);
          expect(
            mean!.toARGB32(),
            isNot(0xFFFEEE02),
            reason:
                'the mean now agrees with the background, so this test no longer '
                'demonstrates the difference the policy exists for',
          );
        });
      },
    );

    testWidgets('Given a white cover with black type, Then the tone is white', (
      tester,
    ) async {
      // The user's question, made executable: *can a white book have a white
      // spine?* Under the mean it could only ever be off-white, and under the old
      // chroma lift it came out a dark sage. Here it is white, and `spineToneFor`
      // then leaves it white and writes on it in dark ink.
      await _real(tester, () async {
        _expectHex(
          await coverToneColor(await _flatCoverWithType([255, 255, 255])),
          0xFFFFFFFF,
        );
      });
    });

    testWidgets('Given a cover whose art reaches every edge, Then the tone falls back to '
        'the mean', (tester) async {
      // The other half of the policy, and the reason `share` is thresholded rather
      // than trusted. A photograph or a full-bleed gradient *has* a border, but that
      // border is not the book's colour.
      //
      // Both halves of that sentence are asserted, and the first is the one that
      // matters: a background colour **was** found here, with a perfectly ordinary
      // share, and the threshold rejected it anyway. A version of this test that
      // only checked the final answer would also pass if `coverBackgroundColor`
      // returned null, which is a different code path and not the one under test.
      await _real(tester, () async {
        final image = await _image(100, 150, (x, y) {
          final v = (x * 255 / 99).round();
          return [v, 255 - v, (v * 2) % 256];
        });

        final background = await coverBackgroundColor(image);
        expect(
          background,
          isNotNull,
          reason:
              'the fixture stopped producing a background at all, so the '
              'threshold is no longer what makes this fall back',
        );
        expect(
          background!.share,
          lessThan(kCoverBackgroundMinShare),
          reason:
              'a 100-column gradient spreads across 32 5-bit bins, so no bin '
              'should come near ${kCoverBackgroundMinShare * 100}% of the ring',
        );

        final tone = await coverToneColor(image);
        final mean = await averageCoverColor(image);
        expect(
          tone!.toARGB32(),
          mean!.toARGB32(),
          reason:
              'a full-bleed gradient took its border colour — a ring that is '
              'not a background was treated as one',
        );
      });
    });

    testWidgets('Given a fully transparent cover, Then there is no tone', (
      tester,
    ) async {
      // Null propagates rather than becoming black, so the caller keeps its
      // fallback — the ISBN swatch — instead of storing a colour that is not the
      // book's.
      await _real(tester, () async {
        expect(
          await coverToneColor(await _image(20, 30, (_, __) => [0, 0, 0, 0])),
          isNull,
        );
      });
    });
  });
}

/// A flat cover with a block of type in the middle: the shape almost every jacket
/// has, and the one a mean cannot describe.
///
/// 100x150 with an 8px ring, so the block at y 40..110 never touches the border.
/// Its mean works out to about `#9F9501`, an olive — which is not a coincidence but
/// the same arithmetic that made the real `주식투자 안내서` store `#979015`.
Future<ui.Image> _flatCoverWithType(List<int> background) => _image(
  100,
  150,
  (x, y) => (y >= 40 && y < 110 && x >= 10 && x < 90) ? [0, 0, 0] : background,
);

void _expectHex(Color? actual, int argb, {String? reason}) {
  expect(actual, isNotNull, reason: reason);
  expect(actual!.toARGB32(), argb, reason: reason);
}
