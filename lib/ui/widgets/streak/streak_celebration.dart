import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame_mark.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_span_track.dart';

/// The spans a run can reach, in order.
///
/// **Nothing in the celebration reads these any more, and that is the point.** They used to
/// drive both the progress bar and its caption, as "the 7-day seal" — a reward that does not
/// exist. There is no award, unlock or earn path anywhere in `lib/`, and `_Seal` in
/// `shareable_library_card.dart` is the app's own logo emboss, present on every Library Card
/// regardless of any streak, so the copy also borrowed a noun the reader already owned. The
/// bar and the caption now measure the reader's own record instead, which
/// `longestStreakProvider` already computes.
///
/// Kept, unused by `lib/`, because the ladder itself is sound and is where making these
/// spans *real* would start — see `docs/mockups/streak-week/index.html`, which draws that
/// proposal and names the two decisions it still needs. `streakMilestoneTarget` and
/// `test/streak_celebration_test.dart`'s ladder group are its only remaining readers.
const List<int> kStreakMilestones = [7, 30, 100, 365];

/// The figure the celebration counts up to, for a test that must not read the flame's own
/// numerals or the week row's.
const Key kStreakCelebrationFigureKey = ValueKey('streak-celebration-figure');

/// The celebration's ground.
///
/// **White, which reverses the cream this shipped with.** Every other value on this screen
/// still comes from `card_lighting.dart`, and the cream [kCandleGlow] was the whole premise:
/// a candlelit surface, warm rather than bright, with the flame's halo readable because the
/// ground was already warm. That premise lost to a plainer one — Duolingo's card is white,
/// the reference the whole screen is measured against is white, and the cream read as a tint
/// over the app rather than as a surface of its own.
///
/// **What it costs, stated rather than discovered later.** The flame's own halo and the pool
/// under the book are amber at low alpha, authored to sit on cream; on white they are paler
/// and closer to invisible, which is exactly what
/// `test/streak_flame_golden_test.dart` used to warn about from the other direction. And the
/// ink below had to move with it, because a mid-amber on white is worse than on cream, not
/// better.
///
/// A constant rather than a literal so the widget, `streak_celebration_test.dart` and the
/// flame's golden cannot disagree about what this screen stands on — they did, once: the
/// golden's ground was hardcoded.
const Color kStreakCelebrationGround = Colors.white;

/// The ink for the figure and its label.
///
/// **[kCandleFlame] #F2A93F — the colour the fire itself is drawn in — and this reverses a
/// documented decision, on instruction.** It was `AppColors.light.flame` #B54708 for exactly
/// the reason `app_theme.dart` gives: that token is deliberately darkened from a true fire
/// orange far enough to pass AA while still reading as orange. The reversal is a deliberate
/// choice to match the flame above rather than to clear a threshold, and the numbers it gives
/// up are worth having written down:
///
/// | on white              | contrast |
/// | --------------------- | -------- |
/// | `flame` #B54708       | 5.43:1   |
/// | **`kCandleFlame`**    | **2.00:1** |
///
/// 2.00:1 is under AA's 4.5:1 for body text **and** under the 3:1 allowed for large text,
/// which the 64pt figure and the 22pt semibold label both qualify as. Darkening this hue
/// until it reaches even 3:1 lands near #BF8632, an ochre that no longer reads as fire, so
/// there is no version of this instruction that is both the flame's colour and compliant —
/// the saturation is what runs out, not the lightness. Duolingo's own figure makes the same
/// trade.
///
/// `final` rather than `const`: kept that way because the value is a token from another
/// library and the previous one could not be `const` either — Dart will not read a field off
/// a const instance inside a constant expression, the same reason `kStreakFlameFactory` in
/// `streak_flame.dart` is `final`.
final Color _kStreakCelebrationInk = kCandleFlame;

/// The next span above this run, or null once every one has been passed.
int? streakMilestoneTarget(int streak) {
  for (final target in kStreakMilestones) {
    if (streak < target) return target;
  }
  return null;
}

/// The one second in the day the reader is owed a reward.
///
/// **Duolingo's grammar, and now on Duolingo's ground.** One figure, one label, the
/// week it belongs to, one way out — over [kStreakCelebrationGround] white, with the flame
/// and the counter in [kCandleFlame]. It shipped on [kCandleGlow] cream and that is recorded
/// on the ground constant rather than deleted. Deliberately
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
    required this.best,
    required this.week,
    required this.today,
    required this.onDone,
  });

  /// The run *after* today was recorded. The figure, and what the bar measures.
  final int streak;

  /// The longest run on record, from `longestStreakProvider`.
  ///
  /// **`longestReadingRun` counts the run in progress**, so `best >= streak` always holds
  /// and `streak == best` is not a tie — it is the day the record is being set. That is
  /// what lets this screen hand out a real reward without one new stored field.
  ///
  /// Passed rather than watched because this widget is deliberately provider-free:
  /// `reading_streak_page.dart` owns every query this feature makes, and a second read here
  /// would be a second source for one number.
  final int best;

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
    // this every day is not waiting for it.
    //
    // **The flame keeps moving after the last cell lands.** This comment used to say the
    // opposite — "nothing moves after the last cell lands, which is why the flicker is part
    // of the arrival and there is no idle loop" — and that was overruled deliberately: a
    // flame that freezes the instant it arrives reads as a decal. See [_alive], and
    // `kStreakFlameIdleAnimation` for what it costs. Everything that is *not* the flame
    // still comes to rest.
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

  /// The same event, on the drive the **artboard** needs rather than the glyph's.
  ///
  /// **Two drives for one beat, because the two drawings are not the same kind of thing.**
  /// [_ignite] scrubs a single continuous scale on a font glyph, and `easeOutBack`'s overshoot
  /// is what gives that its pop. The artboard's `Ignite` timeline already carries its own
  /// easing, authored frame by frame against real time — a hold on the shut book, a back-out
  /// on the covers, a cut on the action, a settle on the flame — so a curve here would be
  /// applied *on top of* that one. That is not a nuance; it was a bug twice over with
  /// `easeOutBack`:
  ///
  /// - it crossed 0 → 1 in about **185ms**, so the 900ms timeline played in roughly three
  ///   frames and a reader saw the flame *appear* rather than a book falling open;
  /// - the overshoot then ran past 1 and back, and seeking past the last frame clamps, so
  ///   **62% of the window was a held frame**.
  ///
  /// So this one is `linear` and spans exactly the timeline's own 900ms. `StreakFlame` seeks
  /// by it; the shape of the motion belongs to `rive/streak_flame/scene.rml`, where it can be
  /// watched with `rive rive/streak_flame` or in the Rive Editor.
  late final Animation<double> _flame = _beat(0, 900, curve: Curves.linear);

  /// How much of the artboard's looping `Idle` timeline to mix in, so the flame keeps
  /// flickering and throwing embers after it has caught.
  ///
  /// **This is the beat that reverses the rule above it**: something does move after the last
  /// cell lands. It ramps rather than switching, because the loop's values sit a few percent
  /// either side of the pose the ignition ends on and a hard cut would step the flame's scale.
  /// It starts before [_flame] finishes on purpose — the last 80ms of the ignition is a settle,
  /// which is exactly where a flicker should begin.
  ///
  /// `StreakFlame` forces it to zero under reduced motion. It cannot be gated here: the gate
  /// below jumps the controller to 1, and this is the one beat whose t=1 state is motion.
  late final Animation<double> _alive = _beat(820, 1120, curve: Curves.linear);
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
  /// means today's burst is the same burst every time this screen is built, and a
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
    // Short of the record, so there is a distance worth naming. `best` counts this run,
    // so the other branch means the record is being set right now.
    final chasing = widget.best > widget.streak;
    // To *beat* a best of N you need N+1 days, not N.
    final toBeat = widget.best + 1 - widget.streak;

    return ColoredBox(
      color: kStreakCelebrationGround,
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
                progress: _flame,
                liveness: _alive,
                // **[StreakFlame.stageSize], not `_Ignition.stageSize`.** The two used to be
                // the same 152, which quietly tied the Rive flame's on-screen size to the
                // point size of the fallback's font glyph; see the long note on that
                // constant. The fallback below keeps its own box.
                size: StreakFlame.stageSize,
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
                  // **Full opacity, and dropping the 0.7 it used to carry is not cosmetic.**
                  // The alpha was fine against `kCandleStockTop`, which still measured 5.8:1
                  // blended over the cream ground. The same 70% on this orange composites to
                  // #CB7740 and **2.8:1**, under AA — so recolouring the label without also
                  // taking the alpha off would have quietly made it fail. At 100% it is
                  // 4.55:1, which clears AA for body text.
                  //
                  // **`titleUser` is the scale's 22pt sans step, one above `subtitle`'s 17.**
                  // Its name records where the step came from rather than restricting it, and
                  // reusing an existing step is what `text_style_test.dart` asks for — a
                  // `subtitleStreak` duplicating these exact metrics is the scale drifting
                  // back into thirteen sizes, which is the thing that guard exists to stop.
                  style: AppTextStyles.titleUser.copyWith(
                    color: _kStreakCelebrationInk,
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
                    // **The span ladder, and this screen is its only home.**
                    //
                    // It shipped on the streak page first, standing between the week row
                    // and the month card, and was moved here on instruction. That move
                    // reconciles the two options the design record had left fighting
                    // (`docs/mockups/streak-week/index.html`): **F** wanted a ladder, **G**
                    // wanted no standing reminder of what the reader has not done and the
                    // whole reward in the celebration. F's object shown only at G's moment
                    // is both — a reader meets the ladder on the day they have just added
                    // to it, and never as a permanent list of four things they have not
                    // managed. It also puts the object on the ground it was drawn for:
                    // `StreakSpanTrack` paints in `kCandleStockTop` and `kCandleFlame`,
                    // which are candle tokens, and on the page it was the only candlelit
                    // thing on `pageBackground`.
                    //
                    // **It replaced `_MilestoneBar`, which is deleted rather than moved
                    // aside.** Two horizontal amber bars 10pt apart is one duplication; the
                    // worse one is that the old bar measured `streak` against `best + 1`
                    // and the sentence directly under it said that same figure in words —
                    // "8 more days to beat your best" *is* the bar, drawn. The ladder says
                    // something the sentence cannot: where today's run sits among spans
                    // that have names. And it is here every day, where the bar vanished
                    // on a record day — the one day with the most to show.
                    //
                    // **The fill does not animate.** It is set once, at the fraction the
                    // run in progress has reached; the `_Rise` above is the reveal.
                    //
                    // **This reads `widget.streak`, not `widget.best`.** It read the record
                    // for one round, on the reasoning that the record is the more honest
                    // number to show since it never falls. That was backwards: it drew the
                    // rail far along a rung the *current* run had no claim on — sharpest
                    // right after a lapse, when the streak has just reset to 1 and the rail
                    // still shows the old run's reach — with nothing on screen saying the
                    // fill was the old run rather than the new one. The record is still
                    // named, in words, by the caption below.
                    StreakSpanTrack(
                      streak: widget.streak,
                      rungs: [
                        StreakSpan(days: 7, label: l10n.streakSpanWeek),
                        StreakSpan(days: 30, label: l10n.streakSpanMonth),
                        StreakSpan(days: 100, label: l10n.streakSpanHundred),
                        StreakSpan(days: 365, label: l10n.streakSpanYear),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      // Three things to say, and the first day still gets its own line:
                      // a countdown is a discouraging thing to read on day one.
                      //
                      // **This used to name a seal, and there is no seal.**
                      // `kStreakMilestones` fed the bar and one sentence and nothing
                      // else — no award, unlock or earn path exists anywhere in `lib/`
                      // — and the noun was already spent on `_Seal` in
                      // `shareable_library_card.dart`, the app's own logo emboss, which
                      // every Library Card carries whether or not its reader has ever
                      // recorded a day. So the line promised an object that is never
                      // granted, named after one the reader already had, which is why it
                      // read as *so what?*. `longestStreakProvider` ships and is the one
                      // stake the app can honestly point at today.
                      widget.streak == 1
                          ? l10n.streakCelebrationFirst
                          : chasing
                          ? l10n.streakCelebrationChasing(toBeat)
                          : l10n.streakCelebrationRecord,
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
/// **Four beats on one mark, and the mark is now the artboard's own silhouette.** This used
/// to say something stronger and wrong: that the flame here had to stay `kReadingStreakIcon`,
/// a Phosphor glyph, *because* the chip needed the same flame in two tints, and that drawing
/// a vector one here would put two flames in the app that could drift. The premise was right
/// and the arithmetic backwards — there were already two flames, this glyph and the Rive
/// artboard a few lines above it, and this is the code path that runs when the artboard is
/// missing. So the fallback was the one place in the app guaranteed to draw a *different*
/// flame from the one it was standing in for. [StreakFlameMark] is generated from the
/// artboard's own point lists, so the fallback and the real thing are one silhouette and the
/// four beats below decorate that.
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
  /// **Not a grey, even though the ground is now white.** Duolingo's dormant flame is
  /// desaturated and its ground is white too, so the original reason given here — that a true
  /// grey on cream reads as a hole — no longer applies. It stays brown anyway for the
  /// stronger reason the note already carried: this is the same hue the copy is set in,
  /// nearly transparent, and it is exactly what the streak page means by an open day, where
  /// `_Hero` tints the flame `secondaryText` until today is in. The ignition is that rule,
  /// animated.
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
                child: StreakFlameMark(
                  size: flameSize,
                  // The colour floods in over the first half of the burst, so the flame is
                  // fully lit by the time it stops growing rather than arriving lit.
                  //
                  // The core is left to `StreakFlameMark`'s own derivation rather than being
                  // lerped separately, which means it lights *with* the body from the same
                  // number. Handing it `kCandleFlameCore` outright would have the core arrive
                  // fully lit over a body still going grey — a bright tongue inside a dead
                  // shape, which is the one frame of this beat that cannot look right.
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
/// nothing happened today. It rolls monotonically while the whole figure drops in with a
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
    // on the day there wasn't one.
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
              // `displayStreak` carries tabular figures, which is what stops the width
              // jumping as the digits roll.
              //
              // **A token rather than `display.copyWith(fontSize: 64)`.** That was the first
              // attempt and `text_style_test.dart` rejected it: no call site under `lib/ui`
              // may state its own size, because a size the scale lacks means the scale is
              // wrong rather than that this line needs an exception. Raising `display`
              // itself was not available either — the Library Card's hero figure and
              // `StatTile` both read it, so this screen would have grown those.
              style: AppTextStyles.displayStreak.copyWith(
                color: _kStreakCelebrationInk,
              ),
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

/// The week this day belongs to, with today stamping in last.
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
        // **A border and no fill, which the move to a white ground forced.** This was
        // `Colors.white` at 45% — a shade of the cream it sat on, so the card read as the
        // same piece of paper rather than a second surface. On white that fill is *nothing*:
        // the card disappeared entirely and only the row inside it remained. A hairline is
        // how a white card on white gets an edge, and it is also the grammar the row
        // redesign is heading toward (`docs/mockups/streak-week/index.html`, `el-card`).
        border: Border.all(color: kCandleStockTop.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ReadWeekRow(
        days: week,
        endingOn: today,
        // The candle pair. **Still the candle pair on a white ground**, because the reason
        // was never the cream: `context.colors` hands back white type in dark mode, and
        // this screen has no dark variant, so a theme-read palette would vanish here.
        palette: ReadWeekPalette.candle,
        // Off, so that exactly one token on this screen arrives tilted. Six already-raked
        // neighbours would bury the one beat the sequence is built around.
        tilt: false,
        // **Lifted rather than inverted, which is a downgrade forced by the row redesign
        // and not a change of mind.** The old cell was a 10% wash inside an edge, so a
        // solid fill with a reversed-out letter was a real escalation away from its six
        // neighbours. Every read day is now *already* solid and already carries a
        // reversed-out check, so there is nothing left to invert to. What marks this one
        // out is the shadow this adds plus the overshoot and tilt below.
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

// **`_MilestoneBar` used to live here and is deleted, not parked.** It was an 8pt rail
// filling `streak / (best + 1)`, hidden on a record day. `StreakSpanTrack` replaced it,
// moved down from the streak page; the reasoning is at its call site above. One thing it
// taught that is worth keeping without it: its `SizedBox` had a height and no width, and
// because the parent `Column` centres its children the whole stack collapsed onto its own
// fill — a `ColoredBox` sizes to its child, and a `FractionallySizedBox` is a fraction *of
// the space it is given*. The bar drew as a short amber dash floating mid-screen with no
// track behind it, and the suite was green throughout. `StreakSpanTrack` cannot repeat that
// — it is a `LayoutBuilder` over the width it is handed — but any future rail here can.
