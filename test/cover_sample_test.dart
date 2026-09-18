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
      // is worth writing down because it is counter-intuitive: **the border is not
      // uniformly weighted in x, and it has no foot.** On a 100x150 cover the band is
      // 8px, so the evidence is 800 pixels of head plus 134 rows x 8 columns = 1072 of
      // each flank (the flanks stop 8px short of the foot) — 2944 in all, and nearly
      // three quarters of that is in the two narrow flanks. A colour split at x = 70
      // therefore takes 560 from the head and the whole 1072-pixel left flank:
      // 1632 / 2944 = 0.554, not the 0.70 its share of the cover's *width* would
      // suggest.
      //
      // Both candidates clear `kCoverBackgroundMinShare` here, so the majority is
      // returned directly and the area tie-break never runs.
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
          reason: 'the minority colour won the border',
        );
        expect(result.share, closeTo(0.554, 0.005));
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
              'a 100-column gradient spreads across 16 4-bit bins, so no bin '
              'should come near ${kCoverBackgroundMinShare * 100}% of the border. '
              'The two biggest are also too small for the area tie-break to run.',
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

  group('the four corrections to the border', () {
    // Each of these pins one correction, and each is named for the real cover that
    // forced it. They were all found by measuring 460 covers out of the live database,
    // because the previous design's tests all passed on synthetic fixtures while the
    // policy they were pinning stored a colour that was nowhere on the book for a third
    // of a real library.

    testWidgets('Given a grainy dark background, Then it survives quantisation '
        '(The House of the Scorpion)', (tester) async {
      // **The bin-width correction.** Uniform RGB bins are perceptually uneven: a
      // near-black background with ordinary JPEG grain scatters across many bins while
      // looking flat, so it loses to its own noise and the cover falls back to a mean
      // mixed out of its artwork. `The House of the Scorpion` is 66% one near-black
      // along its border at 4 bits and 31% at 5, and stored `#651614` — a dark red
      // taken from the scorpion, not from the jacket.
      //
      // The fixture is that failure in miniature. Border values walk 0..31, which is
      // **four** bins at 5 bits (about 25% each, under the threshold) and **two** at 4
      // bits (about 50% each, over it). Deterministic, so it cannot flake.
      await _real(tester, () async {
        final image = await _image(100, 150, (x, y) {
          if (y >= 40 && y < 110 && x >= 10 && x < 90) return [250, 60, 60];
          final v = (x * 7 + y * 13) % 32;
          return [v, v, v];
        });

        final background = await coverBackgroundColor(image);
        expect(background, isNotNull);
        expect(
          background!.share,
          greaterThanOrEqualTo(kCoverBackgroundMinShare),
          reason:
              'the grain fragmented across bins, so a flat dark background lost '
              'to its own noise',
        );
        expect(background.colour.computeLuminance(), lessThan(0.05));

        // And the tone follows the background rather than the mean, which the bright
        // block drags a long way off.
        final tone = await coverToneColor(image);
        expect(tone!.computeLuminance(), lessThan(0.05));
      });
    });

    testWidgets('Given a foot band, Then the foot is not read at all '
        '(주식투자 안내서)', (tester) async {
      // **The dropped-foot correction.** The bottom edge is the least trustworthy part
      // of a book image: an obi, a printed foot-band, or the paper the book was shot
      // on. Of 77 covers examined by hand, 14 had a bottom edge both highly uniform
      // and unlike every other edge — `주식투자 안내서` is a bright yellow jacket whose
      // bottom edge is 100% black.
      //
      // Asserted as *identity between two covers* rather than as a flipped answer, and
      // that is deliberate. A foot band only outvotes the rest of a border when it is
      // large enough to stop being a band, so "the answer changes" would need a
      // dishonest fixture. "Painting the foot black changes nothing" is the actual
      // claim.
      //
      // Two bands, because the border excludes the foot *and the corners beside it*: a
      // band the depth of the border is invisible to it, and a band two and a half times
      // deeper still leaves the yellow winning 93% of the evidence. A four-sided ring
      // would have read 21% black in the first case and 23% in the second.
      await _real(tester, () async {
        const yellow = [254, 238, 2];
        final plain = await coverBackgroundColor(
          await _image(100, 150, (x, y) => yellow),
        );
        final banded = await coverBackgroundColor(
          await _image(100, 150, (x, y) => y >= 142 ? [0, 0, 0] : yellow),
        );
        final deeper = await coverBackgroundColor(
          await _image(100, 150, (x, y) => y >= 130 ? [0, 0, 0] : yellow),
        );

        expect(plain, isNotNull);
        expect(banded, isNotNull);
        expect(banded!.colour.toARGB32(), plain!.colour.toARGB32());
        expect(
          banded.share,
          plain.share,
          reason:
              'a foot band the depth of the border diluted it, so the bottom of '
              'the image is still being counted',
        );

        expect(deeper!.colour.toARGB32(), plain.colour.toARGB32());
        expect(
          deeper.share,
          greaterThan(0.9),
          reason:
              'a deeper foot band cost far more of the border than the flanks '
              'below the cut-off can account for',
        );
      });
    });

    testWidgets('Given a dark jacket inside white trim, Then the trim is excluded '
        '(매치메이커스)', (tester) async {
      // **The paper-margin correction.** Book images are often shot or composited on
      // white, so the jacket sits inside a light frame belonging to the photograph.
      // Dropping the foot is not enough, because the trim is on every side:
      // `매치메이커스` is a dark jacket whose bottom edge is 94% white and whose left and
      // right edges are 32% white each. It stored `#FFFEFE` — pure white, for a book
      // that is nearly black.
      //
      // Here the trim is 6px all round, so it is 77% of the border. Without exclusion
      // the cover stores white; with it, only the jacket is left.
      await _real(tester, () async {
        final image = await _image(100, 150, (x, y) {
          final trim = x < 6 || x >= 94 || y < 6 || y >= 144;
          return trim ? [255, 255, 255] : [42, 42, 42];
        });

        final background = await coverBackgroundColor(image);
        expect(background, isNotNull);
        expect(
          background!.colour.toARGB32(),
          0xFF2A2A2A,
          reason: "the photograph's white trim was taken for the book",
        );
        _expectHex(await coverToneColor(image), 0xFF2A2A2A);
      });
    });

    testWidgets('Given a white cover with central artwork, Then its white is NOT '
        'taken for trim (김대중 자서전)', (tester) async {
      // **The load-bearing safety test for the rule above, and the reason
      // `_paperMaxCoverage` exists.** "Uniform at the edge and absent from the middle"
      // describes a paper margin — and equally describes a white book with a big
      // central illustration. The first version of the rule had only the interior
      // test, and on the 460-cover corpus it deleted the background of thirteen white
      // books: `김대중 자서전` went from storing `#FFFFFD`, present on 66% of its jacket,
      // to a grey present on 0% of it.
      //
      // Area is what separates them. Trim is a few percent of an image; a white cover
      // is a quarter of it or more. This fixture's white is 64%, and its interior is
      // entirely artwork — so it passes every other paper gate and must be rejected
      // by that one alone.
      await _real(tester, () async {
        final image = await _image(100, 150, (x, y) {
          final art = x >= 20 && x < 80 && y >= 30 && y < 120;
          return art ? [48, 80, 160] : [255, 255, 255];
        });

        _expectHex(
          await coverToneColor(image),
          0xFFFFFFFF,
          reason:
              'a white book lost its own background to the paper rule — this is '
              'the thirteen-cover regression that `_paperMaxCoverage` prevents',
        );
      });
    });

    testWidgets('Given a border split between two colours, Then area decides '
        '(세대를 뛰어넘어 함께 일하기)', (tester) async {
      // **The tie-break.** A two-tone jacket divides its own border, so neither half
      // reaches the threshold and the cover falls to a mean that is on neither half.
      // `세대를 뛰어넘어 함께 일하기` is white across its top quarter and yellow below — 93%
      // white along the head, yellow down both flanks — and stored a mean present on
      // 2% of the jacket. Asking which colour covers more of the *cover* returns the
      // yellow, on 53%.
      //
      // The fixture splits the border evenly between white and yellow and then dilutes
      // both below the threshold with a spread of colours, which is what type and grain
      // do on a real jacket. Only the tie-break can resolve it, and it resolves toward
      // yellow because the interior is yellow.
      await _real(tester, () async {
        const yellow = [254, 214, 50];
        final image = await _image(100, 150, (x, y) {
          final border = x < 8 || x >= 92 || y < 8;
          if (!border) return yellow;
          if ((x * 31 + y * 17) % 2 == 0) {
            return [(x * 13) % 256, (y * 29) % 256, ((x + y) * 7) % 256];
          }
          return x < 50 ? [255, 255, 255] : yellow;
        });

        final background = await coverBackgroundColor(image);
        expect(background, isNotNull);
        expect(
          background!.colour.toARGB32(),
          0xFFFED632,
          reason:
              'the border was split and the white half won, or the tie-break did '
              'not run at all',
        );
        expect(
          background.share,
          greaterThanOrEqualTo(kCoverBackgroundMinShare),
          reason:
              'the tie-break must report the winner at its area share, or the '
              'threshold rejects a colour that covers most of the cover',
        );
        _expectHex(await coverToneColor(image), 0xFFFED632);
      });
    });

    testWidgets('Given a band across the head, Then the background below it still '
        'wins (역행자)', (tester) async {
      // **The head is read, and that is safe rather than lucky.** The foot is dropped
      // unconditionally, so the obvious objection is that a band across the *head* lies
      // about the jacket just as loudly — and `역행자` is exactly that book, an orange
      // jacket banded in black at head *and* foot.
      //
      // Pooling the edges is what defuses it. The head strip is the full width by one
      // border depth; the flanks are two border depths by nearly the full height. Over
      // the 460-cover corpus, whose aspect ratios run 0.65–0.69, the head strip is only
      // **27–28% of the pooled border** — under `kCoverBackgroundMinShare`, so a head
      // band cannot be accepted however solid it is. `_borderFraction` carries the
      // algebra, and the four head corrections measured against it and rejected.
      //
      // Three fixtures, deepening: a band one border deep, one two and a half deep, and
      // the real shape with a band at each end. The orange survives all three.
      await _real(tester, () async {
        const orange = [234, 107, 3];
        final plain = await coverBackgroundColor(
          await _image(100, 150, (x, y) => orange),
        );
        final candidates = {
          'a band one border deep': await coverBackgroundColor(
            await _image(100, 150, (x, y) => y < 8 ? [0, 0, 0] : orange),
          ),
          'a band two and a half borders deep': await coverBackgroundColor(
            await _image(100, 150, (x, y) => y < 20 ? [0, 0, 0] : orange),
          ),
          'bands at head and foot': await coverBackgroundColor(
            await _image(
              100,
              150,
              (x, y) => (y < 20 || y >= 130) ? [0, 0, 0] : orange,
            ),
          ),
        };

        expect(plain, isNotNull);
        for (final entry in candidates.entries) {
          expect(entry.value, isNotNull, reason: entry.key);
          expect(
            entry.value!.colour.toARGB32(),
            plain!.colour.toARGB32(),
            reason: '${entry.key} was taken for the background',
          );
          expect(
            entry.value!.share,
            greaterThanOrEqualTo(kCoverBackgroundMinShare),
            reason:
                '${entry.key} diluted the border below the threshold, so the '
                'cover fell back to a mean',
          );
        }
      });
    });

    testWidgets('Given a head band and no rival, Then it is still never accepted', (
      tester,
    ) async {
      // The guarantee above, isolated. The previous test lets the orange win on merit, so
      // it would still pass if the head strip were worth 60% of the border. Here there is
      // no background at all: below the band the jacket is noise, spread thin enough that
      // no bin can carry it. The band is then the largest single colour in the border by a
      // distance, and it must **still** lose, because 28% is 28%.
      //
      // A band that gets accepted when nothing opposes it is a band that gets accepted
      // when something weak opposes it, which is the failure this pins shut.
      await _real(tester, () async {
        final image = await _image(100, 150, (x, y) {
          if (y < 12) return [0, 0, 0];
          return [(x * 13) % 256, (y * 29) % 256, ((x + y) * 7) % 256];
        });

        final background = await coverBackgroundColor(image);
        expect(background, isNotNull);
        expect(
          background!.share,
          lessThan(kCoverBackgroundMinShare),
          reason:
              'a band across the head carried the border, so the head strip is '
              'worth more of it than the 27–28% the corpus measures',
        );

        // So the cover takes its mean, which is the right answer for a jacket with no
        // background.
        final mean = await averageCoverColor(image);
        _expectHex(await coverToneColor(image), mean!.toARGB32());
      });
    });

    testWidgets('Given a cover that is one colour to its edges, Then no part of it '
        'is mistaken for a band', (tester) async {
      // The safety test for all of the above, and the reason the shipped policy detects
      // no bands at all. Every rejected head correction had to answer this fixture, and
      // the cheapest of them — walk down from row 0 while the rows stay uniform — walks
      // to the far edge here and needs a depth cap to survive it. That cap is exactly the
      // arbitrary constant this file tries not to have, and it does not save the rule:
      // measured over 460 covers the walk fires on 302 of them and strips real
      // backgrounds, `역행자`'s orange included.
      //
      // A flat cover has to come out flat, with no band logic in the way.
      await _real(tester, () async {
        const teal = [46, 78, 67];
        _expectHex(
          await coverToneColor(await _image(100, 150, (x, y) => teal)),
          0xFF2E4E43,
        );
        // And with type on it, which is what a real flat jacket looks like.
        _expectHex(
          await coverToneColor(await _flatCoverWithType(teal)),
          0xFF2E4E43,
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
