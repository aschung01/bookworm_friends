// Regression test for the book-details "Reading period" row.
//
// The row used to lay its label, date range and day count out at their
// intrinsic widths, so a long range plus the day count overflowed the row on
// normal phone widths ("RIGHT OVERFLOWED BY 6.0 PIXELS"). Making the parts
// flexible then traded that for truncated text ("Reading ...", "2022...."), so
// the row now wraps: nothing overflows and every value stays fully readable.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/reading_period_row.dart';

Widget _wrap(Widget child, {required double width, Locale? locale}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        // Mirrors the details page: the row sits inside a 30pt-inset column.
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  // 375 (iPhone SE/mini logical width) minus the details page's 30pt padding
  // on each side is where the original overflow was reported.
  const widths = <double>[255, 240, 200, 160];

  for (final width in widths) {
    testWidgets(
      'Given a ${width.toInt()}pt wide reading period row, Then it lays out without overflowing',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ReadingPeriodRow(
              startDate: DateTime(2022, 11, 13),
              finishDate: DateTime(2022, 11, 15),
            ),
            width: width,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ReadingPeriodRow)).width, width);
        // Nothing is truncated: each value is present in full.
        expect(find.text('Reading period'), findsOneWidget);
        expect(find.text('2022.11.13 ~ 2022.11.15'), findsOneWidget);
        expect(find.text('2 days'), findsOneWidget);
      },
    );
  }

  testWidgets('Given a Korean locale, Then the row still fits a narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ReadingPeriodRow(
          startDate: DateTime(2022, 11, 13),
          finishDate: DateTime(2024, 12, 31),
        ),
        width: 200,
        locale: const Locale('ko'),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Given no finish date, Then the row renders the open-ended range without overflowing',
    (tester) async {
      await tester.pumpWidget(
        _wrap(ReadingPeriodRow(startDate: DateTime(2022, 11, 13)), width: 255),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('2022.11.13'), findsOneWidget);
    },
  );
}
