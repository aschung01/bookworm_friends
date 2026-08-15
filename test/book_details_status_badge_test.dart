// Regression tests for the status badge in the book-details hero corner.
//
// On a *friend's* book the right-hand column carries the praise button and the
// compliment chips, so the badge ended up laid out at the bottom-right — the
// exact spot where the `Positioned` shelf label is painted over it, leaving the
// badge invisible. The badge now stacks directly above the label, so the check
// that matters is geometric: the two rects must not intersect.
//
// The owner's own book keeps the badge in the right-hand column (top-right,
// where the praise button would otherwise sit), so it is asserted separately to
// make sure the fix didn't move or duplicate it.

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
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';

import 'support/home_page_harness.dart' show FakeLibraryNotifier;

const _me = 'me';
const _friend = 'friend';
const _shelfId = 's1';

/// The catalog lookup is irrelevant to the hero corner, and hitting the network
/// from a widget test is not an option.
class _NoBookInfo implements BookSearchProvider {
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
/// friend, which is the layout that produced the bug.
Book _finishedBook({required String ownerId}) => Book(
  id: 'b1',
  userId: ownerId,
  shelfId: _shelfId,
  isbn: '440238498',
  title: 'Eldest',
  thumbnail: '', // empty keeps `Image.network` out of the test
  status: 2,
  position: 0,
  startDate: DateTime(2023, 12, 9),
  finishDate: DateTime(2023, 12, 23),
  createdAt: DateTime(2023, 12, 9),
);

List<Shelf> _shelves(String ownerId) => [
  Shelf(
    id: _shelfId,
    userId: ownerId,
    name: 'Novels',
    position: 0,
    createdAt: DateTime(2023),
    books: const [],
  ),
];

BookCompliment _compliment(String emoji) => BookCompliment(
  id: 'c1',
  bookId: 'b1',
  fromUserId: _me,
  compliment: emoji,
  createdAt: DateTime(2024),
);

Future<void> _pumpDetails(
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
        bookSearchProvider.overrideWithValue(_NoBookInfo()),
        bookMemosProvider(book.id).overrideWith((ref) async => <BookMemo>[]),
        bookComplimentsProvider(
          book.id,
        ).overrideWith((ref) async => compliments),
        // Shelf names resolve against the owner's library, so both the self and
        // friend paths need stubbing.
        userLibraryProvider(
          book.userId,
        ).overrideWith((ref) async => _shelves(book.userId)),
        libraryProvider.overrideWith(
          () => FakeLibraryNotifier(_shelves(book.userId)),
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

void main() {
  group('BookDetailsTabView status badge', () {
    testWidgets(
      "Given a friend's finished book, When the details page is shown, Then the status badge is not hidden behind the shelf label",
      (tester) async {
        await _pumpDetails(
          tester,
          book: _finishedBook(ownerId: _friend),
          signedInAs: _me,
          compliments: [_compliment('👏')],
        );

        // The layout that broke: praise button and chips own the top-right.
        expect(find.text('Praise'), findsOneWidget);
        expect(find.text('👏'), findsOneWidget);

        expect(find.byType(BookStatusBadge), findsOneWidget);
        expect(find.byType(ShelfLabel), findsOneWidget);
        expect(find.text('Novels'), findsOneWidget);

        final badge = tester.getRect(find.byType(BookStatusBadge));
        final label = tester.getRect(find.byType(ShelfLabel));

        expect(badge.isEmpty, isFalse);
        expect(label.isEmpty, isFalse);
        expect(
          badge.overlaps(label),
          isFalse,
          reason: 'badge $badge must not sit under the shelf label $label',
        );
        // Specifically: stacked above the label, sharing its right edge.
        expect(badge.bottom, lessThanOrEqualTo(label.top));
        expect(badge.right, closeTo(label.right, 0.5));
      },
    );

    testWidgets(
      "Given the owner's own finished book, When the details page is shown, Then a single badge stays clear of the shelf label",
      (tester) async {
        await _pumpDetails(
          tester,
          book: _finishedBook(ownerId: _me),
          signedInAs: _me,
        );

        // No praise button on your own book, so the column's top-right is free.
        expect(find.text('Praise'), findsNothing);
        // Rendered by the column, not duplicated into the label stack.
        expect(find.byType(BookStatusBadge), findsOneWidget);

        final badge = tester.getRect(find.byType(BookStatusBadge));
        final label = tester.getRect(find.byType(ShelfLabel));

        expect(badge.overlaps(label), isFalse);
        expect(badge.bottom, lessThanOrEqualTo(label.top));
      },
    );
  });
}
