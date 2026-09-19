/// The celebration, and the five things it does in order.
///
/// **What matters here is the stagger and the gate**, not the look. The sequence is ordered
/// so the eye ends on the thing that changed — today's cell, stamping in last — rather than
/// on the total, and a reader who has asked the system to stop animating must get the
/// *finished* state rather than a faster version of it. Both are easy to break silently: a
/// reordered interval still animates, and a missing gate still looks fine on a machine
/// nobody has configured for reduced motion.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/reading_streak_chip.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_celebration.dart';

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

void main() {
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
    await tester.pump(const Duration(milliseconds: 620));
    final figureAt620 = tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('12'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    expect(
      figureAt620,
      greaterThan(0),
      reason: 'the figure is well under way by 620ms',
    );
    expect(
      _todayOpacity(tester),
      lessThan(figureAt620),
      reason: 'today\'s stamp must still be behind the figure at this point',
    );

    await tester.pumpAndSettle();
    expect(_todayOpacity(tester), closeTo(1, 0.001));
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
