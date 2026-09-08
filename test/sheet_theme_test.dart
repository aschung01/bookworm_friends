// Pins the modal bottom sheet background, and the shape every sheet inherits.
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
//
// The shape is here for the same reason one layer up: it used to be passed at each
// of thirteen call sites, so "the app's sheet corner" was a convention rather than
// a value, and the one sheet that forgot it got Material 3's 28 instead. Now it is
// on the theme, and this file is where it is stated independently of the theme that
// declares it.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:awesome_emoji_picker/awesome_emoji_picker.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';

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

/// The shape the sheet's own [Material] is actually built with.
ShapeBorder? _renderedSheetShape(WidgetTester tester) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Material),
        )
        .first,
  );
  return material.shape;
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

  testWidgets(
    'Given a sheet that passes no shape of its own, When it is shown, Then it '
    'inherits the app\'s 24pt top corners from the theme',
    (tester) async {
      // `_pumpSheet` opens a bare `CNBottomSheet.show` with nothing but a builder,
      // which is now what every real call site looks like. Before the shape moved
      // to the theme this sheet came out at Material 3's 28 — visibly rounder than
      // the thirteen that spelled out 20, and nothing failed.
      await _pumpSheet(tester, AppTheme.light);

      expect(
        _renderedSheetShape(tester),
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        reason:
            'stated as a literal: asserting it equals kSheetCornerRadius would '
            'only prove the theme reads its own constant',
      );
      expect(kSheetCornerRadius, 24);
    },
  );

  testWidgets(
    'Given the emoji picker in a sheet, When it paints its background, Then it '
    'matches the sheet rather than the page',
    (tester) async {
      // The picker comes from a package that fills itself with
      // `scaffoldBackgroundColor` and paints its sticky category headers the
      // same. Inside a sheet that is the wrong token: `pageBackground` (#F8F9FA)
      // against the sheet's `sheetBackground` (#EFF5EF). Close enough to read as
      // a rendering artefact, far enough apart to be a visible seam.
      //
      // Lives here rather than with the other picker tests because the invariant
      // is about surfaces inside sheets, so anyone retuning `sheetBackground`
      // meets it.
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          // The picker reads the app's strings, unlike the bare sheet the other
          // tests here open.
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CNBottomSheet.show<void>(
                  context: context,
                  builder: (_) => const SizedBox(
                    height: 400,
                    child: PraiseEmojiPicker(onEmojiSelected: _ignore),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final insidePicker = Theme.of(
        tester.element(find.byType(AwesomeEmojiPicker)),
      );

      expect(
        insidePicker.scaffoldBackgroundColor,
        _renderedSheetColor(tester),
        reason: 'the grid and its sticky headers have to match the sheet',
      );
      expect(
        insidePicker.scaffoldBackgroundColor,
        isNot(AppColors.light.pageBackground),
        reason: 'the page background is the token this used to wrongly inherit',
      );
    },
  );
}

void _ignore(String _) {}
