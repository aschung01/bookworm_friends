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
import 'package:bookworm_friends/providers/libby_library_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show libraryActionsProvider, LibraryActions;
import 'package:bookworm_friends/services/apple_books_lookup.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/services/overdrive_lookup.dart';
import 'package:bookworm_friends/ui/views/book_details_tab_view.dart';

import 'home_page_harness.dart' show FakeLibraryNotifier;
import 'prefs.dart' show sharedPreferencesOverride;

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

/// A finished book — status 2 is what puts the react button on screen for a
/// friend, and the only status a reaction can be *added* to.
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

/// A book still in progress: status 1 withholds the react button.
///
/// [progress] is null by default — the state of every reading book in production
/// on the day the column shipped, and the one that draws no bar and no read-out.
Book readingBook({required String ownerId, double? progress, int? pageCount}) =>
    Book(
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
      progress: progress,
      pageCount: pageCount,
    );

/// Status 0, and the case that decides where the status badge can live: no
/// dates, so no reading-period card for it to sit inside. 133 of 472 books in
/// production are here.
Book interestedBook({required String ownerId}) => Book(
  id: 'b1',
  userId: ownerId,
  shelfId: shelfId,
  isbn: '440238498',
  title: 'Eldest',
  thumbnail: '',
  status: 0,
  position: 0,
  createdAt: DateTime(2023, 12, 9),
);

List<Shelf> shelvesFor(String ownerId, {List<Book> books = const []}) => [
  Shelf(
    id: shelfId,
    userId: ownerId,
    name: shelfName,
    position: 0,
    createdAt: DateTime(2023),
    books: books,
  ),
];

/// One reaction.
///
/// [name] defaults to a readable stand-in rather than to null, because null has
/// a specific meaning here — a profile the `profiles` policy would not let this
/// viewer read — and a test that wanted the ordinary case should not accidentally
/// exercise the fallback. Pass `name: null` deliberately for that.
BookCompliment compliment(
  String emoji, {
  String id = 'c1',
  String from = meId,
  String? name = 'Jihyun',
  String? reactorEmoji,
  String? avatarPath,
}) => BookCompliment(
  id: id,
  bookId: 'b1',
  fromUserId: from,
  compliment: emoji,
  createdAt: DateTime(2024),
  reactorName: name,
  reactorEmoji: reactorEmoji,
  reactorAvatarPath: avatarPath,
);

/// Records `setReaderApp` writes instead of performing them.
///
/// `extends Fake implements LibraryActions` rather than extending the real class,
/// because [LibraryActions] takes a `Ref` a test has no way to construct. Every other
/// member throws, which is what we want: the store sheet's tap path calls exactly one
/// method, and a fake that silently answered the rest would hide it growing a second
/// dependency.
class RecordingLibraryActions extends Fake implements LibraryActions {
  /// `(bookId, from, to)` per write, in order. `from` is the `reader_app` on the [Book]
  /// handed to [setReaderApp] and `to` is the new value; both null-able, since null is
  /// "no shop" at each end.
  ///
  /// **`from` is recorded because it is where a real bug lived.** The real
  /// `setReaderApp` short-circuits when `book.readerApp == storeKey`, so which `Book`
  /// reaches it decides whether a write happens at all. While the page read its book
  /// from the route argument, `from` was frozen at navigation time — so switching shop
  /// and then switching back compared the new key against the *original* value, matched,
  /// and silently did nothing. Asserting `from` is how a test sees that.
  final List<(String, String?, String?)> readerAppWrites = [];

  @override
  Future<void> setReaderApp(Book book, String? storeKey) async {
    readerAppWrites.add((book.id, book.readerApp, storeKey));
  }
}

Future<void> pumpBookDetails(
  WidgetTester tester, {
  required Book book,
  required String signedInAs,
  List<BookCompliment> compliments = const [],

  /// Which catalogue the fake app is on.
  ///
  /// Must be overridden rather than left to resolve, because the real chain runs
  /// `bookSearchSourceProvider` -> `bookSourcePreferenceProvider` ->
  /// `sharedPreferencesProvider`, and that last one throws by design until
  /// `main()` overrides it. Defaults to Google Books, which is also the path that
  /// supplies a volume id inline and therefore fires no extra lookup — so no test
  /// touches the network unless it asks to.
  BookSearchSource source = BookSearchSource.googleBooks,

  /// The answer the on-demand volume-id lookup gives, for tests exercising the
  /// Kakao path where the catalogue supplies none.
  String? resolvedVolumeId,

  /// What Apple Books says about the book.
  ///
  /// **Always overridden, even at its default, and that is the point.** Unlike the
  /// volume-id lookup this one is unconditional — nothing the catalogue returns
  /// could contain an Apple id, so there is no source that makes it skippable.
  /// Without an override here every details-page test that opens the sheet would
  /// issue a real request to `itunes.apple.com`.
  ///
  /// Defaults to [AppleBooksAvailability.unknown], which is the "we could not ask"
  /// answer and leaves the Apple row in place as a search. Pass a
  /// [AppleBooksResult.notSold] to exercise the row being dropped.
  AppleBooksResult apple = const AppleBooksResult.unknown(),

  /// What Apple Books says about the book **in a named storefront**, overriding
  /// [apple] for the countries listed.
  ///
  /// Exists so a test can prove *which* storefront the lookup was asked about, which
  /// no other observable reveals: a found URL comes straight out of the lookup, so a
  /// view that asked the wrong country would still render a plausible row. Give the
  /// two countries different answers and the row's presence becomes the assertion --
  /// `{'kr': notSold, 'us': found(...)}` with `storefront: 'kr'` drops the row only if
  /// `kr` really was the country asked.
  Map<String, AppleBooksResult>? applePerCountry,

  /// What OverDrive says about the book.
  ///
  /// **Always overridden, for exactly the reason [apple] is** — the lookup is
  /// unconditional, so without this every details-page test that opens the sheet
  /// would issue a real request to `overdrive.com` and `thunder.api.overdrive.com`.
  /// This was missed when the lookup landed and the suite was quietly doing so.
  ///
  /// Defaults to [OverDriveResult.none], the "could not ask / nobody lends it"
  /// answer, which leaves the Libby row a search. Pass a found result to exercise
  /// the exact link — and note it is also what makes the library picker reachable,
  /// since a library key has nothing to point at without a title id.
  OverDriveResult overDrive = const OverDriveResult.none(),

  /// The reader's stored Libby library, seeded into `SharedPreferences`.
  ///
  /// Null leaves the store empty, which is `unasked` — the state where tapping
  /// Libby with a resolved title id opens the picker. Pass a pair to act as a reader
  /// who has already answered.
  ({String key, String name})? libbyLibrary,

  /// What the owner's library holds, which is **not** necessarily the book passed as
  /// [book].
  ///
  /// The page takes its `Book` from `ModalRoute.settings.arguments` — a snapshot frozen
  /// at navigation time — but reads the *live* row out of the library and prefers it.
  /// Passing a different version of the same id here is how a test proves that: set
  /// [book] to the stale copy and put the fresh one in this list.
  ///
  /// Empty by default, which exercises the fallback — no library row, so the snapshot
  /// stands. That is also the first-frame state on a real device, before the library
  /// resolves.
  List<Book> libraryBooks = const [],

  /// A stand-in for [LibraryActions], for cases that need to see a write happen.
  ///
  /// The real one reaches Supabase, which a widget test has no client for -- and
  /// `setReaderApp` swallows its own failures on purpose, so a test using the real
  /// class cannot tell "wrote" from "tried and silently gave up". That swallow is
  /// correct behaviour (see its comment) and is exactly why it hid a dead column for
  /// the feature's whole life, so a test that depends on it is no test at all.
  LibraryActions? libraryActions,

  /// The reader's App Store storefront, as a lowercase alpha-2 code.
  ///
  /// **Overridden even at its default**, because the real provider reaches a platform
  /// channel that does not exist under `flutter test`. Null is the honest default — it
  /// is what Android and the simulator report — and leaves `storeCountryFor` falling
  /// back to the locale, which is the behaviour every existing case was written
  /// against. Pass `'us'` with a `ko` locale, or `'kr'` with `en`, to exercise the two
  /// mismatches that the locale guess used to get wrong.
  String? storefront,

  /// The app's language, as a locale code.
  ///
  /// Only the language matters -- the view reads
  /// `Localizations.localeOf(context).languageCode`. Kept a `String` rather than a
  /// `Locale` so a case reads `locale: 'ko'` next to `storefront: 'us'`, since the
  /// whole point of having both is that they can disagree.
  String locale = 'en',

  /// Logical surface to pump at.
  ///
  /// **Widen it for any case that opens `showBookStatusBottomSheet`.** In a test
  /// `BookStatusSelector` falls back to a Material `Row` — the iOS 26 segmented
  /// control is a platform view with no Flutter-side hit target — and that fallback
  /// overflows the sheet's 342pt content width by 27. The overflow is an artifact of
  /// the fallback rather than a defect on device, where the sheet draws
  /// `CNSegmentedControl` and there is no `Row` to overflow, so it is not this
  /// suite's to fix.
  Size logicalSize = const Size(390, 844),
}) async {
  tester.view.physicalSize = logicalSize * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Needed because the store sheet reads the reader's Libby library, and
        // `sharedPreferencesProvider` throws until something overrides it.
        await sharedPreferencesOverride(
          libbyLibrary == null
              ? const {}
              : {
                  libbyLibraryPrefKeys.key: libbyLibrary.key,
                  libbyLibraryPrefKeys.name: libbyLibrary.name,
                  libbyLibraryPrefKeys.asked: true,
                },
        ),
        currentUserIdProvider.overrideWithValue(signedInAs),
        bookSearchProvider.overrideWithValue(NoBookInfo()),
        bookSearchSourceProvider.overrideWithValue(source),
        volumeIdForIsbnProvider(
          book.isbn,
        ).overrideWith((ref) async => resolvedVolumeId),
        overDriveProvider((
          title: book.title,
          author: book.authors.isEmpty ? '' : book.authors.first,
        )).overrideWith((ref) async => overDrive),
        appStoreStorefrontProvider.overrideWith((ref) async => storefront),
        // Every storefront a case might resolve to, so a test may set a locale or a
        // storefront without the override silently ceasing to apply and letting a real
        // request through to `itunes.apple.com`.
        for (final country in {
          'us',
          'kr',
          ?storefront,
          ...?applePerCountry?.keys,
        })
          appleBooksProvider((
            isbn: book.isbn,
            title: book.title,
            author: book.authors.isEmpty ? '' : book.authors.first,
            country: country,
          )).overrideWith((ref) async => applePerCountry?[country] ?? apple),
        bookMemosProvider(book.id).overrideWith((ref) async => <BookMemo>[]),
        bookComplimentsProvider(
          book.id,
        ).overrideWith((ref) async => compliments),
        // Shelf names resolve against the owner's library, so both the self and
        // friend paths need stubbing.
        userLibraryProvider(book.userId).overrideWith(
          (ref) async => shelvesFor(book.userId, books: libraryBooks),
        ),
        libraryProvider.overrideWith(
          () =>
              FakeLibraryNotifier(shelvesFor(book.userId, books: libraryBooks)),
        ),
        if (libraryActions != null)
          libraryActionsProvider.overrideWithValue(libraryActions),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: Locale(locale),
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
