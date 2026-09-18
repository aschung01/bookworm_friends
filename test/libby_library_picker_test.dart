// Asking the reader which library they belong to, once.
//
// **Why the app asks at all is a routing fact, and it is worth restating here
// because it is the only justification for adding a question to a flow.** Libby
// resolves `title/<id>` only beneath `library/<key>` — its own controller builds
// `"library/" + this.ancestor.args.key` — so without a key the Libby row cannot
// reach a book inside the app. A device confirmed it: `libbyapp.com/title/<id>`
// shows "View not found." and lands on the Shelf.
//
// Four claims are pinned:
//
//   1. The ask is **just-in-time**: it appears on a Libby tap, not on opening the
//      sheet, and not on a tap of any other shop.
//   2. It appears **only when a title id exists**, because a library key with no
//      title to point at collects an answer that changes nothing.
//   3. Dismissing **does not block** — the row still works — and is remembered, so
//      a reader who declined is not asked again.
//   4. Once answered, the Libby row is exact and **says so through its reach**,
//      not through hand-written copy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/services/overdrive_lookup.dart';

import 'support/book_details_harness.dart';

/// A book the reader wants but does not have, which is the state the library picker
/// lives in.
///
/// **`status` is 0 deliberately, and it used to be 2.** For your own book the sheet
/// picks its intent from status: reading or finished means "you already have this", so
/// every row becomes `Open X` and every per-book id is withheld -- including the
/// OverDrive title id this picker exists to point at. So on a finished book there is no
/// ask at all, by design: a library key cannot improve `libbyapp.com/shelf/loans`.
/// Interested is the state where the key buys the reader an exact in-app title link,
/// and therefore the only state worth asking in.
Book book({String? readerApp, int status = 0}) => Book(
  id: 'b1',
  userId: meId,
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

/// A found OverDrive answer, in the shape the live endpoint returns.
const found = OverDriveResult('1344919', OverDriveFormat.ebook);

Finder get whereToRead => find.byTooltip('Where to read');
Finder get picker => find.text('Which library?');
Finder get libbyRow => find.text('Libby');

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(whereToRead);
  await tester.pumpAndSettle();
}

void main() {
  group('the just-in-time ask', () {
    // Not on opening the sheet: the reader has expressed interest in *a* shop, not
    // in Libby, and asking there would be a toll on a screen they may be using to
    // reach Kindle.
    testWidgets('does not appear merely from opening the sheet', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      expect(picker, findsNothing);
    });

    // **It does appear on a book the reader already has, and an earlier draft had this
    // backwards.** The draft withheld the OverDrive title id on that path, which
    // disarmed the ask -- on the reasoning that a key could not improve
    // `libbyapp.com/shelf/loans`. True of the *shelf* link, but the key does not leave
    // the row there: title id plus key builds `library/<key>/title/<id>`, the title's
    // own page with its Borrow / Place Hold / **Open** action. So the answer changes
    // the destination here exactly as it does on the acquire path, and charging for it
    // is charging for something.
    testWidgets('appears on a book the reader already has too', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(status: 2),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      await tester.tap(find.text('Open Libby'));
      await tester.pumpAndSettle();

      expect(picker, findsOneWidget);
    });

    testWidgets('appears on the first Libby tap', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      await tester.tap(libbyRow);
      await tester.pumpAndSettle();
      expect(picker, findsOneWidget);
    });

    // Tapping a different shop must not raise a question about Libby.
    testWidgets('does not appear when another shop is tapped', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      await tester.tap(find.text('Kindle'));
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
    });

    // **The guard that keeps the question honest.** With no title id a library key
    // has nothing to point at, so the row would be a search either way and the
    // answer would buy the reader nothing on this tap.
    testWidgets('does not appear when nothing was found to point at', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        // The default, spelled out because it is the precondition under test.
        overDrive: const OverDriveResult.none(),
      );
      await openSheet(tester);
      await tester.tap(libbyRow);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
    });

    // A reader who already answered is not asked again \u2014 the whole promise of
    // "once".
    testWidgets('never returns once a library is stored', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
        libbyLibrary: (key: 'sfpl', name: 'San Francisco Public Library'),
      );
      await openSheet(tester);
      await tester.tap(libbyRow);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
    });
  });

  group('the picker itself', () {
    testWidgets('explains why it is asking, in Libby\'s terms not ours', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      await tester.tap(libbyRow);
      await tester.pumpAndSettle();
      // The reason is Libby's constraint, so a reader can tell this is not the app
      // collecting something for its own purposes.
      expect(
        find.textContaining('Libby searches one library at a time'),
        findsOneWidget,
      );
    });

    // Dismissing is a first-class outcome with a real control, not only a drag.
    testWidgets('offers a way out that is not the drag handle', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      await tester.tap(libbyRow);
      await tester.pumpAndSettle();
      expect(find.text('Not now'), findsOneWidget);
    });

    // Nothing is asked until there is enough to ask about: one or two letters match
    // thousands of branches and would show a list that means nothing.
    testWidgets('shows no results for a query too short to be one', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      await tester.tap(libbyRow);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sa');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Nothing by that name'), findsNothing);
      expect(find.text('Looking for libraries\u2026'), findsNothing);
    });
  });

  group('declining', () {
    // **Dismissing must not block.** The row worked before the question existed and
    // it still works: the sheet closes, the link is launched, nothing is stuck.
    testWidgets('closes and leaves the reader on their way', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      await tester.tap(libbyRow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      // The store sheet closed on the way in, so nothing of the flow is left on
      // screen and the details page is intact.
      expect(whereToRead, findsOneWidget);
    });

    // Remembered, so the reader is not asked on the next book. Asserted by
    // reopening the whole flow rather than by reading the store back, because the
    // claim is about what the reader sees.
    testWidgets('is remembered, so the ask does not come back', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      await tester.tap(libbyRow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      await openSheet(tester);
      await tester.tap(libbyRow);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
    });
  });

  group('with a library stored', () {
    // The payoff, read off the row's own supporting line. The four-character
    // difference from the general promise is the whole point: without it the
    // destination would get better and the row would look identical.
    testWidgets('the Libby row names the book it will borrow', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
        libbyLibrary: (key: 'sfpl', name: 'San Francisco Public Library'),
      );
      await openSheet(tester);
      expect(find.text('Borrow this book from your library'), findsOneWidget);
      expect(find.text('Borrow free from your library'), findsNothing);
    });

    // The contrast. Neither line claims the copy is *available* — availability is
    // per-library and only the reader's own library can settle it — but only the
    // exact one gets to say "this book".
    testWidgets('and without a library it keeps the general promise', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      expect(find.text('Borrow free from your library'), findsOneWidget);
      expect(find.text('Borrow this book from your library'), findsNothing);
    });

    // The open intent is where the upgrade is visible in copy: a stored Libby book
    // moves from "Opens your Libby library" to "Opens at this book", and that
    // sentence is derived from the reach rather than written for Libby.
    testWidgets('a stored Libby copy now opens at the book', (tester) async {
      await pumpBookDetails(
        tester,
        book: book(readerApp: 'libby'),
        signedInAs: meId,
        overDrive: found,
        libbyLibrary: (key: 'sfpl', name: 'San Francisco Public Library'),
      );
      await openSheet(tester);
      expect(find.text('Read in Libby'), findsOneWidget);
      expect(find.text('Opens at this book'), findsOneWidget);
      expect(find.text('Opens your Libby library'), findsNothing);
    });

    // The contrast that makes the previous case mean something: without a key the
    // same book reaches only the shelf, and says so.
    testWidgets('and without one it still only reaches the shelf', (
      tester,
    ) async {
      await pumpBookDetails(
        tester,
        book: book(readerApp: 'libby'),
        signedInAs: meId,
        overDrive: found,
      );
      await openSheet(tester);
      expect(find.text('Opens your Libby library'), findsOneWidget);
      expect(find.text('Opens at this book'), findsNothing);
    });
  });
}
