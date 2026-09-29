// Regression test for the book-details band's reading-period card.
//
// The row used to lay its label, date range and day count out at their intrinsic widths,
// so a long range plus the day count overflowed on normal phone widths ("RIGHT OVERFLOWED
// BY 6.0 PIXELS"). Making the parts flexible then traded that for truncated text
// ("Reading ...", "2022...."), so the row wraps: nothing overflows and every value stays
// fully readable.
//
// **Then the merge put a position in it too, and a reader called the result messy.** Four
// values beside the badge, wrapping onto two lines at the default text size on the widest
// phone — which is not a wrap valve opening, it is too much in the card. The card now has
// two slots, and most of this file pins which fact goes in each:
//
//   * slot 1, *where or when*: the position if there is one, else the finish date, else
//     nothing. **The start date is gone** — `15 days` is what it was there to say.
//   * slot 2, *how long*: the day count, always.
//   * exactly one of the two is `brandText`; the other recedes.
//
// So the four width cases below no longer expect a range, and that is a reversal rather
// than a drift. `reading_period_row_render_preview.dart` is the frame that judged it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
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

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

/// How many of the card's **values** are drawn in `brandText`, badge excluded.
///
/// The diagnosis behind the two-slot rule was "three green things on one line": the badge,
/// and both values. The badge's green is not negotiable — it is the status — so it is
/// filtered out here rather than counted, and the rule this pins is that at most one
/// *value* is ever the answer.
///
/// Counted through `RichText` rather than `Text` because one of the two values is a real
/// `RichText` (the position, whose total sits back at 60%) and the other is a `Text`, which
/// builds a `RichText` whose root span carries the resolved style. Only the root span is
/// read, so the position's dimmed `/ 432` child is correctly not a second green.
int _greenValues(WidgetTester tester, AppColors colors) {
  final inBadge = find
      .descendant(
        of: find.byType(BookStatusBadge),
        matching: find.byType(RichText),
      )
      .evaluate()
      .toSet();
  var green = 0;
  for (final element
      in find
          .descendant(
            of: find.byType(ReadingPeriodRow),
            matching: find.byType(RichText),
          )
          .evaluate()) {
    if (inBadge.contains(element)) continue;
    final span = (element.widget as RichText).text;
    if (span is TextSpan && span.style?.color == colors.brandText) green++;
  }
  return green;
}

void main() {
  final colors = AppColors.light;

  // 375 (iPhone SE/mini logical width) minus the details page's 30pt padding on each side
  // is where the original overflow was reported.
  const widths = <double>[255, 240, 200, 160];

  for (final width in widths) {
    testWidgets(
      'Given a ${width.toInt()}pt wide reading period row, Then it lays out without overflowing',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ReadingPeriodRow(
              status: bookStatusFinished,
              startDate: DateTime(2022, 11, 13),
              finishDate: DateTime(2022, 11, 15),
            ),
            width: width,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ReadingPeriodRow)).width, width);
        // Nothing is truncated: each value is present in full. The status badge stands in
        // for the old "Reading period" label — status, dates and duration are one class of
        // fact, and the badge does more work than the label did, so this removed a string
        // rather than adding one.
        expect(find.byType(BookStatusBadge), findsOneWidget);
        expect(find.text('Finished'), findsOneWidget);
        expect(find.text('Reading period'), findsNothing);
        // The finish date, alone. This used to read `2022.11.13 ~ 2022.11.15` and that
        // string plus `2 days` is what wrapped onto two lines in the band: the one state
        // whose reading period is *complete* was the one that would not fit, spending both
        // lines on a closed range with its own duration printed underneath it.
        expect(find.text('2022.11.15'), findsOneWidget);
        expect(find.textContaining('2022.11.13'), findsNothing);
        expect(find.textContaining('~'), findsNothing);
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
          status: bookStatusReading,
          startDate: DateTime(2022, 11, 13),
          finishDate: DateTime(2024, 12, 31),
        ),
        width: 200,
        locale: const Locale('ko'),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  group('the two slots', () {
    testWidgets(
      'Given a position, Then it takes the first slot and the day count recedes',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ReadingPeriodRow(
              status: bookStatusReading,
              startDate: DateTime.now().subtract(const Duration(days: 15)),
              progress: 0.71,
              pageCount: 432,
            ),
            width: 333,
          ),
        );

        expect(tester.takeException(), isNull);
        // One rounding site, shared with the wheel's rider and the sheet's read-out.
        expect(bookProgressPage(0.71, 432), 307);
        expect(
          find.textContaining('71% · p.307', findRichText: true),
          findsOneWidget,
        );
        // And no date, which is the reversal: a start date is `15 days` stated in the
        // form nobody wants it, and the sheet this card opens still holds both dates.
        expect(find.textContaining('~'), findsNothing);
        expect(find.text('15 days'), findsOneWidget);
        // Context, not the answer.
        expect(_colorOf(tester, '15 days'), colors.secondaryText);
        expect(_greenValues(tester, colors), 1);
      },
    );

    testWidgets(
      'Given no position and no finish date, Then the day count is the whole value',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ReadingPeriodRow(
              status: bookStatusReading,
              startDate: DateTime.now().subtract(const Duration(days: 15)),
            ),
            width: 333,
          ),
        );

        expect(tester.takeException(), isNull);
        // A just-started book has nothing specific to say about where it is, so the first
        // slot is empty rather than filled with the start date the count already carries.
        // The card is sparse here on purpose; it was `2022.11.13 ~   15 days` before,
        // which is one fact printed twice.
        expect(find.textContaining('2022'), findsNothing);
        expect(find.textContaining('~'), findsNothing);
        expect(find.text('15 days'), findsOneWidget);
        // Promoted, because it is now the only answer on the card.
        expect(_colorOf(tester, '15 days'), colors.brandText);
        expect(_greenValues(tester, colors), 1);
      },
    );

    testWidgets(
      'Given a finished book, Then the position is not printed beside a badge that says it',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ReadingPeriodRow(
              status: bookStatusFinished,
              startDate: DateTime(2022, 11, 13),
              finishDate: DateTime(2022, 11, 15),
              progress: 1,
              pageCount: 432,
            ),
            width: 333,
          ),
        );

        expect(tester.takeException(), isNull);
        // A finished book's position is non-null and exactly 1, so `progress != null`
        // alone would print `100% · p.432 / 432` next to a badge already reading
        // *Finished* — three ways of saying the end. The date is what that slot has left
        // to say.
        expect(find.textContaining('100%', findRichText: true), findsNothing);
        expect(find.textContaining('p.432', findRichText: true), findsNothing);
        expect(find.text('2022.11.15'), findsOneWidget);
        expect(_colorOf(tester, '2022.11.15'), colors.brandText);
        expect(_colorOf(tester, '2 days'), colors.secondaryText);
        expect(_greenValues(tester, colors), 1);
      },
    );

    testWidgets(
      'Given a set-aside book, Then the position wins over its finish date',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ReadingPeriodRow(
              status: bookStatusSetAside,
              startDate: DateTime(2022, 11, 13),
              finishDate: DateTime(2022, 11, 15),
              progress: 0.46,
              pageCount: 432,
            ),
            width: 333,
          ),
        );

        expect(tester.takeException(), isNull);
        // How far this one got is the news about it, which a date cannot carry — and
        // unlike a finished book the badge does not already imply the number.
        expect(
          find.textContaining('46% · p.199', findRichText: true),
          findsOneWidget,
        );
        expect(find.textContaining('2022.11.15'), findsNothing);
        expect(_greenValues(tester, colors), 1);
      },
    );
  });

  testWidgets(
    'Given no start date, Then the badge is drawn bare instead of inside a card',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const ReadingPeriodRow(status: 0), width: 255),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Not started'), findsOneWidget);
      // Wrapping a lone chip in a full-width white card was drawn at real scale
      // and looked worse than the corner it replaced, so the card is skipped
      // entirely and the badge shrink-wraps.
      //
      // Compared against the 255pt it is offered rather than against an absolute
      // figure: `flutter_test` draws every glyph as a square of the font size, so
      // "Not started" measures 158pt here against roughly 96pt on device. This is
      // the assertion that caught the badge stretching edge to edge when the
      // parent passed tight constraints — which the band does not, so nothing
      // else would have.
      expect(tester.getSize(find.byType(BookStatusBadge)).width, lessThan(255));
      // And no date came along with it.
      expect(find.textContaining('~'), findsNothing);
    },
  );
}
