// Guards the page block's layout and its dark-mode tones.
//
// This face is the one whose size is not pinned by the chassis: the cover and
// back board are handed tight constraints, but the page block sizes itself. That
// makes it the one face that can silently collapse — and a collapsed page block
// is invisible rather than loud, because the flat back board sits directly behind
// it and shows through in its place. The symptom is a turned book whose fore-edge
// looks like a uniform slab instead of a shaded stack of pages.
//
// The dark-mode group exists because of a real bug: the page block was tinted
// `surfaceVariant`, which is exactly what the details page paints its hero area
// with. The fore-edge was the same colour as the surface behind it and could not
// be seen at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';

const double _thickness = 30;
const double _inset = 2;
const double _boxHeight = 180;

/// Pumps a page block and hands back the chassis colours resolved from the same
/// theme the block was built under.
Future<BookChassisColors> _pumpBlock(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
}) async {
  late BookChassisColors colors;
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Builder(
        builder: (context) {
          colors = BookChassisColors.of(context);
          return Center(
            child: SizedBox(
              width: 120,
              height: _boxHeight,
              child: BookPageBlock(
                thickness: _thickness,
                inset: _inset,
                colors: colors,
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  return colors;
}

/// The strip itself, rather than the [Align] that positions it against the
/// cover's left edge.
Finder _strip() => find
    .descendant(
      of: find.byType(BookPageBlock),
      matching: find.byType(DecoratedBox),
    )
    .first;

Iterable<DecoratedBox> _layers(WidgetTester tester) =>
    tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(BookPageBlock),
        matching: find.byType(DecoratedBox),
      ),
    );

/// Absolute difference in WCAG relative luminance.
double _luminanceGap(Color a, Color b) =>
    (a.computeLuminance() - b.computeLuminance()).abs();

void main() {
  group('layout', () {
    testWidgets('the page block fills the height it is given', (tester) async {
      await _pumpBlock(tester);
      expect(
        tester.getSize(_strip()).height,
        closeTo(_boxHeight - 2 * _inset, 0.5),
        reason:
            'the page block collapsed vertically, so the back board shows '
            'through the fore-edge instead of a shaded page stack',
      );
    });

    testWidgets('the page block is exactly as wide as the book is thick', (
      tester,
    ) async {
      await _pumpBlock(tester);
      expect(tester.getSize(_strip()).width, closeTo(_thickness, 0.5));
    });

    testWidgets('both gradient layers cover the whole block', (tester) async {
      // The vertical page tone and the horizontal edge shading. If the inner one
      // collapses the block turns flat.
      await _pumpBlock(tester);
      expect(_layers(tester).length, 2);
      for (var i = 0; i < 2; i++) {
        final size = tester.getSize(
          find
              .descendant(
                of: find.byType(BookPageBlock),
                matching: find.byType(DecoratedBox),
              )
              .at(i),
        );
        expect(
          size.height,
          closeTo(_boxHeight - 2 * _inset, 0.5),
          reason: 'gradient layer $i did not fill the block',
        );
        expect(size.width, closeTo(_thickness, 0.5));
      }
    });

    testWidgets('the page tone runs top to bottom, not left to right', (
      tester,
    ) async {
      // The reference is `linear-gradient(#fff, #fafafa)`, which in CSS means
      // vertical. Flutter's LinearGradient defaults to centerLeft ->
      // centerRight, so omitting begin/end silently rotates it 90 degrees and
      // stacks it on the same axis as the edge shading.
      await _pumpBlock(tester);
      final gradient =
          (_layers(tester).first.decoration as BoxDecoration).gradient!
              as LinearGradient;
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
    });
  });

  group('dark mode tones', () {
    testWidgets('the page block is distinguishable from every surface a book '
        'sits on', (tester) async {
      final dark = await _pumpBlock(tester, brightness: Brightness.dark);
      for (final background in [
        AppColors.dark.surfaceVariant, // details page hero — the original bug
        AppColors.dark.pageBackground, // home shelves
        AppColors.dark.surface,
      ]) {
        expect(
          _luminanceGap(dark.pageBase, background),
          greaterThan(0.02),
          reason:
              'the dark page block is too close to $background to be seen '
              'against it',
        );
      }
    });

    testWidgets('the page block is not so light it punches a hole in the UI', (
      tester,
    ) async {
      // It should read as paper in low light, not as white paper.
      final dark = await _pumpBlock(tester, brightness: Brightness.dark);
      expect(dark.pageBase.computeLuminance(), lessThan(0.25));
    });

    testWidgets('the page block still shades from base to low', (tester) async {
      final dark = await _pumpBlock(tester, brightness: Brightness.dark);
      expect(
        dark.pageBase.computeLuminance(),
        greaterThan(dark.pageBaseLow.computeLuminance()),
      );
    });

    testWidgets('the back board reads as being behind the pages', (
      tester,
    ) async {
      final dark = await _pumpBlock(tester, brightness: Brightness.dark);
      expect(
        dark.backBoard.computeLuminance(),
        lessThan(dark.pageBase.computeLuminance()),
      );
    });

    testWidgets('light mode keeps the near-white page tone', (tester) async {
      final light = await _pumpBlock(tester);
      expect(light.pageBase.computeLuminance(), greaterThan(0.9));
    });
  });
}
