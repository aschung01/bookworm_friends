// The "where to read this" entry point and sheet, on the details page.
//
// Three claims are worth pinning here, because each is a decision that a later
// refactor could quietly undo:
//
//   1. The icon is NOT gated on `isSelf`. Every other action in this bar is, and a
//      friend's finished book is the whole point of the feature.
//   2. Kindle's row admits it opens a search. The row is the only place that fact
//      can be told, so it is asserted in the app and not left to a copy review.
//   3. `reader_app` is the owner's fact. A friend's book shows the acquire list
//      however their row is set.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/services/apple_books_lookup.dart';
import 'package:bookworm_friends/services/book_search_service.dart';

import 'support/book_details_harness.dart';
import 'support/fake_url_launcher.dart';

/// A book on the reader's own shelf that they do **not** have yet.
///
/// **`status` defaults to 0 ("interested") and that default is load-bearing.** For
/// your own book the sheet picks its intent from status: reading or finished means
/// "you have this somewhere", so every row becomes `Open X`. Only status 0 puts the
/// *acquire* list on screen, and most of this file is about the acquire list — so a
/// default of 2 would have quietly moved almost every case in it to the other list.
/// Pass `status: 2` for the inferred-open group; the friend groups are unaffected,
/// since inference is gated on ownership.
Book book({required String ownerId, String? readerApp, int status = 0}) => Book(
  id: 'b1',
  userId: ownerId,
  shelfId: shelfId,
  isbn: '9791161571188',
  title: 'Live Commerce',
  thumbnail: '',
  status: status,
  position: 0,
  startDate: DateTime(2023, 12, 9),
  finishDate: status == 2 ? DateTime(2023, 12, 23) : null,
  createdAt: DateTime(2023, 12, 9),
  authors: const ['Lee Hyunsook'],
  readerApp: readerApp,
);

Finder get whereToRead => find.byTooltip('Where to read');

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(whereToRead);
  await tester.pumpAndSettle();
}

void main() {
  group('the entry point', () {
    testWidgets('is in the bar on your own book', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      expect(whereToRead, findsOneWidget);
    });

    // The decision this test exists for. `isSelf` gates delete, edit and the FAB,
    // so before this the bar was empty on a friend's book — and a friend's
    // finished book is exactly where "where can I get this" is most useful.
    testWidgets('is also in the bar on a friend\'s book', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: friendId),
        signedInAs: meId,
      );
      expect(whereToRead, findsOneWidget);
    });

    // The icon carries a novel action with no visible label, so the tooltip is
    // also its VoiceOver label. An untooltipped icon here would be unreadable to
    // a screen reader, which the neighbouring icon was until this landed.
    testWidgets('carries a tooltip, and so does its neighbour', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      expect(whereToRead, findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);
      // **There is no Edit here any more, and its absence is the assertion.**
      // `edit_outlined` opened the change-status sheet, which the reading period
      // card in the band now opens — and that card *displays* the status and dates
      // the sheet edits, so the pencil was a second way in to the same place from
      // the one corner a thumb cannot reach. Restoring it would make the card stop
      // reading as the way in. See `book_details_tab_view.dart`'s app bar.
      expect(find.byTooltip('Edit'), findsNothing);
    });
  });

  group('the acquire list', () {
    testWidgets('offers all four shops, titled Where to read', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Where to read'), findsOneWidget);
      expect(find.text('Play Books'), findsOneWidget);
      expect(find.text('Apple Books'), findsOneWidget);
      expect(find.text('Kindle'), findsOneWidget);
      expect(find.text('Libby'), findsOneWidget);
    });

    // The load-bearing assertion of the whole feature. Amazon publishes no
    // per-book deep link, so if this row ever stops saying so the app has started
    // promising something it cannot deliver.
    //
    // Phrased without an article deliberately — an earlier draft read "Opens a
    // {store} search", which renders "Opens a Amazon search". The two shops most
    // often reached this way are Amazon and Apple Books, so the article was wrong
    // in the common case rather than the rare one.
    testWidgets('says it searches Amazon rather than opening the book', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Searches Amazon'), findsOneWidget);
      // And never claims otherwise anywhere in the list.
      expect(find.text('Opens at this book'), findsNothing);
    });

    // No supporting line may begin with an article that has to agree with an
    // interpolated brand name. This is the general form of the bug above, so it is
    // pinned rather than left to whoever writes the next shop's copy.
    testWidgets('no row starts with a mis-agreeing article', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(
        find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'\ba [AEIOU]').hasMatch(w.data ?? ''),
        ),
        findsNothing,
      );
    });

    testWidgets('offers Libby as a free borrow rather than a purchase', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Borrow free from your library'), findsOneWidget);
    });

    // Nothing is being sold by this app, and the copy never suggests otherwise —
    // which is also the cheap half of the guideline 3.1.1 mitigation.
    testWidgets('never uses the word buy', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').toLowerCase().contains('buy'),
        ),
        findsNothing,
      );
    });

    testWidgets('has nothing to forget yet', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Forget where I read this'), findsNothing);
    });
  });

  group('once a shop is remembered', () {
    testWidgets('the sheet retitles itself, because the icon cannot', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, readerApp: 'kindle'),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Your copy'), findsOneWidget);
      expect(find.text('Where to read'), findsNothing);
    });

    // The verb drops to Open because that is all Kindle can do, and the supporting
    // line names the library rather than the book.
    testWidgets('Kindle offers Open, and says it opens the library', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, readerApp: 'kindle'),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Open Kindle'), findsOneWidget);
      expect(find.text('Opens your Kindle library'), findsOneWidget);
    });

    // A tap is not a purchase, so a wrong guess must never be a trap.
    testWidgets('it can be forgotten', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, readerApp: 'kindle'),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Forget where I read this'), findsOneWidget);
    });

    testWidgets('the other shops stay available, since it is only a hint', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, readerApp: 'kindle'),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Apple Books'), findsOneWidget);
      expect(find.text('Play Books'), findsOneWidget);
    });

    // An unrecognised key reads as absent rather than as a shop, which is why the
    // column carries no CHECK constraint. A build that met a newer key must fall
    // back to the state the book was in before anyone tapped anything.
    testWidgets('an unknown key falls back to the acquire list', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, readerApp: 'ridibooks'),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Where to read'), findsOneWidget);
      expect(find.text('Forget where I read this'), findsNothing);
    });
  });

  // `reader_app` belongs to the book's owner. Showing "Open Kindle" here because
  // your friend uses Kindle would be wrong even if the row were readable, and the
  // books policies would refuse the write anyway — so a friend's book needs no
  // write path at all.
  group('a friend\'s book', () {
    testWidgets('shows the acquire list however their row is set', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: friendId, readerApp: 'kindle'),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Where to read'), findsOneWidget);
      expect(find.text('Your copy'), findsNothing);
      expect(find.text('Open Kindle'), findsNothing);
      expect(find.text('Forget where I read this'), findsNothing);
    });
  });

  // The reported bug's real cause, covered end to end. On the Kakao path the
  // catalogue supplies no volume id at all, so before the on-demand lookup every
  // shop degraded to a plain search — "Play Books is the exact one" was true of
  // the English build and false of the Korean one, which is this app's primary
  // market.
  group('a Kakao-sourced book', () {
    testWidgets('degrades to searches when no id can be found', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
        source: BookSearchSource.kakao,
      );
      await openSheet(tester);

      expect(find.text('Searches Play Books'), findsOneWidget);
      expect(find.text('Opens this book'), findsNothing);
    });

    testWidgets('is upgraded to an exact link once the lookup answers', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
        source: BookSearchSource.kakao,
        resolvedVolumeId: 'zyTCAlFPjgYC',
      );
      await openSheet(tester);

      // Play Books' acquire row reaches the exact book but as a **web store
      // page**, because `/store/books/details` is claimed by no Google app. The
      // copy has to say so; "Opens this book" was read as a promise about the app
      // and was reported as a bug on exactly those grounds.
      expect(
        find.text("Opens this book's store page in your browser"),
        findsOneWidget,
      );
      expect(find.text('Searches Play Books'), findsNothing);
    });

    // Kindle cannot be upgraded by anything, and must not appear to be.
    testWidgets('does not upgrade Kindle, which has no per-book link', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
        source: BookSearchSource.kakao,
        resolvedVolumeId: 'zyTCAlFPjgYC',
      );
      await openSheet(tester);

      expect(find.text('Searches Amazon'), findsOneWidget);
    });
  });

  // Apple was the last shop that could never be exact, and not for want of a URL
  // format: `books.apple.com/../id731076045` carries **Apple's own id**, which
  // appears in no catalogue this app reads. So a volume id could not upgrade it and
  // nothing else was ever going to — the gap was that nobody had asked Apple.
  //
  // `appleBookUrlProvider` asks. These cover both answers, because a lookup that
  // silently always missed would look identical to no lookup at all.
  group('Apple Books and its ISBN lookup', () {
    testWidgets('says it searches while nothing has been resolved', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Searches Apple Books'), findsOneWidget);
    });

    testWidgets('becomes an exact row once a URL comes back', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
        apple: AppleBooksResult(
          AppleBooksAvailability.found,
          Uri.parse('https://books.apple.com/us/book/x/id731076045'),
        ),
      );
      await openSheet(tester);

      expect(find.text('Opens this book'), findsOneWidget);
      expect(find.text('Searches Apple Books'), findsNothing);
    });

    // **The assertion that had to be revisited, kept rather than deleted.** It
    // used to pin the exact-row count at one, on the reasoning that Play Books was
    // the only shop that could be exact. Play Books is now `storePage` and Apple is
    // the only row that reaches a book *in an app*, so the number moved twice --
    // but the check is still the one worth having, because two shops resolving
    // independently is the configuration in which a row can pick up the wrong
    // neighbour's reach.
    testWidgets('each resolved shop describes its own destination', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
        source: BookSearchSource.kakao,
        resolvedVolumeId: 'zyTCAlFPjgYC',
        apple: AppleBooksResult(
          AppleBooksAvailability.found,
          Uri.parse('https://books.apple.com/us/book/x/id731076045'),
        ),
      );
      await openSheet(tester);

      // One "Opens this book" (Apple, which reaches the app) and one store-page
      // line (Play, which reaches a browser). The two are deliberately different
      // strings: they reach the same book by different means, and the reader who
      // learns that distinction once can trust every row.
      expect(find.text('Opens this book'), findsOneWidget);
      expect(
        find.text("Opens this book's store page in your browser"),
        findsOneWidget,
      );
      // And the two shops that cannot be exact are unaffected by either lookup.
      expect(find.text('Searches Amazon'), findsOneWidget);
      expect(find.text('Borrow free from your library'), findsOneWidget);
    });

    // The other half of the three-way answer. Apple answering "no edition" is a
    // positive fact, and the only honest use of it is to stop offering the shop:
    // its fallback opens Books on an empty search tab, which cannot be described
    // truthfully in any wording.
    testWidgets('the row is dropped when Apple says it has no edition', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
        apple: const AppleBooksResult.notSold(),
      );
      await openSheet(tester);

      expect(find.text('Apple Books'), findsNothing);
      // The other three stay, and the sheet is still a sheet.
      expect(find.text('Play Books'), findsOneWidget);
      expect(find.text('Kindle'), findsOneWidget);
      expect(find.text('Libby'), findsOneWidget);
      expect(find.text('Where to read'), findsOneWidget);
    });
  });

  // **The reader's storefront, which is not their language.** Which Apple Books
  // catalogue a person can buy from follows their Apple ID's country; the device
  // language was a guess at it, and wrong in both directions. Both failures are
  // pinned here because each looked like correct behaviour from the inside:
  //
  //   * A Korean phone on a US account had Apple Books hidden, so the row that
  //     would have worked was the one row missing.
  //   * An English phone on a Korean account got `/us/` links its store answers
  //     with a 404 -- a dead row, which is the worse half.
  //
  // Every case here sets `locale` and `storefront` to *different* countries on
  // purpose. Agreement is the case the old code already got right.
  group('the reader\'s App Store storefront', () {
    // A friend's book throughout, so a tap launches and stops. On your own book the
    // acquire tap also writes `reader_app`, which would reach Supabase from a widget
    // test; the acquire list itself is identical either way -- `reader_app` is the
    // owner's fact, which the group above pins.
    Book theirBook() => book(ownerId: friendId);

    // Korea is genuinely public-domain-only on Apple Books (Apple's own sell-in
    // list, support.apple.com/en-us/118205), so `notSold` in `kr` beside `found` in
    // `us` is not a contrived pair -- it is what this book really looks like.
    final inUs = AppleBooksResult(
      AppleBooksAvailability.found,
      Uri.parse('https://books.apple.com/us/book/x/id731076045'),
    );
    const notInKr = AppleBooksResult.notSold();

    testWidgets('a Korean phone on a US account is offered the US edition', (
      tester,
    ) async {
      final launcher = recordUrlLaunches();
      await pumpBookDetails(
        tester,
        book: theirBook(),
        signedInAs: meId,
        locale: 'ko',
        storefront: 'us',
        applePerCountry: {'us': inUs, 'kr': notInKr},
      );
      await tester.tap(find.byIcon(Icons.north_east));
      await tester.pumpAndSettle();

      // Present at all, which the locale guess denied this reader outright. Asserted
      // on the brand rather than on copy because the sheet is in Korean here --
      // brand names are Dart literals and never translated.
      expect(find.text('Apple Books'), findsOneWidget);

      await tester.tap(find.text('Apple Books'));
      await tester.pumpAndSettle();
      expect(launcher.only, 'https://books.apple.com/us/book/x/id731076045');
    });

    // The converse, and the reason the storefront has to reach the *lookup* and not
    // only the URL builder: had `us` been asked, this row would be sitting there
    // looking perfectly ordinary and pointing at a 404.
    testWidgets('an English phone on a Korean account is not handed a US link', (
      tester,
    ) async {
      final launcher = recordUrlLaunches();
      await pumpBookDetails(
        tester,
        book: theirBook(),
        signedInAs: meId,
        locale: 'en',
        storefront: 'kr',
        applePerCountry: {'us': inUs, 'kr': notInKr},
      );
      await tester.tap(find.byTooltip('Where to read'));
      await tester.pumpAndSettle();

      expect(find.text('Apple Books'), findsNothing);
      // The rest of the sheet is untouched -- a wrong storefront must not take the
      // other shops down with it.
      expect(find.text('Play Books'), findsOneWidget);
      expect(find.text('Kindle'), findsOneWidget);
      expect(launcher.launched, isEmpty);
    });

    // The search fallback is the other thing the storefront decides, and the only
    // place it still shows when Apple could not be reached at all. `unknown` keeps
    // the row -- a timeout is not evidence of absence -- so the question is only
    // which store the search opens in.
    testWidgets('the search fallback opens in the storefront, not the locale', (
      tester,
    ) async {
      final launcher = recordUrlLaunches();
      await pumpBookDetails(
        tester,
        book: theirBook(),
        signedInAs: meId,
        locale: 'en',
        storefront: 'kr',
        // The offline answer, for both countries: nothing was resolved either way.
      );
      await tester.tap(find.byTooltip('Where to read'));
      await tester.pumpAndSettle();

      expect(find.text('Searches Apple Books'), findsOneWidget);
      await tester.tap(find.text('Apple Books'));
      await tester.pumpAndSettle();
      expect(launcher.only, startsWith('https://books.apple.com/kr/search'));
    });

    // And with no storefront to be had -- Android, the simulator with nobody signed
    // in, the first moments of launch -- the locale is still the answer. This is the
    // path every other test in this file runs on, so it is pinned once here rather
    // than assumed.
    testWidgets('falls back to the locale when there is no storefront', (
      tester,
    ) async {
      final launcher = recordUrlLaunches();
      await pumpBookDetails(
        tester,
        book: theirBook(),
        signedInAs: meId,
        locale: 'ko',
        // storefront deliberately omitted: null is what the platform channel gives
        // back under `flutter test`, and on Android always.
      );
      await tester.tap(find.byIcon(Icons.north_east));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apple Books'));
      await tester.pumpAndSettle();

      expect(launcher.only, startsWith('https://books.apple.com/kr/search'));
    });
  });

  // The row that started this: it promised "Open Play Books" and performed a Play
  // Store search, because Play Books was the only shop with no app fallback.
  group('opening a remembered Play Books copy', () {
    testWidgets('launches the app when there is no id to aim at', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, readerApp: 'play'),
        signedInAs: meId,
        source: BookSearchSource.kakao,
      );
      await openSheet(tester);

      expect(find.text('Open Play Books'), findsOneWidget);
      expect(find.text('Opens your Play Books library'), findsOneWidget);
      // The lie: never both.
      expect(find.text('Searches Play Books'), findsNothing);
    });

    testWidgets('reads the book itself when an id is available', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, readerApp: 'play'),
        signedInAs: meId,
        source: BookSearchSource.kakao,
        resolvedVolumeId: 'zyTCAlFPjgYC',
      );
      await openSheet(tester);

      expect(find.text('Read in Play Books'), findsOneWidget);
      expect(find.text('Opens at this book'), findsOneWidget);
    });
  });

  // **A book you are reading or have finished is one you already have**, so the sheet
  // stops offering to sell it to you and offers to open it instead. No stored shop is
  // needed and nothing is asked: status is the signal.
  //
  // The numbers are why this exists rather than being a nicety. Of 473 books in
  // production, 342 are reading or finished and **3** carry a `reader_app` -- so the
  // old rule sent the large majority of the library to a shop to buy a book it knew
  // they had already read.
  group('a book the reader already has', () {
    testWidgets('a finished book offers to open, not to buy', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, status: 2),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Open Play Books'), findsOneWidget);
      expect(find.text('Open Kindle'), findsOneWidget);
      // And none of the acquire copy survives -- the two lists are never mixed.
      expect(find.text('Searches Amazon'), findsNothing);
      expect(find.text('Borrow free from your library'), findsNothing);
    });

    testWidgets('so does a book still being read', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, status: 1),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Open Kindle'), findsOneWidget);
      expect(find.text('Searches Amazon'), findsNothing);
    });

    // The other half of the rule, and the reason the acquire tests above still have
    // something to assert: wanting a book is not having it.
    testWidgets('an interested book still offers the shops', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, status: 0),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Searches Amazon'), findsOneWidget);
      expect(find.text('Open Kindle'), findsNothing);
    });

    // **The case that caught a real bug in this feature.** Inference was written
    // without an ownership gate, so a friend's finished book offered to open *your*
    // library for *their* book -- and a friend's finished book is the case the whole
    // sheet was built for. `reader_app` was already the owner's fact; status is too.
    testWidgets('a friend\'s finished book still offers the shops', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: friendId, status: 2),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('Searches Amazon'), findsOneWidget);
      expect(find.text('Open Kindle'), findsNothing);
    });

    // **Each row still reaches as far as it can, and Play Books is the interesting
    // one.** An earlier draft withheld the per-book ids here, reasoning that "Read in
    // Play Books / Opens at this book" asserts ownership *in Play* where status only
    // says "somewhere". Checking the humbler alternative is what killed it:
    // `play.google.com/books/reader` with no id **is the Play Books storefront** — so
    // that row promised "Opens your Play Books library" and landed on a shop, a worse
    // lie than the one being avoided. It is also the promise the stored-shop row has
    // always made without verifying entitlement.
    testWidgets('reaches the book itself where a shop can', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, status: 2),
        signedInAs: meId,
        source: BookSearchSource.kakao,
        resolvedVolumeId: 'zyTCAlFPjgYC',
      );
      await openSheet(tester);

      expect(find.text('Read in Play Books'), findsOneWidget);
      expect(find.text('Opens at this book'), findsOneWidget);
      // Kindle cannot, and says so rather than borrowing Play's promise.
      expect(find.text('Open Kindle'), findsOneWidget);
      expect(find.text('Opens your Kindle library'), findsOneWidget);
      // And nothing anywhere is trying to sell a book the reader has finished.
      expect(find.text('Searches Amazon'), findsNothing);
      expect(
        find.text("Opens this book's store page in your browser"),
        findsNothing,
      );
    });

    // **The URL on this path, not just its label.** The labels above are asserted
    // elsewhere; this pins where the tap actually goes, because the failure mode being
    // guarded is subtle: `storeLinksFor` has a `(play, acquire) when volumeId != null`
    // case pointing at `/store/books/details` — the Play *Store* — and an intent or
    // volume-id slip would silently select it. A row reading "Open Play Books" that
    // opened a shop to buy the book again is precisely the class of bug `StoreReach`
    // exists to prevent.
    testWidgets('opens Play Books itself, never the Play Store', (
      tester,
    ) async {
      final launcher = recordUrlLaunches();
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, status: 1),
        signedInAs: meId,
        source: BookSearchSource.kakao,
        resolvedVolumeId: 'zyTCAlFPjgYC',
      );
      await openSheet(tester);
      await tester.tap(find.text('Read in Play Books'));
      await tester.pumpAndSettle();

      expect(
        launcher.only,
        'https://play.google.com/books/reader?id=zyTCAlFPjgYC',
      );
      // Stated negatively too, because that is the row this could regress into: the
      // Play *Store* product page, which is what `(play, acquire)` builds from the same
      // volume id.
      expect(launcher.only, isNot(contains('/store/')));
    });

    // The whole thing is self-correcting rather than a guess that sticks, and this is
    // the mechanism: the tap that opens a shop is also the tap that records it. It
    // used to be gated to acquire taps only, which meant the 339 books with no shop
    // had no route to ever getting one.
    testWidgets('opening a shop records it, so the next visit is exact', (
      tester,
    ) async {
      final launcher = recordUrlLaunches();
      final actions = RecordingLibraryActions();
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, status: 2),
        signedInAs: meId,
        libraryActions: actions,
      );
      await openSheet(tester);
      await tester.tap(find.text('Open Kindle'));
      await tester.pumpAndSettle();

      // Launched by the claimed path rather than a scheme...
      expect(launcher.only, 'https://read.amazon.com/application');
      // ...and recorded, which is the half that used to be skipped.
      expect(actions.readerAppWrites, [('b1', null, 'kindle')]);
    });

    // A friend's book must never write to the owner's row, whatever the reader taps.
    // The `isSelf` gate on recording predates this change; it is pinned here because
    // widening the gate from `acquire`-only came close to it.
    testWidgets('opening from a friend\'s book records nothing', (
      tester,
    ) async {
      recordUrlLaunches();
      final actions = RecordingLibraryActions();
      await pumpBookDetails(
        tester,
        book: book(ownerId: friendId, status: 2),
        signedInAs: meId,
        libraryActions: actions,
      );
      await openSheet(tester);
      await tester.tap(find.text('Kindle'));
      await tester.pumpAndSettle();

      expect(actions.readerAppWrites, isEmpty);
    });
  });

  // **The page reads the live row, not the one it was pushed with.** The `Book` on
  // `ModalRoute.settings.arguments` is frozen at navigation time, so before this the
  // sheet went on naming whichever shop was stored when the reader opened the page --
  // a stored shop looked like it had failed to change, and changing it twice really
  // did fail (see the comment on `_liveBook`).
  group('the sheet follows the library, not the route argument', () {
    testWidgets('a shop stored after arrival is the one shown', (tester) async {
      // The route argument still says Kindle; the library has moved on to Play. This
      // is exactly the state a write leaves behind.
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, status: 2, readerApp: 'kindle'),
        signedInAs: meId,
        libraryBooks: [book(ownerId: meId, status: 2, readerApp: 'play')],
      );
      await openSheet(tester);

      expect(find.text('Your copy'), findsOneWidget);
      // Play leads with the check. Kindle is still *present* -- a finished book offers
      // every shop as an open row -- so what distinguishes the two is which one the
      // sheet singles out, asserted here by Play's row being the one that is not a
      // plain `Open X`.
      expect(find.text('Open Play Books'), findsOneWidget);
      expect(find.text('Open Kindle'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    // Clearing it is the same mechanism, and worth its own case because "Forget where I
    // read this" is the one path that used to *appear* to work -- it popped the sheet,
    // so the reader never saw the stale row it left behind.
    testWidgets('forgetting the shop is reflected too', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId, status: 2, readerApp: 'kindle'),
        signedInAs: meId,
        libraryBooks: [book(ownerId: meId, status: 2)],
      );
      await openSheet(tester);

      // No stored shop, and the book is finished -- so the inferred-open list, with no
      // one shop singled out and nothing to forget.
      expect(find.text('Where to read'), findsOneWidget);
      expect(find.text('Open Kindle'), findsOneWidget);
      expect(find.text('Forget where I read this'), findsNothing);
    });

    // The fallback, which has to keep working: there is a real frame on a real device
    // before the library resolves, and a book can legitimately be absent from it.
    testWidgets(
      'falls back to the route argument when the library has no row',
      (tester) async {
        await pumpBookDetails(
          tester,
          book: book(ownerId: meId, status: 2, readerApp: 'kindle'),
          signedInAs: meId,
          // libraryBooks left empty.
        );
        await openSheet(tester);

        expect(find.text('Open Kindle'), findsOneWidget);
      },
    );

    // A friend's book resolves against *their* library, so the same mechanism has to
    // reach through `userLibraryProvider` rather than `libraryProvider`.
    testWidgets('a friend\'s book follows their library', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: friendId, status: 0),
        signedInAs: meId,
        // The live row is finished. On a friend's book that must *not* flip the sheet
        // to the open list -- inference is the owner's -- so the acquire list stands
        // either way. What this pins is that the live row is what got read at all.
        libraryBooks: [book(ownerId: friendId, status: 2)],
      );
      await openSheet(tester);

      expect(find.text('Searches Amazon'), findsOneWidget);
      expect(find.text('Open Kindle'), findsNothing);
    });

    // **The half of the staleness bug that was not merely cosmetic.** The real
    // `setReaderApp` does nothing when `book.readerApp` already equals the new key, and
    // it compares against whichever `Book` it is handed. Reading that book from the
    // frozen route argument meant: switch Kindle -> Play (writes), then switch back to
    // Kindle and the comparison is 'kindle' vs the *snapshot's* 'kindle' -- match, no
    // write, row stays on Play. A reader could change their shop once and then never
    // again. Pinned by asserting the value the write *came from*.
    testWidgets(
      'a switch back is compared against the live shop, not the stale one',
      (tester) async {
        final actions = RecordingLibraryActions();
        recordUrlLaunches();
        await pumpBookDetails(
          tester,
          book: book(ownerId: meId, status: 2, readerApp: 'kindle'),
          signedInAs: meId,
          // The reader already switched to Play since this page was pushed.
          libraryBooks: [book(ownerId: meId, status: 2, readerApp: 'play')],
          libraryActions: actions,
        );
        await openSheet(tester);
        // Switching back to Kindle. Against the route argument this is a no-op; against
        // the library it is a real change. The row reads `Open Kindle` rather than
        // `Kindle`, because a finished book offers every shop as an open row.
        await tester.tap(find.text('Open Kindle'));
        await tester.pumpAndSettle();

        expect(actions.readerAppWrites, [('b1', 'play', 'kindle')]);
      },
    );
  });

  // The leading chip. Two shops have a real mark and two do not, and that split
  // is a sourcing fact rather than an unfinished job: Simple Icons carries no
  // `amazon*` icon at all and no Libby/OverDrive icon, so Kindle and Libby keep
  // the letter.
  //
  // Worth pinning because both halves are quietly losable. Someone "finishing
  // the set" by drawing the missing two would invent a trademark, and someone
  // mistaking the letter for dead code would delete the fallback that four
  // stores still depend on.
  group('the leading mark', () {
    Finder svgIn(String label) => find.descendant(
      of: find.widgetWithText(ListTile, label),
      matching: find.byType(SvgPicture),
    );

    testWidgets('is a real logo for every shop', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(svgIn('Play Books'), findsOneWidget);
      expect(svgIn('Apple Books'), findsOneWidget);
      expect(svgIn('Kindle'), findsOneWidget);
      expect(svgIn('Libby'), findsOneWidget);
    });

    // **The regression this replaces.** Kindle and Libby shipped as letter chips
    // on the conclusion that no licence-clean mark existed for either. That was
    // wrong twice over -- Simple Icons still carries `amazon` and Arcticons
    // carries Libby -- so the letters are asserted *gone*, to stop the same
    // wrong conclusion putting them back.
    testWidgets('never falls back to a bare initial', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      expect(find.text('K'), findsNothing);
      expect(find.text('L'), findsNothing);
    });

    // Each shop's mark must be its own. A map that returned one asset for
    // everything would satisfy the test above and still be wrong.
    testWidgets('gives each shop a distinct asset', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      final assets = tester
          .widgetList<SvgPicture>(find.byType(SvgPicture))
          .map((svg) => (svg.bytesLoader as SvgAssetLoader).assetName)
          .toSet();

      expect(assets, hasLength(4));
      expect(
        assets,
        containsAll([
          'assets/icons/storePlayIcon.svg',
          'assets/icons/storeAppleIcon.svg',
          'assets/icons/storeKindleIcon.svg',
          'assets/icons/storeLibbyIcon.svg',
        ]),
      );
    });

    // Libby's mark is a stroke where the other three are solid fills, so at one
    // size it reads as the lightest row in the sheet. The larger draw size is an
    // optical correction and is pinned here, because "tidying" the sizes to a
    // single constant would silently reintroduce the imbalance.
    // `store_marks_probe_test.dart` renders both for comparison.
    testWidgets('draws the stroked mark larger to match the solid ones', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      final libby = tester.widget<SvgPicture>(svgIn('Libby'));
      final play = tester.widget<SvgPicture>(svgIn('Play Books'));
      expect(libby.width, greaterThan(play.width!));
    });

    // The chip is tinted from the theme rather than painted in the brand's own
    // colour, so the sheet stays as typographic as the rest of the app and the
    // marks follow dark mode. A bundled full-colour badge would do neither.
    testWidgets('tints the logo rather than using brand colour', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(ownerId: meId),
        signedInAs: meId,
      );
      await openSheet(tester);

      final svg = tester.widget<SvgPicture>(svgIn('Play Books'));
      expect(svg.colorFilter, isNotNull);
    });
  });
}
