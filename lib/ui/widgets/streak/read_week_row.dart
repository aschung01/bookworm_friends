import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';

/// How tall a day cell is.
///
/// The record's `.lweek s` is `height: 34px` with `flex: 1`, so a cell is **wider than it
/// is tall** — which is the first thing a square cell gets wrong. Seven squares at the
/// content width leave a third of the row as gap and the strip reads as seven checkboxes;
/// seven cells that share the width read as a card's worth of days.
const double kReadWeekCellHeight = 34;

/// The gap between one day cell and the next. The record's `.lweek { gap: 6px }`.
const double kReadWeekGap = 6;

/// The corner the stamped and dashed cells are cut to. `border-radius: 4px`.
const double _kCellRadius = 4;

/// The weight of a drawn cell edge. `1.5px`, in both the solid and the dashed case.
const double _kEdgeWidth = 1.5;

/// The ink a week row is drawn in, by role.
///
/// **Seven roles rather than the `(mark, ink)` pair this started as, because the row has
/// four states and they do not share a colour.** The pair could only express "stamped, in
/// some colour" and "not stamped, in some ink", so every unstamped day came out as a
/// visible box and the row lost the thing that makes the record's version read as a
/// stamp card: a day that was missed **has no box at all**, only a baseline rule under a
/// pale letter. Rolling that back into two colours is how the divergence happened the
/// first time.
///
/// It is passed rather than read from the theme because the celebration paints its own
/// cream ground, where `context.colors` hands back white type in dark mode and the whole
/// row would vanish. See [page] and [candle].
@immutable
class ReadWeekPalette {
  /// The wash inside a stamped day. `rgba(9, 188, 138, 0.1)` — [AppColors.brand] at a
  /// tenth, **not** `brandFill`: the fill is the vivid green, the edge is the dark one.
  final Color stampFill;

  /// The edge around a stamped day. `rgba(6, 118, 87, 0.75)`.
  final Color stampEdge;

  /// The letter inside a stamped day. Full `brandText`, bold — a stamped day is the only
  /// thing in the row drawn in the brand colour, which is what makes a run countable
  /// without reading it.
  final Color stampInk;

  /// The dashed edge around today, before it is recorded. `rgba(6, 118, 87, 0.6)`.
  final Color todayEdge;

  /// The letter inside today, before it is recorded. Muted, not brand: an empty slot is
  /// not an achievement and must not be drawn as one.
  final Color todayInk;

  /// The letter on a day that was missed. Paler than [todayInk] — `#cfc6ae` against
  /// `#a0987e` in the record — because a gap should be quiet.
  final Color missInk;

  /// The hairline under a day with no box. The only mark a missed day gets.
  final Color rule;

  /// The fill of the cell that has just been stamped, in the celebration's closing beat.
  /// Solid, not a wash: `.lweek s.fresh` inverts.
  final Color freshFill;

  /// The letter inside that cell, which has to read on [freshFill].
  final Color freshInk;

  const ReadWeekPalette({
    required this.stampFill,
    required this.stampEdge,
    required this.stampInk,
    required this.todayEdge,
    required this.todayInk,
    required this.missInk,
    required this.rule,
    required this.freshFill,
    required this.freshInk,
  });

  /// The row as the streak page draws it: the app's own ink on the app's own paper.
  ///
  /// The alphas are the record's (`docs/mockups/streaks/index.html`, `.lweek`) and the
  /// hues are the theme's, so this survives a palette change where copied hexes would
  /// not. The record's four paper greys map onto the two neutral tokens the app actually
  /// owns: `#e7dfcc` is a divider, `#a0987e` is secondary ink, and `#cfc6ae` is that ink
  /// turned down — the aged-paper values belong to the Library Card's surface, not to a
  /// page that is `pageBackground`.
  factory ReadWeekPalette.page(BuildContext context) {
    final colors = context.colors;
    return ReadWeekPalette(
      stampFill: colors.brand.withValues(alpha: 0.1),
      stampEdge: colors.brandText.withValues(alpha: 0.75),
      stampInk: colors.brandText,
      todayEdge: colors.brandText.withValues(alpha: 0.6),
      todayInk: colors.secondaryText,
      missInk: colors.secondaryText.withValues(alpha: 0.55),
      rule: colors.divider,
      freshFill: colors.brandFill,
      freshInk: colors.surface,
    );
  }

  /// The row as the celebration draws it: candlelight on cream.
  ///
  /// Not the theme's greens — this screen's ground is [kCandleGlow] and the one accent on
  /// it is [kCandleFlame], so a green row would be the only chrome-coloured object on a
  /// screen that deliberately refuses the brand colour. The fill is heavier than the
  /// page's tenth because flame-on-cream at a tenth is nothing at all: two warm colours
  /// a few steps apart need more than two similar greens do.
  static final ReadWeekPalette candle = ReadWeekPalette(
    stampFill: kCandleFlame.withValues(alpha: 0.28),
    stampEdge: kCandleFlame,
    stampInk: kCandleStockTop,
    todayEdge: kCandleFlame.withValues(alpha: 0.6),
    todayInk: kCandleStockTop.withValues(alpha: 0.7),
    missInk: kCandleStockTop.withValues(alpha: 0.4),
    rule: kCandleStockTop.withValues(alpha: 0.15),
    freshFill: kCandleFlame,
    // **Not the cream ground, which is what this had first and it failed by eye.** The
    // record inverts to `#fff` on `brandText`, a dark green — white on dark is the whole
    // trick. [kCandleFlame] is a mid amber, so cream on it is barely a letter. The dark
    // brown reads, and the inversion still lands: what separates this cell from its six
    // neighbours is that its fill is *solid* where theirs are a wash, plus the shadow and
    // the overshoot. The letter was never carrying that.
    freshInk: kCandleStockTop,
  );
}

/// The seven days ending on a given one, stamped or not.
///
/// **One renderer for two surfaces, which is why it takes its palette rather than reading
/// the theme.** The streak page draws this week in the app's own ink on paper; the
/// celebration draws it on a cream candle-lit ground where `context.colors` would hand back
/// white type in dark mode and the row would vanish. Two copies of this widget is how the
/// week the reader sees behind a celebration and the week inside it would come to disagree
/// about which days are in.
///
/// **A week beside a month is not a duplicate.** The month is the record — scannable, and
/// the receipt that lets the celebration be brief. The week is the *run in progress*: seven
/// cells is the span a reader can count without reading, which is what makes a gap on
/// Thursday legible as a gap rather than as a pale square in a grid of thirty.
///
/// **Four states, three of which are not a box.** The record's `.lweek` draws an outline
/// only where something happened or is about to: a stamped day gets a solid edge over a
/// wash, today-before-you-read gets the same edge **dashed** — the affordance, since the
/// tap is what stamps it — and a missed day gets no box whatsoever, just a hairline under a
/// pale letter. Drawing a box on all seven, which is what this widget did first, makes the
/// strip read as a row of empty checkboxes and throws away the one signal that says *this
/// one is waiting for you*.
class ReadWeekRow extends StatelessWidget {
  /// Whether each of the seven days was recorded, **oldest first**.
  final List<bool> days;

  /// The day the last cell is, so the weekday letters can be right.
  final DateTime endingOn;

  /// The ink, by role.
  final ReadWeekPalette palette;

  /// Whether stamped cells are raked over.
  ///
  /// On, on the page: the same hand-stamped gesture the month grid uses, so a week and a
  /// month read as the same object at two spans. **Off in the celebration**, where exactly
  /// one cell is allowed to arrive tilted — today's, as the last beat — and six already
  /// tilted neighbours would bury it.
  final bool tilt;

  /// Draws the last cell inverted: solid fill, reversed-out letter.
  ///
  /// `.lweek s.fresh` — the day that just inked in, so the eye has one thing to land on
  /// when the celebration settles. A separate state rather than a brighter stamp because
  /// it has to win against six neighbours that are already the brand colour.
  final bool freshLast;

  /// Wraps the final cell, for the celebration's closing beat.
  ///
  /// A hook rather than a flag because the animation belongs to the screen that owns the
  /// clock, and this widget owns no controller.
  final Widget Function(Widget cell)? decorateLast;

  const ReadWeekRow({
    super.key,
    required this.days,
    required this.endingOn,
    required this.palette,
    this.tilt = true,
    this.freshLast = false,
    this.decorateLast,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;

    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: kReadWeekGap),
          // `flex: 1`, so the seven share whatever width the caller has rather than
          // leaving a third of the row as gap — which is what a fixed square cell did.
          Expanded(
            child: Builder(
              builder: (context) {
                final date = DateTime(
                  endingOn.year,
                  endingOn.month,
                  endingOn.day - (days.length - 1 - i),
                );
                final isLast = i == days.length - 1;
                final cell = _Cell(
                  letter: narrow[date.weekday % 7],
                  state: days[i]
                      ? (isLast && freshLast
                            ? _DayState.fresh
                            : _DayState.stamped)
                      : (isLast ? _DayState.today : _DayState.missed),
                  palette: palette,
                  // Derived from the day, and by the month grid's own rule — not from the
                  // cell's position in the row, which would re-rake the whole week every
                  // midnight as the days shuffled left.
                  tilt: tilt && days[i] ? ((date.day * 7) % 9) - 4 : 0,
                  today: isLast,
                );
                return isLast && decorateLast != null
                    ? decorateLast!(cell)
                    : cell;
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// What a cell has to say about its day.
enum _DayState {
  /// Read, on a day that is not tonight.
  stamped,

  /// Read, tonight, in the celebration's closing beat.
  fresh,

  /// Tonight, not read yet. The only cell that invites a tap.
  today,

  /// A day that went by unread. Not red, not an X, and not a box.
  missed,
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.letter,
    required this.state,
    required this.palette,
    required this.tilt,
    required this.today,
  });

  final String letter;
  final _DayState state;
  final ReadWeekPalette palette;
  final double tilt;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final letterInk = switch (state) {
      _DayState.stamped => palette.stampInk,
      _DayState.fresh => palette.freshInk,
      _DayState.today => palette.todayInk,
      _DayState.missed => palette.missInk,
    };

    final label = Text(
      letter,
      // **One style, four colours.** The record's `.lweek s.on` is bold where a missed day is
      // not, and that difference is deliberately dropped: `caption` is the scale's stat
      // label, `AppTextStyles`' own rule is that a call site may `copyWith` colour and never
      // weight (`test/text_style_test.dart` enforces it), and the colour gap between
      // `stampInk` and `missInk` already carries the distinction — with the box doing the
      // rest.
      style: AppTextStyles.caption.copyWith(color: letterInk),
    );

    Widget cell = switch (state) {
      _DayState.stamped => _boxed(
        child: label,
        fill: palette.stampFill,
        edge: palette.stampEdge,
      ),
      // Inverted, and lifted off the card by its own shadow — the record's
      // `box-shadow: 0 2px 6px`, in the fill's own hue so it reads as the cell casting it.
      _DayState.fresh => _boxed(
        child: label,
        fill: palette.freshFill,
        edge: palette.freshFill,
        shadow: [
          BoxShadow(
            color: palette.freshFill.withValues(alpha: 0.4),
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      // The one cell drawn as an outline with nothing in it: the tap is what fills it.
      _DayState.today => SizedBox(
        key: const ValueKey('streak-week-dashed'),
        height: kReadWeekCellHeight,
        child: CustomPaint(
          painter: _DashedCellBorder(color: palette.todayEdge),
          child: Center(child: label),
        ),
      ),
      // **No box at all.** Only the baseline the whole row shares, so the seven cells sit
      // on one line and the stamped ones rise off it.
      _DayState.missed => Container(
        height: kReadWeekCellHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.rule)),
        ),
        child: label,
      ),
    };

    if (today) {
      cell = KeyedSubtree(
        key: const ValueKey('streak-week-today'),
        child: cell,
      );
    }
    if (tilt == 0) return cell;
    return Transform.rotate(angle: tilt * math.pi / 180, child: cell);
  }

  Widget _boxed({
    required Widget child,
    required Color fill,
    required Color edge,
    List<BoxShadow>? shadow,
  }) {
    return Container(
      height: kReadWeekCellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: edge, width: _kEdgeWidth),
        borderRadius: BorderRadius.circular(_kCellRadius),
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}

/// Today's dashed outline.
///
/// **Hand-stroked, because Flutter's [Border] has no dash and the shape is a rounded
/// rectangle.** `shareable_library_card.dart` already dashes a line by stepping along x,
/// which works for a straight run and cannot turn a corner: stepping in x around a corner
/// puts a dash's worth of ink across the radius. Walking [Path.computeMetrics] instead
/// measures along the outline itself, so the dashes stay the same length through the
/// curves — which is the whole reason CSS's `dashed` looks right and a four-line
/// approximation does not.
class _DashedCellBorder extends CustomPainter {
  const _DashedCellBorder({required this.color});

  final Color color;

  /// Roughly twice the stroke on, a hair under twice it off — which is what a browser
  /// draws for `dashed` at this weight, and dense enough that a 34pt cell reads as an
  /// outline rather than as four ticks.
  static const double _dash = 3;
  static const double _gap = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    // Inset by half the stroke, so the dashes land inside the cell the way a CSS border
    // does instead of straddling its edge and clipping.
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(_kCellRadius),
        ).deflate(_kEdgeWidth / 2),
      );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kEdgeWidth;

    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = math.min(start + _dash, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCellBorder old) => old.color != color;
}
