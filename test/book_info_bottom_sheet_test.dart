// Tests for the "save a book" sheet: its response to a status change, and the cover
// colour it reports back.
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
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_info_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

const _book = BookSearchResult(
  title: 'What You Do Is Who You Are',
  isbn: '9780062871336',
  thumbnail: '',
  authors: ['Ben Horowitz'],
  publisher: 'HarperCollins',
);

/// The shape of the sheet's save callback, named so a test can capture it.
typedef _OnSave =
    void Function(
      String shelfName,
      int status, {
      DateTime? startDate,
      DateTime? finishDate,
      Color? coverColor,
    });

/// Opens the sheet and returns once it has finished presenting.
Future<void> _openSheet(WidgetTester tester, {_OnSave? onSave}) async {
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
                onSavePressed:
                    onSave ?? (_, __, {startDate, finishDate, coverColor}) {},
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

  group('the cover colour it reports back', () {
    // **`addBook` took a `coverColor` that no production caller ever passed**, so every
    // insert wrote `cover_color: null` and the column was filled in later by whichever
    // screen happened to render the book next. Worst for a book saved as *finished*,
    // which `withoutFinishedBooks` keeps off the shelves: the densest backfill path
    // never saw it, and it sat in the read pile wearing an ISBN-hashed brand swatch.
    // `The House of the Scorpion` showed coral `#E0644E`, which is
    // `bookHash('9781665918589') % 6`.
    //
    // The sheet already draws the cover through a [BookWidget], which samples every
    // image it decodes in order to tone its own back board, so the value was being
    // computed and thrown away. These two tests pin the wire it now travels along.

    testWidgets('Given the cover was sampled, When Save is tapped, Then the sample '
        'is handed to the caller', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        Color? saved;
        var calls = 0;
        await _openSheet(
          tester,
          onSave: (_, __, {startDate, finishDate, coverColor}) {
            calls++;
            saved = coverColor;
          },
        );

        // The callback is driven directly rather than by decoding an image, because a
        // real decode is not available here: `flutter_test` installs an `HttpOverrides`
        // that answers every request with a 400, so `NetworkImage` never resolves and
        // the sampler never runs. What is under test is the wiring; `coverToneColor`
        // itself is measured against 460 real covers by the probe tool.
        final cover = tester.widget<BookWidget>(find.byType(BookWidget));
        expect(
          cover.onCoverSampled,
          isNotNull,
          reason: 'the sheet stopped listening for its own cover sample',
        );
        cover.onCoverSampled!(const Color(0xFF2A2A2A));

        await tester.tap(find.byType(ElevatedActionButton));
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(
          saved,
          const Color(0xFF2A2A2A),
          reason: 'the sample was computed and dropped, the original bug',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Given the cover never resolved, When Save is tapped, Then the '
        'colour is null rather than a guess', (tester) async {
      // **Null has to stay ordinary.** A reader can tap Save before the thumbnail
      // arrives, and a book with no thumbnail never samples at all — `_book` here has
      // none. Both cases insert null and fall back to the ISBN swatch until the backfill
      // reaches them, which is what every book did before this wire existed.
      //
      // A sheet that invented a colour instead would be worse than one reporting
      // nothing: `recordCoverColor` skips any book that already has a colour, so a guess
      // would never be revisited.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        Color? saved;
        var calls = 0;
        await _openSheet(
          tester,
          onSave: (_, __, {startDate, finishDate, coverColor}) {
            calls++;
            saved = coverColor;
          },
        );

        await tester.tap(find.byType(ElevatedActionButton));
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(saved, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
