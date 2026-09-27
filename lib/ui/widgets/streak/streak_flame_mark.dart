import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's flame, drawn from the same silhouette as the Rive artboard.
///
/// **Why this exists at all, and why it is not a font glyph.** The flame appeared in four
/// places as `kReadingStreakIcon`, a Phosphor codepoint: the streak chip, the streak page's
/// hero, the record button, and the celebration's fallback. The celebration's *real* flame —
/// the one the whole screen is built around — is `assets/rive/streak_flame.riv`, a completely
/// different drawing. So the app showed two unrelated flames and called them one feature: a
/// chip with a stock icon, and a reward screen with a bespoke one. The design record had
/// flagged that exact risk, in reverse, as the argument *against* adding a vector flame
/// beside the glyph — and the answer to "two flames can drift" is one silhouette, not one
/// font.
///
/// **So the geometry is generated, not traced.** `rive/streak_flame/icon.py` imports the
/// point lists, corner set and radii out of `rive/streak_flame/smooth.py` — the same source
/// the artboard's paths are built from — applies the same Catmull-Rom fit and the same corner
/// rounding, normalises the result into a unit box and prints the tables below. Move a vertex
/// in `smooth.py`, re-run `build.sh` and `icon.py`, and the artboard and the icon move
/// together. There is nothing to keep in step by hand.
///
/// **Two shapes, and everything else left out.** The artboard has a book, a glow, two spark
/// sprays, gradients and a bloom. At 18pt on a button all of that is mud. What survives being
/// small is the body and the core — and they are also the two things that make this read as
/// *our* flame rather than as any flame: the notch on the left shoulder, and the fat core
/// sitting low. See `rive/streak_flame/icon.py --sheet`, which renders this path beside the
/// artboard's own frame; that side-by-side is the only check that means anything, because a
/// table of matching numbers says nothing about whether a curve came out as a flame.
///
/// **A painter rather than an SVG asset**, though the script emits both. The mark has to be
/// tinted at every call site — `flame` on the page, white on a green button, a colour
/// interpolating from grey during the celebration's ignition — and a painter takes a `Color`
/// where an asset needs `BlendMode.srcIn` and a second file for the core. It also draws in a
/// widget test with no asset bundle, which is how `Icon` behaved and is why the tests that
/// assert on the flame did not all have to change shape. The SVG is for the design record.
class StreakFlameMark extends StatelessWidget {
  const StreakFlameMark({
    super.key,
    required this.size,
    required this.color,
    this.coreColor,
  });

  /// The box the mark is drawn in, both wide and tall.
  ///
  /// **A square box holding a 1:1.23 flame**, so this is a drop-in for the `size` that used
  /// to go to `Icon`: the height fills it, the width comes out at [aspect] of that, and the
  /// flame is centred. Boxing it square is what kept every call site's layout identical
  /// through the swap — a narrower box would have re-centred the chip's row and the button's
  /// label.
  final double size;

  /// The body's colour.
  final Color color;

  /// The core's colour, or null to derive one from [color].
  ///
  /// The artboard's own pair is `#F2A93F` over `#FFD479` — a lighter, yellower amber, not a
  /// wash of white. So the default lifts [color]'s **lightness** and leaves its saturation
  /// alone: lerping toward white desaturates, which turns a rust `flame` core into tan mud
  /// while a brighter orange reads as heat. A `color` that is already near-white ends up with
  /// a core it cannot show, which is correct — the white flame on the record button should be
  /// one solid shape, not a shape with a ghost in it.
  final Color? coreColor;

  /// Width over height, generated alongside the path tables.
  ///
  /// **0.8148 is Phosphor Fill `fire`'s own ratio**, and hitting it exactly is the point
  /// rather than a coincidence: the glyph this mark replaced measured 704 × 864 in its 1024
  /// em, and the instruction was a wider flame of that proportion. `smooth.py`'s `SCALE_X`
  /// is solved for it, so the number here and the artboard's silhouette move together.
  ///
  /// It was 0.6222 — 1:1.607 — while `SCALE_X` and `SCALE_Y` were equal, which is recorded
  /// because two of the notes around it argue from that value. What is still true of it: it
  /// is not `FLAME_OUTER`'s raw bounding box, because the corner radii round the tip in,
  /// which costs height and no width; and it is measured off the curve rather than off the
  /// control hull, because the hull is wrong by however far the handles stick out and
  /// fitting to it drew the mark 6% small.
  static const double aspect = _kAspect;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _FlameMarkPainter(
          color: color,
          core: coreColor ?? brighten(color),
        ),
      ),
    );
  }

  /// [color] with more light in it and the same hue and saturation.
  ///
  /// Public because the celebration's ignition interpolates the body colour frame by frame
  /// and has to derive the core the same way, and because a caller passing `coreColor`
  /// explicitly should be able to see what it is overriding.
  static Color brighten(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(math.min(1, hsl.lightness + 0.16)).toColor();
  }
}

class _FlameMarkPainter extends CustomPainter {
  const _FlameMarkPainter({required this.color, required this.core});

  final Color color;
  final Color core;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    for (final layer in [(_kBody, color), (_kCore, core)]) {
      canvas.drawPath(
        _pathOf(layer.$1, side),
        Paint()
          ..color = layer.$2
          ..style = PaintingStyle.fill
          // The core sits entirely inside the body, so the two overlap everywhere the core
          // is drawn. Non-zero rather than even-odd for that reason: even-odd would punch
          // the core out of the body and leave a hole with the ground showing through.
          ..isAntiAlias = true,
      );
    }
  }

  /// One table of `[startX, startY, then 6 per cubic]` as a scaled [Path].
  ///
  /// The tables are normalised into a unit box, so scaling is one multiply and there is no
  /// transform matrix to get wrong. Built per paint rather than cached: a `Path` is cheap
  /// beside the rasterisation, and caching it would need the side length as a key.
  static Path _pathOf(List<double> d, double side) {
    final path = Path()..moveTo(d[0] * side, d[1] * side);
    for (var i = 2; i < d.length; i += 6) {
      path.cubicTo(
        d[i] * side,
        d[i + 1] * side,
        d[i + 2] * side,
        d[i + 3] * side,
        d[i + 4] * side,
        d[i + 5] * side,
      );
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_FlameMarkPainter old) =>
      old.color != color || old.core != core;
}

// Generated by `rive/streak_flame/icon.py` from the same point lists the Rive artboard is
// built from. Do not hand-edit: edit `rive/streak_flame/smooth.py` and re-run.
//
// Both shapes are normalised into one `[0, 1]` box, the long axis filling it and the short
// axis centred, so a call site hands over a single `size` and the flame keeps its proportion
// inside a square. Every number after the first pair is a cubic's two controls and its end
// point, in that order.
const double _kAspect = 0.8148;

const List<double> _kBody = <double>[
  0.62434, 0.03762, // moveTo
  0.69191, 0.14768, 0.77124, 0.24154, 0.82705, 0.36780,
  0.88286, 0.49406, 0.92471, 0.60191, 0.90030, 0.69924,
  0.87588, 0.79657, 0.75031, 0.90178, 0.68055, 0.95176,
  0.61078, 1.00174, 0.54800, 1.00174, 0.48172, 0.99911,
  0.41545, 0.99648, 0.34743, 0.99122, 0.28290, 0.93598,
  0.21837, 0.88074, 0.11024, 0.76763, 0.09454, 0.66767,
  0.07885, 0.56772, 0.16256, 0.43356, 0.18872, 0.33624,
  0.21488, 0.23891, 0.21919, 0.21368, 0.23443, 0.15240,
  0.24252, 0.11984, 0.28123, 0.10613, 0.30801, 0.12633,
  0.32080, 0.13597, 0.33359, 0.14562, 0.34638, 0.15526,
  0.36346, 0.16814, 0.38770, 0.16506, 0.40102, 0.14832,
  0.43246, 0.10881, 0.46390, 0.06929, 0.49534, 0.02977,
  0.52942, -0.01306, 0.59570, -0.00903, 0.62434, 0.03762,
];

const List<double> _kCore = <double>[
  0.51394, 0.54159, // moveTo
  0.53948, 0.57770, 0.56448, 0.59520, 0.59055, 0.64992,
  0.61663, 0.70463, 0.63930, 0.77473, 0.63817, 0.82432,
  0.63703, 0.87390, 0.60982, 0.92092, 0.58375, 0.94742,
  0.55768, 0.97392, 0.51573, 0.98333, 0.48172, 0.98333,
  0.44771, 0.98333, 0.40577, 0.97392, 0.37970, 0.94742,
  0.35362, 0.92092, 0.32641, 0.87390, 0.32528, 0.82432,
  0.32415, 0.77473, 0.34682, 0.70463, 0.37289, 0.64992,
  0.39897, 0.59520, 0.42397, 0.57770, 0.44951, 0.54159,
  0.46523, 0.51935, 0.49821, 0.51935, 0.51394, 0.54159,
];
