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
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
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
              status: 2,
              startDate: DateTime(2022, 11, 13),
              finishDate: DateTime(2022, 11, 15),
            ),
            width: width,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ReadingPeriodRow)).width, width);
        // Nothing is truncated: each value is present in full. The status badge
        // now stands in for the old "Reading period" label — status, dates and
        // duration are one class of fact, and the badge does more work than the
        // label did, so this removed a string rather than adding one.
        expect(find.byType(BookStatusBadge), findsOneWidget);
        expect(find.text('Read'), findsOneWidget);
        expect(find.text('Reading period'), findsNothing);
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
          status: 1,
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
        _wrap(
          ReadingPeriodRow(status: 1, startDate: DateTime(2022, 11, 13)),
          width: 255,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('2022.11.13'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);
    },
  );

  testWidgets(
    'Given no start date, Then the badge is drawn bare instead of inside a card',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const ReadingPeriodRow(status: 0), width: 255),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Interested'), findsOneWidget);
      // Wrapping a lone chip in a full-width white card was drawn at real scale
      // and looked worse than the corner it replaced, so the card is skipped
      // entirely and the badge shrink-wraps.
      //
      // Compared against the 255pt it is offered rather than against an absolute
      // figure: `flutter_test` draws every glyph as a square of the font size, so
      // "Interested" measures 144pt here against roughly 87pt on device. This is
      // the assertion that caught the badge stretching edge to edge when the
      // parent passed tight constraints — which the band does not, so nothing
      // else would have.
      expect(tester.getSize(find.byType(BookStatusBadge)).width, lessThan(255));
      // And no date range came along with it.
      expect(find.textContaining('~'), findsNothing);
    },
  );
}
