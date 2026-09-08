import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

/// The back board's colour, derived from the cover's own tone.
///
/// A board is the same stock as the front cover, so a fixed grey board on a
/// saturated cover reads as two objects instead of one book. The reference does
/// hardcode `bg-gray-200`, but every book in its demo is light-toned, so the
/// mismatch never shows there; on a red or black cover it is the first thing you
/// notice.
///
/// Darkened rather than matched, for two reasons. The board is the far side of
/// the book, angled away from the light, so it should be the deeper tone. And it
/// has to stay separable from the near-white page block that sits in front of it
/// — the whole point of the fore-edge square is that the band is legible. The
/// amount therefore scales with the cover's own lightness: a black cover barely
/// needs darkening to separate from paper, a white one needs a lot.
Color bookBoardColorFor(Color cover) {
  final t = 0.18 + 0.30 * cover.computeLuminance();
  return Color.lerp(cover, const Color(0xFF000000), t)!;
}

/// The smallest saturation a cover can have and still look like a colour rather
/// than a grey.
///
/// No longer used by [spineToneFor] — kept because the *drawing* in
/// `docs/mockups/read-pile-turn/` still documents the chroma-lift design this
/// replaced, and a reader comparing the two needs the number to exist.
@Deprecated(
  'The chroma lift was removed from spineToneFor. Remove this once the mockup '
  'has been rebuilt around the background-colour design.',
)
const double kSpineTintMinSaturation = 0.18;

/// How far toward the brand a fully-neutral, fully-light cover's tone was blended.
///
/// See [kSpineTintMinSaturation]; retained for the same reason.
@Deprecated(
  'The chroma lift was removed from spineToneFor. Remove this once the mockup '
  'has been rebuilt around the background-colour design.',
)
const double kSpineTintChromaLift = 0.45;

/// Contrast a spine's fill must reach against the type it carries.
///
/// A hair over WCAG AA's 4.5 for normal text, so a tone that rounds to 4.49 is not
/// accepted. `brand` itself is 2.45:1 and is documented as decoration-only for
/// exactly this reason; a fill with type on it is not decoration.
const double kSpineTintMinContrast = 4.6;

/// The two inks a spine's title can be drawn in.
///
/// **Deliberately not theme colours, and that is the interesting part.** A spine's
/// fill is opaque: it covers `surface` completely, so whether the title is legible
/// depends only on the fill, and the same cover must therefore get the same ink in
/// both themes. Threading `context.colors.primaryText` in here instead looks more
/// correct and is actively wrong — in dark mode that token is `#F1F3F5`, so *both*
/// inks would be light, there would be no dark ink for a pale spine to use, and a
/// white book would be forced down to a mid grey to make room for off-white type.
/// A white book has to stay a white book when the user turns the lights off.
///
/// [kSpineInkDark] is the same value as `AppColors.light.primaryText`, so a pale
/// spine's title matches body text elsewhere rather than being an arbitrary
/// near-black. Copied rather than referenced to keep this file free of a dependency
/// on the theme, and pinned to it by `test/spine_tone_test.dart` so the two cannot
/// drift apart unnoticed.
const Color kSpineInkLight = Color(0xFFFFFFFF);
const Color kSpineInkDark = Color(0xFF212529);

/// Step size and iteration bound for the contrast walk in [spineToneFor].
///
/// Bounded because the loop's exit condition is a contrast ratio rather than an
/// arithmetic target: 24 steps of 6% reaches near-white or near-black from any
/// starting colour, so the bound can only be hit by a mistake, and hitting it
/// returns an extreme tone rather than hanging.
const double _tintDarkenStep = 0.06;
const int _tintDarkenMaxSteps = 24;

/// WCAG 2.x contrast ratio.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The fill and the title colour for a book's **spine** — one decision, so the two
/// cannot disagree.
///
/// Distinct from [bookBoardColorFor], which paints the back board, because the two
/// answer to different things. A board carries no text and is seen against the cover
/// it came from. A spine in the read pile carries a 12pt title and is seen against
/// its neighbours, so it has two obligations a board never had: it must be legible
/// under the type it carries, and it must still look like the book it belongs to.
///
/// **The spine is the colour of the book.** The cover's tone passes through, and the
/// only adjustment is a contrast floor — which picks a *direction* rather than
/// always darkening:
///
///  1. Choose the ink: whichever of [lightInk] and [darkInk] reads better on the
///     cover as it stands.
///  2. Push the fill *away* from the chosen ink in [_tintDarkenStep] increments
///     until it clears [kSpineTintMinContrast]. A dark cover darkens, a pale one
///     **lightens**. Stepwise rather than closed-form because the target is a
///     contrast ratio, which is not linear in the mix.
///
/// Step 2 reads the chosen ink's **own luminance** rather than which parameter it
/// arrived in, and that is not defensive coding — it is the dark-mode case. In dark
/// mode `primaryText` is `#F1F3F5`, so *both* inks are light and "away from
/// [darkInk]" would mean toward white, i.e. toward the ink, and the walk would
/// burn all 24 steps making the contrast worse. Against a fixed ink, contrast is
/// monotonic in the fill's luminance, so the pole opposite the ink is always the
/// direction that helps, whatever the cover was.
///
/// ### What this replaces, and why
///
/// This function used to blend a low-chroma cover toward the brand and then run
/// `bookBoardColorFor` before darkening to clear *white* type. Three things were
/// wrong with that once it met a real library rather than a 13-book drawing:
///
///  * **It could not express a white book.** A `#FAFAFA` jacket has no chroma and
///    high luminance, so the lift blended it 43% toward green and the darkening took
///    the rest: `세이노의 가르침` and `Clean Code` both came out the same dark sage.
///  * **It homogenised.** 228 of 471 real covers fell below the old saturation
///    floor, and because the lift aimed them all at one hue they converged — pale
///    lavender, grey-green and grey-sage all landing within a few points of
///    `#617570`.
///  * **Always darkening threw away the light half of the library.** 76% of covers
///    were being darkened to make room for white type; `#DDA7A4` became `#8E6B69`
///    and `#E4E2C9` became `#677163`, which is a different book.
///
/// The pale end is now carried by presentation instead of by recolouring: dark ink,
/// and `BookVertical`'s hairline outline for a fill that would otherwise vanish into
/// `surface`. The old worry that a pale spine "reads as a hole in the shelf" was
/// right, and an outline answers it without changing the book's colour.
///
/// The inks default to [kSpineInkLight] and [kSpineInkDark] and are parameters only
/// so a test can drive the two branches explicitly. They are **not** theme colours —
/// see [kSpineInkDark] for why passing `primaryText` here breaks dark mode.
({Color fill, Color title}) spineToneFor(
  Color cover, {
  Color lightInk = kSpineInkLight,
  Color darkInk = kSpineInkDark,
}) {
  final ink = _contrast(cover, darkInk) > _contrast(cover, lightInk)
      ? darkInk
      : lightInk;
  // The pole opposite the ink, so the walk always increases contrast and always
  // terminates. Pure white and pure black rather than the inks themselves, so
  // there is always somewhere left to go.
  final away = ink.computeLuminance() > 0.5
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  var fill = cover;
  for (
    var i = 0;
    i < _tintDarkenMaxSteps && _contrast(fill, ink) < kSpineTintMinContrast;
    i++
  ) {
    fill = Color.lerp(fill, away, _tintDarkenStep)!;
  }
  return (fill: fill, title: ink);
}

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

/// A book rendered as flat quads in perspective: back board, page block, front
/// cover, and — when the caller supplies one — a spine.
///
/// The boards are full size and the page block is inset from them on every side
/// — [BookMetrics.boardSquare] at head and tail, [BookMetrics.foreEdgeSquare] on
/// the fore-edge, [BookMetrics.depthClearance] at each end in depth — so they
/// overhang it the way a case binding's boards overhang its text block. The
/// fore-edge square is the one that matters most: without it the back board's
/// outer edge coincides exactly with the pages' and the board is invisible at
/// every turn angle.
///
/// Flutter has no `transform-style: preserve-3d`, and nesting [Transform]s does
/// not substitute for it — an inner [Transform] projects its child
/// orthographically before any outer perspective applies, so a z-translation
/// becomes a visual no-op and all depth is lost. Each face therefore receives
/// one fully composed `parent × local` matrix.
///
/// Every face is wrapped in an identically sized box. [Transform] resolves its
/// `alignment` against the child's size, so faces of differing sizes would each
/// pivot about a different point and the geometry would not line up. For the same
/// reason [pivot] is folded into [bookParentMatrix] rather than passed to
/// `Transform.alignment`: the local matrices are written about the face's centre,
/// and moving the alignment point would reinterpret all of them.
///
/// **Paint order.** Back to front: board, pages, spine, cover — fixed, with no
/// z-sorting. It used to be enough to say the order is correct for any
/// `|turn| < π/2`, which held while the only faces were three parallel planes. A
/// spine turning to `-π/2` needs the argument restated, and the restatement is
/// the reason the spine goes **under** the cover rather than over it, which is not
/// where you would first put it:
///
///  * The spine's near long edge *is* the cover's hinge edge, so the two never
///    interleave — whatever the angle, one is entirely on one side of the hinge
///    and the other is entirely on the other. But **which** side flips with the
///    sign of the turn. At `turn < 0` the spine projects outside the hinge and the
///    cover inside it, disjoint, and the order between them does not matter. At
///    `turn > 0` the spine swings the other way and projects *inside the cover's
///    silhouette* — 8.7pt in on a 78pt cover at [kBookTurnAngle] — where it has
///    to be occluded, because a spine is behind the front board of a book that is
///    tipping its fore-edge toward you.
///  * That combination is what makes one fixed order enough: under the cover is
///    required for positive turns and harmless for negative ones. Both signs
///    occur on the same book — the read pile turns a book out to `0` and then
///    holds it to `+kBookTurnAngle` — so this is a real case, not a hypothetical.
///  * Above the board and the pages, because at every negative angle the spine is
///    nearer the camera than either. They meet it edge-on: the spine's far long
///    edge is the back board's hinge edge.
class BookChassis extends StatelessWidget {
  final BookMetrics metrics;

  /// Turn angle in radians. 0 at rest; positive brings the right edge toward the
  /// viewer, exposing the fore-edge.
  ///
  /// The range in use is `[-π/2, +kBookTurnAngle]`. Negative turns the other way
  /// and **exposes the [spine]**, reaching a fully spine-on book at `-π/2` where
  /// the cover has no projected width left. See [bookParentMatrix].
  final double turn;

  /// 0 at rest, 1 while held. Tightens the shadow to read as contact.
  final double press;

  /// Cover artwork — either a real image or a generated cover.
  final Widget cover;

  /// The face seen along the book's binding, or null for a book that is never
  /// turned far enough to show one.
  ///
  /// Null on the shelves and in the month grid, which turn by at most
  /// [kBookTurnAngle] in the positive direction and so never bring it into view.
  /// The read pile is the one caller that does: its books stand spine-out at
  /// `-π/2` and turn forward to their covers.
  ///
  /// Sized here, not by the caller — [BookMetrics.thickness] wide and the full
  /// height of the book — so a spine cannot be handed in at the wrong depth.
  final Widget? spine;

  /// What the [turn] rotates about. [Alignment.center] spins the book on its own
  /// centre line, which is right for a book lying open on a shelf;
  /// [Alignment.centerLeft] hinges it on the spine, which is right for one
  /// standing in a pile — at `-π/2` a centre pivot would slide the book half a
  /// cover width sideways, through its neighbour.
  ///
  /// Only the horizontal component is read. See [bookParentMatrix].
  final Alignment pivot;

  /// Back board tone, normally derived from the cover via [bookBoardColorFor].
  /// Falls back to the theme's neutral board when the cover's colour is not known
  /// yet — an undecoded network image, for instance.
  final Color? boardColor;

  const BookChassis({
    super.key,
    required this.metrics,
    required this.cover,
    this.spine,
    this.boardColor,
    this.turn = 0,
    this.press = 0,
    this.pivot = Alignment.center,
  });

  /// Perspective, then rotation about [pivot]. See [bookParentMatrix].
  Matrix4 get _parent => bookParentMatrix(metrics, turn, pivot: pivot);

  /// See [bookPageLocalMatrix].
  Matrix4 get _pageLocal => bookPageLocalMatrix(metrics);

  /// See [bookBackLocalMatrix].
  Matrix4 get _backLocal => bookBackLocalMatrix(metrics);

  /// See [bookSpineLocalMatrix].
  Matrix4 get _spineLocal => bookSpineLocalMatrix(metrics);

  @override
  Widget build(BuildContext context) {
    final colors = BookChassisColors.of(context);

    return SizedBox(
      width: metrics.width,
      height: metrics.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Painted back to front. See the paint-order note on the class: the
          // order is fixed, the spine belongs under the cover rather than over
          // it, and there is no z-sorting to do.
          _face(local: _backLocal, child: _backBoard(colors)),
          _face(local: _pageLocal, child: _pageBlock(colors)),
          if (spine != null) _face(local: _spineLocal, child: _spineFace()),
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
        color: boardColor ?? colors.backBoard,
      ),
    );
  }

  Widget _pageBlock(BookChassisColors colors) {
    return BookPageBlock(
      // Narrower than the book is thick, leaving a clearance at each end so both
      // boards overhang the text block in depth. Paired with
      // `bookPageLocalMatrix`, which recesses the strip by the same amount.
      thickness: metrics.pageBlockThickness,
      // Proportional to height, calibrated on the reference's 3px at 240pt. It
      // was briefly flat 3px, which measured 1.6% of a 180pt book against the
      // reference's 1.25% and read as an over-cut board.
      inset: metrics.boardSquare,
      colors: colors,
    );
  }

  /// The spine, laid out along the left edge of the face box.
  ///
  /// `bookSpineLocalMatrix` maps that box's x directly onto depth, so x=0 is the
  /// cover's hinge and x=[BookMetrics.thickness] is the back board's. Left-aligned
  /// for the same reason [BookPageBlock] is, and with the same explicit infinite
  /// height: a childless box under loose constraints sizes to
  /// `constraints.smallest`, which collapsed the page strip to nothing once
  /// already.
  Widget _spineFace() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: metrics.thickness,
        height: double.infinity,
        child: spine,
      ),
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
