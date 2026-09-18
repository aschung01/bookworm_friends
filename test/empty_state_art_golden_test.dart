import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/empty_state_art.dart';

/// Renders every empty-state illustration through the real Flutter pipeline.
///
/// The other tests assert the *contract* — same asset, different tint, srcIn.
/// None of them prove the result looks like anything: a stencil whose alpha was
/// baked wrong still satisfies every one of those assertions and renders as a
/// grey slab. This is the only check that exercises PNG decode, `BlendMode.srcIn`
/// against a real canvas, and the alpha compositing that lets the background show
/// through the ribbon knockout and the magnifier lens.
///
/// Two goldens, one per theme, each holding all six pieces at their true
/// call-site sizes. One image per theme rather than twelve files because the
/// thing being reviewed is whether the set agrees with itself.
///
///     flutter test --update-goldens test/empty_state_art_golden_test.dart
///
/// Goldens are font- and platform-sensitive, so the labels use the default test
/// font and no app text styles — the art is what is under test, not the caption.
void main() {
  /// Ship size per piece, matching `scripts/cut_empty_state_assets.py`.
  const sizes = <EmptyStateArtwork, double>{
    EmptyStateArtwork.emptyLibraryOther: 100,
    EmptyStateArtwork.emptyLibraryMine: 100,
    EmptyStateArtwork.searchIdle: 100,
    EmptyStateArtwork.noNote: 48,
    EmptyStateArtwork.noMatch: 40,
    EmptyStateArtwork.noFriends: 40,
  };

  /// Decodes every asset in the tree before the frame the golden captures.
  ///
  /// `Image.asset` resolves asynchronously, and a widget test's clock does not
  /// run the real event loop — without this the golden captures empty boxes and
  /// then "passes" against an equally empty baseline.
  Future<void> settleImages(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
    });
    await tester.pumpAndSettle();
  }

  Widget sheet({required AppColors colors, required Brightness brightness}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        backgroundColor: colors.pageBackground,
        body: Center(
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              for (final entry in sizes.entries)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A mint tile behind two of them, because the sheet colour is
                    // where a bad cutout shows a halo that pure white hides.
                    ColoredBox(
                      color:
                          entry.key == EmptyStateArtwork.noFriends ||
                              entry.key == EmptyStateArtwork.noNote
                          ? colors.sheetBackground
                          : colors.pageBackground,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: EmptyStateArt(entry.key, size: entry.value),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.key.asset} ${entry.value.toInt()}pt',
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Given the light theme, When every piece is drawn at ship size, Then the set '
    'matches its golden',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        sheet(colors: AppColors.light, brightness: Brightness.light),
      );
      await settleImages(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/empty_state_art_light.png'),
      );
    },
  );

  testWidgets(
    'Given the dark theme, When the same files are drawn, Then the set matches '
    'its golden',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        sheet(colors: AppColors.dark, brightness: Brightness.dark),
      );
      await settleImages(tester);

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/empty_state_art_dark.png'),
      );
    },
  );
}
