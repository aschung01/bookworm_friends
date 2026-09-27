/// The celebration, and the five things it does in order.
///
/// **What matters here is the stagger and the gate**, not the look. The sequence is ordered
/// so the eye ends on the thing that changed — today's cell, stamping in last — rather than
/// on the total, and a reader who has asked the system to stop animating must get the
/// *finished* state rather than a faster version of it. Both are easy to break silently: a
/// reordered interval still animates, and a missing gate still looks fine on a machine
/// nobody has configured for reduced motion.
///
/// **Every case here runs against the hand-built flame, deliberately.** Three of them assert
/// its internals — the glyph's colour as it catches, the spark painter, the gleam's
/// `ShaderMask` — and those widgets exist only when the Rive artboard is unavailable. Which of
/// the two paths `StreakFlame` takes depends on whether `rive_native`'s dynamic library has
/// been downloaded into the gitignored `build/`, so left to chance these cases pass on a
/// machine that has not run `dart run rive_native:setup` and fail on one that has — which is
/// exactly what happened the hour the `.riv` was committed. `debugStreakFlameAssetOverride`
/// settles it. The artboard's own wiring is `streak_flame_test.dart`, and how the drawing
/// *looks* is `rive/streak_flame/sheet.py` and a simulator.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_celebration.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame_mark.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_span_track.dart';

import 'still_streak_flame.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int streak,
  int? best,
  List<bool>? week,
  bool reducedMotion = false,
  VoidCallback? onDone,
  Size surface = const Size(393, 852),
}) async {
  // **A phone-shaped surface by default, because the harness default is not one.**
  // `flutter_test` hands out 800×600, and this screen is a column of fixed-height pieces
  // between two `Spacer`s presented full-screen on a phone. 600 points tall is shorter than
  // any device the app supports — the smallest is an iPhone SE at 667 — so every case here
  // was implicitly asserting against a window narrower in the one dimension that matters.
  // The effect was not theoretical: adding the span ladder put the content at about 624
  // points, which fits every real phone and overflowed 27 cases at 600, each of them
  // reported as a `RenderFlex` exception with nothing to do with what it was testing. The
  // two cases at the bottom of this file pass their own size through this parameter, so
  // there is one place that decides how tall the screen is.
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: StreakCelebration(
          streak: streak,
          // `longestReadingRun` counts the run in progress, so a `best` below `streak`
          // is unreachable in production. Defaulting to `streak` therefore means "this
          // run is the record", which is the state most cases here do not care about.
          best: best ?? streak,
          week: week ?? const [true, true, false, true, true, true, true],
          // A fixed day so the weekday letters are stable: the row labels its cells from
          // this, and a case that read the clock would assert a different letter each day.
          today: DateTime(2026, 9, 17),
          onDone: onDone ?? () {},
        ),
      ),
    ),
  );
}

/// How visible today's cell is at this instant.
double _todayOpacity(WidgetTester tester) {
  final cell = find.byKey(const ValueKey('streak-week-today'));
  final fade = find
      .ancestor(of: cell, matching: find.byType(FadeTransition))
      .evaluate()
      .map((e) => (e.widget as FadeTransition).opacity.value)
      // The cell sits under the week card's own fade, so the effective opacity is the
      // product of every fade above it — which is what a reader actually sees.
      .fold<double>(1, (a, b) => a * b);
  return fade;
}

/// How visible the counter is at this instant.
///
/// **Read off its own [Opacity], never off an ancestor [FadeTransition].** The counter used
/// to be a `_Rise` and this was a `FadeTransition` search like the one above; when it became
/// a counter the search kept passing, because `MaterialApp` puts a route transition above
/// everything and that is what it had started matching. A finder that cannot fail is worse
/// than no finder.
double _figureOpacity(WidgetTester tester) {
  final opacity = find.ancestor(
    of: find.byKey(kStreakCelebrationFigureKey),
    matching: find.byType(Opacity),
  );
  return tester.widget<Opacity>(opacity.first).opacity;
}

/// What the counter currently reads.
int _figureValue(WidgetTester tester) => int.parse(
  tester.widget<Text>(find.byKey(kStreakCelebrationFigureKey)).data!,
);

/// The colour the flame is drawn in at this instant.
///
/// The *body*'s colour. `StreakFlameMark` derives its core from that by lifting the
/// lightness, so reading one number is reading both — which is deliberate here: the ignition
/// lerps a single colour out of `dormant`, and a core lit independently of its body would be
/// a bright tongue inside a dead shape.
Color _flameColour(WidgetTester tester) =>
    tester.widget<StreakFlameMark>(find.byType(StreakFlameMark)).color;

void main() {
  // Force the hand-built path. See the note at the top of this file, and the longer one on
  // `useStillStreakFlame`: without this, which flame these cases inspect is a property of the
  // machine rather than of the code — and the artboard's idle loop would stop
  // `pumpAndSettle` ever returning.
  useStillStreakFlame();

  testWidgets('the run, its label and the flame are all present', (
    tester,
  ) async {
    await _pump(tester, streak: 12, reducedMotion: true);

    expect(find.text('12'), findsOneWidget);
    expect(find.text('day streak'), findsOneWidget);
    // **The chip's own mark, and now genuinely the same silhouette rather than a promise
    // that it is.** This used to be `kReadingStreakIcon`, shared with the chip on the
    // reasoning that one constant is one flame — while the artboard a few lines above drew a
    // completely different one. `StreakFlameMark` is generated from the artboard's own point
    // lists, so the fallback and the real thing are one drawing.
    expect(find.byType(StreakFlameMark), findsOneWidget);
  });

  testWidgets('today\'s cell arrives last, after the figure', (tester) async {
    // The beat order is the whole argument: a celebration that lands the total last is about
    // the number, and this one is about the night.
    await _pump(tester, streak: 12);

    await tester.pump(); // schedule
    await tester.pump(const Duration(milliseconds: 700));
    final figureAt700 = _figureOpacity(tester);

    expect(
      figureAt700,
      greaterThan(0),
      reason: 'the figure is well under way by 700ms',
    );
    expect(
      _todayOpacity(tester),
      lessThan(figureAt700),
      reason: 'today\'s stamp must still be behind the figure at this point',
    );

    await tester.pumpAndSettle();
    expect(_todayOpacity(tester), closeTo(1, 0.001));
    expect(_figureOpacity(tester), closeTo(1, 0.001));
  });

  testWidgets('the flame ignites: dormant, then lit', (tester) async {
    // Duolingo's first beat, and it is the streak page's own rule animated rather than a new
    // idea: `_Hero` already tints the flame `secondaryText` while the day is open and `flame`
    // once it is in. Here that transition is the event.
    await _pump(tester, streak: 12);
    await tester.pump();

    // On the very first frame it has not caught.
    expect(
      _flameColour(tester),
      isNot(kCandleFlame),
      reason: 'a flame that starts lit has nothing to ignite',
    );
    expect(
      _flameColour(tester).a,
      lessThan(1),
      reason: 'dormant is the copy\'s own brown, most of the way out',
    );

    await tester.pumpAndSettle();
    expect(_flameColour(tester), kCandleFlame);
  });

  testWidgets('sparks fly, and nothing is left on screen afterwards', (
    tester,
  ) async {
    // The one beat with no precedent in the app, so it is hand-painted — and the thing that
    // makes a hand-painted burst safe is that it *ends*. A painter still drawing at rest would
    // be an idle repaint on a screen a reader opens nightly.
    await _pump(tester, streak: 12);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CustomPaint), findsWidgets);
    final mid = find
        .byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString().contains('Spark'),
        )
        .evaluate()
        .length;
    expect(mid, 1, reason: 'the burst is in the air mid-beat');

    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString().contains('Spark'),
      ),
      findsNothing,
      reason: 'at rest the painter is gone, not merely transparent',
    );
  });

  testWidgets('the flame is given a drive it can actually use', (tester) async {
    // **The artboard's `Ignite` timeline is *seeked* by this value, so its shape over time is
    // what decides which part of the choreography a reader sees** -- and the first curve tried
    // here wasted most of it. `easeOutBack` crossed 0 -> 1 in about 185ms and then overshot to
    // 1.087; seeking past the last frame clamps, so 20 of the window's 32 frames were the same
    // held frame and the whole sequence played in three. Rendered at the real timing, a reader
    // saw the flame appear rather than a book falling open.
    //
    // The drive is `linear` now, because the easing lives in the timeline where it can be
    // watched (`rive rive/streak_flame`, or the Rive Editor). What is pinned here is what a
    // linear drive is *for*: full range, no overshoot, and still moving in the middle. Both
    // failure modes are silent -- an overshoot is discarded by the runtime with no error, and a
    // front-loaded curve still animates, it just animates somewhere nobody can see.
    await _pump(tester, streak: 12);
    await tester.pump();

    Animation<double> drive() =>
        tester.widget<StreakFlame>(find.byType(StreakFlame)).progress;

    final samples = <int, double>{};
    for (var ms = 0; ms <= 1500; ms += 20) {
      samples[ms] = drive().value;
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      samples.values.every((v) => v <= 1.0),
      isTrue,
      reason:
          'a value past 1 is clamped to the last frame and thrown away: '
          'peak was ${samples.values.reduce((a, b) => a > b ? a : b)}',
    );

    // The shut book has to register before it opens. A curve that is already half way through
    // at 100ms has spent the opening inside two frames.
    expect(
      samples[100]!,
      lessThan(0.25),
      reason: 'the book is still shutting at 100ms, not already open',
    );

    // And it must still be moving well into the window rather than parked at the end of it.
    expect(
      samples[400]!,
      inExclusiveRange(0.25, 1.0),
      reason:
          'at 400ms the sequence is mid-flight, neither finished nor stalled',
    );

    await tester.pumpAndSettle();
    expect(drive().value, 1, reason: 'and it lands on the resting pose');
  });

  testWidgets('the flame keeps living after the ignition lands', (
    tester,
  ) async {
    // **The one beat on this screen whose finished state is motion.** Everything else comes to
    // rest, and the comment on `_beats` used to promise that the flame did too -- there was no
    // idle loop at all, and a flame that freezes the instant it arrives reads as a decal of a
    // flame. So this pins the reversal rather than trusting the prose: the liveness drive must
    // be silent while the book is still opening, and fully mixed in by the end.
    //
    // `StreakFlame` is what forces it back to zero under reduced motion; that gate cannot live
    // here, because the gate below jumps the controller to 1 and 1 *is* the moving state.
    // `streak_flame_test.dart` covers it.
    await _pump(tester, streak: 12);
    await tester.pump();

    Animation<double> liveness() =>
        tester.widget<StreakFlame>(find.byType(StreakFlame)).liveness;

    final samples = <int, double>{};
    for (var ms = 0; ms <= 1500; ms += 20) {
      samples[ms] = liveness().value;
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      samples[400],
      0,
      reason: 'nothing to flicker while the book is still opening',
    );
    expect(
      samples[900]!,
      inExclusiveRange(0, 1),
      reason:
          'it ramps in over the ignition\'s settle rather than switching on',
    );

    await tester.pumpAndSettle();
    expect(liveness().value, 1, reason: 'and the flame is left alive');
  });

  testWidgets('the counter rolls from the previous number, and never past the run', (
    tester,
  ) async {
    // **The figure a reader came for is not `12`, it is `11` becoming `12`.** A number that is
    // simply present says nothing happened tonight. And it must never read 13: the spring is
    // on where the figure sits, not on what it says, because this is the one place on the
    // screen that states a fact.
    await _pump(tester, streak: 12);
    await tester.pump();

    expect(_figureValue(tester), 11, reason: 'it starts on last night\'s run');

    final seen = <int>{};
    for (var ms = 0; ms < 1500; ms += 20) {
      await tester.pump(const Duration(milliseconds: 20));
      seen.add(_figureValue(tester));
    }
    expect(
      seen.where((v) => v > 12),
      isEmpty,
      reason: 'an overshoot on the value would print a day that was not earned',
    );
    expect(seen.contains(11) && seen.contains(12), isTrue);

    await tester.pumpAndSettle();
    expect(_figureValue(tester), 12);
  });

  testWidgets('day one counts up from nothing rather than from minus one', (
    tester,
  ) async {
    await _pump(tester, streak: 1);
    await tester.pump();
    expect(_figureValue(tester), 0);
    await tester.pumpAndSettle();
    expect(_figureValue(tester), 1);
  });

  testWidgets('the gleam crosses the flame and then leaves it alone', (
    tester,
  ) async {
    // A `ShaderMask` composites its child into a saved layer, so leaving one in place forever
    // would be a permanent cost for a 380ms effect. It exists only while the band is on the
    // glyph — which is also what keeps the resting frame identical to the one reduced motion
    // serves.
    await _pump(tester, streak: 12);
    await tester.pump();

    final onFlame = find.ancestor(
      of: find.byType(StreakFlameMark),
      matching: find.byType(ShaderMask),
    );
    expect(onFlame, findsNothing, reason: 'not before its beat');

    await tester.pump(const Duration(milliseconds: 800));
    expect(onFlame, findsOneWidget, reason: 'sweeping, mid-beat');

    await tester.pumpAndSettle();
    expect(onFlame, findsNothing, reason: 'and gone once it has passed');
  });

  testWidgets('today\'s cell is the one thing that arrives tilted', (
    tester,
  ) async {
    // The same hand-stamped gesture the month grid draws, so the cell that lands here and the
    // cell the reader sees behind this screen are recognisably one object.
    await _pump(tester, streak: 12, reducedMotion: true);

    final tilted = find.ancestor(
      of: find.byKey(const ValueKey('streak-week-today')),
      matching: find.byType(Transform),
    );
    expect(tilted, findsWidgets);
  });

  testWidgets('reduced motion serves the finished state, with no motion at all', (
    tester,
  ) async {
    // `value = 1` rather than a shorter `forward()`: a reader who turned animation off gets
    // the result, not a brisk version of the sequence. Asserted on the first frame, because
    // that is the only frame where a running animation and a completed one differ.
    await _pump(tester, streak: 12, reducedMotion: true);
    await tester.pump();

    // **Every new beat has to land on its resting state too**, which is the thing that makes
    // the gate cheap: the sparks and the gleam are absent at `value == 1` by construction
    // rather than by a second code path, so there is no "reduced motion" rendering to keep
    // in step with the animated one.
    expect(
      _figureValue(tester),
      12,
      reason: 'the counter has finished counting',
    );
    expect(_flameColour(tester), kCandleFlame, reason: 'the flame is lit');
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString().contains('Spark'),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byType(StreakFlameMark),
        matching: find.byType(ShaderMask),
      ),
      findsNothing,
    );

    expect(_todayOpacity(tester), closeTo(1, 0.001));
    expect(
      tester.hasRunningAnimations,
      isFalse,
      reason:
          'nothing should be ticking when the reader asked for no animation',
    );
  });

  testWidgets('the cell that just landed is lifted, not inverted', (
    tester,
  ) async {
    // **This case used to assert an inversion and the inversion no longer exists.** It was a
    // real escalation when the other six cells were `kCandleFlame` at a 10% wash: the closing
    // one went solid with a reversed-out letter. The row rebuild made every read day solid
    // and gave every one of them a reversed-out check, so there is nothing left to invert to
    // — the fill *is* the neighbours' fill. What marks this cell out is the shadow under it,
    // plus the scale overshoot and the tilt `_WeekCard` wraps it in.
    await _pump(tester, streak: 12, reducedMotion: true);

    final cell = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('streak-week-today')),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = cell.decoration as BoxDecoration;
    expect(decoration.color, ReadWeekPalette.candle.stampFill);
    expect(
      decoration.boxShadow,
      isNotEmpty,
      reason: 'the lift is the whole of what separates it from its neighbours',
    );
  });

  testWidgets('day one gets its own line rather than a countdown', (
    tester,
  ) async {
    // A countdown is a discouraging thing to read on the day someone started, which is
    // the one day the copy has to be kind — so day one keeps its own line even when
    // there is an older record to chase. **A run of 1 after a lapse is day one**, because
    // that is what the figure above it says; the guard is checked before `chasing` on
    // purpose, so a reader coming back reads the same line as a reader starting.
    await _pump(tester, streak: 1, best: 30, reducedMotion: true);

    expect(find.text('One day in!'), findsOneWidget);
    expect(find.textContaining('more days'), findsNothing);
    expect(find.text('day streak'), findsOneWidget);
  });

  testWidgets('short of the record, it names the distance left to beat it', (
    tester,
  ) async {
    // **To beat a best of 30 from 12 you need 19 more days, not 18.** The old copy
    // counted the distance to *reach* a milestone; a record has to be passed, not met.
    await _pump(tester, streak: 12, best: 30, reducedMotion: true);
    expect(find.text('19 more days to beat your best.'), findsOneWidget);
  });

  testWidgets('a record is beaten rather than matched', (tester) async {
    // **The distance is `best + 1 - streak`, so its floor is 2, not 1.** Reaching a best
    // of 30 on day 30 only matches it. That is also why the string has no `=1` case:
    // the bar only shows while `best > streak`, so `best >= streak + 1` and the countdown
    // can never say "1 more day".
    await _pump(tester, streak: 30, best: 31, reducedMotion: true);
    expect(find.text('2 more days to beat your best.'), findsOneWidget);

    // One day earlier is 3, never 2 — pinning the arithmetic rather than one value.
    await _pump(tester, streak: 29, best: 31, reducedMotion: true);
    expect(find.text('3 more days to beat your best.'), findsOneWidget);
  });

  testWidgets('the run being the record is the reward', (tester) async {
    await _pump(tester, streak: 30, best: 30, reducedMotion: true);
    expect(
      find.text('Your longest run yet.'),
      findsOneWidget,
      reason:
          'longestReadingRun counts the run in progress, so streak == best is the '
          'record being set rather than a tie one day short of it',
    );

    await _pump(tester, streak: 31, best: 31, reducedMotion: true);
    expect(find.text('Your longest run yet.'), findsOneWidget);
  });

  testWidgets('the span ladder is here every night, record or not', (
    tester,
  ) async {
    // **This case used to assert that a progress bar disappeared on a record night, and
    // that bar no longer exists.** `_MilestoneBar` measured `streak` against `best + 1`
    // and was hidden once the run *was* the record, on the reasoning that a bar toward a
    // target already passed is furniture. That reasoning was sound about that bar and is
    // exactly why `StreakSpanTrack` replaced it: a ladder of named spans has somewhere
    // further to go on every night there is, so it never has to vanish, and the night the
    // record is set is the night it has the most to say.
    for (final pair in [
      [9, 20],
      [9, 9],
      [1, 1],
      [400, 400],
    ]) {
      await _pump(tester, streak: pair[0], best: pair[1], reducedMotion: true);
      expect(
        find.byType(StreakSpanTrack),
        findsOneWidget,
        reason: 'streak ${pair[0]} of a best of ${pair[1]}',
      );
    }
  });

  testWidgets('the ladder measures tonight\'s run, not the record', (
    tester,
  ) async {
    // **Which of the two numbers it reads is the whole difference from the bar it
    // replaced, and it reads `streak`, not `best`.** It read `best` for one round, on the
    // reasoning that the record never falls and so was the more honest number for a rail.
    // That was backwards: right after a lapse, when `streak` has just reset to 1, a rail
    // filled from `best` sits most of the way to a rung the *new* run has no claim on —
    // and nothing on screen said the fill was the old run rather than this one. The record
    // still has a home: `streakCelebrationChasing`/`streakCelebrationRecord`, in words,
    // directly under the track.
    await _pump(tester, streak: 2, best: 40, reducedMotion: true);

    final track = tester.widget<StreakSpanTrack>(find.byType(StreakSpanTrack));
    expect(track.streak, 2);
    expect(
      StreakSpanTrack.fillFraction(track.streak, track.rungs),
      closeTo(0.25 * 2 / 7, 1e-9),
      reason: '2 days is two sevenths of the way to the first rung',
    );
  });

  testWidgets('the four rungs are the localised spans, in order', (
    tester,
  ) async {
    // The rungs are built here rather than inside the track, because the track draws a
    // ladder and has no opinion about what a rung is called — which is what lets `ko` say
    // `1주` with no second code path. Pinned so a reordering or a dropped rung shows up.
    await _pump(tester, streak: 9, best: 9, reducedMotion: true);

    final track = tester.widget<StreakSpanTrack>(find.byType(StreakSpanTrack));
    expect(track.rungs.map((r) => r.days).toList(), [7, 30, 100, 365]);
    expect(track.rungs.map((r) => r.label).toList(), [
      '1 week',
      '1 month',
      '100 days',
      '1 year',
    ]);
  });

  testWidgets('the ladder does not fill with the beat, only arrive with it', (
    tester,
  ) async {
    // **The bar this replaced filled as the beat ran, and that would be a lie here.** The
    // bar measured tonight's run, so growing it was the news. The ladder measures `best`,
    // which on any night short of a record did not move — so the reveal is the `_Rise`'s
    // fade and slide, and the fill is whatever it already was. Asserted by taking the
    // fill's width mid-sequence and again at rest: same number, while the opacity above
    // it is still climbing.
    await _pump(tester, streak: 5, best: 40);
    await tester.pump(const Duration(milliseconds: 1400));

    Size fillSize() => tester.getSize(
      find.descendant(
        of: find.byType(StreakSpanTrack),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == kCandleFlame,
        ),
      ),
    );

    final midway = fillSize();
    await tester.pumpAndSettle();
    expect(fillSize().width, closeTo(midway.width, 0.01));
    expect(
      midway.width,
      greaterThan(0),
      reason: 'and it was already drawn, rather than starting at nothing',
    );
  });

  testWidgets('no copy anywhere still promises a seal', (tester) async {
    // `kStreakMilestones` used to drive the caption as "the 7-day seal", naming a reward
    // with no award path anywhere in `lib/` and borrowing the noun from the Library
    // Card's logo emboss, which every card carries regardless of any streak.
    for (final pair in const [
      [1, 1],
      [12, 30],
      [30, 30],
      [400, 400],
    ]) {
      await _pump(tester, streak: pair[0], best: pair[1], reducedMotion: true);
      expect(
        find.textContaining('seal'),
        findsNothing,
        reason: 'streak ${pair[0]}, best ${pair[1]}',
      );
    }
  });

  testWidgets('the way out is the only call to action', (tester) async {
    // Deliberately absent: confetti, a sound, a share prompt, a second button. The reward for
    // reading is the reading; this is a receipt with good manners.
    var done = false;
    await _pump(
      tester,
      streak: 12,
      reducedMotion: true,
      onDone: () => done = true,
    );

    expect(find.byType(ElevatedButton), findsOneWidget);
    await tester.tap(find.text('Keep it going'));
    expect(done, isTrue);
  });

  testWidgets('it is in the library\'s candlelight, not the brand\'s green', (
    tester,
  ) async {
    // Duolingo's green is *this app's brand colour* and means something else on every other
    // screen, so a celebration in it would read as chrome rather than as a reward.
    await _pump(tester, streak: 12, reducedMotion: true);

    final ground = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(StreakCelebration),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(
      ground.color,
      kStreakCelebrationGround,
      reason:
          'white, and the constant rather than a literal so this and the '
          "flame's golden cannot disagree about what the screen stands on",
    );
    expect(
      tester.widget<StreakFlameMark>(find.byType(StreakFlameMark)).color,
      kCandleFlame,
    );
  });

  testWidgets('it lays out on a phone, at the size it is presented at', (
    tester,
  ) async {
    // This screen is a column of fixed-height pieces between two `Spacer`s, which is the
    // shape that overflows first on a short phone. 393×852 is the frame the drawings use,
    // and is also `_pump`'s default now — stated here anyway, because this case is about
    // the size rather than merely at it.
    //
    // The longest copy this screen can carry: a three-digit run, so the figure is widest,
    // and a record still being chased, so the subtitle is a countdown rather than the
    // shorter record line.
    await _pump(
      tester,
      streak: 400,
      best: 500,
      reducedMotion: true,
      surface: const Size(393, 852),
    );

    expect(find.text('400'), findsOneWidget);
    expect(find.text('Keep it going'), findsOneWidget);
  });

  testWidgets('it lays out on the shortest phone it has to', (tester) async {
    // **375×667 is the case the flame's size is actually spent against.** The flame's box
    // went 152 → 252 so the Rive drawing would reach the screen three times taller (see
    // `StreakFlame.stageSize`), and 100 points of that comes straight out of the two
    // `Spacer`s. At 393×852 there is slack to absorb it and the case above passes either
    // way; this is an iPhone SE, which is the smallest thing the column has to survive, and
    // before the flame grew **nothing in the suite set a surface short enough to fail**.
    //
    // A `RenderFlex` overflow throws rather than merely painting a stripe, so the assertions
    // below are almost incidental — pumping at this size at all is the test.
    // **And it is now the binding case for more than the flame.** The span ladder moved
    // here from the streak page and cost about 30 points net over the progress bar it
    // replaced, which leaves roughly 40 points of slack at this size. Anything else added
    // to this column should be measured here first.
    //
    // **The box is no longer square, and this case is where that gets checked.** The artboard
    // went 300×300 → 360×300 to give the burst spray somewhere to be seen, so the box is
    // 302.4 × 252 (see `StreakFlame.artboardAspect`). The height is what the vertical slack
    // above is about and it did not move; what is new is the *width*, and 375 is the phone
    // where that could bite — the celebration pads itself 28 points each side, so the budget
    // here is 319 and this leaves 17. A squeeze would show up as a width below 302.4 rather
    // than as an overflow, which is why this asserts the size instead of trusting the pump.
    await _pump(
      tester,
      streak: 400,
      reducedMotion: true,
      surface: const Size(375, 667),
    );

    expect(find.text('400'), findsOneWidget);
    expect(
      tester.getSize(find.byType(StreakFlame)),
      Size(
        StreakFlame.stageWidthFor(StreakFlame.stageSize),
        StreakFlame.stageSize,
      ),
      reason: 'the flame must get its whole box, not a squeezed one',
    );
  });

  group('the span ladder', () {
    // **Nothing in `lib/` reads these any more.** They drove the bar and the caption as
    // "the 7-day seal"; both now measure the reader's own record, because there was no
    // seal to earn. The ladder is kept because it is where making these spans real would
    // start, so it stays covered rather than rotting untested.
    test('names the next span above the run', () {
      expect(streakMilestoneTarget(1), 7);
      expect(streakMilestoneTarget(7), 30);
      expect(streakMilestoneTarget(29), 30);
      expect(streakMilestoneTarget(30), 100);
    });

    test('runs out rather than inventing a rung nobody set', () {
      expect(streakMilestoneTarget(kStreakMilestones.last), isNull);
      expect(streakMilestoneTarget(10000), isNull);
    });

    test('the rungs are ascending, which any progress arithmetic assumes', () {
      // A fraction of a target is only under 1 while the ladder is sorted. An
      // out-of-order rung would fill a bar past its own track.
      for (var i = 1; i < kStreakMilestones.length; i++) {
        expect(kStreakMilestones[i], greaterThan(kStreakMilestones[i - 1]));
      }
    });
  });
}
