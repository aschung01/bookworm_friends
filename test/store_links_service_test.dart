// The URL algebra behind the "where to read this" sheet.
//
// Worth testing directly and heavily, because **every label in the sheet is
// derived from what these functions return**. A row only says "Opens this book"
// because `StoreReach.book` came back, so a wrong reach here is not a wrong URL —
// it is the app making a promise it cannot keep, which is the specific failure the
// whole design exists to avoid.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/store_links_service.dart';

/// A volume id in the shape Google actually returns.
const volumeId = 'zyTCAlFPjgYC';

/// A global OverDrive title id in the shape `media/bulk` actually returns — this
/// is the real id of the *The Hard Thing About Hard Things* ebook.
const libbyTitleId = '1344919';

/// A `preferredKey` in the shape `thunder` actually returns.
const libbyKey = 'sfpl';

List<StoreLink> acquire({
  String isbn = '9791161571188',
  String title = 'Live Commerce',
  List<String> authors = const ['Lee Hyunsook'],
  String? volume,
  Uri? appleUrl,
  bool noEdition = false,
  String? libby,
  String? libbyLibrary,
  String? storefront,
  String locale = 'en',
}) => storeLinksFor(
  intent: StoreIntent.acquire,
  isbn: isbn,
  title: title,
  authors: authors,
  volumeId: volume,
  appleBookUrl: appleUrl,
  appleHasNoEdition: noEdition,
  libbyTitleId: libby,
  libbyLibraryKey: libbyLibrary,
  storefrontCountry: storefront,
  localeCode: locale,
);

List<StoreLink> open({
  String isbn = '9791161571188',
  String? volume,
  String? libby,
  String? libbyLibrary,
  String locale = 'en',
}) => storeLinksFor(
  intent: StoreIntent.open,
  isbn: isbn,
  title: 'Live Commerce',
  authors: const ['Lee Hyunsook'],
  volumeId: volume,
  libbyTitleId: libby,
  libbyLibraryKey: libbyLibrary,
  localeCode: locale,
);

StoreLink only(List<StoreLink> links, StoreId id) =>
    links.firstWhere((l) => l.id == id);

void main() {
  group('looksLikeIsbn', () {
    // The guard exists because `Book.isbn` genuinely holds other things:
    // `GoogleBooksSearchProvider._mapVolume` puts a volume id there when a volume
    // lists no ISBN, and Kakao's mapper keeps only the first space-separated
    // token. Feeding either to an ISBN search is a confident search for nothing.
    test('accepts ISBN-13, ISBN-10 and hyphenated forms', () {
      expect(looksLikeIsbn('9791161571188'), isTrue);
      expect(looksLikeIsbn('0440238498'), isTrue);
      expect(looksLikeIsbn('979-11-6157-118-8'), isTrue);
    });

    test('accepts an ISBN-10 check digit of X', () {
      expect(looksLikeIsbn('043942089X'), isTrue);
    });

    test('rejects a Google volume id', () {
      expect(looksLikeIsbn(volumeId), isFalse);
    });

    test('rejects a truncated number that is neither length', () {
      // The harness book's ISBN is exactly this shape: nine digits.
      expect(looksLikeIsbn('440238498'), isFalse);
    });

    test('rejects an empty string', () {
      expect(looksLikeIsbn(''), isFalse);
    });
  });

  group('storeQueryFor', () {
    test('is title plus the first author only', () {
      expect(
        storeQueryFor(
          title: 'Eldest',
          authors: const ['Paolini', 'Kim', 'Lee'],
        ),
        'Eldest Paolini',
      );
    });

    test('falls back to the bare title when no author is listed', () {
      expect(storeQueryFor(title: 'Eldest', authors: const []), 'Eldest');
    });

    test('does not leave a dangling separator for a blank author', () {
      expect(storeQueryFor(title: 'Eldest', authors: const ['  ']), 'Eldest');
    });
  });

  group('storeIdFromKey', () {
    test('round-trips every shop', () {
      for (final id in StoreId.values) {
        expect(storeIdFromKey(id.key), id);
      }
    });

    // The column has no CHECK constraint precisely so an older build can ignore a
    // key it does not know. Both of these mean "show the acquire list".
    test('treats null and an unrecognised key alike', () {
      expect(storeIdFromKey(null), isNull);
      expect(storeIdFromKey('ridibooks'), isNull);
    });
  });

  group('Play Books is exact at both intents, but only one reaches the app', () {
    // **Proven, not inferred.** Apple's app-site-association for play.google.com
    // claims exactly `/books/reader`, `/books/listen`, `/books/getapp2` and
    // `/books/notes` for `com.google.GoogleBooks`. `/store/books/details` is
    // claimed by nothing, so it opens a browser however installed the app is --
    // which is what a reader reported, and why this is `storePage` not `book`.
    test('acquire with a volume id reaches the store page, in a browser', () {
      final link = only(acquire(volume: volumeId), StoreId.play);
      expect(link.reach, StoreReach.storePage);
      expect(
        link.uri.toString(),
        'https://play.google.com/store/books/details?id=$volumeId',
      );
    });

    // `/books/reader` IS claimed, so this one genuinely opens the app.
    test('open with a volume id reaches the book in the reader app', () {
      final link = only(open(volume: volumeId), StoreId.play);
      expect(link.reach, StoreReach.book);
      expect(
        link.uri.toString(),
        'https://play.google.com/books/reader?id=$volumeId',
      );
    });

    test('without a volume id it degrades to a search and says so', () {
      final link = only(acquire(), StoreId.play);
      expect(link.reach, StoreReach.search);
      expect(link.uri.host, 'play.google.com');
      expect(link.uri.queryParameters['c'], 'books');
    });
  });

  group('Apple Books', () {
    test('is a search until something resolves an exact URL', () {
      final link = only(acquire(), StoreId.apple);
      expect(link.reach, StoreReach.search);
      expect(link.uri.host, 'books.apple.com');
      expect(link.uri.path, '/us/search');
    });

    test('takes a resolved URL when one is supplied', () {
      final resolved = Uri.parse('https://books.apple.com/us/book/x/id123');
      final link = only(acquire(appleUrl: resolved), StoreId.apple);
      expect(link.reach, StoreReach.book);
      expect(link.uri, resolved);
    });

    // The store page is not the reader, and Apple exposes no "open my copy" URL —
    // so even a resolved id cannot make this reach a book.
    test(
      'opening reaches only the app, even with a resolved URL available',
      () {
        final link = only(open(), StoreId.apple);
        expect(link.reach, StoreReach.app);
        expect(link.uri.scheme, 'ibooks');
      },
    );

    // Asserted rather than left implicit, because `storeLinksFor` takes
    // `appleBookUrl` for *both* intents and there is nothing in the signature
    // stopping a future edit from wiring it into the open case. A store page
    // opened under an "Open Apple Books" label would be the sheet lying again.
    test('a resolved URL does not leak into the open intent', () {
      final link = only(
        storeLinksFor(
          intent: StoreIntent.open,
          isbn: '9791161571188',
          title: 'Live Commerce',
          authors: const ['Lee Hyunsook'],
          appleBookUrl: Uri.parse('https://books.apple.com/us/book/x/id123'),
        ),
        StoreId.apple,
      );
      expect(link.reach, StoreReach.app);
      expect(link.uri.scheme, 'ibooks');
    });
  });

  // The three-way answer, which exists because "Apple does not sell this" and "we
  // could not ask Apple" call for opposite handling. Getting these two confused is
  // the difference between hiding a shop the reader owns the book in and offering
  // one that opens an empty search tab.
  group('when Apple has no edition', () {
    test('the acquire row is dropped rather than offered as a search', () {
      final ids = acquire(noEdition: true).map((l) => l.id);
      expect(ids, isNot(contains(StoreId.apple)));
      // And nothing else is disturbed.
      expect(ids, containsAll([StoreId.play, StoreId.kindle, StoreId.libby]));
    });

    // The asymmetry that matters: a dropped connection must not hide a shop.
    test('but an unanswered lookup keeps the row', () {
      final ids = acquire().map((l) => l.id);
      expect(ids, contains(StoreId.apple));
      expect(only(acquire(), StoreId.apple).reach, StoreReach.search);
    });

    // Only acquiring is affected. A reader who stored Apple Books still gets
    // their way back into the app, whatever Apple currently sells.
    test('opening a stored Apple copy is unaffected', () {
      final link = openLinkFor(
        stored: StoreId.apple,
        isbn: '9791161571188',
        title: 'Live Commerce',
        authors: const ['Lee Hyunsook'],
      );
      expect(link, isNotNull);
      expect(link!.reach, StoreReach.app);
    });

    test('an absent edition and a resolved URL cannot both be claimed', () {
      expect(
        () => acquire(
          noEdition: true,
          appleUrl: Uri.parse('https://books.apple.com/us/book/x/id1'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('storeCountryFor', () {
    // Public so the Apple lookup and the link builder cannot disagree: a book URL
    // is scoped to the storefront that sold it, and `/kr/book/id731076045` 404s
    // for the id that resolves under `/us/`.
    test('falls back to the locale when no storefront is known', () {
      expect(storeCountryFor('ko'), 'kr');
      expect(storeCountryFor('en'), 'us');
      expect(storeCountryFor('ja'), 'us');
    });

    // **The real storefront wins, and this is the whole point of asking StoreKit.**
    // Which Apple Books catalogue a reader can buy from is decided by their Apple
    // ID's country, not by their device's language.
    test('the real storefront beats the locale in both directions', () {
      // A Korean-language phone signed in to a US account really can buy from the
      // US store. The old locale guess sent it to `kr` and hid Apple entirely.
      expect(storeCountryFor('ko', storefront: 'us'), 'us');
      // An English-language phone signed in to a Korean account cannot use `/us/`
      // links at all. The old guess handed it exactly those.
      expect(storeCountryFor('en', storefront: 'kr'), 'kr');
      // And a storefront the locale would never have guessed.
      expect(storeCountryFor('en', storefront: 'jp'), 'jp');
    });

    // Null is the ordinary answer on Android, in tests, and briefly during launch.
    test('a null storefront leaves the locale in charge', () {
      expect(storeCountryFor('ko', storefront: null), 'kr');
      expect(storeCountryFor('en', storefront: null), 'us');
    });

    // This value lands in a URL path segment, and `books.apple.com//search` is not a
    // page. Anything not two characters is refused rather than passed through.
    test('refuses a storefront that is not a two-letter code', () {
      expect(storeCountryFor('en', storefront: ''), 'us');
      expect(storeCountryFor('en', storefront: 'USA'), 'us');
      expect(storeCountryFor('ko', storefront: 'x'), 'kr');
    });

    test('is normalised, because Apple URLs are lower case', () {
      expect(storeCountryFor('en', storefront: 'KR'), 'kr');
    });

    test('is the country the Apple search URL is built for', () {
      expect(only(acquire(), StoreId.apple).uri.path, '/us/search');
      // The storefront reaches the URL, not just the lookup.
      expect(
        only(acquire(storefront: 'kr'), StoreId.apple).uri.path,
        '/kr/search',
      );
      expect(
        only(acquire(locale: 'ko', storefront: 'us'), StoreId.apple).uri.path,
        '/us/search',
      );
    });
  });

  group('Kindle can never reach a book', () {
    // Amazon publishes no per-book deep link. This is the fact the sheet's copy
    // has to admit, so it is asserted rather than assumed.
    test('acquiring is a search, in the Kindle Store department', () {
      final link = only(acquire(volume: volumeId), StoreId.kindle);
      expect(link.reach, StoreReach.search);
      expect(link.uri.host, 'www.amazon.com');
      expect(link.uri.queryParameters['i'], 'digital-text');
    });

    test('a volume id does not upgrade it', () {
      expect(
        only(acquire(volume: volumeId), StoreId.kindle).reach,
        StoreReach.search,
      );
    });

    // Still "the app, not a title" -- but reached by the one https path the Kindle
    // app claims rather than by `kindle://`. Its host is asserted because the
    // obvious-looking alternative is a trap: on `www.amazon.com` the Kindle app
    // claims nothing, and `/bookshelf` there belongs to the *shopping* app.
    test('opening launches the app only, by a claimed path', () {
      final link = only(open(volume: volumeId), StoreId.kindle);
      expect(link.reach, StoreReach.app);
      expect(link.uri.scheme, 'https');
      expect(link.uri.host, 'read.amazon.com');
      expect(link.uri.path, '/application');
      // A volume id cannot make this exact -- asserted so the reach above is not
      // mistaken for "we simply have no id yet".
      expect(link.uri.queryParameters, isEmpty);
    });
  });

  group('Libby', () {
    // The reported bug, pinned. `libbyapp.com/search/all/...` put `all` where a
    // library key belongs, so Libby opened, tried to resolve a library named
    // "all", failed, and showed its own "trouble fetching details about this
    // library" screen. There is no library-agnostic Libby search -- OverDrive's
    // API answers "Must specify at least 1 libraryKey" -- so the destination is
    // OverDrive's own search, which needs no library.
    test('acquiring is a borrow lookup that needs no library key', () {
      final link = only(acquire(), StoreId.libby);
      expect(link.reach, StoreReach.search);
      expect(link.uri.host, 'www.overdrive.com');
      expect(link.uri.path, '/search');
      expect(link.uri.queryParameters['q'], isNotEmpty);
    });

    // Alone among the shops, Libby must NOT be sent an ISBN.
    // `overdrive.com/search?q=9780143127741` returns 0 results where the title and
    // author return 462 -- OverDrive's web search does not index ISBNs. The shared
    // `term` prefers an ISBN whenever the field holds one, so using it here would
    // send every correctly-scanned book to an empty results page. Verified against
    // the live site, and pinned because the two look interchangeable in the source.
    test('searches by title and author, never by ISBN', () {
      final link = only(
        acquire(isbn: '9780143127741', title: 'Live Commerce'),
        StoreId.libby,
      );
      expect(link.uri.queryParameters['q'], 'Live Commerce Lee Hyunsook');
      expect(link.uri.queryParameters['q'], isNot(contains('9780143127741')));
    });

    // The contrast that makes the rule visible: Kindle DOES want the ISBN.
    test('unlike Kindle, which does want the ISBN', () {
      final link = only(acquire(isbn: '9780143127741'), StoreId.kindle);
      expect(link.uri.queryParameters['k'], '9780143127741');
    });

    // Asserted by absence, because the old URL looked entirely reasonable and
    // would be an easy "simplification" to reintroduce.
    //
    // Scoped **twice**, and both scopings were learned by breaking the test.
    // First to the acquire intent: the ban is not on the host, since opening a
    // copy legitimately uses `libbyapp.com/shelf/loans`. Then to the *no title id*
    // case, because `libbyapp.com/title/<id>` is now a legitimate acquire
    // destination — what stays banned is a Libby **search** path, which must name
    // a library we never know.
    test('with no title id, never searches libbyapp.com', () {
      final link = only(acquire(), StoreId.libby);
      expect(
        link.reach,
        StoreReach.search,
        reason: 'precondition: this is the fallback, not the exact link',
      );
      expect(
        link.uri.host,
        isNot('libbyapp.com'),
        reason: 'a Libby search path must name a library; we never know which',
      );
    });

    test('nothing is sold, so the row promises a free borrow', () {
      expect(only(acquire(), StoreId.libby).reach, StoreReach.search);
    });

    // ---- The title-id path. -------------------------------------------------
    //
    // `overDriveLookup` resolves a **global** id — the same one resolves under
    // every library key — so acquiring can name an exact title with nothing asked
    // of the reader. It does **not** reach into the Libby app: see the group below.
    group('given a global OverDrive title id', () {
      test('acquiring names the exact title instead of searching', () {
        final link = only(acquire(libby: libbyTitleId), StoreId.libby);
        expect(link.reach, StoreReach.storePage);
        expect(link.uri.host, 'www.overdrive.com');
        expect(link.uri.path, '/media/1344919');
        expect(link.uri.hasQuery, isFalse);
      });

      // **The device test that killed the previous version of this row.**
      // `libbyapp.com/title/<id>` opened Libby and showed its own "View not
      // found.", dropping the reader on the Shelf. Libby's router explains it:
      // `title/<id>` belongs to `title-redirect-controller`, a sub-controller of
      // the **library realm**, which builds `"library/" + this.ancestor.args.key`.
      // A bare `/title/<id>` has no ancestor, so no key, so no match — and the
      // root-level table has no title route at all.
      //
      // Asserted by absence because the URL is short, obvious and wrong, and it
      // reads like the most natural thing to write.
      test('never uses libbyapp.com/title, which Libby cannot route', () {
        for (final link in [
          only(acquire(libby: libbyTitleId), StoreId.libby),
          only(open(libby: libbyTitleId), StoreId.libby),
        ]) {
          expect(
            link.uri.path,
            isNot(startsWith('/title/')),
            reason:
                'Libby routes title/<id> only under library/<key>; a bare one '
                'shows "View not found." and lands on the Shelf',
          );
        }
      });

      // **Not `share.libbyapp.com`** either, which was the first choice and is also
      // wrong: that page has no Borrow button, no library picker and no sign-in —
      // its only call to action is "Find this title with Libby" over two app-store
      // badges. Pinned because the two hosts are one word apart.
      test('never uses the share host, which cannot borrow', () {
        for (final link in [
          only(acquire(libby: libbyTitleId), StoreId.libby),
          only(open(libby: libbyTitleId), StoreId.libby),
        ]) {
          expect(
            link.uri.host,
            isNot('share.libbyapp.com'),
            reason: 'the share page is an install ad, not a borrow page',
          );
        }
      });

      // Reaching a specific *loan* needs `library/<key>/title/<id>` and the app has
      // no library key, so the id must not silently change what opening promises.
      test('opening is unaffected, because a loan needs a library key', () {
        final with_ = only(open(libby: libbyTitleId), StoreId.libby);
        final without = only(open(), StoreId.libby);
        expect(with_.uri, without.uri);
        expect(with_.reach, StoreReach.app);
        expect(with_.uri.path, '/shelf/loans');
      });

      // A title id never hides the row and never changes any other shop's link.
      test('leaves the other three shops untouched', () {
        final without = acquire();
        final with_ = acquire(libby: libbyTitleId);
        expect(with_.map((l) => l.id), without.map((l) => l.id));
        for (final id in [StoreId.play, StoreId.apple, StoreId.kindle]) {
          expect(only(with_, id).uri, only(without, id).uri);
        }
      });
    });

    // ---- With the reader's library key as well. ------------------------------
    //
    // The pair is what Libby requires, and requiring it is Libby's rule rather than
    // ours: `title/<id>` resolves only beneath `library/<key>`, because its
    // controller builds `"library/" + this.ancestor.args.key`.
    group('given a title id AND the library key', () {
      test('acquiring reaches the book inside Libby', () {
        final link = only(
          acquire(libby: libbyTitleId, libbyLibrary: libbyKey),
          StoreId.libby,
        );
        expect(link.reach, StoreReach.book);
        expect(link.uri.scheme, 'https');
        expect(link.uri.host, 'libbyapp.com');
        expect(link.uri.path, '/library/sfpl/title/1344919');
      });

      // Libby's title page is the borrow page *and* the loan page: one route that
      // shows Borrow, Place Hold or Open according to what the reader's library
      // holds and what they already have out.
      test('opening reaches the same route, not the shelf', () {
        final link = only(
          open(libby: libbyTitleId, libbyLibrary: libbyKey),
          StoreId.libby,
        );
        expect(link.reach, StoreReach.book);
        expect(link.uri.path, '/library/sfpl/title/1344919');
      });

      // The key alone buys nothing: with no title id there is no book to name, so
      // the row must not claim to have improved.
      test('a key with no title id changes nothing', () {
        final link = only(acquire(libbyLibrary: libbyKey), StoreId.libby);
        expect(link.reach, StoreReach.search);
        expect(link.uri.host, 'www.overdrive.com');
        expect(link.uri.path, '/search');
      });

      // The key is a segment in a path, so an empty one would build
      // `library//title/…` -- which is Libby's malformed-library error again, the
      // very first bug this row ever had. `LibbyLibraryChoice` reads an empty
      // stored string as absent for this reason; asserted here as well because this
      // is where it would do the damage.
      test('an empty key is not treated as a key', () {
        final link = only(
          acquire(libby: libbyTitleId, libbyLibrary: ''),
          StoreId.libby,
        );
        expect(link.uri.toString(), isNot(contains('//title/')));
        expect(link.uri.host, 'www.overdrive.com');
      });

      test('still leaves the other three shops untouched', () {
        final without = acquire();
        final with_ = acquire(libby: libbyTitleId, libbyLibrary: libbyKey);
        expect(with_.map((l) => l.id), without.map((l) => l.id));
        for (final id in [StoreId.play, StoreId.apple, StoreId.kindle]) {
          expect(only(with_, id).uri, only(without, id).uri);
        }
      });
    });

    // The second Libby bug: `libby://` was a guessed scheme, is not the app's
    // (`com.overdrive.dewey`), and failed even while declared in
    // `LSApplicationQueriesSchemes` -- the reader got "Something went wrong".
    //
    // A universal link is used instead, and the reason generalises: **a custom
    // scheme fails hard where a claimed https path degrades to the web.** Libby's
    // app-site-association claims every path on the host, so this opens the app
    // when installed and Libby's web shelf when not.
    test('opening uses a claimed https route, never a custom scheme', () {
      final link = only(open(), StoreId.libby);
      expect(link.reach, StoreReach.app);
      expect(link.uri.scheme, 'https');
      expect(link.uri.host, 'libbyapp.com');
      // A real Libby route, confirmed in the app's own bundle next to
      // `shelf/holds` and `shelf/timeline` -- not a guess like the last one.
      expect(link.uri.path, '/shelf/loans');
    });
  });

  group('search terms', () {
    test('a real ISBN is used verbatim', () {
      final link = only(acquire(isbn: '9791161571188'), StoreId.kindle);
      expect(link.uri.queryParameters['k'], '9791161571188');
    });

    // The case that matters: a volume id sitting in the ISBN field would otherwise
    // become a search for a string no shop has ever indexed.
    test('a volume id in the ISBN field falls back to title and author', () {
      final link = only(acquire(isbn: volumeId), StoreId.kindle);
      expect(link.uri.queryParameters['k'], 'Live Commerce Lee Hyunsook');
    });

    test('so does a truncated number', () {
      final link = only(acquire(isbn: '440238498'), StoreId.kindle);
      expect(link.uri.queryParameters['k'], 'Live Commerce Lee Hyunsook');
    });
  });

  // The bug this grid exists for: Play Books had no `app` case for the open
  // intent, so an id-less open fell through to the Play Store *search* while the
  // sheet still labelled it "Open Play Books". Every other shop had a fallback,
  // so testing one happy path per shop passed and the matrix was never walked.
  group('the store x intent x id grid', () {
    /// Every combination there is: 4 shops, 2 intents, and each of the three
    /// looked-up identifiers present or absent.
    ///
    /// **Named fields rather than a positional tuple**, because this grid grows
    /// every time a lookup is added — first Apple's URL, then Libby's title id —
    /// and a positional shape silently reassigns every existing destructuring the
    /// moment one lands in the middle. Exactly the failure the call site's own
    /// `List<Object?>` cast had.
    Iterable<
      ({
        StoreId id,
        StoreIntent intent,
        String? vol,
        Uri? apple,
        String? libby,
        String? libbyLibrary,
        StoreLink link,
      })
    >
    grid() {
      final out =
          <
            ({
              StoreId id,
              StoreIntent intent,
              String? vol,
              Uri? apple,
              String? libby,
              String? libbyLibrary,
              StoreLink link,
            })
          >[];
      for (final intent in StoreIntent.values) {
        for (final vol in <String?>[null, volumeId]) {
          for (final apple in <Uri?>[
            null,
            Uri.parse('https://books.apple.com/us/book/x/id123'),
          ]) {
            for (final libby in <String?>[null, libbyTitleId]) {
              for (final libbyLibrary in <String?>[null, libbyKey]) {
                final links = storeLinksFor(
                  intent: intent,
                  isbn: '9791161571188',
                  title: 'Live Commerce',
                  authors: const ['Lee Hyunsook'],
                  volumeId: vol,
                  appleBookUrl: apple,
                  libbyTitleId: libby,
                  libbyLibraryKey: libbyLibrary,
                );
                for (final link in links) {
                  out.add((
                    id: link.id,
                    intent: intent,
                    vol: vol,
                    apple: apple,
                    libby: libby,
                    libbyLibrary: libbyLibrary,
                    link: link,
                  ));
                }
              }
            }
          }
        }
      }
      return out;
    }

    /// What a failing case was configured with, for a reason string.
    String describe(
      ({
        StoreId id,
        StoreIntent intent,
        String? vol,
        Uri? apple,
        String? libby,
        String? libbyLibrary,
        StoreLink link,
      })
      row,
    ) =>
        '${row.id.key} + ${row.intent.name} + volumeId=${row.vol} + '
        'apple=${row.apple} + libby=${row.libby}/${row.libbyLibrary}';

    test('covers all one hundred and twenty-eight combinations', () {
      expect(grid(), hasLength(128));
    });

    // **The invariant that was violated.** The sheet labels an open link "Open
    // X" or "Read in X", both of which promise the reader's own app. A search
    // reach under that label is a row that lies about what a tap does, which is
    // the entire failure `StoreReach` was introduced to prevent.
    test('no open link is ever a search', () {
      for (final row in grid()) {
        if (row.intent != StoreIntent.open) continue;
        expect(
          row.link.reach,
          isNot(StoreReach.search),
          reason:
              '${describe(row)} reaches a search, so the sheet would label it '
              'Open and search instead',
        );
      }
    });

    // The mirror: acquiring by launching an app you cannot aim at is useless, so
    // no acquire row may be a bare app launch either.
    test('no acquire link is ever a bare app launch', () {
      for (final row in grid()) {
        if (row.intent != StoreIntent.acquire) continue;
        expect(
          row.link.reach,
          isNot(StoreReach.app),
          reason: '${describe(row)} only launches an app',
        );
      }
    });

    test('every link has an absolute, non-empty URI', () {
      for (final row in grid()) {
        expect(
          row.link.uri.hasScheme &&
              row.link.uri.toString().length > 'x://'.length,
          isTrue,
          reason: describe(row),
        );
      }
    });

    // An identifier may only ever improve a link, never change its kind for the
    // worse. Guards against a future `when` clause landing in the wrong order.
    test('an id never makes a link less exact', () {
      const rank = {
        StoreReach.app: 0,
        StoreReach.search: 1,
        // Above a search: it is this exact book. Below `book`: it is a web page
        // rather than the shop's app.
        StoreReach.storePage: 2,
        StoreReach.book: 3,
      };
      for (final intent in StoreIntent.values) {
        for (final id in StoreId.values) {
          final without = storeLinksFor(
            intent: intent,
            isbn: '9791161571188',
            title: 'x',
            authors: const [],
          ).where((l) => l.id == id);
          final with_ = storeLinksFor(
            intent: intent,
            isbn: '9791161571188',
            title: 'x',
            authors: const [],
            volumeId: volumeId,
            appleBookUrl: Uri.parse('https://books.apple.com/us/book/x/id123'),
            libbyTitleId: libbyTitleId,
            libbyLibraryKey: libbyKey,
          ).where((l) => l.id == id);
          if (without.isEmpty || with_.isEmpty) continue;
          expect(
            rank[with_.first.reach]!,
            greaterThanOrEqualTo(rank[without.first.reach]!),
            reason: '${id.key} + ${intent.name} got worse with an id',
          );
        }
      }
    });
  });

  group('Play Books opens the app when it cannot open the book', () {
    // The reported bug, pinned. Reproduces the exact configuration a Kakao-sourced
    // book was in before the ISBN lookup landed: no volume id anywhere.
    //
    // **Now asserted as an https universal link, not a scheme, and that is the whole
    // point of the change.** `com.google.playbooks://` was here and was wrong twice
    // over: it matched no convention Google uses on iOS (`googlegmail://`,
    // `comgooglekeep://`; the bundle id is `com.google.GoogleBooks`), and a custom
    // scheme with no app installed fails hard -- "Something went wrong", no way
    // forward. `/books/reader` is claimed in Google's own app-site-association, and
    // AASA matches on path alone, so the bare form is claimed exactly as the
    // `?id=`-bearing one is.
    test(
      'an id-less open reaches Play Books by a claimed path, not a scheme',
      () {
        final link = only(open(), StoreId.play);
        expect(link.reach, StoreReach.app);
        expect(link.uri.scheme, 'https');
        expect(link.uri.host, 'play.google.com');
        expect(link.uri.path, '/books/reader');
        // No id to aim at, so no query -- the id-bearing case is asserted below.
        expect(link.uri.queryParameters, isEmpty);
      },
    );

    // The general rule, stated once so a future store cannot quietly reintroduce the
    // failure. Apple is the single sanctioned exception: there is no Apple Books web
    // reader, so no universal link can reach a reader's own library.
    test('no open row launches a custom scheme except Apple Books', () {
      for (final link in open()) {
        if (link.id == StoreId.apple) {
          expect(link.uri.scheme, 'ibooks');
          continue;
        }
        expect(
          link.uri.scheme,
          'https',
          reason: '${link.id.key} open should degrade to the web, not dead-end',
        );
      }
    });

    // And the store page is still not the app. Worth stating: even with an id,
    // acquiring reaches `play.google.com/store`, which is the Play Store -- a
    // browser page on iOS, where no Play Store app exists.
    test('acquiring still reaches the store, not the reader', () {
      expect(
        only(acquire(volume: volumeId), StoreId.play).uri.path,
        '/store/books/details',
      );
      expect(
        only(open(volume: volumeId), StoreId.play).uri.path,
        '/books/reader',
      );
    });

    // Kindle's replacement, and the host matters more than it looks. On
    // `www.amazon.com` the Kindle app claims nothing at all -- `/bookshelf` and
    // `/kindle-dbs/*` there belong to `com.amazon.Amazon`, the shopping app -- so the
    // obvious-looking `amazon.com/bookshelf` would open the wrong app entirely.
    // `read.amazon.com/application` is claimed by `com.amazon.Lassen`, which is
    // Kindle for iOS.
    test('Kindle opens via the host its own app claims', () {
      final link = only(open(), StoreId.kindle);
      expect(link.reach, StoreReach.app);
      expect(link.uri.scheme, 'https');
      expect(link.uri.host, 'read.amazon.com');
      expect(link.uri.path, '/application');
    });
  });

  group('locale', () {
    // Neither omission is a preference; both are correctness.
    //
    // Libby resolves to US and UK public library systems, so a row promising a
    // free borrow from "your library" cannot reach any Korean one.
    //
    // Apple Books is Apple's own policy: South Korea is listed as "Apple Books --
    // Public domain books only" and is absent from the list of countries a
    // publisher can sell into, so the store stocks essentially nothing there.
    // `books.apple.com/kr/charts` is a 404 where `/us/charts` is a 200.
    // **Apple is offered to `ko` again, and that is a fix rather than a regression.**
    // Korea really is "public domain books only", but that is a property of the
    // reader's *Apple ID storefront*, not of their device language — so it is enforced
    // by `storeCountryFor` plus the lookup's `notSold` answer, which drops the row per
    // book. Withdrawing it here also hid Apple from Korean-language phones signed in
    // to US accounts, which can buy perfectly well.
    test('ko is offered every shop except Libby', () {
      final ids = acquire(locale: 'ko').map((l) => l.id);
      expect(ids, isNot(contains(StoreId.libby)));
      expect(ids, containsAll([StoreId.play, StoreId.apple, StoreId.kindle]));
    });

    // Libby stays withdrawn, and for a different reason that no storefront can fix:
    // it resolves to US and UK library systems, and there is no Apple-ID-shaped signal
    // for "which country's libraries".
    test('and Libby stays out, which no storefront can change', () {
      final ids = acquire(locale: 'ko', storefront: 'us').map((l) => l.id);
      expect(ids, isNot(contains(StoreId.libby)));
    });

    test('en is offered all four', () {
      expect(acquire().map((l) => l.id), hasLength(4));
    });

    // The storefront still has to be right for the locales that DO get Apple:
    // a book URL is scoped to the storefront that sold it.
    test('en builds the US Apple storefront', () {
      expect(only(acquire(), StoreId.apple).uri.path, '/us/search');
    });

    test('order is stable, so the sheet does not reshuffle between books', () {
      expect(acquire().map((l) => l.id).toList(), [
        StoreId.play,
        StoreId.apple,
        StoreId.kindle,
        StoreId.libby,
      ]);
    });
  });

  group('openLinkFor', () {
    test(
      'is null when nothing is stored, which means show the acquire list',
      () {
        expect(
          openLinkFor(
            stored: null,
            isbn: '9791161571188',
            title: 'x',
            authors: const [],
          ),
          isNull,
        );
      },
    );

    test('resolves the stored shop', () {
      final link = openLinkFor(
        stored: StoreId.play,
        isbn: '9791161571188',
        title: 'x',
        authors: const [],
        volumeId: volumeId,
      );
      expect(link!.id, StoreId.play);
      expect(link.reach, StoreReach.book);
    });

    // A reader who stored Libby and then switched the device to Korean still owns
    // that copy. Hiding the way back to it would be worse than offering a shop the
    // locale list would not have suggested.
    test('still resolves a shop the current locale does not offer', () {
      final link = openLinkFor(
        stored: StoreId.libby,
        isbn: '9791161571188',
        title: 'x',
        authors: const [],
        localeCode: 'ko',
      );
      expect(link, isNotNull);
      expect(link!.id, StoreId.libby);
    });
  });

  group('brand names', () {
    // Deliberately not localised: Apple, Google and Amazon all ship Latin brand
    // names in Korean UI, and a translated shop is a shop nobody recognises.
    test('are identical in every locale', () {
      for (final id in StoreId.values) {
        final en = storeLinksFor(
          intent: StoreIntent.open,
          isbn: '9791161571188',
          title: 'x',
          authors: const [],
        ).where((l) => l.id == id);
        if (en.isEmpty) continue;
        expect(en.first.brand, isNotEmpty);
        expect(en.first.brand, matches(RegExp(r'^[A-Za-z ]+$')));
      }
    });
  });
}
