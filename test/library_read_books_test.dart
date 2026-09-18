// Read books belong to the "Books read" pile at the bottom of the library, not
// to the shelves above it. Showing them in both places listed every read book
// twice, so the shelves filter them out.
//
// The book keeps its shelf in the database: only the display is filtered, and a
// reorder that can't see the finished books must not drop them from state.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

import 'support/home_page_harness.dart';

Book _readBook() => testBook(
  'b2',
  's1',
  position: 1,
  title: 'Dune',
  status: bookStatusFinished,
);

/// One shelf holding an unread book and a read one.
List<Book> _mixedShelfBooks() => [
  testBook('b1', 's1', position: 0, title: 'Clean Code'),
  _readBook(),
];

Future<void> _pumpMixedLibrary(WidgetTester tester) => pumpHome(
  tester,
  shelves: [testShelf('s1', _mixedShelfBooks(), name: 'Dev')],
  extraOverrides: [
    finishedBooksProvider.overrideWith((ref) async => [_readBook()]),
  ],
);

/// Ids of the books on [shelfId] in library state, in order.
List<String> _idsOn(ProviderContainer container, String shelfId) => container
    .read(libraryProvider)
    .value!
    .firstWhere((s) => s.id == shelfId)
    .books
    .map((b) => b.id)
    .toList();

void main() {
  group('shelves', () {
    // **These cases are about the shelves, and deliberately assert nothing about the pile.**
    // Three of them used to, and went stale when `ReadPile` moved out of the library page
    // into `FinishedBooksSheet` (presented from `home_page.dart`): a bare pumped home has no
    // pile inline any more, so expectations on a spine, on a finished book's title, or on
    // the pile's own empty state were failing for a reason that had nothing to do with what
    // they were named for. The pile's side of each claim is covered where the pile now lives
    // — `finished_books_sheet_test.dart` for the spines, `read_month_grid_test.dart` for the
    // "no books read yet" state. What is left here is the half this file is actually about:
    // a read book is off the plank, and the library keeps its shelves rather than falling
    // back to the add-a-book prompt.
    testWidgets(
      'Given a shelf holding a read book, When the library is shown, Then only the unread cover is on the shelf',
      (tester) async {
        await _pumpMixedLibrary(tester);

        expect(find.byType(BookWidget), findsOneWidget);
        expect(
          tester.widget<BookWidget>(find.byType(BookWidget)).heroTag,
          'book_b1',
        );
      },
    );

    testWidgets(
      'Given every book on a shelf is read, When the library is shown, Then the shelf empties rather than the library',
      (tester) async {
        await pumpHome(
          tester,
          shelves: [
            testShelf('s1', [_readBook()], name: 'Dev'),
          ],
          extraOverrides: [
            finishedBooksProvider.overrideWith((ref) async => [_readBook()]),
          ],
        );

        expect(find.byType(BookWidget), findsNothing);
        expect(find.text('Dev'), findsOneWidget);
      },
    );

    testWidgets(
      'Given every book is read but the pile filter excludes them, When the library is shown, Then the shelves stay instead of the add-a-book prompt',
      (tester) async {
        await pumpHome(
          tester,
          shelves: [
            testShelf('s1', [_readBook()], name: 'Dev'),
          ],
          // Stands in for a year/month filter that matches nothing.
          extraOverrides: [
            finishedBooksProvider.overrideWith((ref) async => <Book>[]),
          ],
        );

        expect(find.text('Dev'), findsOneWidget);
        expect(find.textContaining('to add a book'), findsNothing);
      },
    );
  });

  group('withoutFinishedBooks', () {
    test('Given a mixed shelf, Then only the unfinished books are kept', () {
      final filtered = withoutFinishedBooks([
        testShelf('s1', _mixedShelfBooks()),
      ]);

      expect(filtered.single.books.map((b) => b.id), ['b1']);
    });

    test('Given a shelf, Then the original list is left alone', () {
      final shelves = [testShelf('s1', _mixedShelfBooks())];

      withoutFinishedBooks(shelves);

      expect(shelves.single.books.map((b) => b.id), ['b1', 'b2']);
    });
  });

  group('reordering a shelf that hides read books', () {
    test(
      'Given the read books are not listed, When reordering, Then they survive and the listed ones are renumbered',
      () async {
        final container = ProviderContainer(
          overrides: [
            libraryProvider.overrideWith(
              () => FakeLibraryNotifier([
                testShelf('s1', [
                  testBook('b1', 's1', position: 0),
                  testBook('b2', 's1', position: 1, status: bookStatusFinished),
                  testBook('b3', 's1', position: 2),
                ]),
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(libraryProvider.future);

        // The optimistic reorder lands synchronously; the database write behind
        // it has no Supabase to reach from a unit test, so its failure is
        // swallowed here.
        final reorder = container
            .read(libraryProvider.notifier)
            .reorderBooksInShelf('s1', ['b3', 'b1'])
            .catchError((_) {});

        expect(_idsOn(container, 's1'), containsAll(['b1', 'b2', 'b3']));
        final positions = {
          for (final book
              in container.read(libraryProvider).value!.single.books)
            book.id: book.position,
        };
        expect(positions['b3'], 0);
        expect(positions['b1'], 1);
        // Untouched: its position only matters again once it is unread.
        expect(positions['b2'], 1);

        await reorder;
      },
    );
  });
}
