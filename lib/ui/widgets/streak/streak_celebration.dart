import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/reading_streak_chip.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';

/// The seals a run can earn, in order.
///
/// **Provisional, and the design record says so** (open question 7): 7 / 30 / 100 is the
/// obvious ladder, and the constraint it has to satisfy is that seals stay rare enough to
/// mean something on a Library Card that will eventually carry several. It is a constant
/// here rather than a literal in the celebration so that changing the ladder is one edit
/// and cannot leave the bar filling toward one number while the copy names another.
const List<int> kStreakMilestones = [7, 30, 100, 365];

/// The seal this run is working toward, or null once every one has been passed.
int? streakMilestoneTarget(int streak) {
  for (final target in kStreakMilestones) {
    if (streak < target) return target;
  }
  return null;
}

/// The one second in the day the reader is owed a reward.
///
/// **Duolingo's grammar, in the library's own candlelight.** One figure, one label, the
/// week it belongs to, one way out — and the palette is [kCandleFlame] over [kCandleGlow],
/// the tokens `card_lighting.dart` owns and the reading lamp already borrows. Deliberately
/// *not* Duolingo's green: in this app green is the brand colour and means something else
/// on every other screen, so a celebration in it would read as chrome.
///
/// **Its ink is fixed rather than themed**, which is the one thing here that looks like an
/// oversight and is not. This screen paints its own cream ground, so `context.colors`
/// would hand it white type in dark mode and the whole celebration would be blank. The
/// inks are therefore the candle family's own browns — the same file the ground came from.
///
/// **Why it may take over the screen at all.** The same argument lost on the library
/// screen (`sc-increment` in the design record): a takeover there interrupts someone who
/// was doing something else. Here the reader was *on the streak page* and asked for this,
/// so nothing is being interrupted.
///
/// **One [AnimationController] rather than six delayed implicit animations, and that is a
/// deviation worth stating.** The record specifies implicit animation — `TweenAnimationBuilder`,
/// `AnimatedScale`, `AnimatedSlide` — which is right about not reaching for a package and
/// right about the feel. What it does not address is the *stagger*: implicit animations
/// have no delay, so six beats means six `Future.delayed` calls, every one of which has to
/// be cancelled on dispose or it rebuilds a disposed widget. One controller with six
/// [Interval]s is core Flutter, is a single thing to dispose, and makes the timings
/// readable in one place — which is also what lets a test drive them.
class StreakCelebration extends StatefulWidget {
  const StreakCelebration({
    super.key,
    required this.streak,
    required this.week,
    required this.today,
    required this.onDone,
  });

  /// The run *after* tonight was recorded. The figure, and what the milestone bar measures.
  final int streak;

  /// The seven days ending today, oldest first: whether each was recorded.
  ///
  /// The last entry is today and is always true — this screen only exists because today
  /// was just recorded — and it is the one that stamps in last.
  final List<bool> week;

  /// The day the week ends on, so its letters are the reader's own.
  final DateTime today;

  final VoidCallback onDone;

  @override
  State<StreakCelebration> createState() => _StreakCelebrationState();
}

class _StreakCelebrationState extends State<StreakCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beats = AnimationController(
    // Long enough for six beats to read as a sequence rather than a flash, short enough
    // that a reader who does this every night is not waiting for it. Nothing moves after
    // the last cell lands.
    duration: const Duration(milliseconds: 1360),
    vsync: this,
  );

  /// The beats, in the order the eye should travel: the flame, the figure, the label, the
  /// week, the bar, and **today's cell last** — so the thing that changed is the thing the
  /// eye ends on rather than the total.
  late final Animation<double> _flame = _beat(0, 620);
  late final Animation<double> _figure = _beat(300, 820);
  late final Animation<double> _label = _beat(560, 900);
  late final Animation<double> _weekCard = _beat(680, 1020);
  late final Animation<double> _bar = _beat(820, 1200);
  late final Animation<double> _stamp = _beat(1020, 1360);

  Animation<double> _beat(
    int fromMs,
    int toMs, {
    Curve curve = Curves.easeOut,
  }) {
    final total = _beats.duration!.inMilliseconds;
    return CurvedAnimation(
      parent: _beats,
      curve: Interval(fromMs / total, toMs / total, curve: curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // **The same gate every hold in `book_widget.dart` already honours.** A reader who has
    // asked the system to stop animating gets the finished state, not a faster version of
    // the sequence — and `value = 1` rather than `forward()` means there is no frame of
    // motion at all.
    if (MediaQuery.disableAnimationsOf(context)) {
      _beats.value = 1;
    } else if (!_beats.isAnimating && _beats.value == 0) {
      _beats.forward();
    }
  }

  @override
  void dispose() {
    _beats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = streakMilestoneTarget(widget.streak);

    return ColoredBox(
      color: kCandleGlow,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Beat one: the flame arrives overshooting, which is the only bounce on the
              // screen. Everything after it settles rather than springs.
              ScaleTransition(
                scale: Tween<double>(begin: 0.4, end: 1).animate(
                  CurvedAnimation(parent: _flame, curve: Curves.easeOutBack),
                ),
                child: const Icon(
                  kReadingStreakIcon,
                  size: 76,
                  color: kCandleFlame,
                ),
              ),
              const SizedBox(height: 12),
              // Beat two: the figure rolls up from below. Slide and fade together, so it
              // arrives rather than appearing at its destination already.
              _Rise(
                animation: _figure,
                child: Text(
                  '${widget.streak}',
                  style: AppTextStyles.display.copyWith(color: kCandleStockTop),
                ),
              ),
              _Rise(
                animation: _label,
                child: Text(
                  l10n.streakCelebrationLabel(widget.streak),
                  style: AppTextStyles.subtitle.copyWith(
                    color: kCandleStockTop.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _Rise(
                animation: _weekCard,
                child: _WeekCard(
                  week: widget.week,
                  today: widget.today,
                  stamp: _stamp,
                ),
              ),
              const SizedBox(height: 28),
              _Rise(
                animation: _bar,
                child: Column(
                  children: [
                    if (target != null) ...[
                      _MilestoneBar(
                        animation: _bar,
                        progress: widget.streak / target,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      // Three different things to say, and the first day gets its own
                      // line: "29 more days to the 30-day seal" is a discouraging thing to
                      // read on the night someone started.
                      widget.streak == 1
                          ? l10n.streakCelebrationFirst
                          : target == null
                          ? l10n.streakCelebrationSealed(kStreakMilestones.last)
                          : l10n.streakCelebrationMilestone(
                              target - widget.streak,
                              target,
                            ),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        color: kCandleStockTop.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // One way out, and no second call to action. Deliberately absent: confetti,
              // a sound, a share prompt. The reward for reading is the reading; this is a
              // receipt with good manners.
              SizedBox(
                width: double.infinity,
                child: ElevatedActionButton(
                  height: 50,
                  buttonText: l10n.streakCelebrationGo,
                  onPressed: widget.onDone,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade and lift, together, off one beat.
///
/// Its own widget because five things do it and a `FadeTransition` nested in a
/// `SlideTransition` five times over is the kind of repetition that ends with one of them
/// sliding the wrong way.
class _Rise extends StatelessWidget {
  const _Rise({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          // A third of the child's own height, so a big figure travels further than a
          // small label and the two read as one movement rather than two speeds.
          begin: const Offset(0, 0.34),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

/// The week this night belongs to, with today stamping in last.
///
/// **The row itself is [ReadWeekRow]** — the same object the streak page draws behind this
/// screen. What is local is the card it sits on, the candle palette, and the closing beat.
class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.week,
    required this.today,
    required this.stamp,
  });

  final List<bool> week;
  final DateTime today;
  final Animation<double> stamp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        // A shade of the ground rather than white: a white card on cream reads as a
        // different surface, and this is meant to be part of the same piece of paper.
        color: Colors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ReadWeekRow(
        days: week,
        endingOn: today,
        // The candle pair, because this screen paints its own cream ground and the theme's
        // inks would be white on it in dark mode.
        palette: ReadWeekPalette.candle,
        // Off, so that exactly one cell on this screen arrives tilted. Six already-raked
        // neighbours would bury the one beat the sequence is built around.
        tilt: false,
        // The closing beat's cell is inverted rather than merely stamped — `.lweek s.fresh`
        // in the record. Against six neighbours that are already the accent colour, a
        // seventh in the same wash is not somewhere for the eye to land.
        freshLast: true,
        decorateLast: (cell) => ScaleTransition(
          // Overshooting its own size and staying there: the record's
          // `rotate(-4deg) scale(1.12)`, so the cell that just landed sits a little proud
          // of its neighbours once everything has settled.
          scale: Tween<double>(
            begin: 0.2,
            end: 1.12,
          ).animate(CurvedAnimation(parent: stamp, curve: Curves.easeOutBack)),
          // **Reversed from 14°, which was mine and was wrong.** The record presses this
          // one on at the same −4° the grid rakes a day by; a steeper angle was reasoned
          // as "it is being pressed on in front of them" and in practice made the one cell
          // the sequence ends on look like a layout bug next to six square ones.
          child: Transform.rotate(angle: -4 * math.pi / 180, child: cell),
        ),
      ),
    );
  }
}

/// How far this run is toward its next seal.
class _MilestoneBar extends StatelessWidget {
  const _MilestoneBar({required this.animation, required this.progress});

  final Animation<double> animation;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: ColoredBox(
          color: kCandleStockTop.withValues(alpha: 0.12),
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              // Fills *with* the beat rather than jumping to its value, so the bar is one
              // of the six things that happen instead of a figure that was already there.
              widthFactor: (progress * animation.value).clamp(0.0, 1.0),
              child: const ColoredBox(color: kCandleFlame),
            ),
          ),
        ),
      ),
    );
  }
}
