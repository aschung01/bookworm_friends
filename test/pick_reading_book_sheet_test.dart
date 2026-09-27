/// The book picker: step one of the mandatory pair.
///
/// **What the cases are about.** Three variants were drawn (`docs/mockups/streaks/index.html`,
/// `cp-d-pick` / `-big` / `-shelf`) and the chosen one is the 44×66 list. Two of its
/// properties are the reason it was chosen rather than decoration: the *ordering* (reading
/// books first, because on an ordinary night the answer is a few rows from the top) and the
/// *ribbon* (because the very next question is how far in, so the reader should see where the
/// app already thinks they are on the thing they are tapping).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/pick_reading_book_sheet.dart';

import 'support/home_page_harness.dart';

List<Book> _library() => [
  testBook(
    'open-a',
    's',
    title: 'The Dispossessed',
    status: 1,
    progress: 0.46,
    authors: const ['Ursula K. Le Guin'],
  ),
  testBook(
    'open-b',
    's',
    title: 'Piranesi',
    status: 1,
    authors: const ['Susanna Clarke'],
  ),
  testBook(
    'shelved',
    's',
    title: 'Middlemarch',
    authors: const ['George Eliot'],
  ),
  testBook(
    'wanted',
    's',
    title: 'Stoner',
    status: 0,
    authors: const ['John Williams'],
  ),
];

/// Opens the sheet and hands back whatever it resolved to.
Future<Book?> _open(WidgetTester tester, {List<Book>? books}) async {
  Book? chosen;
  var resolved = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                chosen = await showPickReadingBookSheet(
                  context,
                  books: books ?? _library(),
                );
                resolved = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // Read by the caller after it taps a row; `resolved` exists so a case can tell "not
  // chosen yet" from "chosen null".
  addTearDown(() => expect(resolved || chosen == null, isTrue));
  return chosen;
}

void main() {
  testWidgets('reading books are their own group and come first', (
    tester,
  ) async {
    // On almost every night the answer is three rows from the top. A reader who has to
    // *search* for the book in their hand has been failed by the ordering, not by the field.
    await _open(tester);

    expect(find.text('Reading now'), findsOneWidget);
    expect(find.text('Everything else'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Reading now')).dy,
      lessThan(tester.getTopLeft(find.text('Everything else')).dy),
    );
    expect(
      tester.getTopLeft(find.text('The Dispossessed')).dy,
      lessThan(tester.getTopLeft(find.text('Middlemarch')).dy),
    );
  });

  testWidgets('tapping a row answers with that book', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Piranesi'));
    await tester.pumpAndSettle();

    // The sheet's whole contract: it resolves to a Book, and a dismissal resolves to null so
    // the caller can abandon the pair rather than stamping a day with no attribution.
    expect(find.text('Reading now'), findsNothing);
  });

  testWidgets('the search field filters on title and on author', (
    tester,
  ) async {
    // The field is for the case the grouping does not cover: a book that is not on the
    // Reading shelf. Authors are searchable because "the Le Guin one" is how a reader holds
    // a book whose title they cannot spell.
    await _open(tester);

    await tester.enterText(find.byType(TextField), 'middle');
    await tester.pumpAndSettle();
    expect(find.text('Middlemarch'), findsOneWidget);
    expect(find.text('Piranesi'), findsNothing);
    expect(
      find.text('Reading now'),
      findsNothing,
      reason:
          'a group with no surviving members should not leave its heading behind',
    );

    await tester.enterText(find.byType(TextField), 'clarke');
    await tester.pumpAndSettle();
    expect(find.text('Piranesi'), findsOneWidget);
    expect(find.text('Middlemarch'), findsNothing);
  });

  testWidgets('an empty library is a prompt to add a book', (tester) async {
    // Split from the case below rather than asserted beside it: `pumpWidget` keeps the
    // navigator's state, so a second `_open` in one test opens a sheet behind the first and
    // finds nothing. `select_percent_bottom_sheet_test` documents the same trap.
    await _open(tester, books: const []);
    expect(find.textContaining('Add a book'), findsOneWidget);
  });

  testWidgets('a query that matched nothing says so instead', (tester) async {
    // Different facts, different lines: telling a reader with 300 books to add one because
    // their search missed would be absurd.
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing matches'), findsOneWidget);
    expect(find.textContaining('Add a book'), findsNothing);
  });

  testWidgets('the ribbon is drawn on open books and on nothing else', (
    tester,
  ) async {
    // The shipped rule: a book that is not being read carries no mark. Drawing one would
    // claim a position the book has no business having.
    await _open(tester);

    expect(find.byType(ReadingBookmark), findsNWidgets(2));
    for (final bookmark in find.byType(ReadingBookmark).evaluate()) {
      final row = find.ancestor(
        of: find.byWidget(bookmark.widget),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: row, matching: find.text('Middlemarch')),
        findsNothing,
      );
    }
  });

  testWidgets('the ribbon is scaled to this cover, not drawn at shelf size', (
    tester,
  ) async {
    // The card's own rule for a smaller cover. Unscaled, a 38pt asset on a 66pt cover is
    // more than half the jacket and reads as a bookmark sticking out of a pamphlet.
    await _open(tester);

    final bookmark = tester.widget<ReadingBookmark>(
      find.byType(ReadingBookmark).first,
    );
    expect(bookmark.scale, kPickerCoverHeight / kReadingBookmarkBook);
    expect(bookmark.scale, lessThan(1));
  });

  testWidgets('the cover is 44×66 at the app\'s own aspect', (tester) async {
    // The size is the decision: at 26×39 a cover is a colour swatch, legible as *a book* and
    // useless as *which book*. The width is derived from the aspect rather than typed, so
    // this row cannot draw a book at a ratio no shelf uses.
    await _open(tester);

    final cover = tester.getSize(
      find
          .ancestor(
            of: find.byType(ReadingBookmark).first,
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(cover.height, kPickerCoverHeight);
    expect(
      cover.width,
      closeTo(kPickerCoverHeight * kDefaultCoverAspect, 0.01),
    );
  });

  testWidgets('the jacket carries no title, because the row already does', (
    tester,
  ) async {
    // Below `kGeneratedCoverMinWidth` a generated title sets under 7pt and reads as a
    // rendering fault. `CardCoverRow` and the add-book sheet make the same trade; this row
    // has the extra reason that the title is already beside the cover at 15pt.
    await _open(tester);

    expect(
      find.text('The Dispossessed'),
      findsOneWidget,
      reason:
          'one title per book: the row\'s. A second on the jacket is a 6pt smudge',
    );
  });

  testWidgets(
    'a known position rides beside the book, and an unknown one does not',
    (tester) async {
      // The exact figure beside the approximate one: the ribbon says *about halfway*, this says
      // 46%. Absent rather than 0% where nothing is recorded — null and zero are deliberately
      // different facts on `Book.progress`.
      await _open(tester);

      expect(find.text('46%'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    },
  );
}
