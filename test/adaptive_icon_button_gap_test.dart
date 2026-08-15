// Tests for the gap between adjacent adaptive icon buttons.
//
// A native Liquid Glass button fills its whole diameter, so two of them sitting
// next to each other (the library's search and settings buttons) touched edge to
// edge. The Material fallback is an `IconButton`, which already insets its icon,
// so it must not gain extra spacing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets(
    'Given two adjacent icon buttons, Then the gap matches the rendering in use',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdaptiveIconButton(
                symbol: 'magnifyingglass',
                icon: Icons.search,
                semanticLabel: 'Search',
                onPressed: () {},
              ),
              const AdaptiveIconButtonGap(),
              AdaptiveIconButton(
                symbol: 'line.3.horizontal',
                icon: Icons.menu,
                semanticLabel: 'Settings',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      final gap = tester.getSize(find.byType(AdaptiveIconButtonGap)).width;

      if (AdaptiveIconButton.usesNativeGlass) {
        // Glass buttons paint to their edges, so they need real separation.
        expect(gap, 8);
      } else {
        // The Material fallback already has padding around its icon.
        expect(gap, 0);
      }
    },
  );

  testWidgets('Given a custom width, Then the glass gap honours it', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AdaptiveIconButtonGap(width: 12)));

    expect(
      tester.getSize(find.byType(AdaptiveIconButtonGap)).width,
      AdaptiveIconButton.usesNativeGlass ? 12 : 0,
    );
  });
}
