import 'package:bookworm_friends/constants/app_layout.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/app_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two shapes [AppSheet] presents, pinned by geometry rather than by widget
/// type, so the assertions survive a change of implementation.
///
/// These exist because the bug they guard against was invisible on a phone for the
/// app's whole life: every sheet inherited Material 3's `maxWidth: 640` and nothing
/// else, so on an iPad the width was capped and the height was not.
void main() {
  const contentKey = Key('sheet-content');

  /// Opens a sheet on a screen of exactly [surface] logical points.
  ///
  /// `devicePixelRatio` is pinned to 1 so the numbers below are the logical points
  /// the layout actually reasons about; the harness default of 3 would make every
  /// assertion here a division.
  Future<Rect> openSheet(WidgetTester tester, Size surface) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => AppSheet.show<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const SizedBox(
                    key: contentKey,
                    // `double.infinity`, not an unconstrained box: a `SizedBox`
                    // with no width lays out at zero under the sheet's loose
                    // constraints, which would make every width assertion below
                    // pass against nothing.
                    width: double.infinity,
                    height: 120,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(contentKey), findsOneWidget);
    return tester.getRect(find.byKey(contentKey));
  }

  testWidgets('Given a phone-sized screen, When a sheet opens, '
      'Then it spans the width and sits flush with the bottom', (tester) async {
    const surface = Size(393, 852);
    final rect = await openSheet(tester, surface);

    expect(rect.width, surface.width);
    expect(rect.bottom, surface.height);
  });

  testWidgets('Given an iPad-sized screen, When a sheet opens, '
      'Then it is capped at the content width and floats clear of the bottom', (
    tester,
  ) async {
    // 13-inch iPad in portrait. The bug being guarded is specifically that the
    // 640 cap applied here and nothing else did.
    const surface = Size(1024, 1366);
    final rect = await openSheet(tester, surface);

    expect(rect.width, kContentMaxWidth);
    expect(rect.bottom, lessThan(surface.height));
    // Centred in what is left, so the card is not merely narrow but placed.
    expect(rect.center.dx, closeTo(surface.width / 2, 0.5));
  });

  testWidgets('Given an iPad-sized screen, When a sheet opens, '
      'Then every corner is rounded, not just the top two', (tester) async {
    await openSheet(tester, const Size(1024, 1366));

    // A flush sheet rounds its top corners through `BottomSheetThemeData.shape`
    // and leaves the bottom two to the display's own mask. A floating card has no
    // mask to borrow, so it has to round all four itself.
    final card = tester.widgetList<Material>(
      find.ancestor(
        of: find.byKey(contentKey),
        matching: find.byType(Material),
      ),
    );

    expect(
      card.any(
        (m) => m.borderRadius == BorderRadius.circular(kSheetCornerRadius),
      ),
      isTrue,
      reason:
          'no ancestor Material rounds all four corners at $kSheetCornerRadius',
    );
  });

  testWidgets('Given the harness default surface, Then it is treated as a phone', (
    tester,
  ) async {
    // Regression guard with teeth. `flutter test` renders at 800x600, so a
    // breakpoint of `shortestSide >= 600` silently moved *every* widget test in
    // the suite onto the tablet path and changed two unrelated height
    // assertions. Whatever the breakpoint becomes, the default harness must stay
    // on the phone path or the suite stops describing phones.
    late bool tablet;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            tablet = isTabletLayout(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      tester.view.physicalSize / tester.view.devicePixelRatio,
      const Size(800, 600),
    );
    expect(tablet, isFalse);
  });
}
