import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/reading_streak_chip.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame.dart';

/// The seals a run can earn, in order.
///
/// **Provisional, and the design record says so** (open question 7): 7 / 30 / 100 is the
/// obvious ladder, and the constraint it has to satisfy is that seals stay rare enough to
/// mean something on a Library Card that will eventually carry several. It is a constant
/// here rather than a literal in the celebration so that changing the ladder is one edit
/// and cannot leave the bar filling toward one number while the copy names another.
const List<int> kStreakMilestones = [7, 30, 100, 365];

/// The figure the celebration counts up to, for a test that must not read the flame's own
/// numerals or the week row's.
const Key kStreakCelebrationFigureKey = ValueKey('streak-celebration-figure');

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
/// **One [AnimationController] rather than nine delayed implicit animations, and that is a
/// deviation worth stating.** The record specifies implicit animation — `TweenAnimationBuilder`,
/// `AnimatedScale`, `AnimatedSlide` — which is right about not reaching for a package and
/// right about the feel. What it does not address is the *stagger*: implicit animations
/// have no delay, so nine beats means nine `Future.delayed` calls, every one of which has
/// to be cancelled on dispose or it rebuilds a disposed widget. One controller with nine
/// [Interval]s is core Flutter, is a single thing to dispose, and makes the timings
/// readable in one place — which is also what lets a test drive them.
///
/// **And no vector-animation runtime, which was a decision rather than a default.**
/// Duolingo's increment choreography was decomposed beat by beat and every one of them is
/// a transform, a colour tween or a gradient: the ignition from grey to lit, a spark
/// burst, a rolling counter with a spring overshoot, a diagonal gleam, then the staggered
/// reveal. None of it is character animation, which is the one thing Rive would be needed
/// for and the one thing this app has no asset for — there is no mascot, and
/// `docs/mockups/empty-states/PROMPTS.md` records what producing art here costs. A `.riv`
/// would also be a binary blob in a codebase whose whole discipline is that a claim is
/// greppable, and it would break two things this screen honours on purpose:
/// [MediaQuery.disableAnimationsOf] and *nothing moves once the last beat lands*.
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
    // **1500, up from 1360**, which bought the ignition and the gleam. Long enough for the
    // sequence to read as one event rather than a flash, short enough that a reader doing
    // this every night is not waiting for it. Nothing moves after the last cell lands —
    // which is why the flicker is part of the arrival and there is no idle loop.
    duration: const Duration(milliseconds: 1500),
    vsync: this,
  );

  /// The beats, in the order the eye should travel: the flame ignites and throws sparks,
  /// the figure counts, the flame gleams, then the label, the week, the bar, and **today's
  /// cell last** — so the thing that changed is the thing the eye ends on rather than the
  /// total.
  late final Animation<double> _ignite = _beat(
    0,
    520,
    curve: Curves.easeOutBack,
  );
  late final Animation<double> _bloom = _beat(60, 760);
  late final Animation<double> _sparks = _beat(120, 720, curve: Curves.linear);
  late final Animation<double> _figure = _beat(300, 860);

  /// The same window as [_figure] on a springier curve. **Two animations rather than one**
  /// because the overshoot belongs to where the figure *sits*, never to what it *says*: a
  /// back curve on the value would print one more day than the reader has and take it back,
  /// which is a lie in the only place on this screen that states a fact.
  late final Animation<double> _figureDrop = _beat(
    300,
    860,
    curve: Curves.easeOutBack,
  );
  late final Animation<double> _gleam = _beat(
    620,
    1000,
    curve: Curves.easeInOut,
  );
  late final Animation<double> _label = _beat(700, 1040);
  late final Animation<double> _weekCard = _beat(820, 1160);
  late final Animation<double> _bar = _beat(960, 1340);
  late final Animation<double> _stamp = _beat(1160, 1500);

  /// The spark table, built once.
  ///
  /// **Seeded from the run, for the reason the month's rake is derived from the day**
  /// (`readCalendarPatchTilt`): a re-roll on every paint cannot be told from a regression,
  /// could not be screenshotted, and could not be golden-tested. Seeding from the streak
  /// means tonight's burst is the same burst every time this screen is built, and a
  /// different one at a different number.
  late final List<_Spark> _sparkTable = _buildSparks(widget.streak);

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
    // motion at all. Every beat below is built so that its t=1 state is the resting one:
    // the sparks have faded, the gleam has left the glyph, the counter reads the run.
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
              // **The flame is the one part of this screen Rive draws.** Everything below it
              // is localised copy and themed widgets, which have no business inside a
              // binary. If the artboard is missing — which it is until it has been authored
              // — `_Ignition` runs instead, so the sequence is complete either way.
              StreakFlame(
                progress: _ignite,
                size: _Ignition.stageSize,
                fallback: (context) => _Ignition(
                  ignite: _ignite,
                  bloom: _bloom,
                  sparks: _sparks,
                  gleam: _gleam,
                  sparkTable: _sparkTable,
                ),
              ),
              const SizedBox(height: 12),
              _Counter(
                value: _figure,
                drop: _figureDrop,
                streak: widget.streak,
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

/// The flame catching: it lights, it throws sparks, it glows, and then it gleams.
///
/// **Four beats on one glyph, and the glyph is the shipped one.** [kReadingStreakIcon] is a
/// font codepoint precisely because the chip needs the same flame in two tints; replacing it
/// here with a drawn or vector flame would put two flames in the app that can drift, which
/// is the defect `reading_streak_chip.dart` already warns about for the share card's.
/// Everything below therefore *decorates* that glyph rather than substituting for it.
class _Ignition extends StatelessWidget {
  const _Ignition({
    required this.ignite,
    required this.bloom,
    required this.sparks,
    required this.gleam,
    required this.sparkTable,
  });

  final Animation<double> ignite;
  final Animation<double> bloom;
  final Animation<double> sparks;
  final Animation<double> gleam;
  final List<_Spark> sparkTable;

  /// The glyph's own size, unchanged from the first cut.
  static const double flameSize = 76;

  /// The box the bloom and the sparks get to play in. Twice the flame, so a spark can leave
  /// the glyph and still be drawn, and so the halo has somewhere to fall off to.
  static const double stageSize = flameSize * 2;

  /// The flame before it catches: the candle family's own brown, most of the way out.
  ///
  /// **Not a grey.** Duolingo's dormant flame is desaturated because its ground is white;
  /// this ground is [kCandleGlow] cream, and a true grey on cream reads as a hole rather
  /// than as an unlit wick. This is the same hue the copy is set in, nearly transparent —
  /// which is also exactly what the streak page means by an open day, where `_Hero` tints
  /// the flame `secondaryText` until tonight is in. The ignition is that rule, animated.
  static final Color dormant = kCandleStockTop.withValues(alpha: 0.32);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: stageSize,
      height: stageSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The light, behind the thing making it. It arrives a beat after the flame and
          // settles dimmer than it peaked, so the room brightens and then holds.
          AnimatedBuilder(
            animation: bloom,
            builder: (context, _) {
              final t = bloom.value;
              // Up to a third strength, then back to a sixth: a flare, then a steady burn.
              final alpha = t < 0.45
                  ? (t / 0.45) * 0.3
                  : 0.3 - ((t - 0.45) / 0.55) * 0.14;
              return Transform.scale(
                scale: 0.35 + t * 0.65,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // A *warmer* halo rather than a lighter one, which is the only kind
                    // that reads as light on a cream ground: white on cream is invisible.
                    gradient: RadialGradient(
                      colors: [
                        kCandleFlame.withValues(alpha: alpha),
                        kCandleFlame.withValues(alpha: 0),
                      ],
                      stops: const [0.15, 1],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
          // The sparks, over the light and under the flame, so the glyph stays the clearest
          // shape on screen while they are in the air.
          AnimatedBuilder(
            animation: sparks,
            builder: (context, _) {
              if (sparks.value == 0 || sparks.value == 1) {
                return const SizedBox.shrink();
              }
              return CustomPaint(
                size: const Size.square(stageSize),
                painter: _SparkBurst(t: sparks.value, sparks: sparkTable),
              );
            },
          ),
          AnimatedBuilder(
            animation: Listenable.merge([ignite, gleam]),
            builder: (context, _) {
              final flame = Transform.scale(
                // `easeOutBack` is already the overshoot — it carries past 1 and settles —
                // so this is one tween rather than a `TweenSequence` pretending to be one.
                scale: 0.4 + ignite.value * 0.6,
                child: Icon(
                  kReadingStreakIcon,
                  size: flameSize,
                  // The colour floods in over the first half of the burst, so the flame is
                  // fully lit by the time it stops growing rather than arriving lit.
                  color:
                      Color.lerp(
                        dormant,
                        kCandleFlame,
                        (ignite.value / 0.55).clamp(0.0, 1.0),
                      ) ??
                      kCandleFlame,
                ),
              );

              final t = gleam.value;
              if (t == 0 || t == 1) return flame;
              // **`srcATop`, so the band lands on the glyph and nowhere else.** A gleam
              // painted over the box would be a white stripe across the screen; composited
              // on to the source it is a highlight travelling over the flame's own shape.
              return ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) {
                  // **Narrow and not quite opaque.** A wider, whiter band at 0.22/0.75 read
                  // as the flame briefly turning into paper rather than catching the light;
                  // a gleam is a highlight travelling over a shape, so it has to leave most
                  // of the shape's own colour behind it.
                  const band = 0.15;
                  final centre = -band + t * (1 + band * 2);
                  return LinearGradient(
                    // Diagonal, which is what makes it read as a specular sweep rather
                    // than a wipe.
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0x00FFFFFF),
                      Colors.white.withValues(alpha: 0.55),
                      const Color(0x00FFFFFF),
                    ],
                    stops: [
                      (centre - band).clamp(0.0, 1.0),
                      centre.clamp(0.0, 1.0),
                      (centre + band).clamp(0.0, 1.0),
                    ],
                  ).createShader(bounds);
                },
                child: flame,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One ember: where it was thrown, how hard, and how big.
class _Spark {
  const _Spark({
    required this.angle,
    required this.speed,
    required this.radius,
    required this.lag,
  });

  /// Radians, measured from straight up.
  final double angle;

  /// How far it travels, as a fraction of the stage's half-width.
  final double speed;
  final double radius;

  /// A head start, so the burst is not one ring leaving at once.
  final double lag;
}

/// The burst, seeded from the run so it is the same burst every time.
List<_Spark> _buildSparks(int streak) {
  final random = math.Random(streak);
  const count = 14;
  // **A fan, not a ring, and the first cut got this wrong in a way worth naming**: even
  // spacing over a full turn drew a mechanical starburst, and the comment claimed a fan
  // while the code drew a circle. Sparks come off a flame, and a flame does not throw them
  // at its own wick — so this is 250° centred on straight up, with the gap at the bottom.
  const fan = 250 * math.pi / 180;
  return [
    for (var i = 0; i < count; i++)
      _Spark(
        // Spaced across the fan and then knocked off that spacing by up to most of a slot,
        // because evenly separated embers are the other half of what made it read as a
        // diagram. Derived from the seeded roll, so it is still stable.
        angle:
            -fan / 2 +
            (i + 0.5) / count * fan +
            (random.nextDouble() - 0.5) * (fan / count) * 1.6,
        // A wide spread on purpose: embers that all stop at the same radius are a ring
        // however they were aimed.
        speed: 0.28 + random.nextDouble() * 0.72,
        radius: 1.2 + random.nextDouble() * 1.8,
        lag: random.nextDouble() * 0.3,
      ),
  ];
}

class _SparkBurst extends CustomPainter {
  const _SparkBurst({required this.t, required this.sparks});

  final double t;
  final List<_Spark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final reach = size.width / 2;
    final paint = Paint();

    for (final spark in sparks) {
      // Its own clock, so the fan leaves in a ripple.
      final p = ((t - spark.lag) / (1 - spark.lag)).clamp(0.0, 1.0);
      if (p <= 0) continue;

      // Out fast, then coasting: the same decay a thrown ember has.
      final travel = reach * spark.speed * (1 - math.pow(1 - p, 3));
      final dx = math.sin(spark.angle) * travel;
      // Up along its angle, then pulled back down — which is what stops the burst reading
      // as a mechanical starburst.
      final dy = -math.cos(spark.angle) * travel + reach * 0.5 * p * p;

      paint.color = kCandleFlame.withValues(
        // Gone before the beat ends, so `value == 1` leaves nothing on screen.
        alpha: (1 - p) * (1 - p),
      );
      canvas.drawCircle(
        centre + Offset(dx, dy),
        spark.radius * (1 - p * 0.45),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparkBurst old) => old.t != t || old.sparks != sparks;
}

/// The run, counted up to rather than printed.
///
/// **It counts from the previous number, which is the point.** The figure a reader came here
/// to see is not `12`, it is *`11` becoming `12`* — a number that is simply present says
/// nothing happened tonight. It rolls monotonically while the whole figure drops in with a
/// spring, so the bounce is positional and the value never overshoots into a day the reader
/// has not earned.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.value,
    required this.drop,
    required this.streak,
  });

  final Animation<double> value;
  final Animation<double> drop;
  final int streak;

  @override
  Widget build(BuildContext context) {
    // Day one counts up from nothing, which is the honest version of "the previous number"
    // on the night there wasn't one.
    final from = math.max(0, streak - 1);

    return AnimatedBuilder(
      animation: Listenable.merge([value, drop]),
      builder: (context, _) {
        return Opacity(
          opacity: value.value,
          child: Transform.translate(
            // **Down, where everything else on this screen rises.** The label, the week and
            // the bar all come up from below; the figure arriving from above is what marks
            // it as the subject rather than another row in a stack.
            offset: Offset(0, (1 - drop.value) * -26),
            child: Text(
              '${(from + (streak - from) * value.value).round()}',
              key: kStreakCelebrationFigureKey,
              // `display` carries tabular figures, which is what stops the width jumping
              // as the digits roll.
              style: AppTextStyles.display.copyWith(color: kCandleStockTop),
            ),
          ),
        );
      },
    );
  }
}

/// Fade and lift, together, off one beat.
///
/// Its own widget because three things do it and a `FadeTransition` nested in a
/// `SlideTransition` three times over is the kind of repetition that ends with one of them
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
              // of the beats that happen instead of a figure that was already there.
              widthFactor: (progress * animation.value).clamp(0.0, 1.0),
              child: const ColoredBox(color: kCandleFlame),
            ),
          ),
        ),
      ),
    );
  }
}
