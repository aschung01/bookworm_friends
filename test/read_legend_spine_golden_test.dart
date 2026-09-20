// Pins the month legend's spine — the mark that keys the grid to a book.
//
// **What cannot be asserted numerically.** `reading_streak_page_test.dart` checks the
// spine is 9x17, that its binding is 22% of that, and that its fore edge takes the app's
// page-block tone. All three would still pass if the binding were invisible against the
// jacket, if the fore-edge sliver read as a white gap rather than as leaves, or if the
// whole thing looked like a wider rounded tick — which is precisely the state the 5x15
// version was in, and the reason `cp-g-spine-thick` widened it. The claim under review is
// "this reads as a book standing on a shelf", and only a look settles it.
//
//     flutter test --update-goldens test/read_legend_spine_golden_test.dart
//
// **Look at the image.** Two things to check before accepting a new baseline —
//
//   1. the hinge is visible on every jacket, including the darkest. A binding shadow on a
//      near-black spine is the case that fails first, and a spine with no visible hinge is
//      a rectangle;
//   2. the fore edge reads as *pages* — slightly under the boards, not a bright white
//      stripe cutting the colour.
//
// Both themes, because the fore edge is the one part that changes with them:
// `BookChassisColors` gives white leaves in light and a mid grey in dark, deliberately not
// `surfaceVariant`, so that the edge does not disappear into the surface behind it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/pages/reading_streak_page.dart';

void main() {
  testWidgets('the legend spine reads as a book, in both themes', (
    tester,
  ) async {
    // Real jacket colours, and the two that matter are the ends: near-black is where the
    // binding shadow has the least to work with, and near-white is where the fore edge
    // has to separate from the boards rather than from the page.
    const jackets = [
      Color(0xFF20242B),
      Color(0xFF8C3B2E),
      Color(0xFF6B4A7A),
      Color(0xFF1F3A5F),
      Color(0xFFC9A227),
      Color(0xFFF2EFE6),
    ];

    Widget sheet(ThemeData theme) => Theme(
      data: theme,
      child: Builder(
        builder: (context) => ColoredBox(
          color: context.colors.surface,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // At the size it ships, so the baseline answers the shipped question.
                Row(
                  children: [
                    for (final c in jackets)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ReadLegendSpine(colour: c),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // And at 5x, because a 9x17 object cannot be reviewed at 9x17. The
                // anatomy is what is under review; the row above is whether it survives
                // being small.
                //
                // `FittedBox` rather than `Transform.scale`, and the difference was
                // visible: `Transform` does not affect layout, so an unboxed row of
                // magnified spines overlapped into one striped slab — and boxing it in a
                // `SizedBox` instead handed the spine *tight* 45x85 constraints, which
                // stretched it before the scale and filled the baseline with bands.
                // `FittedBox` leaves the child unbounded, so it sizes itself at 9x17 and
                // is then scaled whole.
                Row(
                  children: [
                    for (final c in jackets)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: ReadLegendSpine.width * 5,
                          height: ReadLegendSpine.height * 5,
                          child: FittedBox(child: ReadLegendSpine(colour: c)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [sheet(AppTheme.light), sheet(AppTheme.dark)],
        ),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/read_legend_spine.png'),
    );
  });
}
