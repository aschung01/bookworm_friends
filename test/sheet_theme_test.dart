// Pins the modal bottom sheet background.
//
// Left to Material's defaults, a sheet is painted with
// `colorScheme.surfaceContainerLow`, which `ColorScheme.fromSeed` derives
// *tonally* from the brand-green seed. The resulting faint mint tint is wanted,
// but as a derived value it silently moves whenever the seed changes or Flutter
// retunes its palette algorithm — and it is not expressible in the app's own
// token vocabulary. These tests assert the literal colors, so any such drift
// (or an accidental token edit) fails here instead of shipping.
//
// The expected values are exactly what the tonal default produced before it was
// pinned, so the pin was a visual no-op.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';

/// The color the sheet's own [Material] is actually painted with.
Color _renderedSheetColor(WidgetTester tester) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Material),
        )
        .first,
  );
  return material.color!;
}

Future<void> _pumpSheet(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => CNBottomSheet.show<void>(
              context: context,
              builder: (_) => const SizedBox(height: 120),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Given the light theme, When a modal sheet is shown, Then it is painted with the pinned mint tint',
    (tester) async {
      await _pumpSheet(tester, AppTheme.light);

      expect(_renderedSheetColor(tester), const Color(0xffEFF5EF));
      expect(AppColors.light.sheetBackground, const Color(0xffEFF5EF));
    },
  );

  testWidgets(
    'Given the dark theme, When a modal sheet is shown, Then it is painted with the pinned dark tint',
    (tester) async {
      await _pumpSheet(tester, AppTheme.dark);

      expect(_renderedSheetColor(tester), const Color(0xff171D1A));
      expect(AppColors.dark.sheetBackground, const Color(0xff171D1A));
    },
  );

  testWidgets(
    'Given a color scheme whose tonal surface disagrees, When a modal sheet is shown, Then the pinned color wins',
    (tester) async {
      // The load-bearing assertion. The two tests above only catch *drift*: they
      // pass either way today, because the pinned literals are the values the
      // tonal default currently produces. This one proves the sheet no longer
      // reads that derived value at all.
      final hostile = AppTheme.light.copyWith(
        colorScheme: AppTheme.light.colorScheme.copyWith(
          surfaceContainerLow: const Color(0xffFF00FF),
        ),
      );
      await _pumpSheet(tester, hostile);

      expect(_renderedSheetColor(tester), const Color(0xffEFF5EF));
    },
  );
}
