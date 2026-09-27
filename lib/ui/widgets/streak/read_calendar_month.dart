import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';

/// The gap between one day cell and the next, both ways.
///
/// Cells are square and sized from the width the caller gives them — seven of them and
/// six of these share it — so this is the only typed number in the grid's geometry and
/// everything else is derived from it. A cell that was itself a constant would drift
/// the moment the card it sits in changed its padding.
const double kReadCalendarGap = 5;

/// How far a day's stamp is inset from its cell, horizontally and vertically.
///
/// **A point in on all four sides, because the mark is now a round die rather than a
/// block.** The patch this replaced was `left/right: 1px` against `top/bottom: 6px` — a
/// low wide strip, and the asymmetry was the point of it. A ring has no long axis to
/// favour, and cropping it vertically would print an oval, which is a different die
/// (`cp-f-stamp-oval` in the record) rather than this one pressed badly.
const EdgeInsets kReadCalendarStampInset = EdgeInsets.all(1);

/// The ink the die carries: the book's colour at roughly two thirds.
///
/// Higher than the patch's fifth, and it has to be: a patch spent a whole cell of area
/// on the colour, where two hairline bands spend almost none, so at 0.22 a ring is a
/// smudge. The numeral still sits over it in ordinary ink with no shadow, because the
/// bands run *around* the digit rather than under it — which is the property that let
/// the ink go up at all.
const double kReadCalendarStampAlpha = 0.65;

/// How far a day's stamp is raked over, in degrees.
///
/// **Derived from the day, never random, and this is the only definition of the rule.**
/// A random tilt cannot be screenshotted and compared with the last screenshot: the
/// month would reshuffle on every rebuild, so a reviewer could not tell a layout change
/// from a re-roll, and a golden test could not exist at all. Taking it from the day
/// number means the 14th is always raked the same way and the month is stable for as
/// long as it is that month.
///
/// The expression is the design record's (`docs/mockups/streaks/index.html`), which is
/// also the one the Library Card stamps and [ReadWeekRow] use. A second copy of a
/// mannerism is how two surfaces come to disagree about what a hand-stamped day looks
/// like, so callers call this rather than restating the arithmetic.
///
/// Range is ±4°, which is deliberately small. This is a stamp that missed square, not a
/// sticker applied by someone in a hurry; past about 6° a run stops reading as pressed
/// by hand and starts reading as a mistake.
double readCalendarPatchTilt(int day) => ((day * 7) % 9) - 4;

/// One month of the reader's recorded nights, drawn as date stamps.
///
/// **The mark carries the colour, not a band, and the mark is a stamp the reader's own
/// hand would make.** Eighteen weights were drawn before this one
/// (`docs/mockups/streaks/index.html`, groups (f) through (f+++)) and the one that won is
/// `cp-f-stamp-double`: each recorded day gets a **two-band ring** in its book's
/// `cover_color`, raked over by [readCalendarPatchTilt]. A saturated capsule per day is
/// the most information per pixel and also the loudest thing on a page made of paper and
/// hairlines — it needs white numerals with a shadow under them to survive, which is the
/// tell that a fill is doing too much. A ring spends almost no ink and still names the
/// book.
///
/// **A ninth family was drawn after the mascot arrived, and this file now draws one frame
/// out of it.** Group (h) in the same record replaced the die with the streak widget's
/// cat's own paw — eight frames, measured off
/// `docs/mockups/streak-widget/cats/m01-flex.png` rather than drawn generically — and a
/// filled paw normalised to the die's *ink* rather than its *alpha* came out at 1.4:1
/// against the card, which is invisible; the die's own 0.65 is what a paw has to be pressed
/// at instead. Group (i) then mixed that paw with this ring rather than replacing it —
/// the ring keeps doing the one thing it was chosen for, a closed curve around the date
/// with nothing on the numeral, and a small paw is layered on top as an accent. The frame
/// this file draws is `cp-i-stamp-corner-tr45`: the ring **unmodified**, plus the tidy
/// (symmetric-toed) print boxed into the cell's top-right corner and rotated a further
/// 45° on top of [readCalendarPatchTilt]'s own rake. That corner and that angle were one
/// pick off a full sweep of all four corners at every 45° — the working note is
/// `docs/mockups/streaks/gen_paw_sweep.py` — chosen because the pad, not the toes, is what
/// crosses the ring's band there: a big shape crossing a hairline reads as an overlap, and
/// three small ones crossing it read as noise. [ReadCalendarStampDie] is what changes; see
/// its own doc for the paw's construction.
///
/// **Two bands rather than one, and they fail together.** Both rings lose their ink at
/// the *same* angles, because one press made them both — that shared failure is the
/// difference between a drawn seal and two circles, and it is why [_StampDie] hands one
/// nick set to both bands rather than rolling per band. The grammar is deliberately
/// officialdom's: a customs stamp is two bands, a notary's seal is two bands, and this
/// grid is a record.
///
/// **The die is drawn, not composed.** An earlier cut of this mark was a `BoxDecoration`
/// circle, and the objection that killed it is the one this file cannot restate often
/// enough: a perfect circle is a *diagram* of a stamp. So the bands are painted with
/// per-angle wobble, breathing width and pressure nicks — the same construction
/// `docs/mockups/streaks/gen_patch_marks.py` uses for the record's own dies, ported
/// rather than re-invented. Three dies, chosen by `day % 3`, so neighbours differ.
///
/// **There is no run capsule and no connecting thread, on purpose.** Adjacent stamps very
/// nearly touch, and because no two neighbours are raked or nicked the same way the small
/// misalignments *are* the continuity — the way a row of stamps in a passport is. A
/// ligature joining them was drawn and is not here: it says the same thing twice and it
/// puts a hard geometric shape under a deliberately hand-made one.
///
/// **A pure widget.** It resolves no providers, reads no clock and performs no lookups:
/// the caller hands it the month, the marks already keyed by day, and what today is. That
/// is what lets one renderer serve the streak page, a future Library Card month and a
/// golden test without any of the three being able to disagree about the arithmetic.
///
/// **Four states for an unstamped day, not one.** Today gets a rule down its leading edge,
/// a past day that went by gets a hollow dot, a day still to come is dimmed, and a stamped
/// day carries the die. The first two exist because a month that draws "yesterday, and you
/// did not read" the same as "next Tuesday" cannot show the one thing it is for — where the
/// thread broke — without the reader counting cells.
class ReadCalendarMonth extends StatelessWidget {
  /// Any day inside the month to draw. Normalised internally, so passing the 14th and
  /// passing the 1st give the same grid.
  final DateTime month;

  /// The recorded days of this month, and what was read on each.
  ///
  /// Keys must be date-only local midnights — `readingDate`'s own shape — because
  /// `DateTime` equality is equality of instants and a stray time component would make
  /// every lookup miss in silence, drawing an empty month for a reader who has one.
  ///
  /// A null value is a recorded day with no attribution: either the row predates the
  /// `book_id` column or the book has since been deleted. It draws in neutral ink rather
  /// than being dropped, because the night happened and the streak counts it.
  final Map<DateTime, Color?> marks;

  /// What the reader's clock says today is, as a reading date.
  ///
  /// Passed in rather than read here for the reason every other date in this feature is:
  /// the midnight rollover means only the caller knows which day "now" belongs to, and
  /// three widgets reading the clock separately is how they come to disagree across the
  /// boundary.
  final DateTime today;

  const ReadCalendarMonth({
    super.key,
    required this.month,
    required this.marks,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final materialL10n = MaterialLocalizations.of(context);

    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // Which column the 1st falls in, honouring the locale's own week start rather than
    // assuming Sunday. `DateTime.weekday` is 1..7 from Monday; `narrowWeekdays` is
    // indexed from Sunday; `firstDayOfWeekIndex` is in the latter's terms. Reducing
    // everything to the Sunday-indexed space first is what keeps the header labels and
    // the cell offsets from being off by one in exactly one locale.
    final firstWeekdaySunday = first.weekday % 7;
    final weekStart = materialL10n.firstDayOfWeekIndex;
    final lead = (firstWeekdaySunday - weekStart + 7) % 7;

    final headers = [
      for (var i = 0; i < 7; i++)
        materialL10n.narrowWeekdays[(weekStart + i) % 7],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Seven squares and six gaps share the width. Derived, so the grid cannot come
        // to disagree with the box it was given — which is the defect a typed cell size
        // produces the first time a caller changes its padding.
        final cell = (constraints.maxWidth - kReadCalendarGap * 6) / 7;
        final rows = ((lead + daysInMonth) / 7).ceil();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: kReadCalendarGap),
                  SizedBox(
                    width: cell,
                    child: Text(
                      headers[i],
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: kReadCalendarGap),
            Stack(
              children: [
                // **The weekend wash, one box per column behind the whole grid rather than
                // one per cell.** Painted per cell it would sit over the patches and a run
                // would appear to change colour on a Saturday — the record's own note. Its
                // job is to give the month a rhythm to scan against, which is what stops
                // thirty numerals reading as an undifferentiated block.
                //
                // The columns are computed from the locale's week start rather than fixed
                // at 5 and 6: the record's grid is Monday-first, and hardcoding its column
                // indices would wash Friday and Saturday in every Sunday-first locale.
                Positioned.fill(
                  child: Row(
                    // Stretched, or the washes are laid out against a loose height and a
                    // childless `DecoratedBox` collapses to nothing — which is a wash that
                    // is present in the tree and invisible on screen.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 7; i++) ...[
                        if (i > 0) const SizedBox(width: kReadCalendarGap),
                        SizedBox(
                          width: cell,
                          child: _isWeekendColumn(i, weekStart)
                              ? DecoratedBox(
                                  key: ValueKey('streak-weekend-$i'),
                                  decoration: BoxDecoration(
                                    color: colors.secondaryText.withValues(
                                      alpha: 0.05,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var row = 0; row < rows; row++) ...[
                      if (row > 0) const SizedBox(height: kReadCalendarGap),
                      Row(
                        children: [
                          for (var col = 0; col < 7; col++) ...[
                            if (col > 0)
                              const SizedBox(width: kReadCalendarGap),
                            SizedBox(
                              width: cell,
                              height: cell,
                              child: _cellFor(
                                context,
                                dayNumber: row * 7 + col + 1 - lead,
                                daysInMonth: daysInMonth,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Whether the column at [index] holds a Saturday or a Sunday, given the locale's
  /// [weekStart] in `narrowWeekdays`' Sunday-indexed terms.
  static bool _isWeekendColumn(int index, int weekStart) {
    final sundayIndexed = (weekStart + index) % 7;
    return sundayIndexed == 0 || sundayIndexed == 6;
  }

  /// One cell, or nothing where the month has not started or has ended.
  Widget _cellFor(
    BuildContext context, {
    required int dayNumber,
    required int daysInMonth,
  }) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final date = DateTime(month.year, month.month, dayNumber);
    final marked = marks.containsKey(date);
    final todayDate = DateTime(today.year, today.month, today.day);
    final isToday = date == todayDate;
    // A day the reader has not reached yet is not a day they failed to record, so it is
    // drawn fainter than an unrecorded past one. The record's rule: this grid notes a
    // gap, it does not scold.
    final future = date.isAfter(todayDate);
    // **The two states this grid used to draw identically.** A day before today with
    // nothing on it and a day next week were both a plain numeral, so the one thing the
    // month exists to show — where the thread broke — could only be found by counting.
    final gap = !marked && !isToday && !future;

    // Neutral ink for a night with no attribution. Not skipped: the night happened, the
    // streak counts it, and a hole in the month would say it did not.
    final colour = marked ? (marks[date] ?? colors.secondaryText) : null;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (colour != null)
          Padding(
            // A point in on all four sides: two adjacent dies nearly touch without the
            // rake making them overlap, and neither fills its cell corner to corner.
            padding: kReadCalendarStampInset,
            child: Transform.rotate(
              angle: readCalendarPatchTilt(dayNumber) * math.pi / 180,
              child: CustomPaint(
                key: ValueKey('streak-stamp-$dayNumber'),
                // Sized by the cell it was handed, so the die scales with the grid
                // rather than needing a typed diameter that would drift from it.
                size: Size.infinite,
                painter: ReadCalendarStampDie(
                  colour: colour.withValues(alpha: kReadCalendarStampAlpha),
                  day: dayNumber,
                ),
              ),
            ),
          ),
        // Today, before it is recorded: a rule down the leading edge rather than a fill.
        // Duolingo's own grammar, and the reason for it is that today is not an
        // achievement yet and must not be drawn as one.
        //
        // **Warm, not brand green, which is a reversal.** This shipped in `brandFill` on
        // the reasoning that green is how the app marks its own things. But the run is
        // what this page is about, the flame above is the run, and a warm hue is the one
        // thing an all-green palette does not already spend. A green rule also competes
        // with a green stamp on any day whose book has a green jacket, which is the case
        // the record's amber avoids.
        //
        // **And a second reversal on top of it: [kCandleFlame] #F2A93F rather than
        // `colors.flame` #B54708, on instruction.** The theme token is the *readable*
        // orange and this is the *flame's* orange — the amber the Rive artboard, the hero
        // mark and `ReadWeekRow` above this grid are all drawn in. Keeping the rust here
        // put three different accents on one screen (a rust rule under an amber week under
        // an amber flame) and made the month look like it belonged to another page. The
        // cost is light mode's contrast and nothing else: 2.00:1 on `surface` against
        // #B54708's 5.43:1, while dark mode *gains* — 8.35:1 against the token's 7.46:1,
        // since `flame` is already a bright #FF922B there. It lands on the numeral below,
        // which is `label`-sized text; the rule itself is a 2.5pt bar and was never type.
        // `reading_streak_chip.dart` records the same trade in full.
        if (isToday && !marked)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              key: const ValueKey('streak-today-rule'),
              width: 2.5,
              height: double.infinity,
              // Held off the cell's top and bottom by the 6pt the retired patch used,
              // rather than by the die's own 1pt inset. A rule as tall as the stamp's
              // full diameter reads as a divider between columns; today is a mark
              // inside its cell, so it stays visibly shorter than the cell.
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 1),
              decoration: BoxDecoration(
                color: kCandleFlame,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        // A day that went by unrecorded: a hollow dot rather than a cross or a colour.
        // The month is a record, not a report card — but it has to be *readable* as a
        // record, and an unmarked numeral is indistinguishable from next Tuesday's.
        if (gap)
          Align(
            alignment: AlignmentDirectional.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Container(
                key: ValueKey('streak-gap-$dayNumber'),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.divider),
                ),
              ),
            ),
          ),
        Text(
          '$dayNumber',
          // `label` carries tabular figures, which is what stops a column of 1-heavy
          // and 8-heavy dates sitting at different widths down the grid.
          //
          // **The record's `font-weight: 800` on a stamped day is dropped.** `label` is the
          // only token with tabular figures, so varying the weight would mean a literal
          // `fontWeight:` at the call site, which `test/text_style_test.dart` forbids for a
          // good reason. The die around the numeral and the ink it is set in already say
          // which days are in; a heavier numeral was the third signal.
          style: AppTextStyles.label.copyWith(
            color: future
                ? colors.secondaryText.withValues(alpha: 0.45)
                : isToday && !marked
                ? kCandleFlame
                : marked
                ? colors.primaryText
                : colors.secondaryText,
          ),
        ),
      ],
    );
  }
}

/// The two-band date stamp one recorded day carries.
///
/// **Public, deliberately.** It is the one piece of this file a caller outside it has a
/// reason to touch: the doc on [ReadCalendarMonth] promises one renderer can serve the
/// streak page, a future Library Card month and a golden test without the three
/// disagreeing, and a Card that pressed its own die would be exactly that disagreement.
/// Being nameable is also what lets a test assert the ink rather than read a screenshot.
///
/// **Why this is painted rather than decorated.** The first cut of this mark was a
/// `BoxDecoration` with `shape: BoxShape.circle` and two borders, and the objection that
/// killed it in the record is worth keeping in front of whoever edits this next: *a
/// perfect circle is a diagram of a stamp, not a stamp.* What makes a pressed die read as
/// pressed is the failure — a rim that is not quite round, a band whose width breathes,
/// and the places where the pad did not take. None of those are expressible in a
/// `Border`, so the bands are drawn.
///
/// **The construction is the design record's own**, ported from the generator that draws
/// the record's dies (`docs/mockups/streaks/gen_patch_marks.py`, `band()` and
/// `double()`): 72 samples around the rim, a two-term low-frequency wobble on the radius,
/// a width that varies on a third term, and two *pressure nicks* where the band thins to
/// almost nothing. Ported rather than re-derived so the two surfaces cannot come to
/// disagree about what a stamped day looks like — the same rule [readCalendarPatchTilt]
/// exists for.
///
/// **The nicks are shared between the bands.** One press made both rings, so both lose
/// their ink at the same angles; rolling nicks per band would draw two stamps that happen
/// to be concentric, which is what the record's note calls the difference between a drawn
/// seal and two circles.
///
/// **Three dies, chosen by `day % 3`.** Every value comes from a `Random` seeded from
/// that choice, so a die is stable across rebuilds — the same property
/// [readCalendarPatchTilt] protects, and for the same reason: a month that reshuffles on
/// every paint cannot be screenshotted, reviewed or golden-tested. Only three so that
/// neighbours differ; thirty distinct dies would be noise nobody could read as a set.
///
/// The dies are *not* pixel-identical to the record's, and that is not drift: Dart's
/// `Random` and Python's Mersenne sequence differ, so what is shared is the anatomy and
/// the arithmetic, not one particular roll of it.
///
/// **A fourth blob-group, the paw, is layered on top of the ring rather than folded into
/// it.** `cp-i-stamp-corner-tr45` in the record: the two bands above are drawn completely
/// unmodified, then the mascot's own paw — pad and three symmetric toes, ported from
/// `paw_parts(sym: true, box: 34)` in `gen_patch_marks.py` — is pressed into the cell's
/// top-right corner at full strength (`colour` with its alpha put back to 1, since the
/// ring's own 0.65 would make a print this small read as nothing) and rotated a further
/// 45° on top of the day's own tilt. Drawn as its own `Path` and its own `drawPath`, after
/// the ring's: the ring's fill is even-odd so a shape sharing its `Path` would print a
/// hole wherever the paw crosses the band, which is the one place it is meant to.
///
/// **The extra 45° pivots on the paw's own small box, not the cell's centre — and that is
/// an approximation, named rather than hidden.** [readCalendarPatchTilt]'s rotation is
/// applied once, outside this painter, about the whole cell; correct for the ring, which
/// is centred, but the paw's box sits in a corner, and the record's own CSS pivots that
/// box on *itself*. Composing "45° about the paw's box" here with "the day's tilt about
/// the cell" outside is a different operation from one combined rotation about a single
/// point, so across the day's own ±4° range the paw lands a fraction of a unit from where
/// the record's transform would put it. Accepted for the reason two paragraphs up already
/// accepts Dart's `Random` diverging from Python's: the anatomy and the arithmetic are
/// shared, not one exact roll of either.
class ReadCalendarStampDie extends CustomPainter {
  /// The book's colour, already at [kReadCalendarStampAlpha].
  final Color colour;

  /// The day of the month, which chooses the die.
  final int day;

  const ReadCalendarStampDie({required this.colour, required this.day});

  /// The record's viewBox is 40 units across, and every measurement below is in those
  /// units, so the die can be scaled to whatever cell the grid computed without any of
  /// its proportions being re-tuned.
  static const double _box = 40;

  @override
  void paint(Canvas canvas, Size size) {
    // Square and centred: a ring cropped to a non-square box would print an oval, which
    // is a different die in the record (`cp-f-stamp-oval`) rather than this one pressed
    // badly.
    final u = size.shortestSide / _box;
    if (u <= 0) return;
    final centre = Offset(size.width / 2, size.height / 2);

    final rng = math.Random(day % 3);
    // Two nicks, rolled before either band so both can be handed the same set.
    final nicks = [
      rng.nextDouble() * 2 * math.pi,
      rng.nextDouble() * 2 * math.pi,
    ];

    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.fill
      // The bands are hairlines at this size, so without this the rim aliases into a
      // dotted line on the diagonals.
      ..isAntiAlias = true;

    final path = Path()..fillType = PathFillType.evenOdd;
    _band(path, rng, centre, u, radius: 17.6, width: 1.5, nicks: nicks);
    _band(path, rng, centre, u, radius: 14.4, width: 0.8, nicks: nicks);
    canvas.drawPath(path, paint);

    // The paw, drawn after and as its own path: sharing the ring's even-odd `Path`
    // would print a hole wherever the print crosses the band, which is the one place
    // it is meant to. Full strength, not the ring's 0.65 -- `withValues` only ever
    // touches the alpha channel, so this recovers the book's own colour rather than
    // inventing a new one.
    final pawPaint = Paint()
      ..color = colour.withValues(alpha: 1)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(_paw(centre, u, day), pawPaint);
  }

  /// One band, added to [path] as an outer rim and a reversed inner rim.
  ///
  /// Even-odd fill makes the pair a band rather than a disc, which is what lets one
  /// `Path` and one `drawPath` carry both rings — two fills would double the ink where
  /// they overlap, and at these alphas that is visible.
  void _band(
    Path path,
    math.Random rng,
    Offset centre,
    double u, {
    required double radius,
    required double width,
    required List<double> nicks,
  }) {
    const samples = 72;
    // Vertically squashed a touch, as the record's dies are: a die pressed by a hand
    // rather than a press is never perfectly round.
    const yRatio = 0.9;
    // Two phases, so the rim's wobble is low-frequency and organic rather than
    // per-sample noise — noise reads as a bad renderer, not as a hand.
    final ph1 = rng.nextDouble() * 2 * math.pi;
    final ph2 = rng.nextDouble() * 2 * math.pi;

    final outer = <Offset>[];
    final inner = <Offset>[];
    for (var i = 0; i < samples; i++) {
      final a = (i / samples) * 2 * math.pi;
      final wobble =
          0.55 * math.sin(2 * a + ph1) + 0.35 * math.sin(3 * a + ph2);
      final ro = radius + wobble + (rng.nextDouble() - 0.5) * 0.4;
      var w =
          width + 0.35 * math.sin(4 * a + ph2) + (rng.nextDouble() - 0.5) * 0.3;
      for (final nick in nicks) {
        // Angular distance to the nick, wrapped, so a nick near 0 still thins the band
        // on both sides of the seam.
        final gap = ((a - nick + math.pi) % (2 * math.pi) - math.pi).abs();
        if (gap < 0.14) {
          // Tapered rather than cut: the pad lifts, it does not slice. A floor keeps the
          // band from vanishing entirely, which would break the rim into arcs.
          w *= math.max(0.08, gap / 0.14);
        }
      }
      final ri = ro - math.max(0.12, w);
      outer.add(_point(centre, u, ro, a, yRatio));
      inner.add(_point(centre, u, ri, a, yRatio));
    }

    _closedThrough(path, outer);
    _closedThrough(path, inner.reversed.toList());
  }

  /// The mascot's own paw, pressed into the ring's top-right corner --
  /// `cp-i-stamp-corner-tr45` in the design record. Pad first, then three symmetric
  /// toes, already placed and scaled into this die's own 40-unit viewBox: these four
  /// blobs are `paw_parts(sym: true, box: 34)`'s own output
  /// (`gen_patch_marks.py`), fitted into a box 38% as wide as the cell and inset
  /// 7.25% from the cell's own top and right edges -- the record's 16px box on its
  /// ~42pt cell, scaled to this file's units. Re-measuring the cat moves the
  /// record's numbers; this copy has to be re-derived by hand alongside it, the same
  /// trade the ring's own ported constants above already make.
  ///
  /// `(cx, cy, rx, ry, rot)` per blob, in that fitted position -- pad, then the
  /// left, middle and right toe.
  static const List<List<double>> _pawBlobs = [
    [29.5, 13.47, 4.28, 3.32, 0.0],
    [24.89, 7.9, 1.71, 2.03, -39.62],
    [29.5, 6.24, 1.71, 2.03, 0.0],
    [34.11, 7.9, 1.71, 2.03, 39.62],
  ];

  /// The centre of the paw's own small box -- where the extra 45deg the class doc
  /// describes pivots, rather than the cell's own centre.
  static const Offset _pawPivot = Offset(29.5, 10.5);

  /// The paw's outline, as its own `Path` -- see the class doc for why it is not
  /// folded into the ring's.
  Path _paw(Offset centre, double u, int day) {
    final rng = math.Random(day % 3);
    final path = Path();
    for (final blob in _pawBlobs) {
      final pts = _blob(rng, blob[0], blob[1], blob[2], blob[3], blob[4]);
      final placed = pts
          .map((p) => _rotateAround(p, _pawPivot, 45 * math.pi / 180))
          .map(
            (p) => Offset(
              centre.dx + (p.dx - _box / 2) * u,
              centre.dy + (p.dy - _box / 2) * u,
            ),
          )
          .toList();
      _closedThrough(path, placed);
    }
    return path;
  }

  /// One pressed bean: an ellipse with low-frequency wobble, ported from `blob()` in
  /// `gen_patch_marks.py` at that generator's own amp (0.028) and sample count (22)
  /// for the tidy print -- the same "why sampled rather than drawn" `_band` above
  /// already argues, applied to a print instead of a rim.
  static List<Offset> _blob(
    math.Random rng,
    double cx,
    double cy,
    double rx,
    double ry,
    double rotDeg, {
    double amp = 0.028,
    int n = 22,
  }) {
    final ph1 = rng.nextDouble() * 2 * math.pi;
    final ph2 = rng.nextDouble() * 2 * math.pi;
    final t = rotDeg * math.pi / 180;
    final ct = math.cos(t);
    final st = math.sin(t);
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final a = (i / n) * 2 * math.pi + (rng.nextDouble() * 2 - 1) * 0.03;
      final k =
          1 +
          amp * math.sin(2 * a + ph1) +
          0.6 * amp * math.sin(3 * a + ph2) +
          (rng.nextDouble() * 2 - 1) * amp * 0.3;
      final x = rx * k * math.cos(a);
      final y = ry * k * math.sin(a);
      pts.add(Offset(cx + x * ct - y * st, cy + x * st + y * ct));
    }
    return pts;
  }

  /// [p] rotated by [angle] radians about [pivot] -- the extra 45deg's own centre,
  /// never the cell's, per the class doc.
  static Offset _rotateAround(Offset p, Offset pivot, double angle) {
    final dx = p.dx - pivot.dx;
    final dy = p.dy - pivot.dy;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(pivot.dx + dx * c - dy * s, pivot.dy + dx * s + dy * c);
  }

  static Offset _point(
    Offset centre,
    double u,
    double r,
    double a,
    double yRatio,
  ) => Offset(
    centre.dx + r * u * math.cos(a),
    centre.dy + r * u * math.sin(a) * yRatio,
  );

  /// A closed, smooth curve through [pts] — Catmull-Rom converted to cubic Béziers, the
  /// same smoothing the generator applies, so a 72-sample rim reads as a curve rather
  /// than as a 72-sided polygon.
  static void _closedThrough(Path path, List<Offset> pts) {
    final n = pts.length;
    if (n < 3) return;
    path.moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = pts[(i - 1 + n) % n];
      final p1 = pts[i];
      final p2 = pts[(i + 1) % n];
      final p3 = pts[(i + 2) % n];
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    path.close();
  }

  @override
  bool shouldRepaint(ReadCalendarStampDie old) =>
      old.colour != colour || old.day != day;
}
