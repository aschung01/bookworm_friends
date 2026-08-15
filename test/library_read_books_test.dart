// Read books belong to the "Books read" pile at the bottom of the library, not
// to the shelves above it. Showing them in both places listed every read book
// twice, so the shelves filter them out.
//
// The book keeps its shelf in the database: only the display is filtered, and a
// reorder that can't see the finished books must not drop them from state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/pages/user_library_page.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
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
    finishedBooksProvider.overrideWith((ref, filter) async => [_readBook()]),
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

/// Pumps [UserLibraryPage] for a friend whose one shelf holds [shelfBooks] and
/// whose pile holds [pileBooks]. The page reads its target user from the route
/// arguments, hence `onGenerateRoute`.
Future<void> _pumpFriendPage(
  WidgetTester tester, {
  required List<Book> shelfBooks,
  required List<Book> pileBooks,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u'),
        isFollowingProvider.overrideWith((ref, userId) async => true),
        userLibraryProvider.overrideWith(
          (ref, userId) async => [testShelf('s1', shelfBooks, name: 'Dev')],
        ),
        userFinishedBooksProvider.overrideWith(
          (ref, params) async => pileBooks,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          settings: const RouteSettings(
            arguments: <String, dynamic>{'user_id': 'f1', 'username': 'friend'},
          ),
          builder: (_) => const UserLibraryPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group("a friend's library page", () {
    testWidgets(
      'Given a shelf holding a read book, When the page is shown, Then the read book is in the pile and off the shelf',
      (tester) async {
        await _pumpFriendPage(
          tester,
          shelfBooks: _mixedShelfBooks(),
          pileBooks: [_readBook()],
        );

        expect(find.byType(BookWidget), findsOneWidget);
        expect(
          tester.widget<BookWidget>(find.byType(BookWidget)).heroTag,
          'book_b1',
        );
        expect(find.byType(BookVertical), findsOneWidget);
        expect(find.text('Dune'), findsOneWidget);
      },
    );

    testWidgets(
      'Given the friend has no books at all, When the page is shown, Then the empty-library message replaces the pile',
      (tester) async {
        await _pumpFriendPage(tester, shelfBooks: [], pileBooks: []);

        expect(find.text('This library is empty'), findsOneWidget);
        expect(find.byType(BookVertical), findsNothing);
        expect(find.text('Books read'), findsNothing);
      },
    );

    testWidgets(
      'Given the friend has only read books, When the page is shown, Then the pile shows them instead of the empty message',
      (tester) async {
        await _pumpFriendPage(
          tester,
          shelfBooks: [_readBook()],
          pileBooks: [_readBook()],
        );

        expect(find.text('This library is empty'), findsNothing);
        expect(find.text('Dune'), findsOneWidget);
      },
    );
  });

  group('shelves', () {
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
      'Given a shelf holding a read book, When the library is shown, Then the read book is in the pile',
      (tester) async {
        await _pumpMixedLibrary(tester);

        expect(find.byType(BookVertical), findsOneWidget);
        expect(find.text('Dune'), findsOneWidget);
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
            finishedBooksProvider.overrideWith(
              (ref, filter) async => [_readBook()],
            ),
          ],
        );

        expect(find.byType(BookWidget), findsNothing);
        expect(find.text('Dev'), findsOneWidget);
        expect(find.text('Dune'), findsOneWidget);
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
            finishedBooksProvider.overrideWith((ref, filter) async => <Book>[]),
          ],
        );

        expect(find.text('Dev'), findsOneWidget);
        expect(find.text('No books read yet 🥲'), findsOneWidget);
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
