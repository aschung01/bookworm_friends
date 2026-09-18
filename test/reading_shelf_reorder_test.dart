// Reordering the Reading shelf by dragging.
//
// The shelf shipped fully inert, on the reasonable grounds that a book gets here by having
// its status set in `book_info_bottom_sheet` and there is no other way in or out. That is
// still true of every way in and out — but it also left the *arrangement* unreachable, and
// the arrangement belongs to the reader rather than to the app. `readingBooksOf`'s own doc
// used to concede the point: the order was "a consequence of where the books came from,
// which is the one thing a reader cannot change about it".
//
// Two things here are worth understanding rather than just passing.
//
// **The drag's payload type is the feature's only safety mechanism.** A `ReadingBookDrag`
// cannot be accepted by a queue shelf's `DragTarget<ShelfBookDrag>`, and this row's target
// cannot accept a book lifted off a plank. There is no shelf-id comparison to forget,
// which matters because the permissive version is not merely lax: `moveBookToShelf`
// rewrites `shelf_id` without touching `status`, so a book dropped on a plank would bounce
// straight back onto this shelf having changed nothing the reader can see.
//
// **A reorder writes `reading_shelf_index` and never `position`.** That is what keeps
// `withoutReadingBooks`' promise that clearing a book's status puts its cover back on its
// own plank where the reader filed it — the wart that retiring `withReadingFirst` removed.
// This file pins the order handed *out* of the widget; `shelf_reading_out_test.dart` pins
// what the sort then does with it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/reading_shelf_row.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart'
    show ShelfBookDrag, kShelfLiftDelay, kShelfPartDuration;

import 'support/home_page_harness.dart';

/// Three open books, in the order the reader has arranged them.
List<Book> _open() => [
  for (var i = 0; i < 3; i++)
    testBook(
      'abc'[i],
      's1',
      position: i,
      status: bookStatusReading,
      readingShelfIndex: i,
    ),
];

/// The orders the row reported, in the order it reported them.
late List<List<String>> reported;

/// How many times a hold asked for edit mode.
late int holds;

/// The row on its own, which is all these cases need: the drag is entirely the row's, and
/// mounting the whole shell would put a second `ReadingShelfRow` and a dozen shelves in the
/// way of `find.byType(BookWidget)`.
///
/// Localizations are not optional — the row asks for `readingShelfName` on its tab, and
/// `AppLocalizations.of` null-checks.
MaterialApp _app(List<Book> books, LibraryMode mode) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ReadingShelfRow(
      books: books,
      mode: mode,
      onLongPress: () => holds++,
      onReorder: (ids) => reported.add(ids),
    ),
  ),
);

Future<void> _pumpRow(
  WidgetTester tester, {
  required LibraryMode mode,
  List<Book>? books,
}) async {
  reported = [];
  holds = 0;
  await tester.pumpWidget(ProviderScope(child: _app(books ?? _open(), mode)));
  if (mode == LibraryMode.editLibrary) {
    await _settle(tester);
  } else {
    await tester.pumpAndSettle();
  }
}

/// Advances past the row's own animations without waiting for the shelf to stand still.
///
/// **`pumpAndSettle` cannot be used in edit mode, and that is not a performance note.**
/// Every cover there is inside a `Wiggle`, which repeats for as long as edit mode lasts, so
/// there is no quiescent frame to settle to and `pumpAndSettle` fails with a timeout instead
/// of returning. The shared harness's `enterEditMode` says the same thing about the shelves
/// below. The covers started wobbling here when the Reading shelf gained the badge and the
/// wiggle it always should have had, which is what turned seven of these cases red.
///
/// What actually has to finish is the gap preview and the snap that follows a drop, and both
/// are [kShelfPartDuration] at their longest — hence a bounded number of frames rather than
/// a wait for stillness.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(kShelfPartDuration);
  }
}

Finder _covers() => find.byType(BookWidget);

/// Drags the cover at [from] just past the cover at [to] and lets go.
///
/// The hold has to outlast [kShelfLiftDelay] before the draggable will start, and the move
/// has to be reported to the `DragTarget` before the drop, or nothing knows where the book
/// would land.
///
/// **Past, not onto, and the few pixels matter.** A cover is stepped over only once the
/// finger is *more than* halfway across it — `dropIndexForPointer` compares with `>=`, so a
/// finger resting exactly on a centre resolves to the near side and stays there rather than
/// flickering between two slots. Landing dead on the target's centre therefore inserts
/// *before* it, which is correct and was worth discovering here rather than on a device.
Future<void> _dragCover(
  WidgetTester tester, {
  required int from,
  required int to,
}) async {
  final start = tester.getCenter(_covers().at(from));
  final target = tester.getCenter(_covers().at(to));
  final overshoot = to == from ? 0.0 : (to > from ? 3.0 : -3.0);
  final end = target + Offset(overshoot, 0);

  final gesture = await tester.startGesture(start);
  await tester.pump(kShelfLiftDelay + const Duration(milliseconds: 60));
  // Moved in steps: a single jump reports one `onMove`, which works, but a real finger
  // crosses the covers in between and the drop index is recomputed at each one.
  for (var step = 1; step <= 4; step++) {
    await gesture.moveTo(Offset.lerp(start, end, step / 4)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await _settle(tester);
}

void main() {
  group('a drag reorders the row', () {
    testWidgets(
      'Given the first cover dragged onto the last, Then the order is '
      'reported with it moved to the end',
      (tester) async {
        await _pumpRow(tester, mode: LibraryMode.editLibrary);

        await _dragCover(tester, from: 0, to: 2);

        expect(reported, [
          ['b', 'c', 'a'],
        ]);
      },
    );

    testWidgets(
      'Given the last cover dragged onto the first, Then it is reported '
      'at the head',
      (tester) async {
        await _pumpRow(tester, mode: LibraryMode.editLibrary);

        await _dragCover(tester, from: 2, to: 0);

        expect(reported, [
          ['c', 'a', 'b'],
        ]);
      },
    );

    testWidgets(
      'Given a cover put back where it came from, Then nothing is written',
      (tester) async {
        // A hold that lifts a cover and sets it straight down is a common way to leave edit
        // mode, and it should not cost an UPDATE per book on the whole reading set.
        await _pumpRow(tester, mode: LibraryMode.editLibrary);

        await _dragCover(tester, from: 1, to: 1);

        expect(reported, isEmpty);
      },
    );

    testWidgets('Given the row reports an order, Then it is every open book exactly '
        'once', (tester) async {
      // Unlike `reorderBooksInShelf`, whose caveat is that it only covers what the caller
      // can see, this row hides nothing: the whole reading set is renumbered, so a missing
      // id would leave a book holding a stale index and sorting somewhere arbitrary.
      await _pumpRow(tester, mode: LibraryMode.editLibrary);

      await _dragCover(tester, from: 0, to: 1);

      expect(reported.single.toSet(), {'a', 'b', 'c'});
      expect(reported.single.length, 3);
    });
  });

  group('the drag is confined to this row', () {
    testWidgets('Given edit mode, Then the row accepts only its own drag type', (
      tester,
    ) async {
      await _pumpRow(tester, mode: LibraryMode.editLibrary);

      expect(find.byType(DragTarget<ReadingBookDrag>), findsOne);
      // The queue shelves' type. Accepting it would let a book be dropped here from a
      // plank, which would mean "start reading this" — a claim the bottom sheet owns.
      expect(find.byType(DragTarget<ShelfBookDrag>), findsNothing);
    });

    testWidgets('Given view mode, Then the row is not a drop target at all', (
      tester,
    ) async {
      await _pumpRow(tester, mode: LibraryMode.library);

      expect(find.byType(DragTarget<ReadingBookDrag>), findsNothing);
    });

    testWidgets('Given view mode, Then a cover still carries the drag that becomes '
        'the lift', (tester) async {
      // The draggable has to exist *before* the hold completes: a drag cannot be started
      // programmatically, and one that appears after the finger is down can never adopt
      // that pointer, because a recognizer claims its route at pointer-down. This is what
      // makes a single hold both enter edit mode and leave the cover carried.
      await _pumpRow(tester, mode: LibraryMode.library);

      expect(
        find.byType(LongPressDraggable<ReadingBookDrag>),
        findsNWidgets(3),
      );
    });
  });

  group('the cover in flight is the cover that was lifted', () {
    testWidgets('Given a book in the air, Then it still wears its ribbon', (
      tester,
    ) async {
      // **Every book on this shelf is open, so a lifted cover that loses its ribbon is
      // un-marked at the one moment the reader is looking straight at it.** The feedback is
      // built by `_DraggedCover` rather than by the widget that draws the resting cover, so
      // nothing made the two agree until this pinned it.
      await _pumpRow(
        tester,
        mode: LibraryMode.editLibrary,
        books: [_open().first],
      );

      expect(find.byType(ReadingBookmark), findsOne);

      final start = tester.getCenter(_covers().first);
      final gesture = await tester.startGesture(start);
      await tester.pump(kShelfLiftDelay + const Duration(milliseconds: 60));
      await gesture.moveTo(start + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));

      // Two, not one: the invisible ghost holding the slot keeps its own ribbon, and the
      // cover under the finger has the second. Counting alone would pass for two ghosts, so
      // the split below is the assertion that matters — the feedback is mounted in the
      // route's `Overlay`, which is not inside the row.
      expect(find.byType(ReadingBookmark), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(ReadingShelfRow),
          matching: find.byType(ReadingBookmark),
        ),
        findsOne,
      );

      await gesture.up();
      await _settle(tester);
    });

    testWidgets('Given a book in the air, Then it is jittered from the same page '
        'count', (tester) async {
      // The jitter is hashed from the ISBN *and* the page count, so a feedback handed only
      // the ISBN is a subtly different book from the one that left the row — and the gap the
      // row opens for it was measured off the real slot. Invisible at rest, and a few px of
      // mismatch under the finger, which is why it survived until the ribbon was looked at.
      //
      // Spelled out here rather than taken from [_open], whose books leave `pageCount` null
      // — against which this assertion would pass without the feedback carrying anything.
      final book = testBook(
        'a',
        's1',
        status: bookStatusReading,
        readingShelfIndex: 0,
        pageCount: 412,
      );
      await _pumpRow(tester, mode: LibraryMode.editLibrary, books: [book]);

      final start = tester.getCenter(_covers().first);
      final gesture = await tester.startGesture(start);
      await tester.pump(kShelfLiftDelay + const Duration(milliseconds: 60));
      await gesture.moveTo(start + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));

      for (final cover in tester.widgetList<BookWidget>(_covers())) {
        expect(cover.pageCount, book.pageCount);
        // Nothing can hold a cover in flight: the drag already owns the pointer.
        expect(cover.pressEffect, isFalse);
      }

      await gesture.up();
      await _settle(tester);
    });
  });

  group('a hold in view mode asks for edit mode', () {
    testWidgets('Given a hold on a cover, Then edit mode is asked for once', (
      tester,
    ) async {
      await _pumpRow(tester, mode: LibraryMode.library);

      final gesture = await tester.startGesture(
        tester.getCenter(_covers().first),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await gesture.up();
      await tester.pumpAndSettle();

      // The *drag* announces this rather than a long-press timer beside it: two
      // recognizers on one pointer would sometimes cancel the gesture that was about to
      // become the drag, and the hold would open edit mode with nothing in hand.
      expect(holds, 1);
    });

    testWidgets('Given a hold in edit mode, Then it is not asked for again', (
      tester,
    ) async {
      await _pumpRow(tester, mode: LibraryMode.editLibrary);

      await _dragCover(tester, from: 0, to: 1);

      expect(holds, 0);
    });
  });

  group('a book that leaves mid-drag', () {
    testWidgets('Given the lifted book is finished elsewhere, Then the drag is '
        'abandoned without writing an order', (tester) async {
      // Finished on another device, or its status cleared by a details page pushed over
      // this one. The cover under the finger is simply gone, and there is nothing left to
      // land — holding a drag against a book the row no longer draws would report an order
      // containing a book that is no longer on the shelf.
      await _pumpRow(tester, mode: LibraryMode.editLibrary);

      final start = tester.getCenter(_covers().first);
      final gesture = await tester.startGesture(start);
      await tester.pump(kShelfLiftDelay + const Duration(milliseconds: 60));
      await gesture.moveTo(start + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));

      // The book leaves the reading set while it is in the air.
      await tester.pumpWidget(
        ProviderScope(
          child: _app([
            for (final book in _open())
              if (book.id != 'a') book,
          ], LibraryMode.editLibrary),
        ),
      );
      await tester.pump();
      await gesture.up();
      await _settle(tester);

      expect(reported, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
