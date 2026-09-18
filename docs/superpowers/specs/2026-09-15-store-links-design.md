# Where to read this

Give a book on the details page a route to the shops and reader apps that carry it —
Kindle, Apple Books, Play Books, Libby — from a single app-bar icon that opens a sheet.

Mockups: `docs/mockups/store-links/index.html` (`bar-sheet` is the chosen root; the two
alternatives are kept as superseded branches).

## The problem this closes

A reader looking at a book in Libstack has nowhere to go with it. On a friend's finished
book that gap is widest: the app is built so that you see what other people read, and
then offers no way to act on it. `BookSearchResult.url` has been carried since the first
catalogue provider and read by nothing.

Two intents were asked for, and both are in scope:

1. **Acquire** — "I want to read this"
2. **Open my copy** — "I already own this, take me to it"

## The constraint everything else follows from

**The two intents have inverted reliability.** Of six store × intent cells, only two are
exact per-book links:

|                 | Acquire                                                         | Open my copy                                       |
| --------------- | --------------------------------------------------------------- | -------------------------------------------------- |
| **Play Books**  | exact, but a **web** page — `store/books/details?id=<volumeId>` | **exact, in the app** — `accessInfo.webReaderLink` |
| **Apple Books** | exact **in the app** via the iTunes API, or **withdrawn**       | app launch only (`ibooks://`)                      |
| **Kindle**      | **search only** — `amazon.com/s?k=<isbn>&i=digital-text`        | app launch only (`kindle://`)                      |
| **Libby**       | search only — `overdrive.com/search` (no library key needed)    | app launch only — `libbyapp.com/shelf/loans`       |

Amazon publishes no per-book deep link, and `kindle://` opens the app's library rather
than a title. No wording changes that.

**Two of those cells were narrowed by device testing, after the first build shipped, and
a third URL was outright broken.**

Play Books' acquire link opens Safari rather than the app — proven from Apple's
app-site-association for `play.google.com`, which claims `/books/reader`, `/books/listen`,
`/books/getapp2` and `/books/notes` and _not_ `/store/books/details`. Apple's search
fallback opens the Books app on an _empty_ search tab, because Books claims the domain and
then ignores `term`. And Libby's search URL named a library that does not exist. All three
are covered in _Verified on device_ below.

**Ownership is unknowable.** Even with the scheme declared in
`LSApplicationQueriesSchemes`, `canLaunchUrl('kindle://')` proves the app is _installed_,
never that the book is _in it_.

Together these mean a uniform list of four interchangeable-looking stores would make
promises it cannot keep in three of six cells — and the failure is asymmetric in the worst
way. A reader who taps **Kindle** wanting their copy and lands on an Amazon search results
page has been lied to, which is worse than not shipping the feature.

## Decisions

### The entry point is an app-bar icon opening a sheet

One `IconButton` in the details page's `AppBar`, opening a `showMenuBottomSheet`-shaped
list. Nothing is added to the hero or the tab body.

Three reasons it wins. It costs the carefully-composed hero nothing. Availability is a
network answer, and resolving it _inside_ an already-open sheet is the only place a
spinner is unremarkable and no layout above it moves. And the bar is pinned by
`SliverPersistentHeader`, so the control is reachable from both tabs and at any scroll
offset.

Rejected: **a section at the top of the Book info tab**, which was the earlier
recommendation. It showed all four supporting lines with nothing to tap — its one genuine
advantage, and it is a real loss — but it disappears on the Notes tab and spends 193pt of
the tab body on a secondary action. Four `ListTile`s at their real 56pt pushed the
description off a 393pt frame entirely, which is what forced 48pt rows and made the cost
visible.

Also rejected: **a row in the band under `ReadingPeriodRow`**. It read as first-class and
survived the tab swipe, but it spent permanent header height on every book, hid all four
supporting lines behind a sheet _anyway_, and could not handle the empty state — hiding
the row varies the header height, which moves the title handoff `_handleScroll` measures
against the title's own box.

### The entry point is not gated on `isSelf`

`isSelf` gates the bar's delete and edit actions (`book_details_tab_view.dart:208`) and the
FAB (`:484`), so a friend's book currently has no actions at all. This one appears for both
viewers, because a friend's finished book is the discovery moment.

Consequence worth stating: on a friend's book this feature has to **bring the actions group
into existence** for a single icon, and that icon is then the only thing in the bar.

### A supporting line on every row, and it is not decoration

Each row carries a second line saying what a tap actually does. This is the only place
Kindle can admit it opens a search rather than the book, so it is load-bearing.

Rejected: **a chip row**. Half the height and a lighter weight that suited a secondary
action, but a chip has no second line, so a search-only destination can only be _marked_
and never _explained_. Drawing both side by side is what settled this.

### The verb carries the capability

`Read in Play Books` promises a book. `Open Kindle` promises an app. A reader who learns
that distinction once can trust every row afterwards, and it is four characters.

### Ownership is inferred from a tap, and remembered

Tapping a store records it on the book. Afterwards the sheet's title becomes **Your copy**,
that store takes the check `MenuAction.isSelected` already draws, and its verb drops to
whatever it can honestly deliver.

This is what makes intent #2 deliverable: the reader has told us where their copy lives, so
"launch the app" stops being a guess about ownership and becomes exactly right.

Two things fall out for free rather than needing rules of their own:

- **Status conditionality.** ~~An Interested book has no stored store, so it shows the
  acquire list; a Reading book you bought shows Open.~~ **This bullet was wrong, and its
  wrongness was quantitative rather than logical.** It holds only for a book whose shop is
  stored, and almost none are: of 473 books in production, 342 are Reading or Finished and
  **3** carry a `reader_app`. So the "Reading book you bought shows Open" case essentially
  never happened, and the sheet spent its life offering to sell people books they had
  already read. Status is now read directly — see _A book you already have is not one to
  go buy_.
- **`isSelf` conditionality.** The column is the _owner's_ fact, so a friend's book always
  shows the acquire list — never "Open Kindle" because your friend uses Kindle. A friend's
  book needs no write path at all, which RLS would refuse anyway. **This one held**, and
  the status rule above had to be given the same gate explicitly to keep it holding.

### It lives in a nullable column, not on the device

`books.reader_app text` — the shape `book_authors.sql`, `book_page_count.sql` and
`book_cover_color.sql` all already use, with null load-bearing exactly as `Book`'s existing
doc comments describe for `pageCount` and `coverColor`.

Rejected: **`shared_preferences`**, which is already a dependency and would need no
migration, but would not sync — and this is a multi-device social app.

### A tap is not a purchase, so it must be undoable

`Forget where I read this` sits at the bottom of the remembered sheet. Not drawn red:
`showMenuBottomSheet`'s API makes `isDestructive` one flag away, but forgetting a store is
not deleting a book.

## Copy

Reviewed against `app_en.arb`, whose voice is sentence case, freely contracted
("Couldn't load book info"), British _catalogue_, `…` not `...`, and whose failures come
as **title + body** stating what happened and why without blame (`scanNoMatchTitle`/`Body`).

| Key                    | English                                                                                       |
| ---------------------- | --------------------------------------------------------------------------------------------- |
| `whereToRead`          | `Where to read`                                                                               |
| `yourCopy`             | `Your copy`                                                                                   |
| `forgetReaderApp`      | `Forget where I read this`                                                                    |
| `checkingStores`       | `Checking the stores…`                                                                        |
| `noEbookTitle`         | `No ebook edition of this one`                                                                |
| `noEbookBody`          | `None of the stores we check have one. Print-only and small-press books often aren't listed.` |
| `storeOpensThisBook`   | `Opens this book`                                                                             |
| `storeOpensAtThisBook` | `Opens at this book`                                                                          |
| `storeOpensSearch`     | `Searches {store}`                                                                            |
| `storeOpensLibraryApp` | `Opens your {store} library`                                                                  |
| `storeBorrowFree`      | `Borrow free from your library`                                                               |
| `storeOpenApp`         | `Open {store}`                                                                                |
| `storeReadIn`          | `Read in {store}`                                                                             |

Store rows, acquiring: `Play Books` / _Opens this book's store page in your browser_;
`Apple Books` / _Opens this book_ (or the row is absent); `Kindle` / _Searches Amazon_;
`Libby` / _Borrow free from your library_.

The two exact rows are worded **differently on purpose**. Both reach the book; only Apple's
reaches it inside the shop's app, and a reader reported the Play Books row as broken
precisely because _Opens this book_ read as a promise about the app. The label stays the
bare brand name in both cases — the second line is where the difference belongs, and saying
it twice would make the list harder to scan, not clearer.

Store rows, remembered: `Read in Play Books` / _Opens at this book_; `Open Kindle` /
_Opens your Kindle library_; `Open Apple Books` / _Opens your Books library_.

`Where to read` also serves as the icon's `tooltip`, which is its VoiceOver label. It
covers both intents without committing to either, so one string serves a book you own and
one you don't — and it never says _buy_.

Rejected drafts, and why: _Opens the app, not the book_ (leads with what doesn't happen,
and is less accurate than naming the library); _Search results, no exact match_ (a clinical
caveat in a voice that doesn't write them); _Get it elsewhere_ ("get" implied buying);
_Forget where this lives_ (an idiom that would not survive translation). All are
asserted absent in the mockup so they cannot creep back.

**One reviewed string did not survive the build.** _Opens an Amazon search_ became
`Searches {store}`, because an article cannot agree with an interpolated brand name — it
rendered "Opens a Amazon search", and Amazon and Apple Books are precisely the two shops
most often reached this way, so it was wrong in the common case rather than the rare one.
A widget test caught it and now pins the general form: no supporting line may begin with
an article that has to agree with a brand.

## Localization

`app_ko.arb` is at **297/297 parity** and that is a hard gate: six new keys, six Korean
strings, in the warm `-어요` register the existing failure copy uses.

**The Korean store set is wrong, and it is not a wording problem.** Libby maps to US and UK
library systems and is meaningless in Korea; Korean readers use 리디북스, 밀리의서재, 예스24
and 교보. Given Kakao is the primary catalogue, the `ko` store list has to be decided before
strings are written. Open.

**Note on this section's premise.** "The `ko` locale" turned out to be the wrong unit for
two of the three questions it raises. Which Apple Books catalogue a reader can buy from is
decided by their Apple ID, not their language, so it is no longer read off the locale at
all — see _The storefront is a fact, not a guess from the language_. Libby's question
survives intact, because no equivalent signal exists for library systems. The store set
below is therefore locale-derived only where nothing better can be had.

Brand names (`Kindle`, `Apple Books`, `Play Books`) should stay Dart literals rather than
`.arb` entries — Apple, Google and Amazon all ship Latin brand names in Korean UI. This is
a deliberate exception to the parity rule.

## Components

- **`lib/services/store_links_service.dart`** — maps `(isbn, title, authors, locale)` to a
  list of `(store, label, supportingLine, Uri)`. Pure, so URL construction is testable
  without widgets. Owns the capability table that decides which label pair a row gets.
- **`lib/services/app_store_storefront.dart`** + **`ios/Runner/AppDelegate.swift`** — reads
  the reader's real App Store storefront over a `bookworm/app_store` method channel, and
  converts StoreKit's alpha-3 to the alpha-2 Apple's own URLs and search API require. The
  conversion is in Dart on purpose: unit-testable without a device.
- **`BookSearchResult.volumeId`** — a new field. `GoogleBooksSearchProvider._mapVolume`
  (`book_search_service.dart:189`) currently uses the volume id only as an ISBN fallback
  and discards it otherwise; capturing it is what unlocks the exact Play Books links.
- **`books.reader_app`** — one nullable column, plus the `Book` field, `copyWith`, and a
  `LibraryActions` write.
- **The sheet** — presented from `book_details_tab_view.dart`, built on the existing
  `showMenuBottomSheet` vocabulary.
- **`ios/Runner/Info.plist`** — `LSApplicationQueriesSchemes` gains the reader-app schemes.
  Currently Kakao's only.

## Error handling

- **Nothing found** is ordinary, not exceptional: `Book.isbn` is sometimes a Google volume
  id, and Kakao's mapper keeps only the first space-separated token, so lookups genuinely
  miss. Title + body in the sheet.
- **Lookup failure** (offline, quota) reuses the `scanLookupFailed` register rather than
  inventing a new one.
- **`canLaunchUrl` false** — drop the row rather than offer a dead tap.

## Testing

- `store_links_service` unit tests: exact vs search URLs per store; that a Google volume id
  masquerading as an ISBN does not produce a garbage ISBN query; locale selection.
- Widget tests: the icon appears on a friend's book; the sheet shows acquire rows with no
  check and no forget row for a non-owner; the title switches to `Your copy` once
  `reader_app` is set; the empty state renders title + body.
- A copy assertion, in the spirit of `test/color_contrast_test.dart`: Kindle's acquire row
  never claims an exact link. The mockup already asserts this; the app should too.
- `flutter test` is currently fully green (1313 cases) — any red is a real regression.

## What shipped, and what did not

Built and green. `lib/services/store_links_service.dart` (pure),
`lib/ui/widgets/bottom_sheets/store_links_sheet.dart`, the app-bar icon in
`book_details_tab_view.dart`, `BookSearchResult.volumeId`, `Book.readerApp`,
`LibraryActions.setReaderApp`, `supabase/migrations/20260915130000_book_reader_app.sql`,
thirteen `.arb` keys in both locales, and the three reader-app schemes in `Info.plist`.
46 new tests; `flutter test` is **1363 green** and `flutter analyze` is clean of both
errors and warnings in `lib/` and `test/`.

**Apple Books shipped as a search, and is now exact.** As first shipped an exact Apple URL
needed an iTunes Search API round trip, and keeping `storeLinksFor` pure and synchronous
was worth more than one extra exact link. The parameter was left in place (`appleBookUrl`)
so wiring a resolver would be purely additive, with an assertion pinning the exact-row
count at 1 so that adding it had to be a deliberate revisit. It has since been wired — see
_Apple Books can be exact_ below, including the revisited assertion.

Also deferred: the glyph does not change when a store is remembered (open question 2), and
there is no widget coverage of the launch-and-record path, because it ends in `launchUrl`
leaving the process.

## Post-ship fixes

Two bugs found in use, both mine, plus the gap that let them through.

### Play Books had no app fallback

Apple, Kindle and Libby each had a `StoreReach.app` case for the open intent. Play
Books did not, so an open with no volume id fell through to the Play Store _search_
case — and the sheet labels `(open, *)` as "Open Play Books" while labelling
`reach: search` as "Searches Play Books". A row promised the reader's app and
performed a store search: exactly the failure `StoreReach` was introduced to make
impossible.

Fixed with `com.google.playbooks://`, declared in `LSApplicationQueriesSchemes`.

**Why the tests missed it.** They walked one happy path per shop instead of the
matrix, so `play + open + no id` was never constructed.
`store_links_service_test.dart` now enumerates all sixteen store × intent × id
combinations and asserts two invariants directly: **no open link may ever be a
search**, and no acquire link may be a bare app launch. Verified by reverting the
fix and watching the grid fail with the precise combination named.

### A volume id was almost never available

`bookSearchProvider` resolves to Kakao whenever the locale is `ko` or the
preference says so, and Kakao supplies no volume id — nor does Open Library, which
`FallbackBookSearchProvider` may answer from. So "Play Books is the one shop exact
at both intents" was true of the English build and false of the Korean one, which
is this app's primary market. Every shop degraded to a plain search.

Fixed with `volumeIdForIsbnProvider`: one keyless Google Books `isbn:` lookup, on
demand, reusing `GoogleBooksSearchProvider.getByIsbn` rather than issuing fresh
HTTP. It is skipped entirely when the source already supplies an id
(`sourceSuppliesVolumeIdProvider`), skipped when `Book.isbn` is not really an ISBN,
never throws, and is cached per ISBN. On the Kakao path it runs **concurrently**
with the catalogue lookup, because there the answer is known in advance to be
needed.

One request fixes two shops: the same identifier feeds the exact Play Books links
and, once a resolver is wired, `appleBookUrl`.

### Android package visibility

`<queries>` listed only Kakao and Instagram, so under Android 11+ visibility the
Open rows could not resolve any reader app. Added `com.amazon.kindle`,
`com.google.android.apps.books` and `com.overdrive.mobile.android.libby`.
Deliberately _not_ added: an Apple Books package, because it does not exist on
Android while `storesForLocale` still offers the row. That gap is real and tracked
rather than papered over.

### The leading mark: a real logo for all four

The glyph on each row was a letter in a rounded chip. **All four shops now carry
their real mark.** An intermediate round shipped marks for Play Books and Apple
Books and letter chips (`K`, `L`) for Kindle and Libby, on the conclusion that no
licence-clean mark existed for either. **That conclusion was wrong twice over**,
and the correction is recorded here because the same dead end is easy to walk into
a third time:

- **Simple Icons still carries `amazon`.** `cdn.simpleicons.org/amazon` does 404,
  which is what produced the "the whole `amazon*` family was removed upstream"
  claim — but the icon is live at `api.iconify.design/simple-icons/amazon.svg`,
  still CC0. Checking one distribution channel and concluding the asset does not
  exist was the error. Kindle now draws the Amazon mark.
- **Arcticons carries Libby.** 15,057 icons under CC BY-SA 4.0, monochrome and
  `currentColor`, including real `kindle`, `libby` and `overdrive` marks. It was
  never considered, because the search stopped at Simple Icons.

Two deliberate consequences:

- **Kindle draws the _Amazon_ mark, not a Kindle one.** No redistributable Kindle
  glyph exists in any set. This is not a compromise: the row's own second line
  already reads _Searches Amazon_, so the mark names the ecosystem and the label
  names the shop, and the two agree rather than compete.
- **Libby is a stroke where the other three are solid fills**, so it carries less
  ink at equal size and read as the lightest row in the sheet. `_Glyph` therefore
  draws it at **20** of the 30pt box where the others get 16. That is an optical
  correction, not a nudge, and flattening the sizes back to one constant is the
  tidy-up that would silently undo it. `test/store_marks_probe_test.dart` renders
  both for comparison and **exists to be looked at**, on the same principle as the
  empty-state contact sheets.

Still rejected, unchanged: **hand-drawing** a missing mark (inventing a trademark;
`AGENTS.md` records ten rejected rounds of hand-written SVG for the empty-state
art), and the **official brand kits** — Apple's "Get it on Apple Books" and
Google's Play badges are full-colour wordmark lockups with prescriptive
clear-space and minimum-size rules that a 30pt chip breaks. They are badges, not
glyphs.

The marks are tinted to `primaryText` rather than drawn in brand colour, for the
same reason the empty-state art is tinted: in a sheet that is otherwise entirely
typographic a coloured chip is the loudest thing on the page, and a bundled
full-colour asset would not follow dark mode. The rejected brand-colour treatment
is drawn beside the shipped one in the mockup's `el-logos` element.

**Attribution is now a licence condition, not a courtesy.** Arcticons is CC BY-SA
4.0, and bundled SVG assets never appear in Flutter's aggregated licence page —
that only collects `LICENSE` files from packages. So `settings_page.dart` names
both sources in `applicationLegalese` via the new `storeMarksCredit` key; if that
line goes, nothing else carries the obligation.

`storePlayIcon.svg`, `storeAppleIcon.svg`, `storeKindleIcon.svg` and
`storeLibbyIcon.svg`; the mapping is `_Glyph._mark` in `store_links_sheet.dart`,
keyed on `StoreId` so a new store cannot forget to answer the question, and
returning the size alongside the asset. Five widget tests pin it — a real mark for
every shop, **no** letter fallback anywhere, four distinct assets, the stroked mark
drawn larger, and tinting rather than brand colour.

**Resolved:** open question 4 is closed. Kindle and Libby are not lettered
indefinitely; they have real marks.

### Apple Books can be exact

Apple was the last shop that could never reach a book, and the reason was worth
stating precisely: not a missing URL format, but a missing **id**.
`books.apple.com/us/book/…/id731076045` carries Apple's own identifier, which
appears in no catalogue this app reads, so no amount of volume-id plumbing was
ever going to upgrade that row. The gap was that nothing had asked Apple.

`appleBookUrlFor` in `lib/services/apple_books_lookup.dart` asks: one keyless
iTunes Search API `lookup?isbn=…&entity=ebook&country=…`, exposed through
`appleBookUrlProvider` and awaited concurrently with the two lookups already
running. `store_links_service.dart` stays pure — it still just takes a URL.

Four things were **verified against the live endpoint** rather than assumed, and
each one changed the code:

- **`isbn=` matches thirteen digits only.** `0143127741` returns nothing;
  `9780143127741` returns the book. This is not an edge case in this column —
  Google's mapper falls back to ISBN-10 and Kakao keeps whichever form came
  first — so the lookup normalises through the existing `normalisedIsbn13`,
  which already handles hyphens and already rejects a volume id in the field.
  Without it a large share of the library would silently never match.
- **A book URL is scoped to its storefront.** `/kr/book/id731076045` is a 404 for
  the id that resolves under `/us/`. So the URL is taken verbatim from
  `trackViewUrl` instead of being rebuilt, the provider is keyed on ISBN **and**
  country, and `_country` became the public `storeCountryFor` so the lookup and
  the link builder cannot drift apart.
- **`kr` cannot resolve a commercial book at all, and this is Apple policy rather
  than thin data.** Apple's own _Availability of Apple Media Services_ lists South
  Korea as **"Apple Books — Public domain books only"**, and Apple Books Partner
  Support's sell-in list omits Korea entirely (Japan is on it). The probes match
  the policy exactly: a `kr` ebook search for "harry potter" returns _Alice's
  Adventures in Wonderland_ and _Mathilda_, and `books.apple.com/kr/charts` is a
  404 where `/us/charts` is a 200.

  Note the distinction, because it is easy to state wrongly: the **Books app**
  ships on every Korean iPhone and reads sideloaded EPUBs fine. It is the **store**
  that sells only public-domain titles there. Deliberately **not** worked around by
  retrying against `us`: that returns a URL a Korean account cannot buy from, which
  is worse than an honest search. **`storesForLocale` therefore withdraws Apple
  Books from `ko` outright**, on the same grounds it already withdrew Libby — a row
  that can never reach a commercial Korean book is broken, not merely weak.

  **Re-confirmed when queried, and cited so it need not be taken on trust.** Source:
  _Availability of Apple Media Services_, `support.apple.com/en-us/118205`, published
  **15 Sep 2026** — South Korea's Apple Books entry reads "Public domain books only"
  where Japan's reads "Book & Audiobook purchases". Korea is not singled out: in
  Asia-Pacific only **Japan, Australia and New Zealand** have a commercial book
  store, while Hong Kong, Taiwan, Singapore, India, Indonesia, Malaysia, the
  Philippines, Thailand and Vietnam are public-domain-only alongside Korea. Two
  further probes agree — `kr` returns **0** results for _소년이 온다_ and _불편한
  편의점_, both of which resolve under `us` and `jp`, and a `kr` search for 한강
  returns Conan Doyle.

- **The ISBN index is incomplete even for books Apple sells**, so an ISBN miss is
  not evidence of absence, and a second question is asked: a **title-and-author
  search**, guarded. Verified against the live endpoint — it recovers _Dune_ both
  when the row's ISBN field holds a Google volume id and when the real ISBN simply
  is not indexed, neither of which the ISBN query could reach.

  The guard is what makes it safe, and it took two attempts. Title _and_ author
  must both agree: for _The Body Keeps the Score_ the live search returns the real
  edition second, behind `"… - Summary and Analysis"` by _Summary Life_, so an
  unguarded `results[0]` would send a reader to a study guide under a row saying
  _Opens this book_. The first guard compared folded titles with `startsWith`, and
  accepted **`Dune Messiah` for `Dune`** — a different book by the same author, so
  the author check cannot catch it. It now splits off a `:` subtitle and a trailing
  bracketed edition marker _before_ folding and requires exact equality, so
  `Dune: Book One` and `Dune (Enhanced Edition)` match and `Dune Messiah` does not.

- **`uo=4` is echoed into every `trackViewUrl`.** Apple's own affiliate marker,
  asked for by nobody, stripped so it does not end up in a URL a reader can share.

The host is checked to be `books.apple.com` before the URL is used, because it
goes to `launchUrl` with `externalApplication` — without that check a third
party's JSON could send the reader anywhere the OS can open.

The pinned exact-row count assertion was **revisited rather than deleted**: it now
asserts two shops can be exact simultaneously and that Kindle and Libby are
unaffected by either lookup, which is the configuration in which a row could pick
up a neighbour's reach. The store x intent x id grid grew an `appleBookUrl`
dimension, 16 combinations to 32, which is what pins the invariant that a resolved
URL never leaks into the `open` intent.

A miss is an ordinary outcome, not an error, so every failure path — miss, timeout
(4s), offline, non-200, malformed body, wrong `kind` — returns null and the
existing search fallback and its honest copy take over. No copy changed.

### Verified on device, and it cost two reaches

A reader tested the shipped build and reported two rows behaving wrongly. Both were
real, and between them they retired the last two "unverifiable from here" items.

**Play Books' acquire link opens Safari, not the app.** Proven rather than argued:
Apple's app-site-association for `play.google.com` claims exactly four paths for
`EQHXZ8M8AV.com.google.GoogleBooks` — `/books/reader`, `/books/listen`,
`/books/getapp2`, `/books/notes`. `/store/books/details` is claimed by no Google app
at all, so iOS _cannot_ hand it to Play Books however installed it is.

The URL is nonetheless correct — Google cannot sell books in-app on iOS, so the web
store page is the only purchase route — so the fix is the copy, not the link. This
closes the previously-open _`StoreReach.book` conflates two destinations_ item with a
new reach, **`StoreReach.storePage`**, and a new line: _Opens this book's store page in
your browser_. `/books/reader` **is** claimed, which is why opening a remembered copy
remains `StoreReach.book` and still says _Opens at this book_.

**Apple's search fallback opens an empty search tab.** `books.apple.com` _is_ claimed
by Books — so the app opens, settling the question the missing app-site-association
left open — and then ignores `term` entirely. A row reading _Searches Apple Books_ that
searches nothing is the exact failure this design exists to prevent, and no wording
fixes it: a bare app launch is banned for an acquire link, correctly, since an app you
cannot aim at is not a way to get a book.

So the row is **withdrawn** when Apple confirms it has no edition. That required the
lookup to answer three ways rather than two — see `AppleBooksAvailability`. The
asymmetry is load-bearing: only a _confirmed_ absence hides the row, because hiding a
shop on the strength of a dropped connection is the worse error, so `unknown` keeps the
weak fallback. `storeLinksFor` asserts the two halves are never claimed at once.

Only acquiring is affected. A reader who stored Apple Books keeps their way back into
the app whatever Apple currently sells.

**Libby's search URL named a library that does not exist.** The shipped URL was
`libbyapp.com/search/all/search/query-<term>`, and the segment holding `all` is a
**library key**. Libby claims the domain, so it opened, read `all` as the name of a
library, could not find it, and showed its own error: _"I'm having trouble fetching
details about this library."_

There is no library-agnostic form of that URL, and this is a product constraint rather
than a missing parameter: Libby search is always scoped to a library the reader has
added, and OverDrive's API refuses the question directly —
`thunder.api.overdrive.com/v2/media/search` returns **"Must specify at least 1
libraryKey"**. Knowing the reader's library would mean asking for it and storing it,
which is a feature and not a URL fix.

So the row goes to **`overdrive.com/search?q=`**, which needs no library, returns a real
results page, and shows which libraries hold a title. Its own tagline is _"Free ebooks,
audiobooks & movies from your library"_ — which is the promise the row already makes, so
the copy is unchanged. It opens in a browser, since Libby claims no `overdrive.com` path.

**The pattern is worth more than the four fixes.** Every one was a URL that read
plausibly and had never been opened on a device, and **no test could have caught any of
them** — a test can assert the URL we chose to build, never that it arrives somewhere.
The device-verification list below is therefore a release blocker, not a nicety.

**Custom schemes fail hard; universal links degrade to the web.** `libby://` was a
guessed scheme for an app actually called `com.overdrive.dewey`, and `launchUrl`
returned false even with `libby` declared in `LSApplicationQueriesSchemes` — which the
sheet surfaced as a bare _"Something went wrong"_. Libby's app-site-association claims
`["NOT /api/*", "*"]`, so the row now opens `libbyapp.com/shelf/loans` — a real route,
confirmed in the app's own bundle beside `shelf/holds` and `shelf/timeline`. When Libby
is absent that opens Libby's _web_ shelf; when `kindle://` is wrong the reader gets a
dialog and nothing else. **Prefer a claimed https path over a scheme wherever one
exists.** The `libby` entry has been removed from `Info.plist`; `kindle`, `ibooks` and
`com.google.playbooks` remain, and remain guesses.

The reach stays `StoreReach.app` — the shelf is not this title. Targeting a specific
loan needs an OverDrive title id **and the reader's library key**. The id turned out to
be obtainable on its own (see below); the key is not, so this conclusion survived even
though its stated reason was incomplete.

### Still open from this round

`20260915130000_book_reader_app.sql` sat unapplied on production from the day the
feature shipped until it was asked about directly. It is applied now — `books.reader_app`
exists on `fkynxmfnsgtafrsbzwtu`, versions aligned so the CLI sees no drift, and the two
unrelated pending migrations from parallel work were deliberately left alone (`db push`
would have taken all three; MCP's `apply_migration` would not).

**Worth recording is why nobody noticed.** The failure was invisible by design.
Reading degraded harmlessly — an absent column reads as null, which is exactly the
acquire list — and `setReaderApp` swallowed every write error on purpose, reasoning
that the reader had already got what they asked for. Both halves are individually
correct, and together they meant the feature's entire second intent was dead:
no shop ever remembered, so no _Your copy_ title, no check, no _Forget where I read
this_, no way to open a copy. It looked like a design decision.

The swallow is now narrowed. A `PostgrestException` carrying `42703`
(Postgres' undefined_column) or `PGRST204` (PostgREST's unknown-column) is a
deployment bug rather than a transient failure, so it trips an `assert` — loud in
debug, still silent in release, where the original reasoning still holds.

The general lesson is not about this column: **a deliberately silent write needs to
be silent about a specific class of failure, not all of them.** Any `catch (_)` that
swallows schema and policy errors alongside network ones can hide a broken
deployment indefinitely.

### Libby names the exact title, but only on the web

The Libby **acquire** row now goes to **`overdrive.com/media/<globalTitleId>`**, resolved by
a new `overdrive_lookup.dart`. Opening is unchanged.

The id comes from two requests, and the split is the whole design. OverDrive publishes no
global search API — `thunder`'s `/v2/media/search` refuses with _"Must specify at least 1
libraryKey"_ — but `overdrive.com/search?q=` **is** global, and its results page exposes
`/media/<id>/` links. So: harvest candidate ids from that page's HTML, then ask the keyless
`thunder.api.overdrive.com/v2/media/bulk?titleIds=…` about them, which answers clean JSON.
The ids are global — the same one resolves under `sfpl`, `lapl` and `chipublib`.

**The HTML dependency is fragile and fails safe, which is the only reason it is
acceptable.** Every judgement about _which_ book was found is made against the JSON, never
the markup. A markup change yields no candidates and the row degrades to the search it ran
before. It can cause a **miss**, never a wrong book. Verified live: _The Hard Thing About
Hard Things_ → `1344919`, _Dune_ → `1243691` (not _Dune Messiah_), a nonsense query → miss,
a book with no author → miss.

The matcher is the Apple one, extracted to **`book_match.dart`** and shared. It earns its
keep immediately: OverDrive returns _"A Joosr Guide to... the Hard Thing about Hard Things
by Ben Horowitz"_ with a **null creator** in the same results, which title-only matching
would have accepted.

**Audiobooks are accepted, and an ebook-only filter was a bug caught before it shipped.**
Libraries lend audiobooks as first-class stock — for one title at one library, 4 ebook
licences against **19** audiobook — so filtering to `ebook` would report "no edition" for a
book the library demonstrably lends, and would do so every time for an audio-only title. An
ebook wins where both exist; otherwise the search page's order breaks the tie, since
`media/bulk` does **not** preserve the order of the ids it was sent.

#### Two wrong URLs before the right one, and only a device found the second

**`share.libbyapp.com/title/<id>`** was the first choice. It has no Borrow button, no
library picker and no sign-in — its entire call to action is _"Find this title with Libby"_
over App Store and Google Play badges. An install ad with metadata attached.

**`libbyapp.com/title/<id>`** was the second, and it is the one that reached a device.
Libby opened, showed its own **"View not found."** and dropped the reader on the Shelf.
Libby's router says exactly why — `title/<id>` is a real pattern, but it belongs to
`title-redirect-controller`, a **sub-controller of the library realm**:

```js
var s = e.match(/^title\/(\d+)(\/(.+))?$/);
if (s) {
  var a = "library/" + this.ancestor.args.key;
  return { rewrite: a + "/similar-" + n + "/page-1/" + n + r };
}
```

A bare `/title/<id>` has no ancestor, so no `args.key`, so no match. The root-level table
handles only `authenticate/<key>`, `resolve/<key>`, `timeline` and the empty path — **there
is no library-agnostic title route.** `resolve` is not a way round it either: its `commence`
returns `#missing-args` unless a key or websiteId is supplied.

**So an in-app exact Libby link genuinely requires the reader's library key**, via
`libbyapp.com/library/<key>/title/<id>`. That reinstates the `libby-library` proposal rather
than retiring it — see _Open questions_.

What can be had without a key is `overdrive.com/media/<id>`: the exact title, its format,
ISBN, series and publisher, a sample, and OverDrive's own _"Is this your library? / find a
library"_ affordance. Still a real gain over a results page — no wrong-book risk, one less
step — but it is a **browser**, so the reach is `StoreReach.storePage`, not `book`, exactly
as Play Books acquire is.

**The reader's library _card_ is still never asked for.** The key (which library) and the
card (the credential) are different things. Libby cannot lend without the card, but that is
Libby's flow and Libby already owns it; duplicating it would store a credential for no gain,
since only Libby can perform the loan.

**Availability is per-library and no row claims otherwise.** The same id is _87 of 87
available_ at LAPL, _0 of 4 with 11 holds_ at SFPL, and not stocked at all at Nassau County.
The Libby row keeps its `storeBorrowFree` line — _"Borrow free from your library"_ — which is
true in all three cases. No new strings; `.arb` parity is untouched.

The lookup is skipped where no Libby row will be shown, so the `ko` path pays for nothing.
It returns **two** outcomes where Apple's returns three, deliberately: a confirmed absence
makes the _Apple_ row disappear, so "not sold" and "could not ask" need distinguishing
there. Libby's fallback reads honestly either way, nothing acts on the distinction, and with
candidates coming from HTML we could not honestly tell a genuine zero-result page from a
markup change.

### The reader's library, asked once

The `libby-library` branch is **built**. Both Libby rows now reach the book:
**`libbyapp.com/library/<preferredKey>/title/<globalTitleId>`**, which Libby rewrites
internally to `library/<key>/similar-<id>/page-1/<id>`.

**The blocker that had stopped this was a wrong conclusion, and how it was wrong is
the more useful half.** The design record said no library **name** search API
existed. What had actually been established was narrower: `thunder`'s `/v2/libraries`
really is a 13,112-row directory filtering only by `libraryKeys` and `websiteIds`, and
`/libraries/search` and `/libraries/autocomplete` really do 404. But Libby does not use
`thunder` for this. Its bundle builds a **separate service** by rewriting its own root:

```js
_createDeweyLocateService: var i = this._serviceURI("ROOT_URI");
                           i = i.replace("//", "//locate.");
… APP.services.deweyLocate.fetch("autocomplete/" + encodeURIComponent(query), …)
```

`https://locate.libbyapp.com/autocomplete/<query>` — keyless, 200. _"This API does not
exist"_ is a far stronger claim than _"I did not find it on the host I was looking
at"_, and only the second had ever been shown. Worth remembering next time a feature
is parked on the first one.

Two hops, in `libby_library_lookup.dart`, because neither service answers the whole
question: `locate` knows names and geography but returns a system's `websiteId`, and
the URL needs its key, which `thunder/v2/libraries?websiteIds=…` supplies as
**`preferredKey`** (not `baseKey`, which comes back null on that endpoint). A candidate
with no resolved key is **dropped, never guessed** — a wrong key is Libby's "trouble
fetching details about this library" screen, which is where this whole row started.

**It searches branches, and that is a gift rather than a limitation.** The drawn design
spent a whole empty state warning readers not to search a branch. They can: _"Mission
Bay Branch Library"_ resolves to San Francisco Public Library, _"Auburn Library"_ to
King County Library System. The empty-state copy now offers all three kinds of query
instead of warning against one of them.

#### What the reader sees

Just-in-time, as drawn: the picker appears on the **first Libby tap**, not on opening
the sheet, and not on a tap of any other shop. It is skipped entirely when no title id
was resolved, because a library key with nothing to point at collects an answer that
changes nothing about that tap.

Dismissing **never blocks** — the row falls back to what it did before, which works —
and is remembered, so a reader who declined is not asked again. `LibbyLibraryChoice`
keeps three states for exactly this: `reader_app` taught that "never asked" and "asked
and declined" are different facts, and only the first may open a picker.

The row's supporting line splits on the reach like every other row's:
`Borrow this book from your library` once a library is known, `Borrow free from your
library` otherwise. **The four characters are load-bearing** — without them the
destination would get better and the row would look identical. Neither line claims the
copy is _available_: the same title is 87-of-87 at LAPL and eleven deep in holds at
SFPL, so the row names the book and the lender and lets Libby settle the outcome.

Settings gets a row beside the book-source picker, opening the same sheet. Dismissing
there is only a cancel, not an answer.

#### Stored in SharedPreferences, not the drawn nullable column

A deliberate departure, for three reasons in order of weight. It is a device preference
of exactly the same character as `book_source_preference`, and it sits beside that row —
two mechanisms for one kind of setting is a thing to explain forever. `books.reader_app`
sat **unapplied on production for this feature's entire life**, which is a recent and
expensive argument against adding a column when nothing needs one. And nothing here is
queried, joined or shared between users. The cost is that a reinstall re-asks: one
field, once.

#### Two gaps this closed that were not in the plan

The test harness never overrode **`overDriveProvider`**, so from the moment that lookup
landed every details-page test that opened the sheet was issuing live requests to
`overdrive.com`. The `apple` parameter's own doc comment warns about precisely this and
it was still missed. Both lookups are now stubbed by default.

And `storeLinksFor` now requires the library key to be **non-empty**, not merely
non-null. It is a path segment, so an empty one builds `library//title/<id>` — a
malformed library key, and Libby's answer to that is the error screen this row's first
bug produced. Guarded in two places, and pinned.

### The storefront is a fact, not a guess from the language

`storeCountryFor` used to derive the Apple storefront from the device language: `ko` →
`kr`, everything else → `us`. That is a guess at the wrong variable. Which Apple Books
catalogue a person can buy from follows their **Apple ID's country**, which is
independent of the device's language _and_ of where the phone physically is.

It was wrong in both directions, and the two failures are not symmetrical:

| Phone language | Apple ID | Old behaviour              | Why it was wrong                                                                                                                 |
| -------------- | -------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `ko`           | US       | Apple Books row **hidden** | That account buys from the US store perfectly well. The one row that would have worked was the one row missing.                  |
| `en`           | KR       | Rows built against `/us/`  | That account cannot buy from `/us/` at all. **A dead link, not a missing row — the worse half**, because it looks like it works. |

Only StoreKit can answer it, and it does so with no purchase, no product request and no
entitlement: `SKPaymentQueue.default().storefront?.countryCode`, iOS 13+ against a
deployment target of 15. So the app now asks.

- **`ios/Runner/AppDelegate.swift`** registers `bookworm/app_store` on
  `engineBridge.applicationRegistrar.messenger()` — an application-level channel, not a
  plugin's, so it does not go through `pluginRegistry`. The channel is held in an ivar;
  a `FlutterMethodChannel` does not retain its handler's owner, so a local would stop
  answering the moment registration returned.
- **Swift returns raw alpha-3** (`USA`, `KOR`) and converts nothing. The mapping lives in
  Dart (`lib/services/app_store_storefront.dart`) precisely so it is unit-testable
  without a device — 10 cases, no simulator.
- **Alpha-2 is not a preference.** `itunes.apple.com/search?country=USA` returns a
  non-JSON error where `country=us` works, and `books.apple.com/USA/...` is not a path.
  The full 249-entry ISO table is kept rather than trimmed to the storefronts Apple
  operates today, because a trimmed list is one that rots silently when Apple adds a
  country.

**Null is an ordinary answer and must cost nothing but precision.** Android has no
equivalent, the simulator with nobody signed in has no storefront, `flutter test` has no
channel, and StoreKit legitimately reports `nil` for a short window early in launch.
Every one of those falls back to the locale-derived country — which is exactly the
previous behaviour, so the degraded path is the one that shipped and worked.

**Awaited before the Apple lookup, not alongside it.** The storefront decides _which
store that lookup interrogates_, so running them concurrently would mean asking the
wrong one. It is one cheap platform call, cached by a non-`autoDispose` provider for the
session, so the serialisation is paid once.

#### What this let us give back to Korean readers

Apple Books was withdrawn from the `ko` store set on the strength of Apple's own sell-in
list. That withdrawal is now **reverted**, and the storefront is why: Korea-ness is
enforced by the real storefront plus the lookup's `notSold` answer, which already drops a
row on confirmed absence. So `ko` is `[play, apple, kindle]` again, and a Korean reader on
a Korean account still loses the Apple row for anything but public-domain titles — while a
Korean reader on a US account keeps it for everything.

The residual is honest and shared: an `unknown` lookup (offline, timeout) leaves the weak
search fallback in place, identical to every other storefront's behaviour. **Libby stays
withdrawn from `ko`**, for a different reason — no storefront-shaped signal exists for
"which country's libraries", and the OverDrive answer is global.

#### Tested, and the tests were made to fail first

`test/store_links_sheet_test.dart` gained a group in which `locale` and `storefront`
always **disagree**, since agreement is the case the old code already got right. Two
affordances made it possible: the harness takes a `locale`, and an `applePerCountry` map
that answers the lookup differently per storefront — without which a view that asked the
wrong country would still render a perfectly plausible row.

The suite also gained its **first URL assertions**. Until now it could only read row
_labels_, which is the blind spot this feature's whole history is made of — a row that
said "Open Play Books" and ran a Play Store search, four wrong Libby URLs.
`test/support/fake_url_launcher.dart` stands in for the platform side of `url_launcher`
(`extends UrlLauncherPlatform`, so `PlatformInterface.verify` accepts it and no mocking
package is needed) and records what the app hands over.

The four cases were then verified by mutation: `storeCountryFor` was made to ignore its
`storefront` argument, and **exactly the three storefront-dependent cases failed** while
the locale-fallback case correctly kept passing.

It still cannot see whether a URL _arrives_. Two of the four wrong Libby URLs were
reasoned from real evidence and would have passed a test like this.

### Custom schemes are a last resort, not the default

Every `open` row launched a guessed `scheme://`. Two of the three are gone, replaced by
https paths the target app **claims in its own app-site-association**:

| Row         | Was                       | Now                            | Evidence                                                    |
| ----------- | ------------------------- | ------------------------------ | ----------------------------------------------------------- |
| Play Books  | `com.google.playbooks://` | `play.google.com/books/reader` | `play.google.com` AASA, `EQHXZ8M8AV.com.google.GoogleBooks` |
| Kindle      | `kindle://`               | `read.amazon.com/application`  | `read.amazon.com` AASA, `J7P34ALZ5R.com.amazon.Lassen`      |
| Apple Books | `ibooks://`               | **unchanged, deliberately**    | see below                                                   |

**The argument is the failure mode, not elegance.** A custom scheme with no app
installed fails hard: `launchUrl` returns false, the reader gets "Something went wrong"
and there is nowhere to go. A universal link cannot do that — it degrades to that shop's
web reader. And in both cases the web reader _is_ the reader's library (Play Books web
reader; Kindle Cloud Reader), so the row's promise survives the fallback rather than
dying on it.

This is not a new rule. Libby was moved off `libby://` for exactly this reason after it
failed on a device, and `Info.plist` already recorded the conclusion — _prefer that shape
for any future store_. These two are that rule being applied.

**`com.google.playbooks://` was also simply wrong**, which is worth recording because it
read so plausibly. The iOS bundle id is `com.google.GoogleBooks`, and Google ships
`googlegmail://`, `googledrive://`, `comgooglekeep://` — that string matched no convention
Google uses anywhere, and Play Books appears in no published scheme list. It looks like it
was built from an Android-style package name, and even the Android one is
`com.google.android.apps.books`.

**Kindle's host is a trap worth naming.** On `www.amazon.com` the Kindle app claims
_nothing_: `/bookshelf` and `/kindle-dbs/hz/bookshelf/prime` are there, but against
`com.amazon.Amazon` — the shopping app. So the obvious-looking `amazon.com/bookshelf`
would open the wrong app entirely. Only `read.amazon.com` lists `com.amazon.Lassen`
(Lassen is Kindle for iOS), and only for `/application`, `/application/*`, `/gp/r.html`.

#### Why Apple Books keeps its scheme

The original plan was to swap all three. Apple was reversed on evidence:

- **`ibooks://` is documented, not invented.** It appears in the widely-used AppURLs
  reference alongside `itms-books://` / `itms-bookss://` — unlike
  `com.google.playbooks://`, which appears nowhere.
- **There is no Apple Books web reader.** So no https URL exists that reaches a reader's
  own library; `books.apple.com/` bare is a _storefront_. Swapping would trade an app
  that opens for a shop that does not — worse, not safer.
- Books ships preinstalled, so the hard failure the rule guards against barely arises.

#### Verified on a device

✅ **`read.amazon.com/application` opens Kindle at the library page.** Confirmed by hand,
which is the only confirmation this feature accepts. The `app` reach and the "Opens your
Kindle library" line are both earned rather than assumed.

Note what did _not_ need testing: `kindle://`. It was replaced rather than verified,
because the argument for a claimed path never depended on the scheme being wrong — only on
the scheme being able to fail hard.

No copy changed. `storeOpensLibraryApp` ("Opens your {store} library") stays accurate
because both new fallbacks are library pages; only [StoreReach.app]'s doc comment needed
widening to say the destination may be the web equivalent.

### A book you already have is not one to go buy

The sheet chose its intent from **`reader_app` alone**, so a book with no stored shop got
the acquire list however far through it the reader was. Offering "get this" on a book
someone finished last month reads as absurd, and it was not an edge case:

| Status         | Books | With `reader_app` |
| -------------- | ----- | ----------------- |
| 0 · interested | 131   | 0                 |
| 1 · reading    | 110   | **3**             |
| 2 · finished   | 232   | 0                 |

**342 of 473 books were being sent to a shop to buy something the app knew had been
read.** `reader_app` and status are now read as the two independent facts they are:

- **`reader_app` decides which shop leads** and carries the check. _(unchanged)_
- **Status decides whether the other shops are `open` rows or `acquire` rows.** _(new)_

Getting that second part wrong is what the first attempt shipped: inference required _no_
stored shop, so storing one sent every **other** shop back to the storefront. A book at
Reading with Apple Books stored still offered _"Opens this book's store page in your
browser"_ for Play Books. Storing Apple says nothing about Play, and certainly not that the
reader wants to go buy a book they are halfway through.

#### Why this needs no extra step, and why a picker was the wrong instinct

The first design considered was an explicit "I already have this" row opening a shop
picker. It was rejected, correctly: **this feature already decided that ownership is
inferred from a tap, not asked for** (see _Ownership is inferred from a tap, and
remembered_). A picker adds a step in front of a decision the tap itself expresses.

So the open list is not a dead end needing an escape hatch — it is a **second writer for
`reader_app`**, and the only one that will ever reach those 339 books. Tapping "Open Kindle"
on a finished book _is_ the assertion. That required widening the recording gate, which was
`acquire`-only; its stated justification ("re-tapping the stored shop should not rewrite
it") was already handled by `setReaderApp` short-circuiting an unchanged value, so the gate
was doing no work the writer did not already do. It also means a reader who stored the
wrong shop corrects it by tapping the right one, rather than having to find `Forget where I
read this` first.

The worry that this means "four rows, three of them wrong" applies equally to the four
_acquire_ rows it replaces. Same shops, same number of choices; the reader knows where
their copy is and the other three never get tapped.

#### Each row still reaches as far as it can — and the humbler version was worse

The first attempt **withheld every per-book id** on this path, so all four rows sat at
`StoreReach.app` (_"Open X / Opens your X library"_). The reasoning: with a volume id Play's
row becomes `StoreReach.book` and reads _"Read in Play Books / Opens at this book"_, which
asserts ownership **in Play** where status only says "somewhere".

**Checking the humbler alternative is what killed it.**
`play.google.com/books/reader` with no `id` **is the Play Books storefront** — deals, top
charts, new releases. So the row that was trying to over-promise less promised _"Opens your
Play Books library"_ and landed on a **shop**: a worse lie than the one being avoided, and
the exact failure `StoreReach` exists to prevent. With the id it reaches the book's own
reader.

Two further reasons the withholding bought nothing:

- The stored-shop row has **always** said "Opens at this book" without verifying
  entitlement, so withholding here created an inconsistency rather than removing one.
- It disarmed the Libby library picker, which was recorded as a feature and was a second
  mistake — see below.

So the ids are passed, and the rows differ by capability as they do everywhere else in this
sheet: Play reaches the book, Kindle says it can only reach the library.

#### The Libby ask belongs here after all

The first attempt claimed the picker should not fire on a book the reader already has,
because `libbyapp.com/shelf/loans` is library-agnostic and a key could not improve it.
**True of the shelf link, but the key does not leave the row there**: title id plus key
builds `library/<key>/title/<id>`, the title's own page carrying Borrow / Place Hold /
**Open**. The answer changes the destination exactly as it does on the acquire path, so the
ask is charging for something. The OverDrive lookup is therefore not skipped on this path
either.

#### The cost, taken knowingly

**A reader who finished a paper book is offered four ways to open a copy they do not have
digitally, and no one-tap store search.** Paper is invisible to this app — no format field
anywhere, and catalogue metadata describes the _edition_, never what the reader owns — so it
cannot be detected. Judged smaller than the 342-book problem it fixes.

It also sharpens _Open question 1_ ("a tap is not a purchase"): there are now more taps
that write, on books where the reader may be browsing rather than asserting. `Forget where
I read this` remains the undo.

#### Tested by mutation, and two comments were wrong

Three claims were each verified by breaking them:

| Mutation                                  | Failed                                                                    |
| ----------------------------------------- | ------------------------------------------------------------------------- |
| drop the `isSelf` gate on inference       | a friend's finished book offers the shops; a friend's tap records nothing |
| restore the `acquire`-only recording gate | opening a shop records it                                                 |
| point the open row at the Play _Store_    | opens Play Books itself, never the Play Store                             |

The `isSelf` gate was a **real bug caught by an existing test** — inference was written
without it, so a friend's finished book offered to open _your_ library for _their_ book,
and a friend's finished book is the case the sheet was built for.

Mutation also corrected a comment about which mechanism disarmed the Libby ask — moot now
that the ask is kept, but a reminder that "belt and braces" claims are usually one belt and
an untested brace.

### The page was reading a snapshot, so writes landed nowhere visible

Storing a shop worked and looked broken. The write reached `books.reader_app` and
`libraryProvider` was invalidated, but `BookDetailsTabView` takes its `Book` from
**`ModalRoute.settings.arguments`** — an object frozen when the route was pushed, which
nothing invalidates because nothing watches it. So the sheet went on naming the previous
shop until the page was popped and pushed again, which reads exactly like a failed write.

**It was also a correctness bug, not only a stale-paint one.** `setReaderApp`
short-circuits when `book.readerApp == storeKey`, and it compares against whichever `Book`
it is handed:

1. Stored shop is Kindle. Reader taps Play → `'kindle' != 'play'` → writes. Row is Play.
2. Same page session, reader taps Kindle again → compared against the **snapshot's**
   `'kindle'` → match → returns early. **No write. The row stays on Play.**

So a reader could change their shop once and then silently not at all. Both halves are one
fix: resolve the live row out of the library the page already watches.

```dart
final book = _liveBook(shelves, routeBook.id) ?? routeBook;
```

Four details worth keeping:

- **The library watch moved above every read of the book**, since it is now the source of
  the book rather than only of shelf names.
- **Searched by id across every shelf**, not inside the shelf the snapshot names —
  `shelfId` is itself a thing a write changes, so looking in the old shelf would find
  nothing and fall silently back to the stale copy. Id is the only field that never moves.
- **The library is unfiltered.** `withoutFinishedBooks` / `withoutReadingBooks` are applied
  by `library_view`, not by the provider, so a finished book is found here — which is the
  majority of this page's traffic and would otherwise have been the one case still broken.
- **Falls back to the snapshot**, covering the two honest gaps: the first frame before the
  library resolves, and a book genuinely no longer in it.

#### It repairs more than the reader app

Every other field the page reads was equally frozen. The clearest case is the status sheet,
which is pre-filled from `book.status`, `book.startDate`, `book.progress`, `book.pageCount`:
editing status and reopening the sheet in the same session showed the **pre-edit** values.
That is fixed by the same line, though it is not what the change was made for and has no
test of its own yet.

#### Tested by mutation

Replacing the resolution with `final book = routeBook;` fails exactly three cases — the
stored shop being shown, forgetting being reflected, and the switch-back comparison.

The third of those needed the test fake to record **which value the write came from**, not
just the value written: `RecordingLibraryActions` now captures `(bookId, from, to)`, because
`from` is the field the short-circuit reads and therefore the only place the bug was
visible. The harness gained a `libraryBooks` parameter so a test can make the route
argument and the library **disagree** on purpose, which is the whole shape of the bug.

### A print row was considered and rejected

Raised because Libby's ebook records are labelled **`FORMAT: Book`** in its own UI, which
reads as paper and prompted the question directly. It does not mean paper — `FORMAT: Book`
is how Libby words "the non-audio one", and its own share page for the same record says
_Library Ebook_.

OverDrive has no physical concept anywhere: `type.id` takes only `ebook`, `audiobook` and
`magazine`, and across 100 results for one author at one library the split was
`{ebook: 62, audiobook: 38}`. A library's print catalogue lives in a different system
entirely — SFPL's is BiblioCommons — which Libby neither sees nor links to.

So a print row could not be served by Libby at all; it would mean a separate destination
(`worldcat.org/isbn/<isbn>`, 교보 / 알라딘 for `ko`) making a separate promise. Out of scope:
library **digital** lending is a first-class destination on its own terms and does not need
a print row to justify it.

## Open questions

1. **A tap is not a purchase.** Tapping Kindle to check a price and not buying leaves the
   book wrongly marked. `Forget where I read this` mitigates it; asking outright, or only
   remembering on a second visit, has not been ruled out. **Sharpened by the status-inferred
   open list**, which both widened the recording gate to open taps and put open rows in
   front of every Reading/Finished book — so there are now more writing taps, on books a
   reader may be browsing. See _A book you already have is not one to go buy_.
2. **Should the glyph change when a store is known?** The chosen design's structural cost is
   that the icon is identical either way, so opening your own copy is always two taps and is
   never advertised. Copy cannot substitute — `Where to read` is equally true in both
   states. A dot on the glyph is drawn as `icon-marked`. Cheap now, expensive after release.
3. **The `ko` store set.** ~~Korean readers now get **two** shops, not three: Apple Books
   joined Libby in being withdrawn.~~ **Half closed.** Apple Books is **back** for `ko`,
   because the app now reads the reader's real App Store storefront instead of guessing it
   from their language — see _The storefront is a fact, not a guess from the language_. So
   `ko` is `[play, apple, kindle]`, and Korea-ness is enforced by the storefront plus
   Apple's own `notSold` answer rather than by the phone's language. **Libby stays
   withdrawn**: it maps to US/UK library systems and no storefront-shaped signal exists for
   "which country's libraries".

   Still open, and unchanged by any of this: whether to add 리디북스 / 밀리의서재 / 예스24 /
   교보. The case is weaker than it was a round ago — `ko` is back to three shops rather
   than two — but Kakao is still the primary catalogue and none of the three shops is where
   a Korean reader actually buys. Not blocking the `ko` build any more. See Localization.
   The related question of a **print** row is closed — see _A print row was considered and
   rejected_.

4. **Kindle and Libby have no logo.** ~~Settled for now as marks where sourceable,
   letters where not.~~ **Closed** — all four shops draw a real mark. Simple Icons
   still carries `amazon` (the CDN 404 was misleading) and Arcticons carries Libby.
   See _The leading mark_.
5. **App Store guideline 3.1.1.** Libstack sells nothing and unlocks nothing, which puts it
   with Goodreads and StoryGraph rather than with reader apps, so this is low-to-moderate
   risk rather than a blocker. The copy avoids _buy_ throughout, and Libby carries no
   exposure at all. Worth a considered decision before submission, not after.
6. ~~**The reader's library key — `libby-library`.**~~ **Closed: built.** It was the
   only route to an exact in-app Libby link, and the API that had blocked it
   (`locate.libbyapp.com/autocomplete`) does exist. See _The reader's library, asked
   once_. Note it stores a **library**, not a card; the card stays Libby's business.

## Verification still needed on a device

**Both Libby URLs are now settled by testing, in opposite directions.**

`libbyapp.com/library/<key>/title/<id>` — **verified, works.** Lands on the title with
its Borrow / Place Hold / Open action, which is what entitles the row to
`StoreReach.book`. Derived from the routing rule its predecessor's failure exposed
(`title-redirect-controller` matches `title/<id>` and prepends
`"library/" + this.ancestor.args.key`), so the ancestor it needs is in the path.

~~`libbyapp.com/title/<id>`~~ — **resolved, negatively.** Libby shows _"View not found."_
and lands on the Shelf. Kept as the record of why the key is not optional.

**Three Libby URLs were wrong before one was right**, and the tally is the argument for
treating this list as a release blocker rather than a nicety: `libby://` (a guessed
scheme), `libbyapp.com/search/all/…` (`all` where a library key belongs),
`share.libbyapp.com/title/<id>` (an install ad with no Borrow button) and
`libbyapp.com/title/<id>` (no library ancestor). Two of those were _reasoned from real
evidence_ and still wrong. **No test can catch this class of bug** — a test asserts the
URL you chose to build, never that it arrives anywhere.

~~`kindle://`, `ibooks://` and `com.google.playbooks://` remain **guessed schemes**~~ —
**closed.** `com.google.playbooks://` and `kindle://` were replaced by https paths their
app claims in its own app-site-association, which cannot fail hard; see _Custom schemes are
a last resort_. `com.google.playbooks://` was wrong besides — it matched no convention
Google uses on iOS. **`read.amazon.com/application` is device-verified: it opens Kindle at
the library page.**

`ibooks://` **stays and is no longer counted as guessed**: it is documented in the AppURLs
reference, and there is no Apple Books web reader, so no universal link could reach a
reader's own library. Books is preinstalled, so a hard failure barely arises. Still worth a
tap on a device, but it is the mildest item here — a wrong answer costs one dead row on a
shop whose app is present on every iPhone.

**What is left on this list is Play Books' two `/books/reader` forms.** Both are claimed in
Google's AASA, so the hand-off should happen; neither has been tapped. The id-bearing one
(`?id=<volumeId>`) is the more interesting, since it is the only row in the app claiming to
reach a book _inside a shop's own reader_ — and a reader URL for a book the person does not
own may well bounce, in which case "Opens at this book" is too strong and the row wants
`storePage` wording.

Resolved by testing, and no longer on this list: `books.apple.com` **does** hand off to
the Books app (which is how the empty-search-tab defect was found), `play.google.com/store/...`
**does not** open Play Books, and `libbyapp.com` **does** open Libby — which is precisely
why its malformed library key produced a visible error rather than a silent miss. See
_Verified on device_.

`play.google.com/books/reader` is claimed in Apple's app-site-association, so it should
open the app; worth confirming, since it is now the only row that claims to reach a book
inside a shop's own reader.

**The storefront channel has been compile-verified and nothing more.** `AppDelegate.swift`
builds (`./build.sh ios --debug --no-codesign`), but no run has yet shown
`bookworm/app_store` returning an actual country. It needs a **real device with an Apple ID
signed in**: a simulator without an account returns `nil`, which exercises the locale
fallback and therefore proves nothing about the channel. The useful check is a device whose
Apple ID country differs from its language, since that is the entire point.

## Not in scope

Price display (adds 3.1.1 exposure for no user gain), affiliate tags, and any attempt to
read the reader's actual library from Amazon, Apple or Google — none of which expose one.
