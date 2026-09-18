// Tests for the "change reading status" sheet.
//
// It mirrors the add-book sheet: choosing a status shows or hides the
// start/finish date rows, and that resize is animated so the sheet grows
// smoothly instead of snapping. Unlike the add-book sheet, it edits a book that
// may already have real reading dates, so those must survive a detour through
// another status.
//
// It is also the home of the **reading position**, which is why the second half of
// this file is about isolation. The position, the status and the two dates all leave
// through one Save, and the streaks design only holds if that Save cannot smear one
// into another — a reader fixing a start date must not have their bookmark moved,
// and closing a book must not zero it.
//
// The Material chip fallback is used to drive the interaction: the iOS 26
// segmented control is a native platform view with no Flutter-side hit target.

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/progress_field_row.dart';
import 'package:bookworm_friends/ui/widgets/read_today_field_row.dart';

typedef _Saved = BookStatusEdit;

/// Opens the sheet and returns once it has finished presenting.
///
/// [saved] collects what the sheet hands back, so a test can assert on the
/// payload rather than on the form alone.
Future<void> _openSheet(
  WidgetTester tester, {
  int currentStatus = 0,
  DateTime? startDate,
  DateTime? finishDate,
  double? progress,
  int? progressPage,
  int? pageCount,
  bool readToday = false,
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
                progress: progress,
                progressPage: progressPage,
                pageCount: pageCount,
                readToday: readToday,
                onSave: (edit) => saved?.add(edit),
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

        expect(saved, [
          (
            status: 0,
            startDate: null,
            finishDate: null,
            progress: null,
            progressPage: null,
            readToday: false,
          ),
        ]);
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

        expect(saved, [
          (
            status: 1,
            startDate: start,
            finishDate: null,
            progress: null,
            progressPage: null,
            readToday: false,
          ),
        ]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  // ---------------------------------------------------------------------------
  // The reading position.
  //
  // The single rule the whole streaks design rests on is that the position and the
  // reading day are not connected, and the first half of keeping them apart is
  // making sure this sheet's Save does not smear one field into another. So these
  // cases are about what *did not* change at least as much as what did.

  group('the reading position row', () {
    testWidgets('appears only while the book is open', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openSheet(tester, currentStatus: 0);
        expect(find.byType(ProgressFieldRow), findsNothing);

        await tester.tap(find.text('Reading'));
        await tester.pumpAndSettle();
        expect(find.byType(ProgressFieldRow), findsOneWidget);

        // A finished book is at 100% by definition and an interested one has no
        // position at all, so on both the row would be a field with one legal
        // answer.
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        expect(find.byType(ProgressFieldRow), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('shows the stored position as a whole percent', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openSheet(tester, currentStatus: 1, progress: 0.46);
        expect(find.text('46%'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // The row echoes the unit the reader answered in. Both halves of that rule are
    // worth a case, because the obvious "improvement" is to print a page whenever the
    // book has a count — which would put a derived `p.199` where the reader said 46%.
    testWidgets(
      'Given the reader typed a page, Then the row prints the page and not the percent',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await _openSheet(
            tester,
            currentStatus: 1,
            progress: 200 / 432,
            progressPage: 200,
            pageCount: 432,
          );

          expect(find.text('p.200'), findsOneWidget);
          // And specifically not the stop the fraction rounds to, which is p.199.
          expect(find.text('46%'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given a page count but a percent answer, Then the row still prints the percent',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await _openSheet(
            tester,
            currentStatus: 1,
            progress: 0.46,
            pageCount: 432,
          );

          expect(find.text('46%'), findsOneWidget);
          expect(find.textContaining('p.'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given the count has gone missing, Then a stored page is not printed alone',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // A metadata refresh can drop `page_count` from under a stored
          // `progress_page`. Nothing else in the app can show `p.200 / 432` then, so a
          // lone `p.200` here would be the only place it survived.
          await _openSheet(
            tester,
            currentStatus: 1,
            progress: 200 / 432,
            progressPage: 200,
          );

          expect(find.textContaining('p.'), findsNothing);
          expect(find.text('46%'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given no stored position, Then the row prompts rather than reading 0%',
      (tester) async {
        // Null is "never asked" and 0% is "at the very start". Showing 0% here
        // would put a claim on every book in the library on day one.
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await _openSheet(tester, currentStatus: 1);
          expect(find.text('0%'), findsNothing);
          // Scoped to the row: a book opened at status 1 with no start date shows
          // the same placeholder in its date row, so a bare text finder here
          // would pass for the wrong reason.
          expect(
            find.descendant(
              of: find.byType(ProgressFieldRow),
              matching: find.text('Select'),
            ),
            findsOneWidget,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given the wheel is never opened, When saved, Then the position is passed through',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // The isolation that matters most, because it is the everyday case: a
          // reader opening this sheet to fix a start date must not have their
          // bookmark rewritten as a side effect.
          final saved = <_Saved>[];
          final start = DateTime(2024, 3, 14);
          await _openSheet(
            tester,
            currentStatus: 1,
            startDate: start,
            progress: 0.46,
            saved: saved,
          );

          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          expect(saved, [
            (
              status: 1,
              startDate: start,
              finishDate: null,
              progress: 0.46,
              progressPage: null,
              readToday: false,
            ),
          ]);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given a new position, When saved, Then status and both dates are untouched',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final saved = <_Saved>[];
          final start = DateTime(2024, 3, 14);
          await _openSheet(
            tester,
            currentStatus: 1,
            startDate: start,
            progress: 0.46,
            pageCount: 320,
            saved: saved,
          );

          await tester.tap(find.byType(ProgressFieldRow));
          await tester.pumpAndSettle();

          // Down one stop on the wheel, then confirm. 34 is its item extent.
          await tester.drag(find.byType(CupertinoPicker), const Offset(0, 34));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Confirm'));
          await tester.pumpAndSettle();

          expect(find.text('45%'), findsOneWidget);

          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          expect(saved, hasLength(1));
          expect(saved.single.progress, closeTo(0.45, 1e-9));
          // The point of the case: nothing else moved.
          expect(saved.single.status, 1);
          expect(saved.single.startDate, start);
          expect(saved.single.finishDate, isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given the wheel is dismissed, When saved, Then the old position survives',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final saved = <_Saved>[];
          await _openSheet(
            tester,
            currentStatus: 1,
            progress: 0.46,
            saved: saved,
          );

          await tester.tap(find.byType(ProgressFieldRow));
          await tester.pumpAndSettle();
          await tester.drag(find.byType(CupertinoPicker), const Offset(0, 34));
          await tester.pumpAndSettle();
          // Backed out instead of confirming, so the turn was never an answer.
          Navigator.of(tester.element(find.byType(CupertinoPicker))).pop();
          await tester.pumpAndSettle();

          expect(find.text('46%'), findsOneWidget);

          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          expect(saved.single.progress, 0.46);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given a position and then a status change, When saved, Then both are kept',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // A position is a fact about the text, not about the status: closing a
          // book must not zero it and finishing one must not fill it to 100%.
          // Either would make the field a derived value with a control attached.
          final saved = <_Saved>[];
          await _openSheet(
            tester,
            currentStatus: 1,
            startDate: DateTime(2024, 3, 14),
            progress: 0.46,
            saved: saved,
          );

          await tester.tap(find.text('Interested'));
          await tester.pumpAndSettle();
          expect(find.byType(ProgressFieldRow), findsNothing);

          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          expect(saved.single.status, 0);
          expect(saved.single.startDate, isNull);
          // The row is off screen, and the value is still the reader's.
          expect(saved.single.progress, 0.46);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given a book with no page count, When the wheel opens, Then it still works',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // About two reading books in three. The wheel spins percent, so this is
          // the ordinary case rather than a degraded one; only the rider is gone.
          await _openSheet(tester, currentStatus: 1, progress: 0.46);

          await tester.tap(find.byType(ProgressFieldRow));
          await tester.pumpAndSettle();

          expect(find.byType(CupertinoPicker), findsOneWidget);
          expect(find.textContaining('p.'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // The reading day.
  //
  // "Should saving a position stamp the day?" is closed by construction, and these
  // cases exist to keep it closed. Nine of the twelve drawn versions of this design
  // died of connecting the two, so the isolation is asserted **in both directions**
  // rather than once.

  group('the read-today row', () {
    testWidgets('appears only while the book is open', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openSheet(tester, currentStatus: 0);
        expect(find.byType(ReadTodayFieldRow), findsNothing);

        await tester.tap(find.text('Reading'));
        await tester.pumpAndSettle();
        expect(find.byType(ReadTodayFieldRow), findsOneWidget);

        // A finished book has no tonight to record, and an unstarted one has no
        // reading to record it against.
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        expect(find.byType(ReadTodayFieldRow), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Given today is recorded, Then it opens ticked', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openSheet(tester, currentStatus: 1, readToday: true);
        expect(
          tester.widget<ReadTodayFieldRow>(find.byType(ReadTodayFieldRow)).read,
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Given today is not recorded, Then it opens unticked', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _openSheet(tester, currentStatus: 1);
        expect(
          tester.widget<ReadTodayFieldRow>(find.byType(ReadTodayFieldRow)).read,
          isFalse,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('ticking it is what the Save carries out', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final saved = <_Saved>[];
        await _openSheet(tester, currentStatus: 1, saved: saved);

        await tester.tap(find.byType(ReadTodayFieldRow));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(saved.single.readToday, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('unticking it is how a mis-recorded day is withdrawn', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // A habit ledger you cannot correct is one you stop trusting, which is why
        // the RLS policy grants DELETE at all.
        final saved = <_Saved>[];
        await _openSheet(
          tester,
          currentStatus: 1,
          readToday: true,
          saved: saved,
        );

        await tester.tap(find.byType(ReadTodayFieldRow));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(saved.single.readToday, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Given the day is recorded, When saved, Then nothing else moved',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Direction one of the isolation: stamping a day touches no position, no
          // date, no status.
          final saved = <_Saved>[];
          final start = DateTime(2024, 3, 14);
          await _openSheet(
            tester,
            currentStatus: 1,
            startDate: start,
            progress: 0.46,
            saved: saved,
          );

          await tester.tap(find.byType(ReadTodayFieldRow));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          expect(saved.single.readToday, isTrue);
          expect(saved.single.status, 1);
          expect(saved.single.startDate, start);
          expect(saved.single.finishDate, isNull);
          expect(saved.single.progress, 0.46);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given a position is set, When saved, Then the day is not recorded',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // Direction two, and the one the drawings kept getting wrong: moving a
          // bookmark is not evidence of having read tonight. A reader tidying up
          // three books on a Sunday has not read three nights.
          final saved = <_Saved>[];
          await _openSheet(
            tester,
            currentStatus: 1,
            progress: 0.46,
            pageCount: 320,
            saved: saved,
          );

          await tester.tap(find.byType(ProgressFieldRow));
          await tester.pumpAndSettle();
          await tester.drag(find.byType(CupertinoPicker), const Offset(0, 34));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Confirm'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          expect(saved.single.progress, closeTo(0.45, 1e-9));
          expect(saved.single.readToday, isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Given the book is closed, When saved, Then the day is still carried',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          // A day the reader recorded is not the status's to withdraw. The row goes
          // off screen; the fact does not.
          final saved = <_Saved>[];
          await _openSheet(
            tester,
            currentStatus: 1,
            startDate: DateTime(2024, 3, 14),
            readToday: true,
            saved: saved,
          );

          await tester.tap(find.text('Interested'));
          await tester.pumpAndSettle();
          expect(find.byType(ReadTodayFieldRow), findsNothing);

          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();

          expect(saved.single.status, 0);
          expect(saved.single.readToday, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
