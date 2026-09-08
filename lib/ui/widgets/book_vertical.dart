import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:flutter/material.dart';

/// Room at the head and the tail of a spine, before its title starts.
///
/// 8 and 9 rather than the 15/15 this used to spend. On a 110–124pt spine that
/// was a quarter of the book's length given to margin, to clear an arch that is
/// 5pt deep — and it cost measure the titles badly needed: 80–94pt became
/// 93–107pt, about one more Hangul syllable, for nothing. Uneven because a spine
/// stands on a plank: the tail is the edge a reader sees against the shelf.
const double kSpinePadHead = 8;
const double kSpinePadTail = 9;

/// How thick a spine must be before it will set its title on two lines.
///
/// Two lines of [AppTextStyles.spine] occupy 25.9pt across the thickness, so this
/// is not the binding constraint — 33 is where a second line starts to look like
/// a choice rather than a squeeze, and it is what the drawing settled on.
const double kSpineTwoLineMinThickness = 33;

/// How far the tail of an overflowing title is ramped away.
///
/// **A fade rather than an ellipsis, and the reason is arithmetic.** Rotated, `…`
/// is three dots stacked down the spine and it costs about a syllable of the very
/// measure it is apologising for. A ramp costs none, works on a wrapped line where
/// `TextOverflow.ellipsis` cannot, and reads as the title running on under the
/// shelf rather than as a string that was cut.
const double kSpineFadeExtent = 15;

/// Where a catalogue title stops being the title.
///
/// A Korean catalogue supplies the original title in parentheses and the subtitle
/// after a colon as a matter of course, and on a spine that is the difference
/// between a title that fits and one that does not: `그로스 해킹(Growth Hacking)`
/// truncates, `그로스 해킹` fits whole with room left. Across the drawing's corpus
/// this was **half of all truncation, and none of it was about measure**.
///
/// Only cuts at an interior mark, and never to nothing — a title that begins with
/// a bracket keeps it, because whatever is inside is all the title there is.
const List<String> kSpineTitleMarks = [
  '(',
  '（',
  ':',
  '：',
  '[',
  ' - ',
  ' ~ ',
  '~',
  '—',
  '―',
];

/// [title] with any parenthetical or subtitle removed. See [kSpineTitleMarks].
///
/// Pure and public so `test/spine_title_test.dart` can pin the cases without
/// building a widget.
String spineTitleOf(String title) {
  var cut = title.length;
  for (final mark in kSpineTitleMarks) {
    final at = title.indexOf(mark);
    if (at > 0 && at < cut) cut = at;
  }
  final kept = title.substring(0, cut).trimRight();
  return kept.isEmpty ? title : kept;
}

/// A book seen along its spine: a flat quad with a rounded head and a rotated
/// title.
///
/// The read pile's resting drawing. Deliberately *not* a [BookChassis]: a pile of
/// spines is the one place in the app that shows every book at once, and a chassis
/// per book would load a cover image per book into the collapsed Library tab. This
/// draws from values the app already has.
///
/// It has to match what the chassis renders at a turn of `-π/2`, because tapping a
/// spine swaps one for the other in place. That is why the fill is a resolved
/// colour rather than a treatment: both sides take the same [spineToneFor] value.
class BookVertical extends StatelessWidget {
  final double width;
  final double height;

  /// Brand green at this opacity, when no [fill] is given.
  ///
  /// The pile's original treatment: three fixed opacities cycled down the row, so
  /// neighbouring spines separate from each other. Superseded by [fill] there, and
  /// kept because this widget is public and the fallback costs one line.
  final double opacity;

  /// The spine's colour, resolved by the caller.
  ///
  /// Overrides [opacity]. Expected to come from `spineToneFor`, whose `fill` and
  /// `title` are decided together — pass its `title` as [titleColor] so the two
  /// cannot drift apart.
  final Color? fill;

  /// The title's colour, resolved by the caller alongside [fill].
  ///
  /// Optional, and when omitted this widget derives its own by contrast. That
  /// fallback exists for callers that resolve a [fill] by some other route; the read
  /// pile passes both, because `spineToneFor` chooses the ink *first* and then walks
  /// the fill away from it. Re-deriving the ink from the walked fill would usually
  /// agree and does not have to: the walk stops the moment it clears 4.6:1, so a
  /// mid-tone cover can land a hair over the floor against the ink that was chosen
  /// while still scoring higher against the other one, and this widget would then
  /// pick the ink the fill was never adjusted for.
  final Color? titleColor;

  /// A hairline down the spine's right edge.
  ///
  /// Unnecessary while every spine was one green at three opacities, because the
  /// opacities separated them. Once each spine takes its own book's tone, two books
  /// with similar covers stand side by side as one wide block without it.
  final bool separator;

  final String title;
  final bool complimented;

  /// Null for a spine that is decoration rather than a target.
  ///
  /// Load-bearing rather than a convenience: this widget is also handed to
  /// `BookChassis.spine`, and the chassis hit-tests through a single detector
  /// wrapping all four faces. A detector inside one of those faces would claim
  /// taps meant for the cover — and would claim them at the *untransformed*
  /// position, since the faces are laid out with `transformHitTests: false`.
  final VoidCallback? onTap;

  /// The rounded head, 5pt deep at each edge.
  ///
  /// **False when this is a face of a `BookChassis`, and that is not a style
  /// choice.** An arch is a notch cut into the top of one face, which a flat
  /// drawing can do and a solid object cannot: the cover beside it is full height,
  /// so at the hinge the spine's head sits 5pt lower than the cover's and the back
  /// board shows through the gap in a different tone. It reads as the spine and the
  /// cover being two different heights, which is exactly what it looks like.
  ///
  /// The cost of switching it off is a one-frame change of head shape at the moment
  /// a flat spine is swapped for a chassis — taken deliberately, because that frame
  /// is also the first frame of a 260ms rotation in which the whole silhouette is
  /// already moving, whereas the notch is a grey wedge visible for the entire turn.
  final bool arch;

  /// The colour behind this spine, for deciding whether it needs an outline.
  ///
  /// Defaults to `surface`, which is what this widget used unconditionally and is
  /// right on a shelf. **It is wrong in the read pile**, which is the
  /// `collapsedBody` of a sheet and therefore sits on `sheetBackground` — `#EFF5EF`,
  /// not `#FFFFFF`.
  ///
  /// That mattered less than it looks (both are very light, so a white spine failed
  /// the test either way) but it failed in the unsafe direction: `#EFF5EF` is
  /// *darker* than `surface`, so a fill measured against white can clear the
  /// threshold while genuinely having no edge against the sheet. A `#E0E0E0` spine
  /// scores 1.27 on white and 1.15 on the sheet.
  final Color? background;

  const BookVertical({
    super.key,
    this.width = 26,
    this.height = 124,
    this.opacity = 1.0,
    this.fill,
    this.titleColor,
    this.separator = false,
    required this.title,
    this.complimented = false,
    this.onTap,
    this.arch = true,
    this.background,
  });

  /// Below this contrast against the colour behind it, a spine has no silhouette of
  /// its own and needs an outline to be a shape at all.
  ///
  /// 1.25 is deliberately low: it is not a legibility threshold, it is the point at
  /// which the eye stops seeing an edge. A genuinely pale spine scores about 1.0 and
  /// simply is not there.
  static const double _kPaleSpineContrast = 1.25;

  /// The outline a pale spine gets, over its fill.
  ///
  /// 11% black over `#FFFFFF` lands on about `#E3E3E3`. Faint on purpose — it is
  /// standing in for the shadow between two books on a shelf, and a darker line reads
  /// as a drawn border around a rectangle rather than as an edge.
  static const Color _kOutline = Color(0x1C000000);

  /// WCAG 2.x contrast ratio. Duplicated rather than shared with `book_chassis.dart`
  /// because that copy is private and this widget has no other reason to depend on
  /// the chassis.
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The title colour: [titleColor] when the caller resolved one, else whichever of
  /// white and `primaryText` reads better on [resolved].
  ///
  /// Derived rather than hardcoded. This used to be white for any caller-resolved
  /// [fill], which held only while `spineTintFor` darkened every tint until white
  /// could sit on it. Now that a pale cover stays pale, roughly half the library
  /// needs dark ink, so white would be unreadable on it.
  ///
  /// The [opacity] path keeps its own 0.7 threshold, which is the rule this widget
  /// has always used for brand green at three opacities.
  Color _titleColor(BuildContext context, Color resolved) {
    if (titleColor != null) return titleColor!;
    if (fill == null) {
      return opacity > 0.7 ? Colors.white : context.colors.primaryText;
    }
    final dark = context.colors.primaryText;
    return _contrast(resolved, Colors.white) >= _contrast(resolved, dark)
        ? Colors.white
        : dark;
  }

  /// The rotated title, faded at the tail only when it actually overflows.
  ///
  /// Laid out twice: once by a [TextPainter] here to find out whether it fits, and
  /// once by the [Text] below to draw it. That is the cost of the fade being
  /// honest — **a mask applied unconditionally fades a title that fits**, which
  /// reads as the type dissolving for no reason, and it was the first thing the
  /// drawing got wrong. The measurement is cheap (one short string, no cache
  /// misses) and the pile does this for at most a screenful of spines.
  ///
  /// The painter is given the same `maxWidth`, `maxLines` and text scale the [Text]
  /// will get, or it would answer a different question from the one being asked.
  ///
  /// The ramp covers the last [kSpineFadeExtent] of the **box**, not of the last
  /// line, so the rule it expresses is "ink that reaches the tail margin
  /// dissolves".
  ///
  /// On a two-line spine that usually means **both** lines ramp, and the reason is
  /// worth knowing: Korean permits a line break between almost any two characters,
  /// so a wrapped title does *not* break at a space the way English does. In
  /// `7_titles.png`, `누구나 하루 30분 투자로 …` breaks mid-word after `투`, which
  /// puts line 1's ink hard against the tail exactly like line 2's. An earlier
  /// version of this comment claimed the first line "ends short of the ramp and
  /// stays solid" — that was one render's luck with one face's advance widths, not
  /// a property of the text.
  ///
  /// It is left this way on purpose. Where Korean breaks is arbitrary, so a first
  /// line ending at the tail has no more meaning than a last one, and dissolving
  /// both reads as the title running on under the shelf. Masking strictly the final
  /// line needs `computeLineMetrics` and a 2D shader — a `LinearGradient` cannot
  /// ramp in x only within a band of y — which is real machinery for a case that
  /// looks correct without it.
  Widget _title(BuildContext context, Color onFill) {
    final style = AppTextStyles.spine.copyWith(color: onFill);
    final display = spineTitleOf(title);

    // Inside the `RotatedBox` the axes swap, so the room along the title's own
    // baseline is the spine's height less its head and tail.
    final measure = height - kSpinePadHead - kSpinePadTail;
    final maxLines = width >= kSpineTwoLineMinThickness ? 2 : 1;
    final scaler = MediaQuery.textScalerOf(context);

    final painter = TextPainter(
      text: TextSpan(text: display, style: style),
      maxLines: maxLines,
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: measure < 0 ? 0 : measure);
    final overflows =
        painter.didExceedMaxLines || painter.size.width > measure + 0.5;
    painter.dispose();

    final Widget text = Text(
      display,
      maxLines: maxLines,
      softWrap: maxLines > 1,
      // Clip rather than ellipsis: where there is overflow the ramp below is the
      // indication, and where there is none neither fires.
      overflow: TextOverflow.clip,
      style: style,
    );

    if (!overflows) return text;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        // A ramp over the last [kSpineFadeExtent] of the *drawn* box. Guarded
        // because a very short spine can be narrower than the ramp, where an
        // unclamped stop goes negative and the gradient inverts.
        final start = bounds.width <= kSpineFadeExtent
            ? 0.0
            : (bounds.width - kSpineFadeExtent) / bounds.width;
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: [start, 1.0],
          colors: const [Color(0xFF000000), Color(0x00000000)],
        ).createShader(bounds);
      },
      child: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = fill ?? context.colors.brand.withOpacity(opacity);
    final onFill = _titleColor(context, resolved);

    // A pale spine has no silhouette against the sheet behind it. The chassis has the
    // same problem with a pale *cover* and solves it the same way — see `_coverFace`'s
    // `Border.all(colors.hairline)`. Only drawn when it is needed, so an ordinary dark
    // spine gains no outline it did not ask for.
    final needsOutline =
        _contrast(resolved, background ?? context.colors.surface) <
        _kPaleSpineContrast;

    final Widget body = SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: resolved),
            child: Padding(
              padding: const EdgeInsets.only(
                top: kSpinePadHead,
                bottom: kSpinePadTail,
              ),
              // **Centred along the spine.** Head-alignment was tried and is the
              // wrong read: it pins every title to a shared datum, which is what
              // makes the row look like a chart rather than a shelf. The height
              // jitter does not need the type to carry it — the silhouette already
              // does, since the spines are genuinely different heights with arched
              // heads and a common foot. Centring lets each title sit in its own
              // book instead.
              child: Center(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: _title(context, onFill),
                ),
              ),
            ),
          ),
          // Inside the clip, so it follows the curve of an arched head rather
          // than standing a point proud of it.
          if (separator)
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 1,
                height: double.infinity,
                child: ColoredBox(color: const Color(0xFF000000).withAlpha(71)),
              ),
            ),
        ],
      ),
    );

    // Clip first, then stroke the *same* path over the top.
    //
    // **This used to be a `Border.all` inside the clip**, with a comment claiming the
    // clip made it trace the head. It does not, and the difference is the whole bug: a
    // box border's top edge is a straight line at y = 0, while the arch rises to y = 0
    // only at the centre and sits at y = 5 at both corners. So the clip *erased* nearly
    // all of the top edge and kept the sides. A pale book got two vertical hairlines
    // and no head at all, which on a device is a white book with its top dissolved into
    // the sheet — reported from a screenshot, invisible in every measurement.
    //
    // A foreground painter also gets the layering right for free. Inside the Stack the
    // outline was competing with the separator for the same right-hand pixel column.
    final Widget shape = arch
        ? ClipPath(clipper: _BookShapeClipper(), child: body)
        : body;

    final Widget outlined = needsOutline
        ? CustomPaint(
            foregroundPainter: BookSpineOutlinePainter(
              colour: _kOutline,
              arch: arch,
            ),
            child: shape,
          )
        : shape;

    final Widget spine = SizedBox(
      width: width,
      height: complimented ? height + 13 : height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(bottom: complimented ? 13 : null, child: outlined),
        ],
      ),
    );

    return onTap == null ? spine : GestureDetector(onTap: onTap, child: spine);
  }
}

/// The book silhouette: a rectangle with a 5pt arched head.
///
/// Shared by [_BookShapeClipper] and [_BookOutlinePainter] rather than written twice,
/// because the outline's only job is to trace the clip exactly. Two copies of these
/// four instructions is how they drift apart.
///
/// [inset] pulls the path in by half a stroke width. A stroke is centred on its path,
/// so tracing the clip boundary itself would put half the line outside the shape, where
/// it renders as a soft fringe on a colour that is not the book's.
Path bookSpinePath(Size size, {double inset = 0}) {
  final l = inset, r = size.width - inset, b = size.height - inset;
  return Path()
    ..moveTo(l, 5 + inset)
    ..quadraticBezierTo(size.width / 2, inset, r, 5 + inset)
    ..lineTo(r, b)
    ..lineTo(l, b)
    ..close();
}

/// Strokes the book silhouette, arch included.
///
/// Used as a `foregroundPainter`, so it draws over the fill and is not subject to the
/// `ClipPath` beneath it — which is exactly why the head survives here and did not
/// survive as a clipped `Border`.
///
/// Public only so that `test/book_vertical_outline_test.dart` can ask whether a spine
/// was given an outline without matching on a private type's name. That question is
/// tree-shaped — an outline on a dark fill is invisible in pixels either way — and a
/// string comparison would have let a rename turn the negative case into a test that
/// passes for the wrong reason.
class BookSpineOutlinePainter extends CustomPainter {
  final Color colour;

  /// Whether the head is arched; see [BookVertical.arch].
  final bool arch;

  const BookSpineOutlinePainter({required this.colour, required this.arch});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(
      arch
          ? bookSpinePath(size, inset: 0.5)
          // No arch means this is a face of a `BookChassis`, where the head is square
          // because the cover beside it is full height. See [BookVertical.arch].
          : (Path()..addRect(
              Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
            )),
      paint,
    );
  }

  @override
  bool shouldRepaint(BookSpineOutlinePainter old) =>
      old.colour != colour || old.arch != arch;
}

class _BookShapeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => bookSpinePath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
