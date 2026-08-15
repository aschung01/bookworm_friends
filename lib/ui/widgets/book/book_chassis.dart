import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

/// Colours for the non-cover parts of a book, resolved per theme.
///
/// The page block and back board are near-white in light mode. Left that way in
/// dark mode they glow against `#121212`, so both get explicit dark values
/// rather than being derived from the cover.
@immutable
class BookChassisColors {
  /// Shading on the page block where it meets the cover.
  final Color pageEdge;

  /// Page block body, top and bottom of a vertical gradient.
  final Color pageBase;
  final Color pageBaseLow;

  /// The board behind the book.
  final Color backBoard;

  /// Hairline around the cover, giving it a defined edge.
  final Color hairline;

  /// Only used in dark mode, where cast shadows barely register and a top rim
  /// does the edge-definition work instead.
  final Color? rim;

  final List<BoxShadow> Function(double scale) shadows;

  const BookChassisColors({
    required this.pageEdge,
    required this.pageBase,
    required this.pageBaseLow,
    required this.backBoard,
    required this.hairline,
    required this.shadows,
    this.rim,
  });

  factory BookChassisColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? BookChassisColors(
            pageEdge: Colors.black.withValues(alpha: 0.40),
            // Deliberately NOT surfaceVariant. The details page paints its hero
            // area with surfaceVariant, so a page block in that tone is the same
            // colour as the surface behind it and the fore-edge disappears. These
            // are a mid grey that reads as paper in low light and separates from
            // both surfaceVariant (#2C2C2E) and pageBackground (#121212).
            pageBase: const Color(0xFF4A4A4E),
            pageBaseLow: const Color(0xFF3E3E42),
            backBoard: const Color(0xFF35353A),
            hairline: Colors.white.withValues(alpha: 0.08),
            rim: Colors.white.withValues(alpha: 0.06),
            shadows: _darkShadows,
          )
        : BookChassisColors(
            pageEdge: const Color(0xFFEAEAEA),
            pageBase: const Color(0xFFFFFFFF),
            pageBaseLow: const Color(0xFFFAFAFA),
            backBoard: const Color(0xFFE3E3E3),
            hairline: Colors.black.withValues(alpha: 0.07),
            shadows: _lightShadows,
          );
  }
}

/// Four stacked layers, offsets and blur scaled so an 86px book doesn't carry
/// the shadow authored for a 196px one.
List<BoxShadow> _lightShadows(double scale) => [
  BoxShadow(
    offset: Offset(0, 1 * scale),
    blurRadius: 1 * scale,
    color: Colors.black.withValues(alpha: 0.035),
  ),
  BoxShadow(
    offset: Offset(0, 3 * scale),
    blurRadius: 6 * scale,
    color: Colors.black.withValues(alpha: 0.045),
  ),
  BoxShadow(
    offset: Offset(0, 10 * scale),
    blurRadius: 18 * scale,
    color: Colors.black.withValues(alpha: 0.05),
  ),
  BoxShadow(
    offset: Offset(0, 22 * scale),
    blurRadius: 36 * scale,
    color: Colors.black.withValues(alpha: 0.055),
  ),
];

/// Two layers at higher alpha. Soft low-alpha shadows are invisible on a
/// near-black background, so stacking four of them only costs paint time.
List<BoxShadow> _darkShadows(double scale) => [
  BoxShadow(
    offset: Offset(0, 2 * scale),
    blurRadius: 5 * scale,
    color: Colors.black.withValues(alpha: 0.30),
  ),
  BoxShadow(
    offset: Offset(0, 14 * scale),
    blurRadius: 28 * scale,
    color: Colors.black.withValues(alpha: 0.26),
  ),
];

/// Gradient stops for the spine binding, from the reference's `--ds-book-bind`.
///
/// The white stop is a highlight ridge and the trailing black stop is the
/// crease where the board folds. Without both, the band reads as a dark smear
/// rather than a binding.
const List<Color> _bindingColors = [
  Color(0x42000000), // black 26%
  Color(0x12000000), // black 7%
  Color(0x4CFFFFFF), // white 30%
  Color(0x1C000000), // black 11%
];
const List<double> _bindingStops = [0.0, 0.34, 0.78, 1.0];

/// A book rendered as three flat quads in perspective: back board, page block,
/// front cover.
///
/// Flutter has no `transform-style: preserve-3d`, and nesting [Transform]s does
/// not substitute for it — an inner [Transform] projects its child
/// orthographically before any outer perspective applies, so a z-translation
/// becomes a visual no-op and all depth is lost. Each face therefore receives
/// one fully composed `parent × local` matrix.
///
/// Every face is wrapped in an identically sized box. [Transform] resolves its
/// `alignment` against the child's size, so faces of differing sizes would each
/// pivot about a different point and the geometry would not line up.
class BookChassis extends StatelessWidget {
  final BookMetrics metrics;

  /// Turn angle in radians. 0 at rest; positive brings the right edge toward the
  /// viewer, exposing the fore-edge.
  final double turn;

  /// 0 at rest, 1 while held. Tightens the shadow to read as contact.
  final double press;

  /// Cover artwork — either a real image or a generated cover.
  final Widget cover;

  const BookChassis({
    super.key,
    required this.metrics,
    required this.cover,
    this.turn = 0,
    this.press = 0,
  });

  /// Perspective, then rotation. See [bookParentMatrix].
  Matrix4 get _parent => bookParentMatrix(metrics, turn);

  /// See [bookPageLocalMatrix].
  Matrix4 get _pageLocal => bookPageLocalMatrix(metrics);

  /// See [bookBackLocalMatrix].
  Matrix4 get _backLocal => bookBackLocalMatrix(metrics);

  @override
  Widget build(BuildContext context) {
    final colors = BookChassisColors.of(context);

    return SizedBox(
      width: metrics.width,
      height: metrics.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Painted back to front. The order is fixed and correct for any
          // |turn| < π/2, so there is no z-sorting to do.
          _face(local: _backLocal, child: _backBoard(colors)),
          _face(local: _pageLocal, child: _pageBlock(colors)),
          _face(local: Matrix4.identity(), child: _coverFace(colors)),
        ],
      ),
    );
  }

  Widget _face({required Matrix4 local, required Widget child}) {
    return Transform(
      transform: _parent.multiplied(local),
      alignment: Alignment.center,
      // Hit testing is handled by the gesture detector wrapping the whole
      // chassis, so the transformed faces don't need to participate.
      transformHitTests: false,
      child: SizedBox(
        width: metrics.width,
        height: metrics.height,
        child: child,
      ),
    );
  }

  Widget _backBoard(BookChassisColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: metrics.radius,
        color: colors.backBoard,
      ),
    );
  }

  Widget _pageBlock(BookChassisColors colors) {
    // Inset top and bottom so the block sits inside the cover's rounded
    // corners rather than poking past them.
    final inset = (3 * metrics.shadowScale).clamp(1.0, 3.0);
    return BookPageBlock(
      thickness: metrics.thickness,
      inset: inset,
      colors: colors,
    );
  }

  Widget _coverFace(BookChassisColors colors) {
    // Shadow tightens toward 0.85× while held.
    final scale = metrics.shadowScale * (1 - 0.15 * press);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: metrics.radius,
        boxShadow: colors.shadows(scale),
      ),
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: metrics.radius,
          border: Border.all(color: colors.hairline, width: 1),
        ),
        child: ClipRRect(
          borderRadius: metrics.radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              cover,
              Align(
                alignment: Alignment.centerLeft,
                child: _BlendMask(
                  blendMode: BlendMode.overlay,
                  child: SizedBox(
                    width: metrics.bindingWidth,
                    height: double.infinity,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: _bindingColors,
                          stops: _bindingStops,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (colors.rim != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(height: 1, color: colors.rim),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The stack of pages seen along the book's fore-edge.
///
/// Public so its layout can be asserted directly: it is the one face whose size
/// is not pinned by the chassis, and a collapsed page block is invisible rather
/// than loud — the flat back board simply shows through in its place.
class BookPageBlock extends StatelessWidget {
  final double thickness;
  final double inset;
  final BookChassisColors colors;

  const BookPageBlock({
    super.key,
    required this.thickness,
    required this.inset,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: inset),
        child: SizedBox(
          width: thickness,
          // Explicit infinite height, which the enclosing Padding clamps to the
          // space available. Without it the height constraint stays loose, and a
          // childless DecoratedBox is a RenderProxyBox that sizes to
          // `constraints.smallest` — so the whole strip collapsed to zero and the
          // flat back board showed through the fore-edge instead.
          height: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                // Vertical, matching the reference's `linear-gradient(#fff,
                // #fafafa)`. CSS defaults that to top-to-bottom; Flutter defaults
                // to left-to-right, so omitting these silently rotates the page
                // tone into the same axis as the edge shading below.
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.pageBase, colors.pageBaseLow],
              ),
            ),
            // The strip's left edge is the one adjacent to the cover, so the
            // edge shading starts there and fades out into the depth.
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [colors.pageEdge, colors.pageEdge.withAlpha(0)],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Composites its child with an explicit [BlendMode].
///
/// Used instead of [BoxDecoration.backgroundBlendMode] because that blends
/// against whatever the *parent* happens to have painted and silently no-ops
/// when the parent is transparent — behaviour that depends on ancestors we
/// don't control. An explicit `saveLayer` bounded to the band means the binding
/// always blends against the cover and nothing else. The layer is only as large
/// as the 8.2%-wide band, so the cost is small.
class _BlendMask extends SingleChildRenderObjectWidget {
  final BlendMode blendMode;

  const _BlendMask({required this.blendMode, required super.child});

  @override
  _RenderBlendMask createRenderObject(BuildContext context) =>
      _RenderBlendMask(blendMode);

  @override
  void updateRenderObject(BuildContext context, _RenderBlendMask renderObject) {
    renderObject.blendMode = blendMode;
  }
}

class _RenderBlendMask extends RenderProxyBox {
  BlendMode _blendMode;

  _RenderBlendMask(this._blendMode);

  set blendMode(BlendMode value) {
    if (value == _blendMode) return;
    _blendMode = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.saveLayer(offset & size, Paint()..blendMode = _blendMode);
    super.paint(context, offset);
    context.canvas.restore();
  }
}
