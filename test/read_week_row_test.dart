/// The week row, drawn once for two surfaces.
///
/// **Why it is worth its own file.** This widget exists because the streak page and the
/// celebration were about to draw the same seven days twice: once in the app's ink on paper
/// and once in candlelight. Two copies is how the week the reader sees behind a celebration
/// and the week inside it come to disagree about which days are in. So the cases below are
/// mostly about the seam — that the palette is the caller's, that the rake is the month
/// grid's rule and not the cell's position, and that exactly one surface suppresses it.
///
/// **And about where the state lives, which this got wrong twice.** The row shipped first as
/// seven identical letter-in-a-box cells, then as four *different* letter-in-a-box
/// treatments. Both put the state on the box and the day's name on the same letter, so every
/// cell was a compound of two variables and the strip could only be read one day at a time.
/// It is now a plain label above a **token that carries a drawn check** — the cases named
/// "one flat empty slot", "marked on the label" and "a solid token" are that rebuild, pinned.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_calendar_month.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_week_row.dart';

/// A Thursday, so the seven days are Fri 11 .. Thu 17 Sept 2026 and every one of them
/// carries a different rake.
final _endingOn = DateTime(2026, 9, 17);

/// Six roles, six values that cannot be mistaken for each other.
///
/// Deliberately not a plausible palette: when the roles were two colours, "stamped in the
/// caller's colour" was all a test could say, and the bug — every unstamped day drawn as a
/// box — sat underneath that assertion perfectly happily.
const _palette = ReadWeekPalette(
  stampFill: Color(0xFF067657),
  stampMark: Color(0xFFFFFFFF),
  emptyFill: Color(0xFFE9ECEF),
  todayEdge: Color(0xFFB54708),
  label: Color(0xFF626A72),
  labelToday: Color(0xFF123456),
);

/// The content width of the narrowest phone the app supports, less the page's 20pt margins.
const double _width = 353;

/// Index of each day in a week ending on [_endingOn]. Fri is oldest.
const _fri = 0, _sat = 1, _sun = 2, _mon = 3, _tue = 4, _wed = 5, _thu = 6;

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

/// The cell at [i], oldest first.
///
/// Addressed by **index rather than by letter**, which the letter-keyed helpers this
/// replaced could not do reliably: an en week has two S's and two T's, and the first draft of
/// the unstamped case read Saturday's tilt while asserting about Sunday. A rolling window's
/// cells have an order and that order is the thing under test.
Finder _cell(int i) => find
    .descendant(of: find.byType(ReadWeekRow), matching: find.byType(Column))
    .at(i);

/// The token at [i] — the 34pt mark under the label, whatever state it is in.
Finder _token(int i) => find.descendant(
  of: _cell(i),
  matching: find.byWidgetPredicate(
    (w) =>
        (w is Container && w.decoration != null) ||
        (w is SizedBox && w.key == const ValueKey('streak-week-dashed')),
  ),
);

/// The token's box, or null where the token is drawn rather than decorated — which is
/// itself the assertion for an unrecorded today.
BoxDecoration? _boxAt(WidgetTester tester, int i) {
  final containers = find.descendant(
    of: _cell(i),
    matching: find.byType(Container),
  );
  if (containers.evaluate().isEmpty) return null;
  return tester.widget<Container>(containers.first).decoration
      as BoxDecoration?;
}

/// The colour of the weekday label at [i].
Color _labelInk(WidgetTester tester, int i) => tester
    .widget<Text>(find.descendant(of: _cell(i), matching: find.byType(Text)))
    .style!
    .color!;

/// The rotation applied to the token at [i], in degrees. Zero where no [Transform] was
/// inserted at all, which is what an unraked token looks like.
double _tiltOf(WidgetTester tester, int i) {
  final transforms = find.descendant(
    of: _cell(i),
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

  testWidgets('narrow single-character labels, not the two-letter header', (
    tester,
  ) async {
    // **A deliberate divergence from the reference, pinned so it cannot drift by accident.**
    // Duolingo sets `Su Mo Tu`, which removes the S/S and T/T collision. We keep
    // `MaterialLocalizations.narrowWeekdays` because the window is rolling and always ends on
    // today, so the *order* says which day each cell is; because `ReadCalendarMonth`'s header
    // is a few hundred pixels below this on the same page and uses the same alphabet; and
    // because two letters is an `en`-only fix — Korean narrow weekdays are already
    // unambiguous single characters, so a blanket `substring(0, 2)` would be wrong.
    await _pump(tester, days: List.filled(7, true));

    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ReadWeekRow),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data!.length)
          .toSet(),
      {1},
      reason: 'every label is one character wide under `en`',
    );
  });

  testWidgets('a read day is a solid token carrying a reversed-out check', (
    tester,
  ) async {
    // **The heart of the rebuild.** This used to be a 10% wash inside a firmer 1.5px edge
    // with the weekday letter on top — two weak signals plus a letter doing a second job.
    // One filled shape with a tick in it is a *mark*, and a run of marks is countable
    // without being read, which is the only reason the reference's row works at a glance.
    // The palette is passed rather than read from the theme, because the celebration paints
    // its own ground and `context.colors` would hand it white type in dark mode.
    await _pump(tester, days: List.filled(7, true));

    final box = _boxAt(tester, _wed)!;
    expect(box.color, _palette.stampFill, reason: 'solid, not a wash');
    expect(
      box.border,
      isNull,
      reason: 'a filled token needs no edge; the old wash did',
    );
    expect(
      box.borderRadius,
      BorderRadius.circular(10),
      reason:
          'a rounded square, not a circle — a raked disc is a no-op, and the rake is '
          'the gesture the week shares with the month grid',
    );
    expect(tester.getSize(_token(_wed)), const Size(34, 34));
    expect(
      _token(_wed),
      paints..path(color: _palette.stampMark, style: PaintingStyle.stroke),
      reason:
          'the check is drawn, not typed — an icon font is absent in a test shell',
    );
  });

  testWidgets('an unread day is one flat empty slot, and only one kind of it', (
    tester,
  ) async {
    // **The divergence this row shipped with, in its second form.** Version one drew a box
    // on all seven days, which reads as seven empty checkboxes. Version two then drew three
    // *different* kinds of not-read: a dashed box for today, a bare hairline under a pale
    // letter for a miss, and nothing at all for anything else. Three ways to say the same
    // thing is three things to learn. One flat slot is a slot.
    await _pump(
      tester,
      days: const [true, true, false, true, true, true, true],
    );

    final box = _boxAt(tester, _sun)!;
    expect(box.color, _palette.emptyFill);
    expect(box.border, isNull, reason: 'no hairline, no rule, no edge');
    expect(box.borderRadius, BorderRadius.circular(10));
    expect(tester.getSize(_token(_sun)), const Size(34, 34));
    expect(
      _token(_sun),
      isNot(paints..path()),
      reason:
          'an empty slot carries no mark at all — the check is the whole signal',
    );
  });

  testWidgets('a missed day is quiet: the label does not change, and is never red', (
    tester,
  ) async {
    // The record notes a gap; it does not scold. **And the label is not where it notes it.**
    // The old row gave a missed day a paler letter and a read day the brand colour, which
    // encoded on the label the one fact the box already carried — so the strip became a
    // gradient of half-states rather than seven yes-or-nos. One label colour; the token
    // says what happened.
    await _pump(
      tester,
      days: const [true, true, false, true, true, true, true],
    );

    expect(_labelInk(tester, _sun), _palette.label);
    expect(
      _labelInk(tester, _sun),
      _labelInk(tester, _wed),
      reason: 'a missed Sunday and a read Wednesday are labelled identically',
    );
  });

  testWidgets('today is marked on the label, never on the token', (
    tester,
  ) async {
    // **The division of labour that is the whole of this option.** The token is reserved for
    // *what happened*, so "where you are" has to be said somewhere else — and the label is
    // the only thing left. Colouring the token would mean a read Thursday and a read Monday
    // looked like different states, which is exactly the compound-cell failure the rebuild
    // exists to remove.
    await _pump(tester, days: List.filled(7, true));

    expect(_labelInk(tester, _thu), _palette.labelToday);
    expect(_labelInk(tester, _mon), _palette.label);
    expect(
      _boxAt(tester, _thu)!.color,
      _boxAt(tester, _mon)!.color,
      reason: 'the two tokens are the same object; only the labels differ',
    );
  });

  testWidgets('today, before it is recorded, is the dashed ring', (
    tester,
  ) async {
    // The affordance: the tap is what fills it. **No slot behind the ring** — a ring over a
    // flat fill is two marks for one state, and the empty middle is what says *this one is
    // waiting for you* rather than *this one is gone*.
    await _pump(
      tester,
      days: const [true, true, true, true, true, true, false],
    );

    expect(
      find.byKey(const ValueKey('streak-week-dashed')),
      findsOneWidget,
      reason: 'exactly one cell invites a tap',
    );
    expect(
      _boxAt(tester, _thu),
      isNull,
      reason: 'drawn, not decorated: there is no fill under the ring',
    );
    expect(tester.getSize(_token(_thu)), const Size(34, 34));
    expect(
      _token(_thu),
      paints..path(color: _palette.todayEdge, style: PaintingStyle.stroke),
    );
    expect(_labelInk(tester, _thu), _palette.labelToday);
  });

  testWidgets('a recorded today is stamped, not dashed', (tester) async {
    await _pump(tester, days: List.filled(7, true));

    expect(find.byKey(const ValueKey('streak-week-dashed')), findsNothing);
  });

  testWidgets('freshLast lifts the closing token rather than inverting it', (
    tester,
  ) async {
    // **This case used to assert an inversion, and the inversion is gone.** It was a real
    // escalation when its six neighbours were a 10% wash: solid fill, reversed-out letter.
    // Every read day is now already solid and already carries a reversed-out check, so there
    // is nothing left to invert *to*. What separates the closing cell is the shadow, plus the
    // scale overshoot and tilt the celebration wraps it in through `decorateLast`.
    await _pump(tester, days: List.filled(7, true), freshLast: true);

    final fresh = _boxAt(tester, _thu)!;
    expect(
      fresh.color,
      _palette.stampFill,
      reason:
          'the same fill as its neighbours — the escalation is not colour any more',
    );
    expect(fresh.boxShadow, isNotEmpty, reason: 'it lifts off the card');
    expect(
      fresh.boxShadow!.single.color.r,
      _palette.stampFill.r,
      reason:
          'cast in the token\'s own hue, so it reads as the token casting it',
    );

    // And its neighbours are untouched: only the last token lifts.
    expect(_boxAt(tester, _wed)!.boxShadow, isNull);
  });

  testWidgets('without freshLast the closing token is an ordinary stamp', (
    tester,
  ) async {
    await _pump(tester, days: List.filled(7, true));

    final last = _boxAt(tester, _thu)!;
    expect(last.color, _palette.stampFill);
    expect(last.boxShadow, isNull);
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

    // Mon 14 rakes +4, Sun 13 rakes −3 — two different signs, so a dropped minus shows up.
    expect(_tiltOf(tester, _mon), closeTo(readCalendarPatchTilt(14), 1e-6));
    expect(_tiltOf(tester, _sun), closeTo(readCalendarPatchTilt(13), 1e-6));
    expect(
      readCalendarPatchTilt(14) * readCalendarPatchTilt(13),
      lessThan(0),
      reason:
          'the two days under test tilt opposite ways, or this proves nothing',
    );
  });

  testWidgets('the rake turns the token and leaves the label upright', (
    tester,
  ) async {
    // A tilted weekday header reads as a layout fault. The gesture is about the *mark*
    // having been pressed on by hand, and nobody pressed a Monday onto a Monday.
    await _pump(tester, days: List.filled(7, true));

    final rotated = find.descendant(
      of: _cell(_mon),
      matching: find.byType(Transform),
    );
    expect(rotated, findsOneWidget);
    expect(
      find.descendant(of: rotated, matching: find.byType(Text)),
      findsNothing,
      reason: 'the label is a sibling of the rotation, not inside it',
    );
  });

  testWidgets('an unstamped token is never raked', (tester) async {
    // There is nothing pressed on it to have landed crooked.
    await _pump(
      tester,
      days: const [true, true, false, true, true, true, true],
    );

    expect(_tiltOf(tester, _sun), 0);
    expect(
      find.descendant(of: _cell(_sun), matching: find.byType(Transform)),
      findsNothing,
      reason: 'and no Transform is inserted at all, not merely a zero one',
    );
  });

  testWidgets('tilt off leaves every token square', (tester) async {
    // The celebration's setting: exactly one token there is allowed to arrive tilted, and six
    // already-raked neighbours would bury the one beat the sequence is built around.
    await _pump(tester, days: List.filled(7, true), tilt: false);

    for (var i = 0; i < 7; i++) {
      expect(_tiltOf(tester, i), 0);
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

  testWidgets('the seven cells share the width; the token keeps its own size', (
    tester,
  ) async {
    // `flex: 1` and a 6pt gap — but the token inside is a fixed 34pt square, centred in
    // whatever share the cell got. **That combination is the thing a fixed-size cell could
    // not have.** The row's first version used a 30pt square *cell*, which left a third of
    // the content width as gap; its second stretched the cell full-width, which is why a
    // letter-in-a-box was the only mark it could hold. A wide cell around a square token is
    // what lets the mark be a token at all.
    // `tilt: false`, because a raked token's *rect* is its rotated bounding box — this case
    // is about how the width is divided, not about the mannerism.
    await _pump(tester, days: List.filled(7, true), tilt: false);

    const share = (_width - kReadWeekGap * 6) / 7;
    for (var i = 0; i < 7; i++) {
      expect(tester.getSize(_cell(i)).width, closeTo(share, 0.01));
      expect(
        tester.getSize(_token(i)),
        const Size(kReadWeekTokenSize, kReadWeekTokenSize),
      );
    }
    expect(
      tester.getRect(_cell(_thu)).right - tester.getRect(_cell(_fri)).left,
      closeTo(_width, 0.01),
      reason: 'the row ends where the content width ends',
    );
    expect(
      tester.getRect(_cell(_sat)).left - tester.getRect(_cell(_fri)).right,
      closeTo(kReadWeekGap, 0.01),
    );
    expect(
      tester.getRect(_token(_fri)).top - tester.getRect(_cell(_fri)).top,
      greaterThan(kReadWeekLabelGap),
      reason: 'the label sits above the token, not inside it',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a whole empty week is seven slots and one ring', (tester) async {
    // The state a brand-new reader sees. It must not read as seven failures: nothing is red,
    // nothing is crossed out, and the only accent on the row is the one cell inviting a tap.
    await _pump(tester, days: List.filled(7, false));

    for (final i in [_fri, _sat, _sun, _mon, _tue, _wed]) {
      expect(_boxAt(tester, i)!.color, _palette.emptyFill);
      expect(_labelInk(tester, i), _palette.label);
    }
    expect(find.byKey(const ValueKey('streak-week-dashed')), findsOneWidget);
    expect(_labelInk(tester, _thu), _palette.labelToday);
  });
}
