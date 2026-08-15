// Tests for the "save a book" sheet's response to a status change.
//
// Choosing a status shows or hides the start/finish date rows, which changes the
// sheet's height. That resize is animated, so the sheet grows smoothly instead
// of snapping to its new size.
//
// The Material chip fallback is used to drive the interaction: the iOS 26
// segmented control is a native platform view with no Flutter-side hit target.

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_info_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';

const _book = BookSearchResult(
  title: 'What You Do Is Who You Are',
  isbn: '9780062871336',
  thumbnail: '',
  authors: ['Ben Horowitz'],
  publisher: 'HarperCollins',
);

/// Opens the sheet and returns once it has finished presenting.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showBookInfoBottomSheet(
                context,
                book: _book,
                shelfNames: const ['자기계발'],
                onSavePressed: (_, __, {startDate, finishDate}) {},
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
}

double _sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byType(AnimatedSize)).height;

void main() {
  testWidgets(
    'Given the sheet is open, When a status adds a date row, Then the height animates',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openSheet(tester);

        final collapsed = _sheetHeight(tester);

        // "Reading" reveals the start-date row.
        await tester.tap(find.text('Reading'));
        await tester.pump();

        // One frame in, the sheet has not jumped straight to its new height.
        await tester.pump(const Duration(milliseconds: 60));
        final midway = _sheetHeight(tester);

        await tester.pumpAndSettle();
        final expanded = _sheetHeight(tester);

        expect(expanded, greaterThan(collapsed));
        expect(midway, greaterThan(collapsed));
        expect(midway, lessThan(expanded));
        expect(find.text('Start date'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Given a status with dates, When "interested" is chosen, Then the sheet shrinks back',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openSheet(tester);
        final collapsed = _sheetHeight(tester);

        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        expect(_sheetHeight(tester), greaterThan(collapsed));

        await tester.tap(find.text('Interested'));
        await tester.pumpAndSettle();

        expect(_sheetHeight(tester), collapsed);
        expect(find.text('Start date'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Given a finished book, Then the finish date cannot precede the start date',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openSheet(tester);

        // "Read" seeds both dates with today.
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Finish date'));
        await tester.pumpAndSettle();

        // The finish picker is bounded below by the start date, so an earlier
        // day (the 2026.08.09-after-2026.08.10 bug) can't be selected.
        expect(
          tester
              .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
              .minimumDate,
          dateOnly(DateTime.now()),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
