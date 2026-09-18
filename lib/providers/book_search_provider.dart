import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/services/apple_books_lookup.dart';
import 'package:bookworm_friends/services/app_store_storefront.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/services/overdrive_lookup.dart';
import 'package:bookworm_friends/services/store_links_service.dart'
    show looksLikeIsbn;

/// User-facing preference for which book catalog to search.
/// [auto] resolves to a source based on the device locale.
enum BookSourcePreference { auto, kakao, googleBooks }

const String _prefKey = 'book_source_preference';

/// Overridden in `main()` with the loaded [SharedPreferences] instance so the
/// preference can be read/written synchronously throughout the app.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

class BookSourceNotifier extends Notifier<BookSourcePreference> {
  @override
  BookSourcePreference build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return _parse(prefs.getString(_prefKey));
  }

  Future<void> set(BookSourcePreference pref) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_prefKey, _serialize(pref));
    state = pref;
  }

  static BookSourcePreference _parse(String? value) {
    switch (value) {
      case 'kakao':
        return BookSourcePreference.kakao;
      case 'google':
        return BookSourcePreference.googleBooks;
      default:
        return BookSourcePreference.auto;
    }
  }

  static String _serialize(BookSourcePreference pref) {
    switch (pref) {
      case BookSourcePreference.kakao:
        return 'kakao';
      case BookSourcePreference.googleBooks:
        return 'google';
      case BookSourcePreference.auto:
        return 'auto';
    }
  }
}

final bookSourcePreferenceProvider =
    NotifierProvider<BookSourceNotifier, BookSourcePreference>(
      BookSourceNotifier.new,
    );

/// Resolves the [BookSourcePreference] into a concrete [BookSearchSource],
/// falling back to the device locale when the preference is [auto].
final bookSearchSourceProvider = Provider<BookSearchSource>((ref) {
  final pref = ref.watch(bookSourcePreferenceProvider);
  switch (pref) {
    case BookSourcePreference.kakao:
      return BookSearchSource.kakao;
    case BookSourcePreference.googleBooks:
      return BookSearchSource.googleBooks;
    case BookSourcePreference.auto:
      final languageCode = PlatformDispatcher.instance.locale.languageCode;
      return languageCode == 'ko'
          ? BookSearchSource.kakao
          : BookSearchSource.googleBooks;
  }
});

/// The active [BookSearchProvider] implementation for the resolved source.
final bookSearchProvider = Provider<BookSearchProvider>((ref) {
  switch (ref.watch(bookSearchSourceProvider)) {
    case BookSearchSource.kakao:
      return KakaoBookSearchProvider();
    case BookSearchSource.googleBooks:
      // Prefer Google Books; fall back to keyless Open Library when Google is
      // unavailable (e.g. keyless quota exceeded / 429).
      return FallbackBookSearchProvider([
        GoogleBooksSearchProvider(),
        OpenLibrarySearchProvider(),
      ]);
  }
});

/// True when the active source can supply a Google Books volume id itself.
///
/// Only the Google path can. Kakao's book document carries eleven keys and none
/// of them is a volume id, and Open Library has no equivalent either — so on
/// those paths an id has to be looked up separately or not had at all.
final sourceSuppliesVolumeIdProvider = Provider<bool>(
  (ref) => ref.watch(bookSearchSourceProvider) == BookSearchSource.googleBooks,
);

/// A Google Books volume id for an ISBN, looked up on demand.
///
/// **Why this exists.** The volume id is the only per-book identifier the app can
/// obtain at all, and it is what makes an exact Play Books link (both the store
/// page and the reader) and an exact Apple Books link possible. But it arrives
/// for free only when the reader's catalogue *is* Google Books. On the Kakao
/// path — which is the default for `ko`, i.e. this app's primary market — it is
/// always null, so every shop degraded to a plain search. "Play Books is the one
/// shop exact at both intents" was true of the English build and false of the
/// Korean one.
///
/// One keyless GET fixes both shops at once, which is why it is worth a request.
///
/// Deliberate properties:
///
///  * **Skipped when the source already supplies one.** Callers check
///    [sourceSuppliesVolumeIdProvider] first; this is for the paths that cannot.
///  * **Skipped for anything that is not an ISBN.** `Book.isbn` sometimes holds a
///    Google volume id or a truncated number, and `isbn:<volume id>` is a
///    confident query for nothing. [looksLikeIsbn] is the same guard the URL
///    builder uses.
///  * **Never throws.** A quota error, an offline device or an unknown ISBN all
///    resolve to null, and null simply leaves every link a search — which the
///    supporting lines already say truthfully. This must not be able to stop the
///    sheet from opening.
///  * **Cached per ISBN** for as long as something is listening, so reopening the
///    sheet on the same book does not re-request.
final volumeIdForIsbnProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, isbn) async {
    if (!looksLikeIsbn(isbn)) return null;
    try {
      // Reuses the existing provider rather than issuing raw HTTP: it already
      // performs `q=isbn:<isbn>`, already normalises the response, and already
      // carries `volumeId` through. A second implementation of the same request
      // is a second thing to keep in step.
      final result = await GoogleBooksSearchProvider().getByIsbn(isbn);
      return result?.volumeId;
    } catch (_) {
      return null;
    }
  },
);

/// The reader's App Store storefront as a lowercase alpha-2 code, or null.
///
/// **Why this is not derived from the locale.** Which Apple Books catalogue a person
/// can buy from is decided by their Apple ID's country. Guessing it from the device
/// language was wrong in both directions — it hid Apple Books from a Korean-language
/// phone on a US account, and handed `/us/` links to an English-language phone on a
/// Korean account, whose store answers those with a 404. Only StoreKit knows.
///
/// Null is an **ordinary** answer, not a failure: Android has no equivalent, the
/// simulator and `flutter test` have no storefront, and StoreKit reports none for a
/// short window early in launch. Every consumer falls back to the locale, which is
/// exactly the behaviour this replaced.
///
/// Not `autoDispose`: a storefront does not change while the app runs (changing it
/// requires signing out of the Apple ID), so one answer serves the whole session and
/// re-asking per sheet would be waste.
final appStoreStorefrontProvider = FutureProvider<String?>(
  (ref) => appStoreStorefrontCountry(),
);

/// What Apple Books says about a book, looked up on demand.
///
/// **Why a second lookup, when [volumeIdForIsbnProvider] already runs.** The two
/// resolve different things and neither substitutes for the other: a Google volume
/// id names a book in Google's catalogue and is what makes Play Books exact, while
/// Apple's `id731076045` is Apple's own and appears in no catalogue the app reads.
/// Before this existed, Apple Books was the one shop that could never be exact
/// even when everything was known about the book — not because of a missing URL
/// format, but because nothing had ever asked Apple.
///
/// Keyed on ISBN, title, author **and storefront country**. The country because a
/// book URL is scoped to the storefront that sold it (`/kr/book/id731076045` 404s
/// for the id that resolves under `/us/`), and the title and author because the
/// lookup falls back to searching on them when the ISBN is not indexed. Pass
/// `storeCountryFor(localeCode)`.
///
/// Returns a three-way answer rather than a nullable URL, because "Apple does not
/// sell this" and "we could not ask Apple" call for opposite handling in the sheet.
/// Never throws — every failure is [AppleBooksAvailability.unknown]. Cached per key
/// while listened to, so reopening the sheet on the same book does not re-request.
final appleBooksProvider = FutureProvider.autoDispose
    .family<
      AppleBooksResult,
      ({String isbn, String title, String author, String country})
    >(
      (ref, key) => appleBooksLookup(
        isbn: key.isbn,
        title: key.title,
        authors: key.author.isEmpty ? const [] : [key.author],
        country: key.country,
      ),
    );

/// The global OverDrive title id for a book, looked up on demand, so the Libby row
/// can name a title instead of running a search.
///
/// **Not keyed on ISBN, and that is not an oversight.** OverDrive's web search does
/// not index ISBNs at all — `overdrive.com/search?q=<isbn>` returns zero results
/// where the title and author return hundreds — and an ebook's ISBN is not its
/// print ISBN, so the number in `Book.isbn` frequently names an edition no library
/// has. Title and author are the only usable key, which is also the whole key.
///
/// **Not keyed on locale either**, unlike Apple's: OverDrive title ids are global.
/// The same id resolves under every library key tried, so there is no storefront to
/// scope to. What *is* per-library is availability, which this deliberately does not
/// ask about — see `overdrive_lookup.dart`.
///
/// Never throws; every failure is [OverDriveResult.none], which leaves the Libby row
/// as the search it was before. Cached per key while listened to, so reopening the
/// sheet on the same book does not re-request.
final overDriveProvider = FutureProvider.autoDispose
    .family<OverDriveResult, ({String title, String author})>(
      (ref, key) => overDriveLookup(
        title: key.title,
        authors: key.author.isEmpty ? const [] : [key.author],
      ),
    );
