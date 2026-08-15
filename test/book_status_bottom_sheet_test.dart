// Tests for the "change reading status" sheet.
//
// It mirrors the add-book sheet: choosing a status shows or hides the
// start/finish date rows, and that resize is animated so the sheet grows
// smoothly instead of snapping. Unlike the add-book sheet, it edits a book that
// may already have real reading dates, so those must survive a detour through
// another status.
//
// The Material chip fallback is used to drive the interaction: the iOS 26
// segmented control is a native platform view with no Flutter-side hit target.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart';

typedef _Saved = ({int status, DateTime? start, DateTime? finish});

/// Opens the sheet and returns once it has finished presenting.
///
/// [saved] collects what the sheet hands back, so a test can assert on the
/// payload rather than on the form alone.
Future<void> _openSheet(
  WidgetTester tester, {
  int currentStatus = 0,
  DateTime? startDate,
  DateTime? finishDate,
  List<_Saved>? saved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showBookStatusBottomSheet(
                context,
                currentStatus: currentStatus,
                startDate: startDate,
                finishDate: finishDate,
                onSave: (status, start, finish) =>
                    saved?.add((status: status, start: start, finish: finish)),
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
    'Given a status is chosen, Then the date it needs is filled in rather than left empty',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openSheet(tester);

        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();

        final today = DateFormat('yyyy.MM.dd').format(DateTime.now());
        expect(find.text('Select'), findsNothing);
        expect(find.text(today), findsNWidgets(2));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    "Given a book's real dates, When another status is visited, Then they are not lost",
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final start = DateTime(2024, 3, 14);
        await _openSheet(tester, currentStatus: 1, startDate: start);
        expect(find.text('2024.03.14'), findsOneWidget);

        await tester.tap(find.text('Interested'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reading'));
        await tester.pumpAndSettle();

        expect(find.text('2024.03.14'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Given a finished book, When it becomes "interested", Then its dates are cleared on save',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: 2,
          startDate: DateTime(2024, 3, 14),
          finishDate: DateTime(2024, 4, 1),
          saved: saved,
        );

        await tester.tap(find.text('Interested'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(saved, [(status: 0, start: null, finish: null)]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Given a finished book, When it becomes "reading", Then only the finish date is dropped',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final saved = <_Saved>[];
        final start = DateTime(2024, 3, 14);
        await _openSheet(
          tester,
          currentStatus: 2,
          startDate: start,
          finishDate: DateTime(2024, 4, 1),
          saved: saved,
        );

        await tester.tap(find.text('Reading'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(saved, [(status: 1, start: start, finish: null)]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
