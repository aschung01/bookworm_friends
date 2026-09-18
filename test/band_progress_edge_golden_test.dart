// Pins the band's bottom edge — the bar that reads the reader's position.
//
// **The clipping is the whole subject.** The bar runs the band's full width and its
// ends are cut by the band's 30pt bottom radius, which is what makes it read as the
// band's own edge being inked in rather than as a bar sitting near the bottom. That
// behaviour cannot be asserted numerically: a painter that ignored the clip, and one
// that traced the arcs instead of running straight across, both satisfy every
// arithmetic check you could write about a 4pt fill. So this is a golden, and the
// four frames are the ones the drawing argued over.
//
// The low two are the trade being pinned, not a bug being tolerated. At 1% and 4% the
// whole fill sits inside the bottom-left corner arc and **nothing is visible**. That
// is accepted because the numbers sit directly above the bar, so an empty-looking
// edge beside a legible `4%` degrades rather than lies. If a future change makes those
// two frames show ink, the edge-to-edge look has been traded away — read
// `band_progress_edge.dart` before updating this baseline.
//
//     flutter test --update-goldens test/band_progress_edge_golden_test.dart
//
// One image holding all four, because what is under review is whether the set agrees
// with itself: 46% must look like the same object as 100%, not like a different one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/band_progress_edge.dart';

void main() {
  /// A stand-in for the band: the same `surfaceVariant` ground and the same bottom
  /// radius, at the real 393pt width of the phone the drawings are measured on.
  Widget band(double progress) {
    return Builder(
      builder: (context) => Container(
        width: 393,
        height: 72,
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(kBookBandCornerRadius),
            bottomRight: Radius.circular(kBookBandCornerRadius),
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Positioned.fill(child: BandProgressEdge(progress: progress)),
          ],
        ),
      ),
    );
  }

  Widget sheet(ThemeData theme, Color background) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: Scaffold(
      backgroundColor: background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final progress in [0.01, 0.04, 0.46, 1.0]) ...[
              band(progress),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    ),
  );

  testWidgets('the band edge, light', (tester) async {
    tester.view.physicalSize = const Size(440, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      sheet(AppTheme.light, AppColors.light.pageBackground),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/band_progress_edge_light.png'),
    );
  });

  testWidgets('the band edge, dark', (tester) async {
    // Drawn in both themes on purpose. The light frames cannot tell `brandText`
    // from `brandFill` — they are the same #067657 there — and the whole reason the
    // painter picks `brandText` is that `brandFill` would leave a 4pt bar all but
    // invisible on a dark band. This is the image that shows it.
    tester.view.physicalSize = const Size(440, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      sheet(AppTheme.dark, AppColors.dark.pageBackground),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/band_progress_edge_dark.png'),
    );
  });

  group('what the goldens cannot say in words', () {
    testWidgets('Given no position, Then nothing is painted at all', (
      tester,
    ) async {
      // Null is not 0. An empty track is a claim — it says the reader started and
      // got nowhere — and every book in the library would make it on day one.
      await tester.pumpWidget(
        const MaterialApp(home: BandProgressEdge(progress: null)),
      );
      expect(
        find.descendant(
          of: find.byType(BandProgressEdge),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('Given 0.0, Then the track is painted', (tester) async {
      // "At the very start" is an answer, and it gets an empty bar to say so.
      await tester.pumpWidget(
        const MaterialApp(home: BandProgressEdge(progress: 0)),
      );
      expect(
        find.descendant(
          of: find.byType(BandProgressEdge),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the bar cannot be tapped through', (tester) async {
      // It overlays the band's bottom padding, which is exactly where the progress
      // row's extended 44pt tap target lives. Painting over a hit area would
      // swallow it.
      await tester.pumpWidget(
        const MaterialApp(home: BandProgressEdge(progress: 0.46)),
      );
      expect(
        find.descendant(
          of: find.byType(BandProgressEdge),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });
  });
}
