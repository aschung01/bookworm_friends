import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';

/// The bottom corner radius of the book details band.
///
/// **One constant, read by both the container and the bar that runs along it.**
/// The band declares this radius on its own `BoxDecoration` and
/// [BandProgressEdge] clips to it; two literal `30`s in two files is precisely how
/// the bar and the band drift apart, and the drift is invisible until it is 1pt and
/// then it looks like a rendering bug.
const double kBookBandCornerRadius = 30;

/// How thick the bar is.
const double kBandProgressEdgeThickness = 4;

/// The reading position, drawn as the band's own bottom edge.
///
/// **Linear and full-bleed, with its ends clipped by the band's corner radius.** It
/// is deliberately *not* traced around the corners — that was drawn (`cl-edge2` in
/// `docs/mockups/streaks/index.html`) and rejected as a different look rather than
/// accepted as a fix, because a stroke following the arc reads as a pill floating on
/// the border instead of as the border being inked in.
///
/// **The low end is blind, and that is a trade rather than a bug.** Below roughly 8%
/// the whole fill sits inside the bottom-left corner arc and nothing is visible: at
/// 4% of a 393pt band the fill is about 16pt wide and the arc's chord at the bar's
/// height is about 15. That is accepted because **the numbers sit directly above the
/// bar** — an empty-looking edge beside a legible `4%` degrades rather than lies, and
/// the bar is an ambient second reading and never the source of truth. The
/// alternative that fixes it, spanning only the flat bottom from x30 to x363, is
/// drawn as `ln-flat`: visible at 1%, and no longer an edge. Nothing sits between the
/// two, because the clipping *is* the edge-to-edge look.
///
/// Draws nothing at all when there is no position. Null is not `0`: an empty track
/// would claim the reader started and got nowhere, on every book in the library.
class BandProgressEdge extends StatelessWidget {
  const BandProgressEdge({super.key, required this.progress});

  /// A fraction 0..1, or null when nothing has been recorded.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    if (value == null) return const SizedBox.shrink();
    return IgnorePointer(
      // The bar overlays the band's own bottom padding, where the progress row's
      // extended tap target lives. Painting over a hit area would swallow it.
      child: CustomPaint(
        painter: _BandProgressEdgePainter(
          progress: value.clamp(0.0, 1.0),
          // `brandText` rather than `brandFill`, which is a deviation from the plan
          // and a no-op in light mode: the two are the same #067657 there, so this
          // draws exactly what the mockup drew. They differ in **dark** mode, where
          // `brandFill` stays #067657 and would leave a 4pt bar all but invisible on
          // a dark band, while `brandText` is the vivid green. This bar is a
          // selection indicator, which is the job `brandText` documents.
          fill: context.colors.brandText,
          // The mockup's literal `rgba(6, 118, 87, 0.16)`, expressed against the
          // token so the dark theme's track follows its own fill.
          track: context.colors.brandText.withValues(alpha: 0.16),
        ),
      ),
    );
  }
}

class _BandProgressEdgePainter extends CustomPainter {
  const _BandProgressEdgePainter({
    required this.progress,
    required this.fill,
    required this.track,
  });

  final double progress;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    // Clipped to the band's own shape, taking the radius from the constant the
    // band's `BoxDecoration` also reads. This is what makes the bar's ends
    // *disappear into* the corners rather than stop short of them, and it is why
    // the painter is given the whole band to paint in rather than a 4pt strip:
    // the corner arcs are only expressible against the band's real height.
    canvas.clipRRect(
      RRect.fromRectAndCorners(
        Offset.zero & size,
        bottomLeft: const Radius.circular(kBookBandCornerRadius),
        bottomRight: const Radius.circular(kBookBandCornerRadius),
      ),
    );

    final top = size.height - kBandProgressEdgeThickness;
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, kBandProgressEdgeThickness),
      Paint()..color = track,
    );
    if (progress <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width * progress, kBandProgressEdgeThickness),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_BandProgressEdgePainter old) =>
      old.progress != progress || old.fill != fill || old.track != track;
}
