/// The span ladder, and the arithmetic that decides how far along it a run has got.
///
/// **The fill fraction is tested apart from the drawing because it is the half that can be
/// wrong while the picture still looks plausible.** A track that fills to a believable-looking
/// place is indistinguishable, by eye, from one that fills to the right place; only the
/// numbers say which. The drawing itself is reviewed in
/// `docs/mockups/streak-week/index.html` (`span-track`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/streak/streak_span_track.dart';

/// The shipped ladder, with the labels `en` gives them.
const List<StreakSpan> _ladder = [
  StreakSpan(days: 7, label: '1 week'),
  StreakSpan(days: 30, label: '1 month'),
  StreakSpan(days: 100, label: '100 days'),
  StreakSpan(days: 365, label: '1 year'),
];

double _fill(int streak) => StreakSpanTrack.fillFraction(streak, _ladder);

Future<void> _pump(WidgetTester tester, int streak) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Center(
          child: SizedBox(
            width: 320,
            child: StreakSpanTrack(streak: streak, rungs: _ladder),
          ),
        ),
      ),
    ),
  );
}

/// Every label's ink, in rung order.
List<Color?> _labelInks(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.style?.color)
    .toList();

void main() {
  group('the fill fraction', () {
    test('an empty record fills nothing', () {
      expect(_fill(0), closeTo(0, 1e-9));
    });

    test('a rung exactly reached fills its whole segment', () {
      // Four rungs, so a segment is a quarter and each boundary is a clean fraction.
      expect(_fill(7), closeTo(0.25, 1e-9));
      expect(_fill(30), closeTo(0.5, 1e-9));
      expect(_fill(100), closeTo(0.75, 1e-9));
      expect(_fill(365), closeTo(1, 1e-9));
    });

    test('the ladder does not run past its end', () {
      // A reader with a four-year run is not owed five quarters of a track.
      expect(_fill(1000), closeTo(1, 1e-9));
      expect(_fill(100000), closeTo(1, 1e-9));
    });

    test(
      'a partial run lands inside the segment it is in, never on a rung',
      () {
        // 3 of the way to 7: three sevenths of the first quarter.
        expect(_fill(3), closeTo(0.25 * 3 / 7, 1e-9));
        // 9 days is two days past a week, of the 23 between a week and a month.
        expect(_fill(9), closeTo(0.25 + 0.25 * 2 / 23, 1e-9));
        // 40 days is ten past a month, of the 70 between a month and a hundred.
        expect(_fill(40), closeTo(0.5 + 0.25 * 10 / 70, 1e-9));
      },
    );

    test('a partial run is strictly between the two rungs it sits between', () {
      // **The property, rather than three more hand-computed values.** An off-by-one in the
      // segment walk shows up here even where a literal would have been copied from the bug.
      for (final best in [1, 3, 6, 8, 15, 29, 31, 66, 99, 101, 364]) {
        final f = _fill(best);
        final below = _ladder.where((r) => r.days <= best).length;
        expect(
          f,
          greaterThan(below * 0.25 - 1e-9),
          reason: '$best days has cleared $below rungs',
        );
        expect(
          f,
          lessThan((below + 1) * 0.25),
          reason: '$best days has not cleared ${below + 1}',
        );
      }
    });

    test('it rises with the record and never falls', () {
      var last = -1.0;
      for (var best = 0; best <= 400; best++) {
        final f = _fill(best);
        expect(f, greaterThanOrEqualTo(last), reason: 'at $best days');
        last = f;
      }
    });

    test('an empty ladder is not a division by zero', () {
      expect(StreakSpanTrack.fillFraction(9, const []), 0);
    });
  });

  group('the track', () {
    testWidgets('one graduation and one label per rung', (tester) async {
      await _pump(tester, 9);

      expect(
        find.byType(Text),
        findsNWidgets(_ladder.length),
        reason: 'every rung is named exactly once',
      );
      // The graduations are the white 2pt marks; the rail and the fill are the rounded bars.
      final marks = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.color == Colors.white)
          .length;
      expect(marks, _ladder.length, reason: 'one hairline per rung');
    });

    testWidgets('an earned label is inked and an unearned one is not', (
      tester,
    ) async {
      await _pump(tester, 9);
      final inks = _labelInks(tester);

      expect(
        inks.first,
        kCandleStockTop,
        reason: 'a week is behind a 9-day run',
      );
      expect(
        inks.last,
        isNot(kCandleStockTop),
        reason: 'a year is not, and must not be drawn as though it were',
      );
      expect(
        inks.where((c) => c == kCandleStockTop).length,
        1,
        reason: 'exactly one rung is earned at 9 days',
      );
    });

    testWidgets('nothing is inked before the first rung', (tester) async {
      await _pump(tester, 3);
      expect(
        _labelInks(tester).any((c) => c == kCandleStockTop),
        isFalse,
        reason: 'three days has earned nothing, and the ladder must say so',
      );
    });

    testWidgets('a full year inks every rung', (tester) async {
      await _pump(tester, 365);
      expect(_labelInks(tester).every((c) => c == kCandleStockTop), isTrue);
    });

    testWidgets('no label is drawn outside the track, and none overflows', (
      tester,
    ) async {
      // **This case used to assert the opposite and was wrong.** It said the first and last
      // labels "deliberately overhang the rail", on the reasoning that a 60pt box centred on
      // a 2pt mark has to. That is true of the *box* and it was allowed to be true of the
      // ink: the last rung sits at the rail's right edge by construction, so `1 year` was
      // drawn from `width - 30` to `width + 30` and the outer half was cut off by the page.
      // A widget test cannot see a clip by the screen — a render can, and did.
      await _pump(tester, 40);

      final track = tester.getRect(find.byType(StreakSpanTrack));
      for (final text in find.byType(Text).evaluate()) {
        final rect = tester.getRect(find.byWidget(text.widget));
        expect(
          rect.left,
          greaterThanOrEqualTo(track.left - 0.01),
          reason: 'no label starts left of the track',
        );
        expect(
          rect.right,
          lessThanOrEqualTo(track.right + 0.01),
          reason: 'and none ends right of it',
        );
      }
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StreakSpanTrack)), const Size(320, 34));
    });

    testWidgets('the end label is right-aligned against the end of the rail', (
      tester,
    ) async {
      // It cannot be centred on its graduation without leaving the track, so it hugs the
      // edge the way an axis label does — and being right-aligned is what keeps it reading
      // as *the end of this* rather than as a caption that drifted.
      await _pump(tester, 40);

      final track = tester.getRect(find.byType(StreakSpanTrack));
      expect(
        tester.getRect(find.text('1 year')).right,
        closeTo(track.right, 0.01),
      );
      // The middle rungs are still centred on their marks: 2 of 4 rungs into a 320pt rail
      // puts `1 month` on 160.
      expect(
        tester.getRect(find.text('1 month')).center.dx,
        closeTo(track.left + 160, 0.01),
      );
    });
  });
}
