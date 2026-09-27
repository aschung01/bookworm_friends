// Pins the month's mark — the two-band date stamp a recorded day carries.
//
// **The anatomy is the whole subject, and it is not numerically assertable.** What makes
// the die read as *pressed* rather than as a drawn circle is a set of failures: a rim
// that is not quite round, a band whose width breathes around the circumference, and two
// pressure nicks where the pad did not take. A painter that drew two perfect concentric
// circles would satisfy every arithmetic check in
// `test/read_calendar_month_test.dart` — the ink, the alpha, the tilt, the seeding, the
// box — and would be the exact thing the design record rejected, in its words, as "a
// diagram of a stamp, not a stamp" (`cp-f-stamp-double`, and the round ring it replaced).
// So this is a golden.
//
//     flutter test --update-goldens test/read_calendar_stamp_golden_test.dart
//
// **Look at the image, not just the pass.** The record's own rule, learned the hard way
// on the empty-state art: a contact sheet is not a look. Two specific things to check
// before accepting a new baseline —
//
//   1. the nicks are visible as *thinning*, not as gaps. A band broken into arcs is a
//      dashed circle, which is a different mark;
//   2. both rings thin at the *same* angles. One press made both, and nicks rolled per
//      band draw two stamps that merely happen to be concentric.
//
// Three days at three scales, and then the real thing: the die repeats every third day,
// so the top block is the whole set, the small sizes are where a hairline band either
// survives or turns into a smudge, and the month underneath is the only view that answers
// the question that actually matters — whether two bands still read as two at the 40pt
// cell the grid computes at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/streak/read_calendar_month.dart';

void main() {
  /// One die, on paper, at [size].
  Widget die(int day, double size, Color colour) => Container(
    width: size,
    height: size,
    color: const Color(0xFFFAF6EC),
    child: CustomPaint(
      painter: ReadCalendarStampDie(
        colour: colour.withValues(alpha: kReadCalendarStampAlpha),
        day: day,
      ),
    ),
  );

  testWidgets('the die is a pressed stamp: eccentric rim, shared nicks', (
    tester,
  ) async {
    // Sized to the content rather than the default 600pt surface, which the anatomy rows
    // plus a full month overflow — and an overflow would put a yellow stripe across the
    // baseline instead of the thing under review.
    tester.view.physicalSize = const Size(1000, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 40pt is the real cell the grid computes at phone width; 96 is there to make the
    // anatomy reviewable by eye, and 24 is the size at which a two-band die either
    // still reads as two bands or has to be abandoned for the single oval.
    const sizes = [96.0, 40.0, 24.0];
    // Two real jacket colours and the neutral a night with no attribution draws in, so
    // the sheet also answers whether the ink survives at each.
    const inks = [Color(0xFF26243E), Color(0xFFA4552F), Color(0xFF6B7280)];

    // A real run, in two jackets, with a gap and an unrecorded today — the month the
    // record's own fixture draws, so this image and `cp-f-stamp-double` can be held up
    // beside each other.
    const navy = Color(0xFF26243E);
    const rust = Color(0xFFA4552F);
    final month = DateTime(2026, 9);
    final marks = <DateTime, Color?>{
      for (var d = 2; d <= 6; d++) DateTime(2026, 9, d): navy,
      for (var d = 7; d <= 11; d++) DateTime(2026, 9, d): rust,
      DateTime(2026, 9, 12): null,
    };

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('en'),
        home: Container(
          color: const Color(0xFFFAF6EC),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final ink in inks)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final size in sizes)
                      // Days 1, 2 and 3 are the three dies, since `day % 3` chooses.
                      for (var day = 1; day <= 3; day++)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: die(day, size, ink),
                        ),
                  ],
                ),
              const SizedBox(height: 20),
              // 325pt is the width the card gives the grid on a 393pt phone, so the cell
              // here is the shipped one rather than a convenient one.
              SizedBox(
                width: 325,
                child: ReadCalendarMonth(
                  month: month,
                  marks: marks,
                  today: DateTime(2026, 9, 17),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/read_calendar_stamp.png'),
    );
  });
}
