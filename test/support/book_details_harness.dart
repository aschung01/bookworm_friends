// Shared setup for widget tests against [BookDetailsTabView].
//
// The view reads its `Book` off `ModalRoute.settings.arguments` and leans on a
// handful of providers (catalog lookup, memos, compliments, the owner's shelves)
// so pumping it takes more scaffolding than a plain `pumpWidget`. Kept here so
// the badge-layout and compliment-visibility suites share one description of
// what a details page needs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/models/book_memo.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/views/book_details_tab_view.dart';

import 'home_page_harness.dart' show FakeLibraryNotifier;

const meId = 'me';
const friendId = 'friend';

/// A third party: someone who is neither the viewer nor the book's owner.
const otherId = 'other';
const shelfId = 's1';
const shelfName = 'Novels';

/// The catalog lookup is irrelevant to the hero corner, and hitting the network
/// from a widget test is not an option.
class NoBookInfo implements BookSearchProvider {
  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async => const [];

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async => null;
}

/// A finished book — status 2 is what puts the praise button on screen for a
/// friend, and the only status that can be praised at all.
Book finishedBook({required String ownerId}) => Book(
  id: 'b1',
  userId: ownerId,
  shelfId: shelfId,
  isbn: '440238498',
  title: 'Eldest',
  thumbnail: '', // empty keeps `Image.network` out of the test
  status: 2,
  position: 0,
  startDate: DateTime(2023, 12, 9),
  finishDate: DateTime(2023, 12, 23),
  createdAt: DateTime(2023, 12, 9),
);

/// A book still in progress: status 1 withholds the praise button.
Book readingBook({required String ownerId}) => Book(
  id: 'b1',
  userId: ownerId,
  shelfId: shelfId,
  isbn: '440238498',
  title: 'Eldest',
  thumbnail: '',
  status: 1,
  position: 0,
  startDate: DateTime(2023, 12, 9),
  createdAt: DateTime(2023, 12, 9),
);

List<Shelf> shelvesFor(String ownerId) => [
  Shelf(
    id: shelfId,
    userId: ownerId,
    name: shelfName,
    position: 0,
    createdAt: DateTime(2023),
    books: const [],
  ),
];

BookCompliment compliment(
  String emoji, {
  String id = 'c1',
  String from = meId,
}) => BookCompliment(
  id: id,
  bookId: 'b1',
  fromUserId: from,
  compliment: emoji,
  createdAt: DateTime(2024),
);

Future<void> pumpBookDetails(
  WidgetTester tester, {
  required Book book,
  required String signedInAs,
  List<BookCompliment> compliments = const [],
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // iPhone-ish, 390x844 dp
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(signedInAs),
        bookSearchProvider.overrideWithValue(NoBookInfo()),
        bookMemosProvider(book.id).overrideWith((ref) async => <BookMemo>[]),
        bookComplimentsProvider(
          book.id,
        ).overrideWith((ref) async => compliments),
        // Shelf names resolve against the owner's library, so both the self and
        // friend paths need stubbing.
        userLibraryProvider(
          book.userId,
        ).overrideWith((ref) async => shelvesFor(book.userId)),
        libraryProvider.overrideWith(
          () => FakeLibraryNotifier(shelvesFor(book.userId)),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The view reads its `Book` off `ModalRoute.settings.arguments`, so it
        // needs a generated route rather than `home:`.
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => const BookDetailsTabView(),
          settings: RouteSettings(name: settings.name, arguments: book),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
