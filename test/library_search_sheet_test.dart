// The search sheet's two sections: the reader's own library, then the catalogue.
//
// Deliberately does **not** use `support/home_page_harness.dart`. That pulls in
// `HomePage` -> `library_view.dart` -> `shelf_row.dart`, and this suite has to be
// able to run while that file is mid-rewrite. The sheet is pumped directly, which
// is also closer to what it is: a modal that only needs a `Navigator` above it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/add_book_bottom_sheet.dart';

const Size _phone = Size(402, 874);

/// A catalogue that answers every query with [pages], one entry per page.
///
/// Records what it was asked for, so the suppression tests can assert on *how
/// many raw pages were pulled* — which is the only way to tell the two paging
/// traps apart from the outside.
class FakeCatalogue implements BookSearchProvider {
  FakeCatalogue(this.pages);

  final List<List<BookSearchResult>> pages;
  final List<int> requested = [];

  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async {
    requested.add(page);
    return page <= pages.length ? pages[page - 1] : const [];
  }

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async => null;
}

class FakeLibrary extends LibraryNotifier {
  FakeLibrary(this.shelves);
  final List<Shelf> shelves;
  @override
  Future<List<Shelf>> build() async => shelves;
}

Book book({
  String id = 'b1',
  String title = 'Dune',
  List<String> authors = const ['Frank Herbert'],
  String isbn = '9780441013593',
  int status = 0,
}) => Book(
  id: id,
  userId: 'u',
  shelfId: 's1',
  isbn: isbn,
  title: title,
  thumbnail: '',
  status: status,
  position: 0,
  createdAt: DateTime(2024),
  authors: authors,
);

Shelf shelf(List<Book> books, {String name = 'Bought, not read'}) => Shelf(
  id: 's1',
  userId: 'u',
  name: name,
  position: 0,
  createdAt: DateTime(2024),
  books: books,
);

BookSearchResult result({
  String title = 'Dune',
  List<String> authors = const ['Frank Herbert'],
  String isbn = '9780441013593',
}) =>
    BookSearchResult(title: title, isbn: isbn, thumbnail: '', authors: authors);

Future<void> pumpSheet(
  WidgetTester tester, {
  required List<Shelf> shelves,
  required BookSearchProvider catalogue,
}) async {
  tester.view.physicalSize = _phone * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryProvider.overrideWith(() => FakeLibrary(shelves)),
        bookSearchProvider.overrideWithValue(catalogue),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAddBookBottomSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Types into the field and submits, which is what asks the catalogue.
///
/// Pass `settle: false` when the expected result keeps a trailing
/// [CircularProgressIndicator] on screen — i.e. whenever `hasMore` stays true.
/// `pumpAndSettle` never returns while one is spinning, the same trap
/// `home_page_harness` records for the loading shimmer.
Future<void> submit(
  WidgetTester tester,
  String query, {
  bool settle = true,
}) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

void main() {
  testWidgets('opens on the empty state, with the scan action reachable', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      shelves: [
        shelf([book()]),
      ],
      catalogue: FakeCatalogue(const []),
    );

    expect(find.text('Search books'), findsOneWidget);
    expect(find.text('Scan a book'), findsOneWidget);
    // Neither section exists until something is typed.
    expect(find.text('IN YOUR LIBRARY'), findsNothing);
    expect(find.text('ADD A NEW BOOK'), findsNothing);
    expect(find.textContaining('Search for'), findsNothing);
  });

  testWidgets('typing answers from the library before the catalogue is asked', (
    tester,
  ) async {
    final catalogue = FakeCatalogue([
      [result(title: 'Something Else', isbn: '9999999999999')],
    ]);
    await pumpSheet(
      tester,
      shelves: [
        shelf([book()]),
      ],
      catalogue: catalogue,
    );

    // Typed, not submitted.
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pumpAndSettle();

    expect(find.text('IN YOUR LIBRARY'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    // The state that makes the one-field design legible: the library has
    // answered and the catalogue has not been consulted at all. Its section is
    // present, but holding an invitation rather than results.
    expect(find.text('ADD A NEW BOOK'), findsOneWidget);
    expect(find.text('Search for “dune”'), findsOneWidget);
    expect(catalogue.requested, isEmpty);
  });

  testWidgets('one query spans all three statuses', (tester) async {
    await pumpSheet(
      tester,
      shelves: [
        shelf([
          book(
            id: 'r',
            title: 'Dune Read',
            status: bookStatusFinished,
            isbn: '1',
          ),
          book(id: 'w', title: 'Dune Wanted', isbn: '2'),
          book(
            id: 'n',
            title: 'Dune Now',
            status: bookStatusReading,
            isbn: '3',
          ),
        ]),
      ],
      catalogue: FakeCatalogue(const []),
    );
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pumpAndSettle();

    // The screen that settles where this feature lives: no per-status surface in
    // the shell could have hosted this list.
    expect(find.byType(BookStatusBadge), findsNWidgets(3));
    expect(find.text('Interested'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    // In-progress first.
    final titles = tester
        .widgetList<BookStatusBadge>(find.byType(BookStatusBadge))
        .map((b) => b.status)
        .toList();
    expect(titles, [bookStatusReading, 0, bookStatusFinished]);
  });

  testWidgets('the row names the shelf the book stands on', (tester) async {
    await pumpSheet(
      tester,
      shelves: [
        shelf([book()], name: 'Bought, not read'),
      ],
      catalogue: FakeCatalogue(const []),
    );
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pumpAndSettle();

    expect(find.text('Bought, not read'), findsOneWidget);
  });

  testWidgets('an unmatched query still draws the section, with its line', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      shelves: [
        shelf([book()]),
      ],
      catalogue: FakeCatalogue([
        [result(title: 'Tomorrow', isbn: '9780593321201')],
      ]),
    );
    await submit(tester, 'tomorrow');

    // Kept above the divider even when empty, so the catalogue cannot jump into
    // the slot the local results held a keystroke ago.
    expect(find.text('IN YOUR LIBRARY'), findsOneWidget);
    expect(find.text('Nothing in your library matches.'), findsOneWidget);
    expect(find.text('ADD A NEW BOOK'), findsOneWidget);
  });

  group('duplicate suppression', () {
    testWidgets('an identical ISBN is dropped from the catalogue', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        shelves: [
          shelf([book()]),
        ],
        // Same ISBN as the owned copy, plus one genuinely new book.
        catalogue: FakeCatalogue([
          [result(), result(title: 'Dune Messiah', isbn: '9780593098233')],
        ]),
      );
      await submit(tester, 'dune');

      // One cover in the catalogue section, not two: the reader's own copy is
      // listed above and does not need drawing twice.
      expect(find.byType(BookWidget), findsOneWidget);
      expect(find.text('Nothing new to add.'), findsNothing);
    });

    testWidgets('everything owned gives "Nothing new to add."', (tester) async {
      await pumpSheet(
        tester,
        shelves: [
          shelf([book()]),
        ],
        catalogue: FakeCatalogue([
          [result()],
        ]),
      );
      await submit(tester, 'dune');

      // A header over nothing would read as a request that failed.
      expect(find.text('ADD A NEW BOOK'), findsOneWidget);
      expect(find.text('Nothing new to add.'), findsOneWidget);
      expect(find.byType(BookWidget), findsNothing);
      // The reader's own copy is still there — nothing was lost by hiding it
      // below.
      expect(find.byType(BookStatusBadge), findsOneWidget);
    });

    testWidgets('a title-and-author match is tagged, not dropped', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        shelves: [
          shelf([book()]),
        ],
        // Same book, different identifier: either another edition or a provider
        // with bad metadata. The app cannot tell, so it must not hide it.
        catalogue: FakeCatalogue([
          [result(isbn: '9999999999999')],
        ]),
      );
      await submit(tester, 'dune');

      expect(find.byType(BookWidget), findsOneWidget);
      expect(find.text('In your library'), findsOneWidget);
    });

    testWidgets('a fully-suppressed page pulls the next one', (tester) async {
      // Trap 2: an empty section has nothing to scroll, so `_onScroll` would
      // never ask for page 2 and the reader would see "nothing to add" while a
      // full page of new books sat one request away.
      final catalogue = FakeCatalogue([
        [for (var i = 0; i < 20; i++) result()], // all owned
        [result(title: 'Dune Messiah', isbn: '9780593098233')],
      ]);
      await pumpSheet(
        tester,
        shelves: [
          shelf([book()]),
        ],
        catalogue: catalogue,
      );
      await submit(tester, 'dune');

      expect(catalogue.requested, [1, 2]);
      expect(find.byType(BookWidget), findsOneWidget);
    });

    testWidgets('a full page that loses some entries still pages on', (
      tester,
    ) async {
      // Trap 1: paging is decided by the RAW page size. Filtering before that
      // check would make this 20-entry page look short, set `hasMore` false, and
      // silently strand the rest of the catalogue.
      final catalogue = FakeCatalogue([
        [
          result(), // owned, dropped
          for (var i = 0; i < 19; i++)
            result(title: 'New $i', isbn: '900000000000$i'),
        ],
        [result(title: 'Second page', isbn: '9780593098233')],
      ]);
      await pumpSheet(
        tester,
        shelves: [
          shelf([book()]),
        ],
        catalogue: catalogue,
      );
      await submit(tester, 'dune', settle: false);

      // Page 1 only so far — there was something to show, so no hop was needed.
      expect(catalogue.requested, [1]);

      // The actual claim, asserted the only way that is robust against a lazy
      // sliver list: paging must still be *live*. Scrolling to the bottom asks
      // for the next page, which cannot happen if the filtered page had been
      // mistaken for a short one and `hasMore` set false.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pump();
      expect(catalogue.requested, [1, 2]);
    });

    testWidgets('suppression stops after a bounded number of hops', (
      tester,
    ) async {
      // A reader who owns everything the catalogue has must not turn one
      // keystroke into an unbounded run of requests.
      final catalogue = FakeCatalogue([
        for (var p = 0; p < 10; p++) [for (var i = 0; i < 20; i++) result()],
      ]);
      await pumpSheet(
        tester,
        shelves: [
          shelf([book()]),
        ],
        catalogue: catalogue,
      );
      await submit(tester, 'dune');

      expect(catalogue.requested, [1, 2, 3]);
    });
  });

  group('the way to the catalogue', () {
    // The bug these cover, reported from a screenshot: type a query the library
    // cannot answer and the sheet drew "Nothing in your library matches." over
    // half a screen of nothing. The only way on was a return key, which is gone
    // the moment the keyboard is. The reader is told a search failed when in fact
    // no search had run.

    testWidgets('a query the library cannot answer still offers a way on', (
      tester,
    ) async {
      final catalogue = FakeCatalogue([
        [result(title: 'A Good Thing', isbn: '9780593321201')],
      ]);
      await pumpSheet(
        tester,
        shelves: [
          shelf([book()]),
        ],
        catalogue: catalogue,
      );
      await tester.enterText(find.byType(TextField), 'good thing');
      await tester.pumpAndSettle();

      expect(find.text('Nothing in your library matches.'), findsOneWidget);
      // Not a dead end: an offer, naming the query, on screen with no keyboard.
      expect(find.text('Search for “good thing”'), findsOneWidget);
      // And still nothing asked of the network until it is taken.
      expect(catalogue.requested, isEmpty);
    });

    testWidgets('taking the offer asks the catalogue and consumes it', (
      tester,
    ) async {
      final catalogue = FakeCatalogue([
        [result(title: 'A Good Thing', isbn: '9780593321201')],
      ]);
      await pumpSheet(
        tester,
        shelves: [
          shelf([book()]),
        ],
        catalogue: catalogue,
      );
      await tester.enterText(find.byType(TextField), 'good thing');
      await tester.pumpAndSettle();

      // The tap has to do exactly what the return key does, because it exists
      // for the readers who no longer have one.
      await tester.tap(find.text('Search for “good thing”'));
      await tester.pumpAndSettle();

      expect(catalogue.requested, [1]);
      expect(find.byType(BookWidget), findsOneWidget);
      // Answered, so the invitation is spent — it must not sit above its own
      // results inviting the same query again.
      expect(find.text('Search for “good thing”'), findsNothing);
    });

    testWidgets('editing after a search offers the new query, keeping the old '
        'results', (tester) async {
      final catalogue = FakeCatalogue([
        [result(title: 'Dune Messiah', isbn: '9780593098233')],
      ]);
      await pumpSheet(
        tester,
        shelves: [
          shelf([book()]),
        ],
        catalogue: catalogue,
      );
      await submit(tester, 'dune');
      expect(find.byType(BookWidget), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'dune messiah');
      await tester.pumpAndSettle();

      // The same defect in another dress: the results below are now answering a
      // query that is no longer the one on screen, so the reader needs the way
      // forward back.
      expect(find.text('Search for “dune messiah”'), findsOneWidget);
      // Kept, not cleared. They are stale, not wrong, and blanking them on a
      // keystroke would throw away the answer the reader is reading.
      expect(find.byType(BookWidget), findsOneWidget);
      // Editing alone must not re-ask the network — that is the whole reason the
      // catalogue waits to be told.
      expect(catalogue.requested, [1]);
    });
  });

  testWidgets('clearing the field puts the empty state back', (tester) async {
    await pumpSheet(
      tester,
      shelves: [
        shelf([book()]),
      ],
      catalogue: FakeCatalogue([
        [result(title: 'Dune Messiah', isbn: '9780593098233')],
      ]),
    );
    await submit(tester, 'dune');
    expect(find.text('IN YOUR LIBRARY'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('IN YOUR LIBRARY'), findsNothing);
    expect(find.text('Scan a book'), findsOneWidget);
  });
}
