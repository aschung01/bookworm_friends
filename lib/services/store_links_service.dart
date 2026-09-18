/// Where a book can be read, and how honestly each destination can be described.
///
/// The whole of this file exists because **the two things a reader might want
/// have inverted reliability**. "Take me somewhere I can get this" and "open my
/// copy" are served by different URLs of very different quality, and of the eight
/// store x intent combinations only two reach an actual book:
///
/// | store       | acquire                        | open my copy            |
/// |-------------|--------------------------------|-------------------------|
/// | Play Books  | exact, but a **web** store page | **exact, in the app**  |
/// | Apple Books | exact **in the app**, or absent | app launch only        |
/// | Kindle      | **search only**                | app launch only         |
/// | Libby       | search only                     | app launch only        |
///
/// Amazon publishes no per-book deep link, and Kindle opens the reader's library
/// rather than a title. No wording changes that, so the design does not
/// try to: every link carries a [StoreReach] saying what it genuinely arrives at,
/// and the UI's supporting line is derived from that rather than written by hand.
/// A row that says "Opens this book" can only say it because [StoreReach.book]
/// came back.
///
/// ## Custom schemes are a last resort, not the default
///
/// Every `open` row used to launch a guessed `scheme://`. Two of the three are gone,
/// replaced by https paths the target app **claims in its own app-site-association**:
/// `play.google.com/books/reader` and `read.amazon.com/application`. The argument is
/// the failure mode rather than elegance -- a custom scheme with no app installed
/// fails hard, surfacing as "Something went wrong" with nowhere to go, while a
/// universal link degrades to that shop's web reader. Libby was moved for exactly
/// this reason after it failed on a device, and `Info.plist` already recorded the
/// rule: _prefer that shape for any future store_.
///
/// `com.google.playbooks://` was also simply wrong. The iOS bundle id is
/// `com.google.GoogleBooks`, and Google ships `googlegmail://`, `googledrive://`,
/// `comgooglekeep://` -- that string matched no convention Google uses.
///
/// **Apple Books is the deliberate exception.** `ibooks://` is documented rather than
/// invented, and there is no Apple Books web reader at all, so no https URL reaches a
/// reader's own library -- `books.apple.com/` bare is a shop. See its case below.
///
/// ## Verified on device, and it cost two reaches
///
/// The table above is narrower than the one that shipped, because two rows were
/// found to be promising more than they delivered:
///
///  * **Play Books' acquire link opens Safari, not the app.** Proven, not guessed:
///    Apple's app-site-association for `play.google.com` lists exactly four paths
///    against `EQHXZ8M8AV.com.google.GoogleBooks` — `/books/reader`,
///    `/books/listen`, `/books/getapp2`, `/books/notes`. `/store/books/details` is
///    claimed by no Google app, so iOS cannot hand it to Play Books however
///    installed it is. It is also the *right* destination — Google cannot sell
///    books in-app on iOS — so the URL stays and [StoreReach.storePage] exists to
///    stop the copy overpromising. `/books/reader` **is** claimed, which is why
///    opening a remembered copy is still [StoreReach.book].
///  * **Apple's search fallback opens an empty search tab.** `books.apple.com` is
///    claimed by Books, so the app does open — and then ignores `term` entirely.
///    A row reading "Searches Apple Books" that searches nothing is the exact
///    failure this file exists to prevent, so it is no longer offered: when Apple
///    confirms it has no edition the row is **omitted** (see [appleHasNoEdition]).
///    It survives only for the case where Apple could not be asked at all.
///  * **Libby's search URL named a library that does not exist.**
///    `libbyapp.com/search/all/…` puts `all` where a **library key** belongs, so
///    Libby opened and reported "I'm having trouble fetching details about this
///    library". Libby search cannot be library-agnostic — OverDrive's API answers
///    "Must specify at least 1 libraryKey" — so the row now goes to
///    `overdrive.com/search`, which needs no library.
///
/// **All three were unverified URLs that read plausibly.** None was caught by a
/// test, because a test can only assert the URL we chose to build; whether that URL
/// arrives anywhere is not a fact the suite can know. The device-verification list
/// in the design doc is therefore a blocker, not a nicety.
///
/// **Pure and synchronous on purpose.** Everything here is string algebra over
/// ids the app already holds, so it is testable without a widget, a network or a
/// clock. The two parts that need a request — asking Apple about a book, and
/// asking OverDrive for its title id — are deliberately *not* here: their answers
/// arrive as [appleBookUrl] / [appleHasNoEdition] and [libbyTitleId]. See
/// `appleBooksLookup` in `apple_books_lookup.dart` and `overDriveLookup` in
/// `overdrive_lookup.dart`.
library;

/// The shops offered. Values are the wire keys stored in `books.reader_app`.
enum StoreId {
  play('play'),
  apple('apple'),
  kindle('kindle'),
  libby('libby');

  const StoreId(this.key);

  /// The value written to `books.reader_app`. Short and opaque; never shown.
  final String key;
}

/// Parses `books.reader_app`.
///
/// Null for an absent value, and — importantly — also for an *unrecognised* one.
/// The column has no CHECK constraint precisely so that a build which does not
/// know a key can ignore it, which puts the book back on the acquire list: the
/// state it was in before anyone tapped anything. See the migration.
StoreId? storeIdFromKey(String? key) {
  if (key == null) return null;
  for (final id in StoreId.values) {
    if (id.key == key) return id;
  }
  return null;
}

/// What a reader is trying to do, which decides which URL a store contributes.
enum StoreIntent { acquire, open }

/// What a link actually arrives at. The honesty of every label depends on this.
enum StoreReach {
  /// This exact book, **in the shop's own app**. Only ever produced when a
  /// per-book identifier is in hand *and* the URL's path is one the app claims.
  book,

  /// This exact book, but as a **web store page** rather than in the app.
  ///
  /// Exists because `play.google.com/store/books/details` is not a path the Play
  /// Books iOS app claims, so it opens in a browser no matter what the reader has
  /// installed. Still an exact destination, and still the only way to buy — but a
  /// row that said "Opens this book" was read as a promise about the app, and was
  /// reported as a bug on exactly those grounds.
  storePage,

  /// A results page. The reader still has to find the book themselves.
  search,

  /// The reader app, at whatever it was last showing. Cannot target a title.
  ///
  /// **Not necessarily the app.** Play Books and Kindle reach this by a *claimed
  /// https path* rather than a custom scheme, so with the app missing they land on
  /// that shop's web reader instead. The label survives the difference because both
  /// web readers show the same library -- which is exactly why the https shape was
  /// preferred: a custom scheme with nothing to open fails hard and dead-ends the
  /// reader. Apple is the exception and keeps `ibooks://`; see its case below.
  app,
}

/// One resolved destination.
class StoreLink {
  const StoreLink({
    required this.id,
    required this.intent,
    required this.reach,
    required this.uri,
  });

  final StoreId id;
  final StoreIntent intent;
  final StoreReach reach;
  final Uri uri;

  /// Brand names are **not** localised and never pass through `.arb`.
  ///
  /// Apple, Google and Amazon all ship Latin brand names in Korean UI, and a
  /// translated shop name would be a shop nobody recognises. This is a deliberate
  /// exception to the otherwise absolute en/ko key parity.
  String get brand => switch (id) {
    StoreId.play => 'Play Books',
    StoreId.apple => 'Apple Books',
    StoreId.kindle => 'Kindle',
    StoreId.libby => 'Libby',
  };

  @override
  String toString() =>
      'StoreLink(${id.key}, ${intent.name}, ${reach.name}, $uri)';
}

/// Which shops are worth offering in a given locale.
///
/// **Korean readers get neither Libby nor Apple Books, and both are correctness
/// decisions rather than preferences.**
///
/// Libby resolves to US and UK public library systems; a row offering "borrow free
/// from your library" that cannot reach any Korean library is simply broken. Device
/// language is a coarse proxy for "which country's libraries", but it is the only
/// signal available — there is no library equivalent of a storefront to ask.
///
/// **Apple Books used to be withdrawn from `ko` here too, and that was the wrong
/// mechanism.** The underlying fact is real: Apple lists South Korea as **"Apple
/// Books — Public domain books only"**, Korea is absent from Apple Books Partner
/// Support's sell-in list, `books.apple.com/kr/charts` is a 404 where `/us/charts` is
/// a 200, and a `kr` ebook search for "harry potter" returns *Alice's Adventures in
/// Wonderland*.
///
/// **Source, because this was queried once and will be again:**
/// _Availability of Apple Media Services_, `support.apple.com/en-us/118205`
/// (published 15 Sep 2026), which lists South Korea's Apple Books entry as
/// "Public domain books only" where Japan's reads "Book & Audiobook purchases".
/// Korea is not singled out — in Asia-Pacific only Japan, Australia and New
/// Zealand have a commercial book store. Re-checkable in one request:
/// `itunes.apple.com/search?term=...&entity=ebook&country=kr` returns 0 results
/// for Korean bestsellers that resolve under `us` and `jp`.
///
/// But **the constraint is the reader's Apple ID storefront, not their device
/// language**, and keying it here was wrong in both directions: it hid Apple Books
/// from a Korean-language phone signed in to a US account, and it did nothing for an
/// English-language phone signed in to a Korean one — which got `/us/` links its store
/// answers with a 404. That is now handled where it belongs, by two mechanisms that
/// already existed:
///
///  * [storeCountryFor] takes the **real** storefront from
///    `appStoreStorefrontCountry`, so the lookup and the URL are built for the
///    account that will open them.
///  * A `kr` lookup then answers `notSold` for anything commercial, and
///    [storeLinksFor] already drops a row on a *confirmed* absence.
///
/// Strictly better than the blanket exclusion: a Korean reader now gets an Apple row
/// for the public-domain titles they genuinely **can** get, and no row at all for the
/// rest. The one case left is `unknown` — offline or timed out — which leaves the weak
/// search fallback, exactly as it does for every other storefront.
///
/// Note the distinction, because it is easy to state wrongly: the Books **app** ships
/// on every Korean iPhone and reads sideloaded EPUBs fine. It is the **store** that
/// has nothing to sell.
///
/// The shops Korean readers actually use — 리디북스, 밀리의서재, 예스24, 교보 — are
/// still an open question in the design record and are not added here yet.
List<StoreId> storesForLocale(String localeCode) => switch (localeCode) {
  'ko' => const [StoreId.play, StoreId.apple, StoreId.kindle],
  _ => const [StoreId.play, StoreId.apple, StoreId.kindle, StoreId.libby],
};

/// Storefront country for this reader, used by Apple and Google.
///
/// Public because the Apple lookup needs the *same* answer this file uses: an
/// Apple book URL is scoped to the storefront that sold it, so a lookup run
/// against one country and a link built for another produce a confident 404.
///
/// [storefront] is the reader's **actual** App Store storefront from
/// `appStoreStorefrontCountry`, and it wins whenever it is known. The locale is only a
/// fallback, and a poor one — it is the device's language, which says nothing reliable
/// about which Apple ID is signed in. Null covers Android, the simulator,
/// `flutter test`, and the brief window early in launch before StoreKit has resolved a
/// storefront; in all of those the old guess is the best available.
///
/// Guarded on length rather than trusted: this value reaches a URL path segment and a
/// query parameter, and `books.apple.com//search` is not a page.
String storeCountryFor(String localeCode, {String? storefront}) {
  if (storefront != null && storefront.length == 2) {
    return storefront.toLowerCase();
  }
  return switch (localeCode) {
    'ko' => 'kr',
    _ => 'us',
  };
}

/// A free-text query for a book, used wherever no identifier will do.
///
/// Title plus the first author, not every author: Amazon and Apple both rank a
/// long author list worse than a short one, and a book with six translators is
/// exactly the case where the extra names are noise.
String storeQueryFor({required String title, required List<String> authors}) {
  final first = authors.isEmpty ? '' : authors.first;
  return [title, first].where((s) => s.trim().isNotEmpty).join(' ').trim();
}

/// True when [isbn] looks like an actual ISBN rather than something standing in
/// for one.
///
/// **This check is not paranoia; the field genuinely holds other things.**
/// `GoogleBooksSearchProvider._mapVolume` stores the Google *volume id* in
/// `Book.isbn` when a volume lists no ISBN, and Kakao's mapper keeps only the
/// first space-separated token, which for Korean books is often the ISBN-10.
/// Feeding a volume id to an `isbn:`-style lookup produces a confident search for
/// nothing, so callers fall back to [storeQueryFor] instead.
bool looksLikeIsbn(String isbn) {
  final digits = isbn.replaceAll('-', '');
  if (digits.length != 10 && digits.length != 13) return false;
  // ISBN-10 may end in 'X'; everything else must be a digit.
  final body = digits.length == 10 && digits.toUpperCase().endsWith('X')
      ? digits.substring(0, 9)
      : digits;
  return body.isNotEmpty && int.tryParse(body) != null;
}

/// Every destination worth offering for one book, in display order.
///
/// [volumeId] is the Google Books volume id, which is the only per-book
/// identifier the app can obtain without an extra request — it comes back in the
/// same response the catalogue search already made.
///
/// [appleBookUrl] and [appleHasNoEdition] are the two halves of what
/// `appleBooksLookup` found, and they are **mutually exclusive**. Passing neither
/// means Apple could not be asked, which leaves the row in place as a search —
/// weak, but hiding a shop because a connection dropped would be worse. Passing
/// [appleHasNoEdition] means Apple answered and has no edition, and the row is
/// **left out entirely**: its search fallback opens the Books app on an empty
/// search tab, so offering it would be worse than offering nothing.
///
/// [libbyTitleId] is the global OverDrive title id from `overDriveLookup`, and
/// [libbyLibraryKey] the reader's `preferredKey` from `libbyLibrarySearch`. **Both
/// are needed for an exact Libby link, and that is Libby's constraint rather than a
/// choice:** it resolves `title/<id>` only beneath `library/<key>`. With both, either
/// intent reaches the book. With the id alone, acquiring reaches an exact OverDrive
/// page in a browser. With neither, acquiring is a search. Opening falls back to the
/// reader's shelf whenever the pair is incomplete.
///
/// A null [libbyTitleId] covers both "could not ask" and "no library lends it", which
/// need no distinguishing because the fallback — a real OverDrive results page — reads
/// honestly either way. Unlike Apple, a Libby row is **never dropped**.
/// [storefrontCountry] is the reader's real App Store storefront, which decides the
/// Apple storefront every Apple URL is scoped to. Null falls back to the locale, which
/// is what this file did before it could ask — see [storeCountryFor].
List<StoreLink> storeLinksFor({
  required StoreIntent intent,
  required String isbn,
  required String title,
  required List<String> authors,
  String? volumeId,
  Uri? appleBookUrl,
  bool appleHasNoEdition = false,
  String? libbyTitleId,
  String? libbyLibraryKey,
  String? storefrontCountry,
  String localeCode = 'en',
}) {
  assert(
    !(appleHasNoEdition && appleBookUrl != null),
    'Apple cannot both have no edition and have resolved a URL',
  );
  final query = storeQueryFor(title: title, authors: authors);
  final cc = storeCountryFor(localeCode, storefront: storefrontCountry);
  // Prefer the ISBN for search terms, but only when it is really one.
  final term = looksLikeIsbn(isbn) ? isbn : query;

  final links = <StoreLink>[];
  for (final id in storesForLocale(localeCode)) {
    // Apple answered and does not stock it. Dropping the row is the only honest
    // option left: `books.apple.com/<cc>/search?term=` opens Books and then
    // ignores the term, so the fallback cannot be described truthfully at all.
    // Only the acquire list is affected — a reader who stored Apple still gets
    // their way back to the app.
    if (id == StoreId.apple &&
        intent == StoreIntent.acquire &&
        appleHasNoEdition) {
      continue;
    }
    final link = switch ((id, intent)) {
      // ----- Play Books: exact at both intents, but only ONE of them reaches
      // the app. `/books/reader` is claimed by the iOS app;
      // `/store/books/details` is claimed by nothing, so it opens a browser. ---
      (StoreId.play, StoreIntent.acquire) when volumeId != null => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.storePage,
        uri: Uri.parse(
          'https://play.google.com/store/books/details?id=$volumeId',
        ),
      ),
      (StoreId.play, StoreIntent.open) when volumeId != null => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.book,
        uri: Uri.parse('https://play.google.com/books/reader?id=$volumeId'),
      ),
      // **Opening without an id still reaches the reader's library, and no longer by
      // a guessed scheme.** `com.google.playbooks://` used to sit here and was almost
      // certainly wrong: the iOS bundle id is `com.google.GoogleBooks` (see the AASA
      // quoted at the top of this file), and Google's iOS apps use `google<app>://`
      // or `comgoogle<app>://` -- `googlegmail`, `googledrive`, `comgooglekeep` --
      // so that string matched no convention Google uses anywhere.
      //
      // `/books/reader` with no `id` is the same **claimed** path the exact-open case
      // uses, and AASA matches on path alone, so the bare URL is claimed too. The
      // point is the failure mode: a custom scheme with no app installed fails hard
      // and the reader gets "Something went wrong" with no way forward, where this
      // opens the Play Books **web** reader -- still their library. Same reasoning
      // that moved Libby off `libby://`; see the note in `Info.plist`.
      (StoreId.play, StoreIntent.open) => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.app,
        uri: Uri.parse('https://play.google.com/books/reader'),
      ),
      (StoreId.play, _) => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.search,
        uri: Uri.https('play.google.com', '/store/search', {
          'q': term,
          'c': 'books',
        }),
      ),

      // ----- Apple Books: exact **in the app** when the lookup found it, since
      // `books.apple.com` is a domain Books claims. The search below survives
      // only for the case where Apple could not be asked; when Apple answered
      // and has no edition the row was skipped above. -----
      (StoreId.apple, StoreIntent.acquire) when appleBookUrl != null =>
        StoreLink(
          id: id,
          intent: intent,
          reach: StoreReach.book,
          uri: appleBookUrl,
        ),
      // Weak and knowingly so: Books opens on an empty search tab because it
      // ignores `term`. Kept only because "we could not reach Apple" is not a
      // reason to hide a shop the reader may well own the book in.
      (StoreId.apple, StoreIntent.acquire) => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.search,
        uri: Uri.https('books.apple.com', '/$cc/search', {'term': term}),
      ),
      // Opening cannot target a book even with an id: the store page is not the
      // reader, and Apple exposes no "open my copy" URL.
      //
      // **The one scheme deliberately kept, against the rule the other two now
      // follow.** Two reasons, and the second is the deciding one:
      //
      //  * It is documented rather than invented -- `ibooks://` (with
      //    `itms-books://` / `itms-bookss://`) is listed in the widely-used AppURLs
      //    reference, unlike `com.google.playbooks://`, which appeared in no list
      //    and fitted no convention.
      //  * **There is no Apple Books web reader**, so no https URL exists that
      //    reaches the reader's library. `books.apple.com/` bare is a *store* page.
      //    Swapping this for a universal link would trade an app that opens for a
      //    shop that does not -- worse, not safer. And Books ships preinstalled, so
      //    the hard-failure case a universal link protects against barely exists.
      (StoreId.apple, StoreIntent.open) => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.app,
        uri: Uri.parse('ibooks://'),
      ),

      // ----- Kindle: a search, always. `i=digital-text` is the Kindle Store
      // department, so the reader lands among ebooks rather than paperbacks. ---
      (StoreId.kindle, StoreIntent.acquire) => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.search,
        uri: Uri.https('www.amazon.com', '/s', {
          'k': term,
          'i': 'digital-text',
        }),
      ),
      // **`kindle://` replaced by the one path the Kindle app actually claims.**
      // `read.amazon.com`'s AASA lists `/application`, `/application/*` and
      // `/gp/r.html` against `J7P34ALZ5R.com.amazon.Lassen` -- Lassen is Kindle for
      // iOS. Note it had to be *that* host: on `www.amazon.com` the Kindle app claims
      // nothing at all, and `/bookshelf` and `/kindle-dbs/*` there belong to
      // `com.amazon.Amazon`, the shopping app. So the obvious-looking
      // `amazon.com/bookshelf` would open the wrong app.
      //
      // Uninstalled, this reaches Kindle Cloud Reader, which *is* the reader's
      // library -- so the row's promise survives the fallback instead of dying on it.
      //
      // **Confirmed on a device: it opens Kindle at the library page.** Which is the
      // only kind of confirmation this file accepts, and the reason the reach is
      // `app` rather than something weaker -- `/application` is the Cloud Reader root
      // and the app honours it. `kindle://` was never verified and never had to be:
      // it is replaced rather than tested, because a claimed path cannot fail hard.
      (StoreId.kindle, StoreIntent.open) => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.app,
        uri: Uri.parse('https://read.amazon.com/application'),
      ),

      // **Exact, in the app, when a title id and the reader's library key are both
      // in hand -- and it takes both.** Libby resolves `title/<id>` only as a
      // sub-controller of the library realm, reading the key off its ancestor:
      //
      // ```js
      // var s = e.match(/^title\/(\d+)(\/(.+))?$/);
      // if (s) { var a = "library/" + this.ancestor.args.key;
      //          return { rewrite: a + "/similar-" + n + "/page-1/" + n + r }; }
      // ```
      //
      // So `library/<key>/title/<id>` rewrites internally to
      // `library/<key>/similar-<id>/page-1/<id>`, and Libby claims every path on the
      // host (`["NOT /api/*", "*"]`), so this opens the app when installed and
      // Libby's web app when not.
      //
      // **Confirmed on a device**, which this file's history says is the only thing
      // that counts: `libby://`, `libbyapp.com/search/all/...` and
      // `libbyapp.com/title/<id>` all read plausibly and all failed. This one lands
      // on the title with its Borrow / Place Hold / Open action, which is what
      // entitles it to `StoreReach.book`.
      //
      // **Both intents share it, because Libby's title page is both pages**: the
      // same route shows Borrow, Place Hold or Open according to what the reader's
      // library holds and what they already have out.
      //
      // **The key is a library, never a library card.** Libby cannot lend without a
      // card, but that is Libby's flow and Libby owns it; the app asks which
      // library, which is a public fact, and stores no credential.
      //
      // **The key must be non-empty, not merely non-null.** It is a path segment, so
      // an empty one builds `library//title/<id>` -- a malformed library key, and
      // Libby's answer to that is the "I'm having trouble fetching details about this
      // library" screen that was this row's very first bug. `LibbyLibraryChoice`
      // already reads an empty stored string as absent; this is the same guard at the
      // place where it would do the damage.
      (StoreId.libby, _)
          when libbyTitleId != null &&
              libbyLibraryKey != null &&
              libbyLibraryKey.isNotEmpty =>
        StoreLink(
          id: id,
          intent: intent,
          reach: StoreReach.book,
          uri: Uri.parse(
            'https://libbyapp.com/library/$libbyLibraryKey/title/$libbyTitleId',
          ),
        ),

      // ----- Libby: a borrow lookup. Nothing is sold, which is also why it
      // carries no App Store guideline 3.1.1 exposure whatsoever.
      //
      // **A title id with no library key reaches the exact book, but only on the
      // web.** This is the third URL this row has had and the second a device
      // disproved: `libbyapp.com/title/<id>` fails, because of the ancestor rule
      // above -- Libby opens, shows its own "View not found." and drops the reader on
      // the Shelf. The root-level table handles only `authenticate/<key>`,
      // `resolve/<key>`, `timeline` and the empty path, so **there is no
      // library-agnostic title route**, and `resolve` is no way round it either: its
      // `commence` returns `#missing-args` without a key or websiteId.
      //
      // `overdrive.com/media/<id>` is what can be had without one, and it is a real
      // gain over the search it replaces: the exact title, its format, ISBN and
      // publisher, a sample, and OverDrive's own "Is this your library? / find a
      // library" affordance. No wrong-book risk and one step fewer.
      //
      // `StoreReach.storePage` rather than `book`, for the same reason Play Books
      // acquire uses it: Libby claims no `overdrive.com` path, so this is a browser
      // however installed Libby is, and a row must not imply otherwise.
      (StoreId.libby, StoreIntent.acquire) when libbyTitleId != null =>
        StoreLink(
          id: id,
          intent: intent,
          reach: StoreReach.storePage,
          uri: Uri.https('www.overdrive.com', '/media/$libbyTitleId'),
        ),

      // No title id: OverDrive could not be asked, or lends no edition under this
      // title and author.
      //
      // **On `overdrive.com` rather than `libbyapp.com`, and that is the fix for a
      // reported bug.** The shipped URL was
      // `libbyapp.com/search/all/search/query-<term>`, and the segment holding
      // `all` is a **library key** -- Libby claims the domain, opened, read `all`
      // as the name of a library, failed to find it and showed "I'm having trouble
      // fetching details about this library". There is no library-agnostic form of
      // that URL: Libby search is always scoped to a library the reader has added,
      // and OverDrive's own API refuses the question outright with
      // "Must specify at least 1 libraryKey".
      //
      // `overdrive.com/search?q=` needs no library, returns a real results page,
      // and shows which libraries hold a title -- its own tagline is "Free ebooks,
      // audiobooks & movies from your library", which is the promise this row makes.
      //
      // **`query`, never `term`.** Alone among the shops, this one must not be sent
      // an ISBN: `overdrive.com/search?q=9780143127741` returns *0 results*, where
      // the title and author return 462. OverDrive's web search does not index
      // ISBNs, so passing the shared `term` -- which prefers an ISBN whenever the
      // field holds one -- would send every properly-scanned book to an empty page.
      (StoreId.libby, StoreIntent.acquire) => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.search,
        uri: Uri.https('www.overdrive.com', '/search', {'q': query}),
      ),
      // Opening goes to the reader's **Loans** as a universal link, not a custom
      // scheme, and this is the second Libby bug this row has had.
      //
      // `libby://` was a guess and it is simply wrong -- the app is
      // `com.overdrive.dewey`, and `launchUrl` returned false even with `libby`
      // declared in `LSApplicationQueriesSchemes`, so the sheet showed "Something
      // went wrong". `shelf/loans` is a real route, confirmed in the app's own
      // bundle alongside `shelf/holds` and `shelf/timeline`, **and confirmed on a
      // device** -- it is where the failed `title/<id>` attempt landed.
      //
      // **The general lesson, which Play Books and Kindle have since followed: a
      // custom scheme fails hard and a universal link degrades to the web.** If
      // Libby is not installed this opens Libby's web app at the same shelf, where a
      // wrong scheme would have left the reader at an error dialog with nowhere to
      // go. Prefer a claimed https path over a scheme wherever one exists -- which
      // now covers every open row but Apple's, and Apple's only because no Apple
      // Books web reader exists to degrade to.
      //
      // **A title id alone deliberately does not upgrade this row.** Reaching a
      // specific loan needs `library/<key>/title/<id>`; with the key missing, the
      // shelf the reader can navigate from is the best available, and says so.
      (StoreId.libby, StoreIntent.open) => StoreLink(
        id: id,
        intent: intent,
        reach: StoreReach.app,
        uri: Uri.parse('https://libbyapp.com/shelf/loans'),
      ),
    };
    links.add(link);
  }
  return links;
}

/// The single destination for a book whose shop is already known.
///
/// Returns null when [stored] is null or unrecognised, which is the caller's cue
/// to show the acquire list instead.
StoreLink? openLinkFor({
  required StoreId? stored,
  required String isbn,
  required String title,
  required List<String> authors,
  String? volumeId,
  String? libbyTitleId,
  String? libbyLibraryKey,
  String? storefrontCountry,
  String localeCode = 'en',
}) {
  if (stored == null) return null;
  // Deliberately not filtered through `storesForLocale`: a reader who stored
  // Libby and then changed the device language still owns that copy, and hiding
  // the way back to it would be worse than offering a shop the locale list would
  // not have suggested.
  final all = storeLinksFor(
    intent: StoreIntent.open,
    isbn: isbn,
    title: title,
    authors: authors,
    volumeId: volumeId,
    libbyTitleId: libbyTitleId,
    libbyLibraryKey: libbyLibraryKey,
    storefrontCountry: storefrontCountry,
    localeCode: localeCode,
  );
  for (final link in all) {
    if (link.id == stored) return link;
  }
  // The stored shop is not offered in this locale, so build its link directly.
  final fallback = storeLinksFor(
    intent: StoreIntent.open,
    isbn: isbn,
    title: title,
    authors: authors,
    volumeId: volumeId,
    libbyTitleId: libbyTitleId,
    libbyLibraryKey: libbyLibraryKey,
    storefrontCountry: storefrontCountry,
  );
  for (final link in fallback) {
    if (link.id == stored) return link;
  }
  return null;
}
