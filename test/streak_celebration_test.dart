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
import 'package:bookworm_friends/ui/widgets/reading_streak_chip.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_celebration.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_flame.dart';

import 'still_streak_flame.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int streak,
  List<bool>? week,
  bool reducedMotion = false,
  VoidCallback? onDone,
}) async {
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
Color _flameColour(WidgetTester tester) =>
    tester.widget<Icon>(find.byIcon(kReadingStreakIcon)).color!;

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
    expect(find.text('days in a row'), findsOneWidget);
    // The chip's own constant, not a second flame that happens to look like it. The flame
    // names the *run*, which is why the week row under it draws stamps.
    expect(find.byIcon(kReadingStreakIcon), findsOneWidget);
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
      of: find.byIcon(kReadingStreakIcon),
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
        of: find.byIcon(kReadingStreakIcon),
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

  testWidgets('the cell that just landed is inverted, not merely stamped', (
    tester,
  ) async {
    // `.lweek s.fresh` in the record. The other six cells on this screen are already the
    // candle's accent at a wash, so a seventh in the same wash is not somewhere for the eye
    // to land — which is the whole point of the closing beat. It is solid, reversed out, and
    // lifted off the card by its own shadow.
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
    expect(decoration.color, ReadWeekPalette.candle.freshFill);
    expect(decoration.boxShadow, isNotEmpty);
    expect(
      decoration.color,
      isNot(ReadWeekPalette.candle.stampFill),
      reason: 'the inversion is what separates it from its neighbours',
    );
  });

  testWidgets('day one gets its own line rather than a countdown', (
    tester,
  ) async {
    // "29 more days to the 30-day seal" is a discouraging thing to read on the night someone
    // started, which is the one night the copy has to be kind.
    await _pump(tester, streak: 1, reducedMotion: true);

    expect(find.textContaining('Day one'), findsOneWidget);
    expect(find.textContaining('more days'), findsNothing);
    expect(find.text('day in a row'), findsOneWidget);
  });

  testWidgets('otherwise it names the next seal and the distance to it', (
    tester,
  ) async {
    await _pump(tester, streak: 12, reducedMotion: true);
    expect(find.text('18 more days to the 30-day seal.'), findsOneWidget);
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
    expect(ground.color, kCandleGlow);
    expect(
      tester.widget<Icon>(find.byIcon(kReadingStreakIcon)).color,
      kCandleFlame,
    );
  });

  testWidgets('it lays out on a phone, at the size it is presented at', (
    tester,
  ) async {
    // This screen is a column of fixed-height pieces between two `Spacer`s, which is the
    // shape that overflows first on a short phone. 393×852 is the frame the drawings use; the
    // default 800×600 test surface would not catch it.
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The longest copy this screen can carry: a three-digit run past the last seal, so the
    // figure is widest and the subtitle is the "seal earned" line rather than a countdown.
    await _pump(tester, streak: 400, reducedMotion: true);

    expect(find.text('400'), findsOneWidget);
    expect(find.text('Keep it going'), findsOneWidget);
  });

  group('the milestone ladder', () {
    test('names the next seal above the run', () {
      expect(streakMilestoneTarget(1), 7);
      expect(streakMilestoneTarget(7), 30);
      expect(streakMilestoneTarget(29), 30);
      expect(streakMilestoneTarget(30), 100);
    });

    test('runs out rather than inventing a seal nobody set', () {
      // Past the last rung there is no next target, and the copy says the seal is earned
      // instead of counting toward a number the ladder does not have.
      expect(streakMilestoneTarget(kStreakMilestones.last), isNull);
      expect(streakMilestoneTarget(10000), isNull);
    });

    test('the rungs are ascending, which the bar\'s arithmetic assumes', () {
      // `streak / target` is only a fraction under 1 while the ladder is sorted. An
      // out-of-order rung would fill the bar past its track.
      for (var i = 1; i < kStreakMilestones.length; i++) {
        expect(kStreakMilestones[i], greaterThan(kStreakMilestones[i - 1]));
      }
    });
  });
}
