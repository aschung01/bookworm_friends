import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';

/// How big the stamp on a day is.
///
/// **Formerly `kReadWeekCellHeight`, and the rename is the redesign in one line.** A cell
/// used to *be* the box: a full-width rectangle with the weekday letter inside it, so its
/// height was the row's height. Now a cell is a label with a fixed-size token under it, and
/// 34 describes only the token — the cell is as wide as the seven share and as tall as
/// `label + [kReadWeekLabelGap] + 34`. Keeping the old name would have made the one constant
/// the row is measured by mean two different things across one commit.
const double kReadWeekTokenSize = 34;

/// The gap between one day and the next.
const double kReadWeekGap = 6;

/// The gap between a day's label and its token.
const double kReadWeekLabelGap = 6;

/// The corner a token is cut to.
///
/// **A rounded square, not a circle, and that is the whole reason option E was chosen over
/// the four circular candidates.** A raked disc is a no-op — rotating a circle changes
/// nothing — so a circular token silently drops the hand-stamped gesture the week shares
/// with [ReadCalendarMonth] and the Library Card's own stamps. 10 of 34 is round enough to
/// read as a token rather than as a checkbox and square enough for the tilt to register.
const double _kTokenRadius = 10;

/// The weight of the dashed ring around an unrecorded today.
///
/// 2, up from the 1.5 the old boxed cell used. The ring is now the *only* mark on that
/// token — there is no fill behind it and no letter inside it — so it has to carry the
/// affordance alone.
const double _kTodayEdgeWidth = 2;

/// The ink a week row is drawn in, by role.
///
/// **Six roles, down from nine, because the token now says what happened and the label only
/// says which day you are looking at.** The nine existed to describe a row where every state
/// was a different *letter* treatment inside a different *box* treatment — `stampFill` under
/// `stampEdge` with `stampInk` on it, a dashed `todayEdge` with `todayInk`, a `rule` hairline
/// with `missInk`, and an inverted `freshFill`/`freshInk` pair on top of all that. Splitting
/// one mark across two channels is what made the row read as a spreadsheet: seven letters,
/// each in its own slightly different frame, none of them countable at a glance.
///
/// The redesign moves the state entirely into the token — solid and marked, flat and empty,
/// or an open dashed ring — which collapses three letter colours into one. What is left is a
/// label colour and the one exception the label still earns: **today**, which is marked on
/// the *label* rather than the token, because the token has to stay free to say whether the
/// day was read. That is Duolingo's division and it is the reason their row is legible at a
/// glance where ours was a legend to be read.
///
/// It is passed rather than read from the theme because the celebration paints its own
/// ground, where `context.colors` hands back white type in dark mode and the whole row would
/// vanish. See [page] and [candle].
@immutable
class ReadWeekPalette {
  /// The fill of a token on a day that was read. **Solid**, where this used to be a 10%
  /// wash inside a firmer edge. A wash plus an edge is two weak signals; one filled shape
  /// is a mark, and a run of them is countable without being read.
  final Color stampFill;

  /// The check drawn inside [stampFill]. Reversed out, so it must read on it — which is a
  /// contract the fill has to honour rather than something this can fix.
  final Color stampMark;

  /// The fill of a token on any day that was not read. **New**, and the single treatment
  /// that replaces the old row's three: a dashed box, a hairline with no box, and nothing
  /// at all. Three ways to say "not read" is three things to learn; one flat token is a
  /// slot, and an empty slot needs no explaining.
  final Color emptyFill;

  /// The dashed ring around today, before it is recorded. The tap affordance, and the only
  /// token drawn as an outline with nothing inside it — the tap is what fills it.
  final Color todayEdge;

  /// Every weekday label except today's.
  ///
  /// One colour for all six, read or not. The old row gave a stamped day's letter the brand
  /// colour and a missed day's a pale grey, which encoded the same fact the box already
  /// carried and made the strip a gradient of half-states.
  final Color label;

  /// Today's weekday label. The one place the row still says *where you are* rather than
  /// *what happened*.
  final Color labelToday;

  const ReadWeekPalette({
    required this.stampFill,
    required this.stampMark,
    required this.emptyFill,
    required this.todayEdge,
    required this.label,
    required this.labelToday,
  });

  /// The row as the streak page draws it: the app's own ink on the app's own paper.
  ///
  /// **The warm roles are [kCandleFlame], and that is two reversals deep.** A read day
  /// shipped as the brand green, on the reasoning that green is how the app marks its own
  /// things. It went to `colors.flame` #B54708 for the reason `ReadCalendarMonth`'s
  /// today-rule already abandoned green — *the run is what this page is about, and the flame
  /// above is the run* — and then to the candle's own #F2A93F on instruction, because
  /// #B54708 read as reddish beside the celebration's amber and the two screens are one
  /// feature.
  ///
  /// **The candle constant itself rather than a theme token equal to it**, which is the one
  /// place this file reaches into the Library Card's palette on purpose. Two names holding the
  /// same hex is precisely how the page and the celebration would come to differ again, and
  /// the instruction was that they must not. It costs the theme-awareness `colors.flame`
  /// gave: this amber is the same in dark mode, where it sits on `#121212` and is if anything
  /// better than it is on paper.
  ///
  /// **What it costs, measured, because every value here got worse.** White on #F2A93F is
  /// **2.00:1** — the same trade the celebration makes and the same order as Duolingo's own
  /// white-on-#FF9600 at 2.18:1 — where white on `colors.flame` was 5.4:1 and on `brandFill`
  /// 5.6:1. And [labelToday], the one piece of *type* in the set, is **1.76:1** on
  /// `pageBackground` #F8F9FA, which is the worst value on the page: worse than the
  /// celebration's 2.00:1, because cream-white paper is darker than white. It is kept anyway
  /// on the same grounds the celebration keeps it — the label is an orientation cue that
  /// position already carries, since today is always the last cell — but it is the value to
  /// revisit first if anyone asks why this row is hard to read. `colors.flame` there would be
  /// 5.2:1 and would put a second orange on one row.
  ///
  /// **The rest of the feature has since followed, so there is no second orange left to put.**
  /// `ReadCalendarMonth`'s today rule and numeral and `ReadingStreakChip`'s mark and numeral
  /// are both on this constant too, and `colors.flame` has no reader in `lib/` at all. The
  /// trade above is therefore the feature's trade rather than this row's;
  /// `reading_streak_chip.dart` carries the full measurement — and carries more of it than it
  /// used to, since that chip has lost the fill and border it was leaning on. This said "whole
  /// capsule" while there was a capsule.
  ///
  /// [stampMark] is **`Colors.white`, not `colors.surface`, and that is a bug fix.** The
  /// reversed-out ink used to be `surface`, which is white in light mode and `#1E1E1E` in
  /// dark — so in dark mode the mark sat on a dark fill at about 1.4:1 and the stamped day
  /// was a blank token. Whatever the fill is, it is an accent chosen to carry white, so the
  /// mark on it cannot be theme-dependent.
  ///
  /// [emptyFill] is `surfaceVariant` rather than `divider`, though the two are the same
  /// hex in light mode. `divider` is for hairlines; `surfaceVariant` is the token for
  /// "subtle filled areas: chips, avatars, input fills", which is what an empty slot is.
  /// Naming the right one matters in dark mode, where they differ.
  factory ReadWeekPalette.page(BuildContext context) {
    final colors = context.colors;
    return ReadWeekPalette(
      stampFill: kCandleFlame,
      stampMark: Colors.white,
      emptyFill: colors.surfaceVariant,
      // The ring, the filled token and today's label are one colour — the distinction is
      // filled against outline and small against large, not hue. Three warm variants for
      // three states is what the nine-role palette did, and it read as a legend.
      todayEdge: kCandleFlame,
      label: colors.secondaryText,
      labelToday: kCandleFlame,
    );
  }

  /// The row as the celebration draws it: the candle family's warm inks, on white.
  ///
  /// Not the theme's greens — this screen's one accent is [kCandleFlame], so a green row
  /// would be the only chrome-coloured object on a screen that deliberately refuses the
  /// brand colour.
  ///
  /// **[stampMark] is white on a mid amber, which measures 2.00:1 and is a deliberate
  /// trade.** Duolingo's own white-on-`#FF9600` is 2.18:1, so this is the same trade at the
  /// same magnitude rather than a worse one, and the alternative was measured and is worse:
  /// darkening the amber until a white mark clears 3:1 lands on `#BF8632`, an ochre —
  /// **saturation runs out before lightness does**, so there is no compliant version of
  /// "the flame's colour". The mark is a 3px tick, not type, and the token's *shape* and
  /// fill already carry the state; see `docs/mockups/streak-week/index.html`, `el-read`.
  ///
  /// **[label] is stock at 0.75, where the mockup drew 0.55.** 0.55 composites to `#8880 78`
  /// on white and measures **3.87:1** — under AA for an 11pt label. 0.75 measures **7.41:1**
  /// and is still visibly quieter than the near-black the old `stampInk` used. The mockup is
  /// a sketch in a browser; it was not a contrast decision, and this is.
  ///
  /// [labelToday] is the flame itself at **2.00:1**, which is the one value here that is
  /// knowingly out of compliance and is the same trade the 64pt counter above it already
  /// makes on this screen. It is an orientation cue duplicated by position — today is always
  /// the last cell — not a piece of information only colour carries.
  static final ReadWeekPalette candle = ReadWeekPalette(
    stampFill: kCandleFlame,
    stampMark: Colors.white,
    emptyFill: kCandleStockTop.withValues(alpha: 0.12),
    todayEdge: kCandleFlame,
    label: kCandleStockTop.withValues(alpha: 0.75),
    labelToday: kCandleFlame,
  );
}

/// The seven days ending on a given one, stamped or not.
///
/// **One renderer for two surfaces, which is why it takes its palette rather than reading
/// the theme.** The streak page draws this week in the app's own ink on paper; the
/// celebration draws it in candlelight on white, where `context.colors` would hand back
/// white type in dark mode and the row would vanish. Two copies of this widget is how the
/// week the reader sees behind a celebration and the week inside it would come to disagree
/// about which days are in.
///
/// **A week beside a month is not a duplicate.** The month is the record — scannable, and
/// the receipt that lets the celebration be brief. The week is the *run in progress*: seven
/// cells is the span a reader can count without reading, which is what makes a gap on
/// Thursday legible as a gap rather than as a pale square in a grid of thirty.
///
/// **Label above, token below — and this is a rebuild, not a restyle.** The row shipped
/// twice before this. First as seven identical boxes with a letter in each, which reads as
/// seven empty checkboxes. Then as four different *letter-in-a-box* treatments: a wash
/// inside a firm edge, that edge dashed, no box at all under a pale letter, and an inverted
/// solid. That second version was correct about drawing a box only where something happened
/// — and still wrong, because it made the letter do two jobs at once. The letter has to say
/// *which day* (it is the only thing that can) and the box had to say *what happened*, so
/// every day was a compound of two variables and the strip could only be read one cell at a
/// time.
///
/// Duolingo's row separates them: the label sits above as a plain header, and the thing
/// below it is a **mark**, not a letter — filled and checked, or flat and empty. Seven marks
/// in a line is a count. Seven letters in seven frames is a table. That separation is the
/// whole of option E, and it is why the check is drawn rather than typed.
///
/// **What E keeps that Duolingo does not have: the token is a rounded square.** Four of the
/// five candidates drawn used a circle, and a circle cannot be raked — a rotated disc is
/// identical to an unrotated one — so those four quietly gave up the hand-stamped tilt the
/// week shares with the month grid and the Library Card. See [_kTokenRadius].
class ReadWeekRow extends StatelessWidget {
  /// Whether each of the seven days was recorded, **oldest first**.
  final List<bool> days;

  /// The day the last cell is, so the weekday letters can be right.
  final DateTime endingOn;

  /// The ink, by role.
  final ReadWeekPalette palette;

  /// Whether stamped tokens are raked over.
  ///
  /// On, on the page: the same hand-stamped gesture the month grid uses, so a week and a
  /// month read as the same object at two spans. **Off in the celebration**, where exactly
  /// one token is allowed to arrive tilted — today's, as the last beat — and six already
  /// tilted neighbours would bury it.
  final bool tilt;

  /// Lifts the last token off the card, for the celebration's closing beat.
  ///
  /// **This used to invert it, and inversion is no longer a thing a token can do.** The old
  /// cell was a 10% wash inside an edge, so "solid fill, reversed-out letter" was a real
  /// escalation away from its six neighbours. Now every read day is *already* solid and
  /// already carries a reversed-out mark — there is nothing left to invert *to*. What
  /// separates the closing cell from the six is the shadow this adds, plus the scale
  /// overshoot and the tilt the caller wraps it in through [decorateLast]. Kept as a flag
  /// rather than folded into that wrapper because a shadow belongs to the token's own
  /// decoration and a `Transform` outside it cannot add one.
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
    // **Narrow single characters, deliberately, where Duolingo sets two.** Under `en` this
    // gives S M T W T F S — two S's and two T's — and two letters would remove that
    // collision. It is not taken, for three reasons. The row is a *rolling* seven days that
    // always ends on today, so the sequence itself says which day each cell is and the
    // letter is confirmation rather than the only cue. `ReadCalendarMonth`'s header sits a
    // few hundred pixels below this on the same page and is `narrowWeekdays` too, so two
    // letters here would put two different weekday alphabets on one screen. And the fix is
    // English-only — Korean narrow weekdays are already unambiguous single characters
    // (일 월 화 수 목 금 토) — so a blanket `substring(0, 2)` would be wrong and a per-locale
    // rule is more machinery than the collision costs. Reversible: it is one line, and
    // `DateFormat.E` would need `AppLocalizations.localizationsDelegates` wired into every
    // harness that pumps this row or it throws `UninitializedLocaleData`.
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;

    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: kReadWeekGap),
          // `flex: 1`, so the seven share whatever width the caller has. The *token* is a
          // fixed 34 and sits centred in that share — which is the arrangement that lets a
          // token be square without leaving a third of the row as gap, the trap the first
          // fixed-square version fell into.
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

/// What a token has to say about its day.
enum _DayState {
  /// Read, on a day that is not tonight.
  stamped,

  /// Read, tonight, in the celebration's closing beat.
  fresh,

  /// Tonight, not read yet. The only token that invites a tap.
  today,

  /// A day that went by unread. Not red, not an X — just an empty slot.
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
    Widget token = switch (state) {
      // Solid and checked. The `fresh` case is the same token plus a shadow in the fill's
      // own hue, so it reads as the token casting it rather than as a different colour.
      _DayState.stamped || _DayState.fresh => _token(
        fill: palette.stampFill,
        mark: palette.stampMark,
        shadow: state == _DayState.fresh
            ? [
                BoxShadow(
                  color: palette.stampFill.withValues(alpha: 0.4),
                  offset: const Offset(0, 2),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
      // The one token drawn as an outline with nothing in it: the tap is what fills it.
      // No `emptyFill` behind the ring — a ring over a slot is two marks for one state.
      _DayState.today => SizedBox(
        key: const ValueKey('streak-week-dashed'),
        width: kReadWeekTokenSize,
        height: kReadWeekTokenSize,
        child: CustomPaint(
          painter: _DashedTokenBorder(color: palette.todayEdge),
        ),
      ),
      // An empty slot, and the same empty slot every unread day gets.
      _DayState.missed => _token(fill: palette.emptyFill),
    };

    // **The rake wraps the token and never the label.** A tilted header reads as a layout
    // fault, and the gesture is about the mark having been *pressed on* — a weekday name has
    // not been pressed on anything. `ReadWeekRow` only ever passes a non-zero tilt for a day
    // that was read, so nothing unstamped can arrive crooked.
    if (tilt != 0) {
      token = Transform.rotate(angle: tilt * math.pi / 180, child: token);
    }

    Widget cell = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          letter,
          // `caption` is the scale's stat-label slot and is already 11pt at w700, which is
          // the weight this wants. One style, two colours: `AppTextStyles`' own rule is that
          // a call site may `copyWith` colour and never size or weight, and
          // `test/text_style_test.dart` enforces it.
          style: AppTextStyles.caption.copyWith(
            color: today ? palette.labelToday : palette.label,
          ),
        ),
        const SizedBox(height: kReadWeekLabelGap),
        token,
      ],
    );

    if (today) {
      cell = KeyedSubtree(
        key: const ValueKey('streak-week-today'),
        child: cell,
      );
    }
    return cell;
  }

  Widget _token({required Color fill, Color? mark, List<BoxShadow>? shadow}) {
    return Container(
      width: kReadWeekTokenSize,
      height: kReadWeekTokenSize,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(_kTokenRadius),
        boxShadow: shadow,
      ),
      child: mark == null
          ? null
          : CustomPaint(painter: _CheckMark(color: mark)),
    );
  }
}

/// The check inside a stamped token.
///
/// **Drawn, not typed.** `Icons.check_rounded` renders as a hollow box in a widget test —
/// MaterialIcons is not loaded in the test shell — so an icon here would make every golden
/// and every pixel assertion on this row a lie. A three-point path is also the only way to
/// pin the mark's geometry to the token's size rather than to a font's metrics.
class _CheckMark extends CustomPainter {
  const _CheckMark({required this.color});

  final Color color;

  /// The tick, as fractions of the token's side, so it scales with [kReadWeekTokenSize]
  /// instead of being a set of magic pixels that silently stop fitting.
  static const List<Offset> _points = [
    Offset(0.27, 0.52),
    Offset(0.43, 0.68),
    Offset(0.74, 0.35),
  ];

  /// Stroke weight, likewise as a fraction of the side. 0.11 is 3.74 at 34 — heavy enough
  /// that the mark survives being the only signal separating a read token from an empty one
  /// (they differ by hue, and by only **1.56:1** in luminance).
  static const double _weight = 0.11;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final path = Path()..moveTo(_points[0].dx * side, _points[0].dy * side);
    for (final p in _points.skip(1)) {
      path.lineTo(p.dx * side, p.dy * side);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _weight * side
        // Round on both, which is what makes it a Duolingo tick rather than a spreadsheet
        // one: the elbow is the only place a check shows its weight.
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckMark old) => old.color != color;
}

/// Today's dashed ring.
///
/// **Hand-stroked, because Flutter's [Border] has no dash and the shape is a rounded
/// rectangle.** `shareable_library_card.dart` already dashes a line by stepping along x,
/// which works for a straight run and cannot turn a corner: stepping in x around a corner
/// puts a dash's worth of ink across the radius. Walking [Path.computeMetrics] instead
/// measures along the outline itself, so the dashes stay the same length through the
/// curves — which is the whole reason CSS's `dashed` looks right and a four-line
/// approximation does not.
class _DashedTokenBorder extends CustomPainter {
  const _DashedTokenBorder({required this.color});

  final Color color;

  /// Twice the stroke on, one and a half off — the ratio a browser draws for `dashed` at
  /// 2px. **Both went up with the stroke**: the old pair was 3 and 2.5 against a 1.5px
  /// edge, and at 2px a 3px dash is barely longer than it is wide and reads as a dotted
  /// line rather than a dashed one.
  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    // Inset by half the stroke, so the dashes land inside the token the way a CSS border
    // does instead of straddling its edge and clipping.
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(_kTokenRadius),
        ).deflate(_kTodayEdgeWidth / 2),
      );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kTodayEdgeWidth;

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
  bool shouldRepaint(_DashedTokenBorder old) => old.color != color;
}
