/// The month grid, and specifically the `stamp-double` die it draws.
///
/// **What these cases are for.** Eighteen other weights were drawn before this one won
/// (`docs/mockups/streaks/index.html`, groups (f) through (f+++)), and four of the die's
/// properties are the reason it won rather than incidental to how it looks: the colour is
/// on a per-day *mark* and not on a run band, the tilt is *derived from the day* so the
/// month is stable across renders, the die itself is *seeded from the day* for the same
/// reason, and the geometry is *derived from the width* so the grid cannot drift from the
/// card it sits in. A test that only checked "thirty numbers appear" would pass for any
/// of the nineteen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_calendar_month.dart';

/// September 2026: 30 days, starting on a Tuesday. Fixed rather than `now`, so a case
/// cannot pass in one month and fail in the next.
final _month = DateTime(2026, 9);
final _today = DateTime(2026, 9, 17);

Future<void> _pump(
  WidgetTester tester, {
  required Map<DateTime, Color?> marks,
  DateTime? today,
  double width = 325,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ReadCalendarMonth(
              month: _month,
              marks: marks,
              today: today ?? _today,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _stampFinder(int day) => find.byKey(ValueKey('streak-stamp-$day'));

/// The die drawn for [day], or null when that day carries none.
///
/// The mark is a `CustomPaint` rather than a `DecoratedBox` because a `Border` cannot
/// express a rim that is not quite round — see the painter's own note.
ReadCalendarStampDie? _stamp(WidgetTester tester, int day) {
  final found = _stampFinder(day);
  if (found.evaluate().isEmpty) return null;
  return tester.widget<CustomPaint>(found).painter as ReadCalendarStampDie;
}

void main() {
  testWidgets('a recorded day carries a stamp and an unrecorded one does not', (
    tester,
  ) async {
    await _pump(tester, marks: {DateTime(2026, 9, 3): const Color(0xFF3366CC)});

    expect(_stamp(tester, 3), isNotNull);
    expect(
      _stamp(tester, 4),
      isNull,
      reason: 'a day with no row must draw no mark at all',
    );
    // The numeral is there either way: the grid is a month, not a list of the nights in it.
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('the mark carries the book\'s colour, at the die\'s own strength', (
    tester,
  ) async {
    // The whole payload of the `book_id` decision: the month stops being a tally and
    // becomes a record of *what* was read. A die in a fixed accent would draw the same
    // month for two readers who read nothing alike.
    const jacket = Color(0xFF3366CC);
    await _pump(tester, marks: {DateTime(2026, 9, 3): jacket});

    final ink = _stamp(tester, 3)!.colour;
    expect(ink.r, closeTo(jacket.r, 1e-6));
    expect(ink.g, closeTo(jacket.g, 1e-6));
    expect(ink.b, closeTo(jacket.b, 1e-6));
    // **Two thirds, not the retired patch's fifth, and the difference is not taste.** A
    // patch spent a whole cell of area on the colour; two hairline bands spend almost
    // none, so at 0.22 a ring is a smudge. The numeral survives on top regardless
    // because the bands run *around* the digit rather than under it.
    expect(ink.a, closeTo(kReadCalendarStampAlpha, 1e-6));
    expect(
      kReadCalendarStampAlpha,
      greaterThan(0.22),
      reason: 'a band cannot carry a fill\'s alpha and stay visible',
    );
  });

  testWidgets('the tilt is derived from the day, so a re-render cannot reshuffle it', (
    tester,
  ) async {
    // **The hedge against a mannerism.** A random rake would make the month reshuffle on
    // every rebuild: a reviewer could not tell a layout change from a re-roll, and a golden
    // could not exist. Taken from the day number, the 14th is always raked the same way.
    await _pump(
      tester,
      marks: {for (var d = 1; d <= 6; d++) DateTime(2026, 9, d): null},
    );

    double angleOf(int day) {
      final rotation = find.ancestor(
        of: _stampFinder(day),
        matching: find.byType(Transform),
      );
      final matrix = tester.widget<Transform>(rotation.first).transform;
      return math.atan2(matrix.entry(1, 0), matrix.entry(0, 0));
    }

    for (var day = 1; day <= 6; day++) {
      expect(
        angleOf(day),
        closeTo(readCalendarPatchTilt(day) * math.pi / 180, 1e-9),
        reason: 'day $day must be raked by the rule, not by chance',
      );
    }

    // And no two neighbours line up, which is the property that makes a run read as
    // stamps pressed on by hand rather than as a bar from a chart.
    for (var day = 1; day < 6; day++) {
      expect(readCalendarPatchTilt(day), isNot(readCalendarPatchTilt(day + 1)));
    }
  });

  testWidgets('the die itself is seeded from the day, and there are three of them', (
    tester,
  ) async {
    // **The same stability argument as the tilt, one level down.** The rim's wobble, its
    // breathing width and its pressure nicks all come from a `Random` seeded by `day % 3`,
    // so a die is identical across rebuilds and a screenshot can be compared with the last
    // one. Asserted the only way a painter allows: paint the same day twice and require
    // the two paintings to be equal, then require neighbours to differ.
    await _pump(
      tester,
      marks: {for (var d = 1; d <= 6; d++) DateTime(2026, 9, d): null},
    );
    final first = [for (var d = 1; d <= 6; d++) _stamp(tester, d)!];

    await _pump(
      tester,
      marks: {for (var d = 1; d <= 6; d++) DateTime(2026, 9, d): null},
    );
    for (var i = 0; i < 6; i++) {
      expect(
        _stamp(tester, i + 1)!.shouldRepaint(first[i]),
        isFalse,
        reason:
            'day ${i + 1} must press the same die on every paint, or it cannot be '
            'screenshotted',
      );
    }

    // Three dies rather than thirty: enough that neighbours differ, few enough that the
    // month still reads as one set of marks rather than as noise.
    expect(
      _stamp(tester, 1)!.shouldRepaint(first[1]),
      isTrue,
      reason: 'adjacent days must not press the identical die',
    );
    expect(
      _stamp(tester, 4)!.day % 3,
      _stamp(tester, 1)!.day % 3,
      reason:
          'the die repeats every third day, so day 4 and day 1 share a rim and '
          'differ only in rake',
    );
  });

  test('the rake stays small enough to read as a stamp that missed square', () {
    // Past about 6° a run stops reading as a misaligned stamp and starts reading as a
    // mistake. Asserted over a whole month rather than at a couple of samples, because the
    // expression is modular and it is the extremes that would bite.
    for (var day = 1; day <= 31; day++) {
      expect(readCalendarPatchTilt(day).abs(), lessThanOrEqualTo(4));
    }
  });

  testWidgets('a night with no attribution still draws, in neutral ink', (
    tester,
  ) async {
    // A row written before the `book_id` column existed, or a book since deleted. The night
    // happened and the streak counts it, so a hole in the month would be a lie — and it
    // would make the grid disagree with the figure above it.
    await _pump(tester, marks: {DateTime(2026, 9, 3): null});

    final ink = _stamp(tester, 3)!.colour;
    final neutral = AppTheme.light.extension<AppColors>()!.secondaryText;
    expect(ink.r, closeTo(neutral.r, 1e-6));
    expect(ink.g, closeTo(neutral.g, 1e-6));
  });

  testWidgets('today draws a rule until it is recorded, and a stamp after', (
    tester,
  ) async {
    // Duolingo's own grammar, and the reason for it: today is not an achievement yet and
    // must not be drawn as one.
    await _pump(tester, marks: const {});
    expect(find.byKey(const ValueKey('streak-today-rule')), findsOneWidget);
    expect(_stamp(tester, 17), isNull);

    await _pump(tester, marks: {_today: const Color(0xFF3366CC)});
    expect(
      find.byKey(const ValueKey('streak-today-rule')),
      findsNothing,
      reason:
          'two marks for one day is the disagreement this grid must not draw',
    );
    expect(_stamp(tester, 17), isNotNull);
  });

  testWidgets('there is no run capsule and no connecting thread', (
    tester,
  ) async {
    // **The property that separates the mark tones from every band tone.** The
    // misalignments are the continuity; a ligature under them says the same thing twice and
    // puts a hard geometric shape beneath a deliberately hand-made one. Asserted by
    // counting: a run of five days is five marks, not five marks and a joining bar.
    await _pump(
      tester,
      marks: {for (var d = 10; d <= 14; d++) DateTime(2026, 9, d): null},
    );

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('streak-stamp-'),
      ),
      findsNWidgets(5),
    );
  });

  testWidgets('the die is square, so it prints a ring rather than an oval', (
    tester,
  ) async {
    // **The shape is the mark.** `.cal.tone-stamp-double .cmk` is a point in on all four
    // sides, and that uniformity matters here in a way it did not for the patch it
    // replaced: the retired block was deliberately low and wide, but a ring cropped to a
    // non-square box prints an oval — which is a *different* die in the record
    // (`cp-f-stamp-oval`) rather than this one pressed badly.
    await _pump(tester, marks: {DateTime(2026, 9, 3): null}, width: 325);

    final cell = (325 - kReadCalendarGap * 6) / 7;
    final size = tester.getSize(_stampFinder(3));
    expect(size.width, closeTo(cell - 2, 0.01));
    expect(size.height, closeTo(cell - 2, 0.01));
    expect(
      size.width / size.height,
      closeTo(1, 0.001),
      reason:
          'an unsquare box would print an oval, which is another frame\'s die',
    );
    expect(
      kReadCalendarStampInset,
      const EdgeInsets.all(1),
      reason: 'the die nearly touches its neighbour; that near-miss is the run',
    );
  });

  testWidgets('a day that went by unrecorded carries a hollow dot', (
    tester,
  ) async {
    // **The two states the grid used to draw identically.** A day before today with nothing
    // on it and a day next week were both a plain numeral, so the one thing this grid exists
    // to show — where the thread broke — could only be found by counting. A dot rather than
    // a cross or a colour: the month is a record, not a report card.
    await _pump(tester, marks: {DateTime(2026, 9, 16): null});

    expect(find.byKey(const ValueKey('streak-gap-15')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('streak-gap-16')),
      findsNothing,
      reason: 'the 16th was read',
    );
    expect(
      find.byKey(const ValueKey('streak-gap-17')),
      findsNothing,
      reason: 'today is not a day you failed to record; it has its own rule',
    );
    expect(
      find.byKey(const ValueKey('streak-gap-18')),
      findsNothing,
      reason: 'tomorrow has not happened',
    );

    // Hollow, and in a hairline rather than an ink: it marks the gap without weighing more
    // than the days that were read.
    final dot = tester.widget<Container>(
      find.byKey(const ValueKey('streak-gap-15')),
    );
    final decoration = dot.decoration as BoxDecoration;
    expect(decoration.color, isNull);
    expect(decoration.shape, BoxShape.circle);
  });

  testWidgets(
    'the weekend columns are washed, behind the marks rather than over them',
    (tester) async {
      // One box per column behind the whole grid, not one per cell: painted per cell it would
      // sit over the patches and a run would appear to change colour on a Saturday — the
      // record's own note. Its job is to give the month a rhythm to scan against.
      await _pump(tester, marks: const {}, width: 325);

      // An en locale's week starts on Sunday, so the weekend is the first column and the last.
      expect(find.byKey(const ValueKey('streak-weekend-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('streak-weekend-6')), findsOneWidget);
      expect(find.byKey(const ValueKey('streak-weekend-3')), findsNothing);

      final wash = tester.getRect(
        find.byKey(const ValueKey('streak-weekend-0')),
      );
      final cell = (325 - kReadCalendarGap * 6) / 7;
      expect(wash.width, closeTo(cell, 0.01));
      expect(
        wash.height,
        greaterThan(cell * 4),
        reason: 'it runs the height of the grid, not of one cell',
      );
    },
  );

  testWidgets('today\'s rule is the warm hue, not the brand green', (
    tester,
  ) async {
    // **Two reversals, stacked.** It shipped in `brandFill` on the reasoning that green is
    // how the app marks its own things; a warm hue is the one thing an all-green palette
    // does not already spend, and the run above this grid is already drawn in it. A green
    // rule also competes with a green patch on any day whose book has a green jacket, which
    // is the case the record's amber avoids. Then the hue itself moved from `colors.flame`
    // #B54708 to `kCandleFlame` #F2A93F, on instruction, so the month matches the flame
    // above it rather than being the one rust accent on an amber page.
    await _pump(tester, marks: const {});

    final rule = tester.widget<Container>(
      find.byKey(const ValueKey('streak-today-rule')),
    );
    expect((rule.decoration as BoxDecoration).color, kCandleFlame);
    expect(
      tester.widget<Text>(find.text('17')).style!.color,
      kCandleFlame,
      reason: 'the numeral goes with its rule',
    );
  });

  testWidgets('cells are square and derived from the width they are given', (
    tester,
  ) async {
    // Seven cells and six gaps share the box. Derived rather than typed, so the grid cannot
    // come to disagree with a caller that changes its padding — which is the defect a
    // constant cell size produces the first time someone does.
    await _pump(tester, marks: const {}, width: 325);

    final cell = (325 - kReadCalendarGap * 6) / 7;
    final box = tester.getSize(find.text('15').hitTestable().first);
    expect(box.width, lessThanOrEqualTo(cell));

    // Measured on the cell rather than the numeral: the numeral is text and sizes to itself.
    // Centres, not left edges — a header Text fills its cell while a numeral is centred in
    // one, so their left edges differ by the centring and only their centres agree.
    final first = tester.getCenter(find.text('1'));
    final second = tester.getCenter(find.text('2'));
    expect(second.dx - first.dx, closeTo(cell + kReadCalendarGap, 0.01));
  });

  testWidgets('the 1st lands in the column its weekday names', (tester) async {
    // September 2026 starts on a Tuesday, so under an en locale's Sunday-first week there
    // are two empty leading cells. Off-by-one here would shift the whole month and every
    // patch with it, which is a bug no colour check would notice.
    await _pump(tester, marks: const {});

    // Centres rather than left edges, for the reason above: the weekday header fills its
    // cell and the numeral is centred in one, so only their centres are comparable — and
    // both centres are the cell's own.
    final sunday = tester.getCenter(find.text('S').first).dx;
    final firstOfMonth = tester.getCenter(find.text('1')).dx;
    final cellStep = (325 - kReadCalendarGap * 6) / 7 + kReadCalendarGap;
    expect(firstOfMonth - sunday, closeTo(cellStep * 2, 0.01));
  });

  testWidgets('a month is drawn to its own length, not to a fixed six rows', (
    tester,
  ) async {
    await _pump(tester, marks: const {});
    expect(find.text('30'), findsOneWidget);
    expect(
      find.text('31'),
      findsNothing,
      reason:
          'September has 30 days; a 31st cell would be a day that does not exist',
    );
  });
}
