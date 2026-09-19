/// The week row, drawn once for two surfaces.
///
/// **Why it is worth its own file.** This widget exists because the streak page and the
/// celebration were about to draw the same seven days twice: once in the app's ink on paper
/// and once in candlelight on cream. Two copies is how the week the reader sees behind a
/// celebration and the week inside it come to disagree about which days are in. So the cases
/// below are mostly about the seam — that the palette is the caller's, that the rake is the
/// month grid's rule and not the cell's position, and that exactly one surface suppresses it.
///
/// **And about the shape of a cell, which this got wrong once.** The row shipped with a box
/// around all seven days and square 30pt cells; the record draws a box only where something
/// happened or is about to, and lets the seven share the width. The cases named "no box",
/// "dashed" and "share the width" are that regression, pinned.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_calendar_month.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';

/// A Thursday, so the letters are unambiguous under an en locale.
final _endingOn = DateTime(2026, 9, 17);

/// Nine roles, nine values that cannot be mistaken for each other.
///
/// Deliberately not a plausible palette: when the roles were two colours, "stamped in the
/// caller's colour" was all a test could say, and the bug — every unstamped day drawn as a
/// box — sat underneath that assertion perfectly happily.
const _palette = ReadWeekPalette(
  stampFill: Color(0x1A09BC8A),
  stampEdge: Color(0xBF067657),
  stampInk: Color(0xFF067657),
  todayEdge: Color(0x99067657),
  todayInk: Color(0xFF626A72),
  missInk: Color(0x8C626A72),
  rule: Color(0xFFE9ECEF),
  freshFill: Color(0xFF123456),
  freshInk: Color(0xFFFEDCBA),
);

/// The content width of the narrowest phone the app supports, less the page's 20pt margins.
const double _width = 353;

Future<void> _pump(
  WidgetTester tester, {
  required List<bool> days,
  bool tilt = true,
  bool freshLast = false,
  Widget Function(Widget)? decorateLast,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _width,
            child: ReadWeekRow(
              days: days,
              endingOn: _endingOn,
              palette: _palette,
              tilt: tilt,
              freshLast: freshLast,
              decorateLast: decorateLast,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The innermost [Container] the cell holding [letter] is drawn by, or null if it has none —
/// which is itself the assertion for a missed day.
BoxDecoration? _decorationOf(WidgetTester tester, String letter, {int at = 0}) {
  final containers = find.ancestor(
    of: find.text(letter).at(at),
    matching: find.byType(Container),
  );
  if (containers.evaluate().isEmpty) return null;
  return tester.widget<Container>(containers.first).decoration
      as BoxDecoration?;
}

/// The rotation applied to the cell holding [letter], in degrees.
///
/// [at] disambiguates the two 'S's and the two 'T's in an en week — which is not a nicety:
/// the first draft of the unstamped case read Saturday's tilt while asserting about Sunday.
double _tiltOf(WidgetTester tester, String letter, {int at = 0}) {
  final transforms = find.ancestor(
    of: find.text(letter).at(at),
    matching: find.byType(Transform),
  );
  if (transforms.evaluate().isEmpty) return 0;
  final m = tester.widget<Transform>(transforms.first).transform;
  return math.atan2(m.entry(1, 0), m.entry(0, 0)) * 180 / math.pi;
}

void main() {
  testWidgets('seven days, labelled from the day the week ends on', (
    tester,
  ) async {
    // Off-by-one here would label every cell with its neighbour's letter, which is a bug no
    // colour or count assertion would notice.
    await _pump(tester, days: List.filled(7, true));

    // The seven days ending Thursday 17 Sept 2026 are Fri..Thu.
    expect(find.text('F'), findsOneWidget);
    expect(find.text('S'), findsNWidgets(2));
    expect(find.text('M'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('T'), findsNWidgets(2));
  });

  testWidgets('a stamped day is a wash inside a firmer edge of the same family', (
    tester,
  ) async {
    // The palette is passed rather than read from the theme, because the celebration paints
    // its own cream ground and `context.colors` would hand it white type in dark mode.
    await _pump(tester, days: List.filled(7, true));

    final decoration = _decorationOf(tester, 'W')!;
    expect(decoration.color, _palette.stampFill);
    final edge = (decoration.border as Border).top;
    expect(edge.color, _palette.stampEdge);
    expect(
      edge.width,
      1.5,
      reason: 'the record\'s `.lweek s.on` is 1.5px, not a hairline',
    );
    expect(
      edge.color.a,
      greaterThan(decoration.color!.a),
      reason:
          'the firmer edge is what makes it a pressed mark rather than a wash',
    );
    expect(
      tester.widget<Text>(find.text('W')).style!.color,
      _palette.stampInk,
      reason: 'a stamped day is the only cell drawn in the brand colour',
    );
  });

  testWidgets('a missed day has no box at all, only the baseline it shares', (
    tester,
  ) async {
    // **The divergence this row shipped with.** A box on every day makes the strip read as
    // seven empty checkboxes and throws away the one signal that says *this one is waiting
    // for you*. The record draws an outline only where something happened or is about to.
    await _pump(
      tester,
      days: const [true, true, false, true, true, true, true],
    );

    // The second 'S' — Sunday, the missed day. The first is Saturday, which is stamped.
    final decoration = _decorationOf(tester, 'S', at: 1)!;
    expect(decoration.color, isNull, reason: 'nothing is filled in');
    final border = decoration.border as Border;
    expect(border.top, BorderSide.none);
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);
    expect(border.bottom.color, _palette.rule);
    expect(decoration.borderRadius, isNull);
  });

  testWidgets('a missed day is faint, never red', (tester) async {
    // The record notes a gap; it does not scold. A red cell on the one screen whose job is
    // encouragement would be the app telling someone off for a Thursday.
    await _pump(
      tester,
      days: const [true, true, false, true, true, true, true],
    );

    final ink = tester.widget<Text>(find.text('S').at(1)).style!.color!;
    expect(ink, _palette.missInk);
    expect(
      ink.a,
      lessThan(_palette.todayInk.a),
      reason: 'paler than the day that has not happened yet',
    );
  });

  testWidgets('today, before it is recorded, is the dashed cell', (
    tester,
  ) async {
    // `.lweek`'s own note: "Today is the dashed slot; the tap is what stamps it." It is the
    // affordance, and it is the one state the two-colour version of this widget could not
    // express at all — so an unrecorded tonight was indistinguishable from a missed Monday.
    await _pump(
      tester,
      days: const [true, true, true, true, true, true, false],
    );

    expect(
      find.byKey(const ValueKey('streak-week-dashed')),
      findsOneWidget,
      reason: 'exactly one cell invites a tap',
    );
    // Today is Thursday, the second 'T'.
    expect(_decorationOf(tester, 'T', at: 1), isNull);
    expect(
      tester.widget<Text>(find.text('T').at(1)).style!.color,
      _palette.todayInk,
    );
  });

  testWidgets('a recorded today is stamped, not dashed', (tester) async {
    await _pump(tester, days: List.filled(7, true));

    expect(find.byKey(const ValueKey('streak-week-dashed')), findsNothing);
  });

  testWidgets('freshLast inverts the closing cell', (tester) async {
    // `.lweek s.fresh` — the day that just inked in, so the eye has one thing to land on.
    // Against six neighbours already in the accent colour, a seventh in the same wash is
    // not somewhere to land, which is why this is a state and not a brighter stamp.
    await _pump(tester, days: List.filled(7, true), freshLast: true);

    final fresh = _decorationOf(tester, 'T', at: 1)!;
    expect(fresh.color, _palette.freshFill);
    expect(
      tester.widget<Text>(find.text('T').at(1)).style!.color,
      _palette.freshInk,
    );
    expect(fresh.boxShadow, isNotEmpty, reason: 'it lifts off the card');

    // And its neighbours are untouched: only the last cell inverts.
    expect(_decorationOf(tester, 'W')!.color, _palette.stampFill);
  });

  testWidgets('without freshLast the closing cell is an ordinary stamp', (
    tester,
  ) async {
    await _pump(tester, days: List.filled(7, true));

    expect(_decorationOf(tester, 'T', at: 1)!.color, _palette.stampFill);
  });

  testWidgets('the rake comes from the date, not from the cell\'s place in the row', (
    tester,
  ) async {
    // **The distinction matters once a day passes.** Taken from the index, every cell would
    // be re-raked at midnight as the days shuffled left — so a week screenshotted on Tuesday
    // and again on Wednesday would show the same days at different angles. Taken from the
    // date, a day keeps its own angle for as long as it is on screen, and it is the *same*
    // angle the month grid gives it.
    await _pump(tester, days: List.filled(7, true));

    expect(_tiltOf(tester, 'W'), closeTo(readCalendarPatchTilt(16), 1e-6));
    expect(_tiltOf(tester, 'M'), closeTo(readCalendarPatchTilt(14), 1e-6));
  });

  testWidgets('an unstamped cell is never raked', (tester) async {
    // There is nothing pressed on it to have landed crooked.
    await _pump(
      tester,
      days: const [true, true, false, true, true, true, true],
    );
    // The second 'S' — Sunday, the missed day. The first is Saturday, which is stamped.
    expect(_tiltOf(tester, 'S', at: 1), 0);
  });

  testWidgets('tilt off leaves every cell square', (tester) async {
    // The celebration's setting: exactly one cell there is allowed to arrive tilted, and six
    // already-raked neighbours would bury the one beat the sequence is built around.
    await _pump(tester, days: List.filled(7, true), tilt: false);

    for (final letter in ['F', 'M', 'W']) {
      expect(_tiltOf(tester, letter), 0);
    }
  });

  testWidgets('the last cell can be wrapped by the caller', (tester) async {
    // The hook the celebration's closing beat hangs on. A flag would not do: the animation
    // belongs to the screen that owns the clock, and this widget owns no controller.
    await _pump(
      tester,
      days: List.filled(7, true),
      decorateLast: (cell) => Opacity(opacity: 0.5, child: cell),
    );

    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('streak-week-today')),
        matching: find.byType(Opacity),
      ),
      findsWidgets,
    );
  });

  testWidgets('the seven cells share the width rather than leaving it as gap', (
    tester,
  ) async {
    // `flex: 1` and a 6pt gap, which is what makes a cell wider than it is tall. The square
    // 30pt cell this replaced left a third of the row empty and read as seven checkboxes on
    // a page whose whole subject is a continuous run.
    // `tilt: false`, because a raked cell's *rect* is its rotated bounding box — this case
    // is about how the width is divided, and measuring it through the rake would be
    // measuring the mannerism.
    await _pump(tester, days: List.filled(7, true), tilt: false);

    final cells = [
      for (var i = 0; i < 7; i++)
        find
            .ancestor(
              of: find.byType(Text).at(i),
              matching: find.byType(Container),
            )
            .first,
    ];

    for (final cell in cells) {
      expect(
        tester.getSize(cell),
        Size((_width - kReadWeekGap * 6) / 7, kReadWeekCellHeight),
      );
    }
    expect(
      tester.getRect(cells.last).right - tester.getRect(cells.first).left,
      closeTo(_width, 0.01),
      reason: 'the row ends where the content width ends',
    );
    expect(
      tester.getRect(cells[1]).left - tester.getRect(cells[0]).right,
      closeTo(kReadWeekGap, 0.01),
    );
    expect(tester.takeException(), isNull);
  });
}
