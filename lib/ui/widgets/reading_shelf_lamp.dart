import 'package:flutter/material.dart';

import 'package:bookworm_friends/ui/widgets/book_widget.dart';

/// The light over the Reading shelf.
///
/// **The Library Card's own light, on a shelf.** `card_lighting.dart` already owns a
/// warm point source with settled tokens — `kCandleFlame` #F2A93F, `kCandleGlow`
/// #FFE8C4, and `kCandleBloomColors`, the bloom it casts. This is that bloom, cast
/// down over one row of books.
///
/// **Adapted, not reused wholesale, and the difference is the whole reason this file
/// exists rather than a call into that one.** The card's candlelight is a *dark
/// scene*: the stock goes to #26190A, the well darker still, and a flame picks out
/// what is pressed into the paper. This is one lit shelf on a daylight screen, so
/// there is no dark stock to fall off into — only the highlight. Taking the card's
/// gradient stops directly would be borrowing the half of that design that does not
/// apply. What is borrowed is the light's *colour* and its falloff.
///
/// The colours are restated here as a deliberate copy rather than imported, because
/// importing them would say the two surfaces must always agree, and they must not:
/// the card's bloom is tuned against near-black and this one against #E9ECEF. If the
/// candle is ever retuned, this should be looked at and not silently follow.
/// `test/reading_shelf_lamp_test.dart` pins the pair so the copy is visible.
const List<Color> kReadingLampBloom = [
  Color(0x52FFC76A),
  Color(0x14FF9A2E),
  Color(0x00FF9A2E),
];

/// Where the bloom's stops land, from the source outward.
///
/// Front-loaded: most of the warmth is inside the first half of the reach, because a
/// lamp above a shelf lights the tops of the books and falls off quickly. An even ramp
/// read as a tinted panel rather than as light.
const List<double> kReadingLampStops = [0.0, 0.55, 1.0];

/// How far down the row the light reaches, as a fraction of the row's height.
///
/// Short of the whole row on purpose. The plank has its own warm pool
/// ([kReadingLampPlankGlow]) and the two meeting in the middle flattened the falloff
/// into a single wash.
const double kReadingLampExtent = 0.82;

/// How far above the Reading shelf's books the light comes from, which is also the
/// library's own top padding.
///
/// **The source sits at the very top of the library, right under the shell's bar.** That
/// is what makes it read as a light *fixed to the room* rather than as a warm rectangle
/// belonging to one row — see [readingLampHeight] and the note on `ReadingShelfRow`.
///
/// Two earlier drafts got this wrong in opposite directions and both are worth recording,
/// because each looked right until the shelf was scrolled. The first painted the reach
/// *outside* the row's own box with a negative `Positioned.top` under `Clip.none`, on the
/// reasoning that it fell into "the 26pt gap the shelf above already leaves" — fiction for
/// this shelf, which is always the *first* in the library, so what is above it is scroll
/// content next to the app bar rather than a reserved gap. The second folded the reach
/// into real height inside the row, which fixed the overflow and left the real problem
/// untouched: the bloom was still part of the scrolling content, so it slid up the screen
/// with the books, and it now had a strip of bare `surfaceVariant` above it where the
/// library's own top padding showed through. Light does not scroll, and there is nothing
/// above a ceiling.
const double kReadingLampSourcePadding = 16;

/// How tall the wash at the top of the library is, for a book of [bookHeight].
///
/// Measured from the library's own top edge — not from the Reading shelf's box — because
/// the lamp is a fixed layer behind the scroll view. [kReadingLampSourcePadding] covers
/// the gap the library leaves above its first shelf, and [kReadingLampExtent] of a row's
/// height carries the falloff down over the covers.
double readingLampHeight(double bookHeight) =>
    kReadingLampSourcePadding + bookRowExtent(bookHeight) * kReadingLampExtent;

/// How far the library scrolls before the lamp is out, for a book of [bookHeight].
///
/// **The distance the Reading shelf's books take to leave the lit zone.** They start
/// [kReadingLampSourcePadding] below the library's top edge and stand [bookRowExtent]
/// tall, so once the library has scrolled by the sum of the two, every cover the lamp was
/// lighting is above that edge and the light has nothing left to fall on. Necessarily
/// longer than [readingLampHeight], which is the same span less [kReadingLampExtent] — so
/// the light is never out while part of the row is still inside its reach.
///
/// The plank is still on screen at that point, and keeps its warmth: the board's pool
/// ([kReadingLampPlankGlow]) is painted on the row and travels with it, the way a mark on
/// a board should.
double readingLampFadeDistance(double bookHeight) =>
    kReadingLampSourcePadding + bookRowExtent(bookHeight);

/// How strong the light is once the library has scrolled by [scrollOffset], as a fraction
/// of full — 1 with the shelf at rest, 0 once [fadeDistance] has passed.
///
/// **This is what a fixed light costs, paid back.** A lamp pinned to the top of the
/// library does not stop lighting things when its shelf leaves: scroll far enough and the
/// bloom is over a *queue* shelf, so the device ends up saying "the library is lit from
/// above" rather than "this row is lit" — which is the opposite of the claim it was built
/// to make. Dimming ties the light back to its subject without putting it back inside the
/// row, which is what both earlier drafts did wrong (see [kReadingLampSourcePadding]).
/// The light is still a fixture; it is just a fixture that has nothing to illuminate.
///
/// **Linear, because the lit fraction of the row is linear.** The row leaves the zone at
/// the speed of the finger, so an equal share of it is gone for every point scrolled — an
/// eased ramp would be a flourish laid over a quantity that is already known. Clamped at
/// both ends, so the overscroll a pull-to-refresh produces (a negative
/// [ScrollMetrics.pixels]) cannot brighten the lamp past full.
double readingLampIntensity({
  required double scrollOffset,
  required double fadeDistance,
}) {
  if (fadeDistance <= 0) return 1;
  return 1 - (scrollOffset / fadeDistance).clamp(0.0, 1.0);
}

/// How far past each end of the row the light spills, as a fraction of the row's width.
const double kReadingLampBleed = 0.02;

/// Horizontal reach, as a fraction of the row's width — the `120%` in the design
/// record's `radial-gradient(120% 100% at 50% 0%, …)`.
///
/// **Wider than the row, and that is what keeps the ends from going dark.** A bloom that
/// finished at the row's edges would read as a vignette on a panel; at 1.2 the falloff is
/// still climbing when it reaches the clip, so the light simply stops with the row the
/// way a real one does.
const double kReadingLampSpread = 1.2;

/// The pool the lamp throws on the board itself, added to the plank's own shadow.
const Color kReadingLampPlankGlow = Color(0x8CFFC76A);

/// How much a lit cover is scaled up, not washed over.
///
/// **This is the rule `card_lighting.dart` is emphatic about, and the reason these are
/// multipliers rather than an overlay colour.** A warm point source *scales* what a
/// surface already reflects — `cover × light` — so it deepens and warms a jacket while
/// keeping its own hue. A translucent warm layer laid on top does the opposite: it
/// pulls every cover toward one colour, which is exactly what that file says a
/// blacklight would do and why the card multiplies instead.
///
/// Small numbers. The covers are the subject; the light is not supposed to be the
/// first thing anyone notices about them.
const double kReadingLampCoverBrightness = 1.05;
const double kReadingLampCoverSaturation = 1.04;

/// The warm wash [LibraryPane] paints across the top of the library when a book is open.
///
/// Sized and positioned by the caller — [readingLampHeight] is the height it expects.
/// Draws nothing but the gradient, so it can sit behind the shelves without taking part
/// in their layout, and **outside the scroll view**, so it does not travel with them.
///
/// **Radial from a point above the middle of the row, not a ramp down it**, and the
/// difference is the whole reading of the device. A vertical ramp is warm right across
/// the row at any given height, which is a tinted band — a panel behind the books. A
/// bloom centred on one point falls off sideways as well as down, so there is somewhere
/// the light is *coming from*, which is the only thing that makes it a lamp.
class ReadingShelfLamp extends StatelessWidget {
  /// How strong the light is, from 0 to 1 — see [readingLampIntensity], which is what
  /// [ReadingLampLayer] feeds this as the Reading shelf scrolls away.
  final double intensity;

  const ReadingShelfLamp({super.key, this.intensity = 1});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          // Top centre — the library's own top edge, since the caller pins this layer
          // there rather than to any row. With [_EllipticalBloom] below, that point is
          // where the light comes from.
          center: Alignment.topCenter,
          // Reach is set entirely by the transform, which scales both axes from the
          // box. Left at 1 so there is one place the ellipse is decided.
          radius: 1,
          colors: _dimmed(intensity),
          stops: kReadingLampStops,
          transform: const _EllipticalBloom(),
        ),
      ),
    );
  }

  /// The bloom with every stop's *alpha* scaled and nothing else touched.
  ///
  /// Turning a light down is not laying grey over it: the hues stay exactly as tuned, so a
  /// dim lamp is the same colour of light as a bright one, and the last stop — already
  /// transparent — stays transparent at every strength.
  ///
  /// Identity at full, so the state the tokens were tuned in draws the constant list
  /// itself rather than a recomputation of it.
  static List<Color> _dimmed(double intensity) {
    if (intensity >= 1) return kReadingLampBloom;
    return [
      for (final color in kReadingLampBloom)
        color.withValues(alpha: color.a * intensity.clamp(0.0, 1.0)),
    ];
  }
}

/// The lamp as the library wears it: a fixed layer across the top, the shelves scrolling
/// underneath it, and the light dimming as the Reading shelf leaves.
///
/// **The offset is read from notifications, not from a [ScrollController]**, because the
/// scrolling widget is [child] — already built by the caller — and threading a controller
/// into it would make the library's list the lamp's business.
///
/// **Two notifications, covering different cases.** [ScrollNotification] is the drag.
/// [ScrollMetricsNotification] is an offset that moved without one: a first layout, or
/// content that grew or shrank under a scrolled list and had its position corrected. The
/// second is also what makes the frame the Reading shelf *appears* on correct — the list
/// is rebuilt when the lamp arrives, and its new position announces itself that way rather
/// than through a drag that has not happened yet.
///
/// [lit] false keeps the layer and draws no light, which is deliberate: the state that
/// tracks the offset outlives a book being opened or finished, so the light does not have
/// to relearn where the library is every time the shelf comes and goes.
class ReadingLampLayer extends StatefulWidget {
  /// Whether anything is in progress. The library is unlit exactly when the Reading shelf
  /// is absent — a lit room with no shelf under the light would be a warm rectangle.
  final bool lit;

  /// The height of a book on these shelves, which both the light's reach and its fade are
  /// measured from — see [readingLampHeight] and [readingLampFadeDistance].
  final double bookHeight;

  /// The scrolling shelves, drawn over the light.
  final Widget child;

  const ReadingLampLayer({
    super.key,
    required this.lit,
    required this.bookHeight,
    required this.child,
  });

  @override
  State<ReadingLampLayer> createState() => _ReadingLampLayerState();
}

class _ReadingLampLayerState extends State<ReadingLampLayer> {
  /// In a notifier rather than in `setState`, so a scroll frame repaints one gradient and
  /// nothing else. The shelves are the expensive half of this stack and they have not
  /// changed.
  final ValueNotifier<double> _intensity = ValueNotifier<double>(1);

  @override
  void dispose() {
    _intensity.dispose();
    super.dispose();
  }

  /// Both listeners land here. Returns false in every case: this layer is reading the
  /// library's scrolling, not consuming it.
  bool _onMetrics(ScrollMetrics metrics) {
    // Vertical only, and this is not a formality — every shelf is a horizontal scroll
    // view of its own whose notifications bubble through here as well, so without the
    // filter a sideways flick along one row would dim the room.
    if (metrics.axis != Axis.vertical || !metrics.hasPixels) return false;
    _intensity.value = readingLampIntensity(
      scrollOffset: metrics.pixels,
      fadeDistance: readingLampFadeDistance(widget.bookHeight),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Unlit is the child alone, with no Stack around it: a Stack whose every child is
    // positioned collapses to nothing under loose constraints, and the library is not
    // owed tight ones. The listeners stay in both states — that is the point of keeping
    // the layer when the shelf is gone.
    final Widget body = widget.lit
        ? Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: readingLampHeight(widget.bookHeight),
                // Not a thing a finger can touch, and never over the shelves.
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _intensity,
                    builder: (context, intensity, _) =>
                        ReadingShelfLamp(intensity: intensity),
                  ),
                ),
              ),
              Positioned.fill(child: widget.child),
            ],
          )
        : widget.child;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) => _onMetrics(notification.metrics),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) => _onMetrics(notification.metrics),
        child: body,
      ),
    );
  }
}

/// The bloom's circle, stretched to the ellipse the row actually wants.
///
/// Flutter measures [RadialGradient.radius] against the box's *shortest* side, so a
/// circle in a row three times wider than it is tall reaches the plank long before it
/// reaches either end. This scales the gradient's own space instead — [kReadingLampSpread]
/// of the width across, the full height down — which is what CSS writes as
/// `radial-gradient(120% 100% at 50% 0%, …)` and what the design record was drawn with.
///
/// Both axes are scaled explicitly rather than only the wide one, so the result does not
/// depend on which side Flutter happened to measure.
class _EllipticalBloom extends GradientTransform {
  const _EllipticalBloom();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final unit = bounds.shortestSide;
    if (unit <= 0) return Matrix4.identity();
    final kx = bounds.width * kReadingLampSpread / unit;
    final ky = bounds.height / unit;
    // Scaled about the source, not about the box's centre: scaling about anywhere
    // else would move the point the light comes from. Written out rather than
    // composed from `translate`/`scale` calls so there is one matrix and no
    // deprecated vector-math overload in it.
    final ox = bounds.center.dx;
    final oy = bounds.top;
    return Matrix4.diagonal3Values(kx, ky, 1)
      ..setTranslationRaw(ox * (1 - kx), oy * (1 - ky), 0);
  }
}

/// [child] as the lamp leaves it: brighter and a shade more saturated, its own colour
/// intact.
///
/// A `ColorFilter` matrix rather than an `Opacity` or a `ColoredBox` for the reason
/// above — this multiplies the cover, it does not tint it.
class ReadingLampWash extends StatelessWidget {
  final Widget child;
  const ReadingLampWash({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: _matrix(
        brightness: kReadingLampCoverBrightness,
        saturation: kReadingLampCoverSaturation,
      ),
      child: child,
    );
  }

  /// Brightness as a scale on each channel, then saturation about the luminance
  /// axis using the same Rec. 709 weights the contrast test uses.
  static ColorFilter _matrix({
    required double brightness,
    required double saturation,
  }) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final s = saturation;
    final b = brightness;
    double r(double w) => (1 - s) * w;
    return ColorFilter.matrix(<double>[
      (r(lr) + s) * b,
      r(lg) * b,
      r(lb) * b,
      0,
      0,
      r(lr) * b,
      (r(lg) + s) * b,
      r(lb) * b,
      0,
      0,
      r(lr) * b,
      r(lg) * b,
      (r(lb) + s) * b,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }
}
