/// The app's flame, and the contract that let it replace a font glyph.
///
/// **What is worth asserting here is narrow, and that is the point.** The mark's geometry
/// comes from `rive/streak_flame/icon.py`, which imports it from the same point lists the Rive
/// artboard is built from; re-deriving those numbers here would be transcribing the generator
/// into a test and would pass on any bug the generator has. Whether the curve came out as a
/// *flame* is answered by looking — `icon.py --sheet` puts it beside the artboard's own frame,
/// and `test/streak_flame_mark_render_preview.dart` draws it at all four sizes the app uses.
///
/// So what is pinned is the part a reader of the code could get wrong: the box, the two
/// layers and their order, how the core is derived, and the one number
/// (`StreakFlameMark.aspect`) that a regenerate can move under everyone's feet.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/streak/streak_flame_mark.dart';

const _body = Color(0xFFB54708);

Future<void> _pump(
  WidgetTester tester, {
  double size = 96,
  Color color = _body,
  Color? core,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Center(
          child: RepaintBoundary(
            key: const ValueKey('mark'),
            child: StreakFlameMark(size: size, color: color, coreColor: core),
          ),
        ),
      ),
    ),
  );
}

/// The bounding box of everything drawn, in pixels, plus the raster's own size.
///
/// **A real raster rather than the `paints` matcher**, because the question is where the ink
/// *lands*: `paints` can say a path was filled in a colour and cannot say whether it filled
/// its box or a third of it. This is the assertion that the mark is a drop-in for the `Icon`
/// it replaced — a flame drawn at 60% of its box would satisfy every other case here.
Future<(Rect, Size)> _ink(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('mark')),
  );
  late ByteData pixels;
  late ui.Image image;
  await tester.runAsync(() async {
    image = await boundary.toImage();
    pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });

  var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      // Alpha only: the ground is transparent inside a repaint boundary, so any opaque
      // pixel is the mark. Thresholded well above zero so antialiasing at the very edge of
      // a curve does not widen the box by a pixel on one run and not the next.
      if (pixels.getUint8((y * image.width + x) * 4 + 3) > 40) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  return (
    Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    ),
    Size(image.width.toDouble(), image.height.toDouble()),
  );
}

void main() {
  testWidgets('it boxes square, which is what made it a drop-in for an Icon', (
    tester,
  ) async {
    // The whole swap off `kReadingStreakIcon` turned on this. The flame is 1:1.23, so a mark
    // sized to its own aspect would be narrower than the glyph it replaced and would have
    // re-centred the chip's row and the record button's label. A square box holding a
    // centred flame means every call site's layout is untouched.
    await _pump(tester, size: 44);
    expect(tester.getSize(find.byType(StreakFlameMark)), const Size.square(44));
  });

  testWidgets('the flame fills its box top to bottom and sits centred', (
    tester,
  ) async {
    // The other half of the drop-in contract, and the half no widget assertion reaches: the
    // *ink*, not the box. Measured off a raster.
    await _pump(tester, size: 96);
    final (ink, raster) = await _ink(tester);

    expect(
      ink.height / raster.height,
      closeTo(1, 0.02),
      reason: 'the tall axis fills the box',
    );
    expect(
      ink.width / ink.height,
      closeTo(StreakFlameMark.aspect, 0.02),
      reason: 'and the narrow one comes out at the flame\'s own proportion',
    );
    expect(
      ink.center.dx / raster.width,
      closeTo(0.5, 0.02),
      reason: 'centred, so a square box reads as one',
    );
  });

  testWidgets('two layers, body then core, in that order', (tester) async {
    // Order matters twice over. The core sits entirely inside the body, so drawing it first
    // would hide it; and both are filled with the non-zero rule rather than even-odd, since
    // even-odd would punch the core out and leave a hole with the ground showing through.
    await _pump(tester, size: 96);

    expect(
      find.byType(StreakFlameMark),
      paints
        ..path(color: _body, style: PaintingStyle.fill)
        ..path(
          color: StreakFlameMark.brighten(_body),
          style: PaintingStyle.fill,
        ),
    );
  });

  testWidgets('an explicit core wins over the derived one', (tester) async {
    // The artboard's own pair is `#F2A93F` over `#FFD479`, which is not what lifting
    // lightness produces — so the celebration can hand the exact value over when it wants
    // the drawing rather than an approximation of it.
    const exact = Color(0xFFFFD479);
    await _pump(tester, color: const Color(0xFFF2A93F), core: exact);

    expect(
      find.byType(StreakFlameMark),
      paints
        ..path()
        ..path(color: exact),
    );
  });

  group('the core is derived by lifting lightness, not by washing with white', () {
    test('it keeps the hue and the saturation', () {
      // **The reason this is not a lerp to white.** White desaturates, which turns the rust
      // `flame` into tan mud; the artboard's core is a *brighter, yellower* amber, and a
      // brighter orange inside a rust flame reads as heat where a pale one reads as dust.
      final from = HSLColor.fromColor(_body);
      final to = HSLColor.fromColor(StreakFlameMark.brighten(_body));

      expect(to.hue, closeTo(from.hue, 0.5));
      expect(to.saturation, closeTo(from.saturation, 0.02));
      expect(to.lightness, greaterThan(from.lightness));
    });

    test('white stays white, so the mark on a filled button is one shape', () {
      // Not a limitation. A two-tone flame inside a green button at 18pt is detail nobody
      // can see, and a core that tried to be visible there would have to be *darker* than
      // the body, which is a different drawing.
      expect(StreakFlameMark.brighten(Colors.white), Colors.white);
    });

    test('it cannot run past white, whatever it is given', () {
      for (final c in [
        Colors.white,
        const Color(0xFFFFFEF8),
        const Color(0xFFF2A93F),
        const Color(0xFF26190A),
      ]) {
        expect(
          HSLColor.fromColor(StreakFlameMark.brighten(c)).lightness,
          lessThanOrEqualTo(1.0),
          reason: '$c',
        );
      }
    });
  });

  test('the aspect is the flame\'s, and a regenerate has to state it', () {
    // **Pinned as a literal on purpose.** `StreakFlameMark.aspect` is generated alongside the
    // path tables, so editing a vertex in `rive/streak_flame/smooth.py` and re-running
    // `icon.py` can move it — and it is the number the chip's and the hero's visual weight
    // rest on. Failing here is not a bug; it is the generator asking for this line to be
    // updated deliberately rather than noticed six months later. It has been updated once,
    // which is the mechanism working: 0.6222 held while `SCALE_X` and `SCALE_Y` were equal.
    //
    // **And this value is not arbitrary — it is Phosphor Fill `fire`'s.** That glyph is
    // 704 × 864 in a 1024 em, so 0.8148, and `smooth.py`'s `SCALE_X` is solved to land the
    // fitted curve on it to four places. A regenerate that moves this number is therefore
    // also moving away from the reference the widening was aimed at.
    expect(StreakFlameMark.aspect, closeTo(0.8148, 0.0001));
    expect(
      StreakFlameMark.aspect,
      lessThan(1),
      reason:
          'a flame is taller than it is wide, in every version of this shape',
    );
    // And not `FLAME_OUTER`'s raw bounding box: the corner radii round the tip in, which
    // costs height and no width. Nor the control hull, which is what the first version
    // measured and which drew the mark 6% small — the hull is wrong by however far the
    // handles stick out past the curve.
    expect(1 / StreakFlameMark.aspect, closeTo(1.227, 0.002));
  });
}
