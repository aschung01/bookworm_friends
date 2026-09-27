import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';

/// One rung on the ladder of spans a reading run can reach.
///
/// The label is already localised by the caller: this widget draws a ladder and has no
/// opinion about what a rung is called, which is what lets `ko` say `1주` where `en` says
/// `1 week` without a second code path in here.
@immutable
class StreakSpan {
  /// The run length that earns this rung.
  final int days;

  /// What to call it under the track.
  final String label;

  const StreakSpan({required this.days, required this.label});
}

/// How far the run in progress has got along the ladder.
///
/// **This replaced a row of four ring badges, and the badges were rejected for five
/// specific reasons** rather than as a matter of taste: the number inside each ring and the
/// label under it said the same thing twice (`100` over `100 days` said it twice in the same
/// words); the set did not cohere, being three named periods and one raw count; four uniform
/// thin grey rings read as disabled form controls, with the one earned ring looking like a
/// selected radio button; the row sat in a card inside a card; and nothing about it belonged
/// to an app whose other marks are candlelight, stock, emboss and stamps. `docs/mockups/
/// streak-week/index.html` keeps them drawn, under `span-row`, so they are not re-derived.
///
/// What a track fixes that a row of badges could not: **it can say where in the gap you
/// are.** Four badges have two states each and nothing in between, so a 9-day run and a
/// 29-day run drew identically.
///
/// **Earned is derived, never stored** — the caller passes `currentReadingRun`'s answer, so
/// there is no new field, no migration, and no way for this to disagree with the days it
/// describes. The only thing derivation gives up is the date a rung was earned, which
/// nothing asks for.
///
/// **This reads the run in progress, not the record — it was `best` (`longestReadingRun`)
/// for one round and that was a defect, not a design.** A reader whose streak had just reset
/// to 1 after a lapse saw the rail sitting most of the way to a rung their *current* run had
/// no claim on, with nothing on screen saying the fill was the old run rather than the new
/// one. The record still has a home: `streakCelebrationChasing`/`streakCelebrationRecord`
/// name it in words, from `widget.best`, directly under this track.
class StreakSpanTrack extends StatelessWidget {
  /// The run in progress, which `currentStreakProvider` already computes.
  final int streak;

  /// The rungs, ascending.
  final List<StreakSpan> rungs;

  const StreakSpanTrack({super.key, required this.streak, required this.rungs});

  /// The rail's height, and therefore the graduations'.
  static const double _rail = 7;

  /// How much of the rail is filled, in 0..1.
  ///
  /// **The segments are even rather than proportional to [StreakSpan.days], and that is the
  /// whole design of this widget.** Spaced to scale, 7 / 30 / 100 all land inside the
  /// leftmost 27% of the track and two thirds of it stays empty until someone has read every
  /// day for a year — so the part of the ladder every reader is actually on would be a
  /// smudge at the left edge. Even segments spend the width on the readers who exist.
  ///
  /// Public, and separately tested, because the arithmetic is the part that can be wrong
  /// while the drawing still looks plausible.
  static double fillFraction(int streak, List<StreakSpan> rungs) {
    if (rungs.isEmpty) return 0;
    final seg = 1 / rungs.length;
    var fraction = 0.0;
    for (var i = 0; i < rungs.length; i++) {
      final lo = i == 0 ? 0 : rungs[i - 1].days;
      final hi = rungs[i].days;
      if (streak >= hi) {
        // Past this rung, so the whole segment is filled — and keep walking, because a
        // later rung may be passed too.
        fraction = (i + 1) * seg;
      } else if (streak > lo) {
        // Inside this segment. Nothing beyond it can be reached, so stop.
        fraction = i * seg + seg * (streak - lo) / (hi - lo);
        break;
      } else {
        break;
      }
    }
    return fraction.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final fraction = fillFraction(streak, rungs);

    return SizedBox(
      height: 34,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                child: _bar(
                  color: kCandleStockTop.withValues(alpha: 0.10),
                  width: double.infinity,
                ),
              ),
              Positioned(
                left: 0,
                top: 6,
                child: _bar(color: kCandleFlame, width: width * fraction),
              ),
              for (var i = 0; i < rungs.length; i++) ...[
                // **A white hairline through the rail, not a dot sitting on it**, and both
                // of the obvious alternatives were drawn and rejected. A round mark large
                // enough to see turns the whole object into a *slider*: a filled bar with a
                // handle on it promises something draggable, which is a worse fault than the
                // badges' because it promises an interaction that does not exist. Squaring
                // it off fixes that and exposes the next one — an earned mark drawn in
                // [kCandleFlame] sits on a [kCandleFlame] fill and vanishes into the bar as
                // a bulge, which a white halo only turns into a bead. A graduation has
                // neither fault: it reads against the fill and against the rail, it has no
                // handle shape, and it is the page-edge hairline the Library Card already
                // draws. Earned-ness is carried by the two things that were carrying it
                // anyway: the fill having passed the mark, and the label's ink.
                Positioned(
                  left: _at(width, i) - 1,
                  top: 6,
                  child: Container(
                    width: 2,
                    height: _rail,
                    color: Colors.white,
                  ),
                ),
                // **Centred on its mark, except where that would hang off the track.** The
                // last rung sits *at* the right edge by construction (see [_at]), so a box
                // centred on it puts half of `1 year` outside the page's content width and
                // the label is cut by the screen — which a widget test cannot see and a
                // render can. The end label hugs the edge instead, the way an axis label
                // does, and is right-aligned so it still reads as belonging to the end.
                _label(width, i),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Rung [i]'s caption, placed under its graduation.
  Widget _label(double width, int i) {
    const box = 60.0;
    final centre = _at(width, i);
    final hugsEnd = centre + box / 2 > width;
    final top = 6 + _rail + 7;

    final text = SizedBox(
      width: box,
      child: Text(
        rungs[i].label,
        // Wider than the column it is centred on, because a label is a word and the mark
        // it belongs to is two pixels. Unclipped, so `100 days` is never wrapped or cut.
        textAlign: hugsEnd ? TextAlign.right : TextAlign.center,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        // One style, two colours. The scale's stat label, which is what the week row's day
        // letters use too, so the two ladders on this page are set in the same type.
        style: AppTextStyles.caption.copyWith(
          color: streak >= rungs[i].days
              ? kCandleStockTop
              : kCandleStockTop.withValues(alpha: 0.40),
        ),
      ),
    );

    return hugsEnd
        ? Positioned(right: 0, top: top, child: text)
        : Positioned(left: centre - box / 2, top: top, child: text);
  }

  /// Where rung [i] sits along a rail of [width].
  ///
  /// The *end* of its segment rather than the start, so the last rung lands flush with the
  /// right edge and the track reads as finished when a year is in.
  double _at(double width, int i) => width * (i + 1) / rungs.length;

  Widget _bar({required Color color, required double width}) => Container(
    width: width,
    height: _rail,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
