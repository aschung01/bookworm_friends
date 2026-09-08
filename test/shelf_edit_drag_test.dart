// Edit mode's one drag.
//
// The library used to answer a cover held in edit mode with two different
// gestures: a *vertical* drag lifted a book instantly and could only be dropped
// on some other shelf, while a long press started a reorder that never left the
// row it began in. This pins the single gesture that replaced them —
//
//   1. nothing lifts without a hold, whichever way the finger then goes;
//   2. a held cover reorders its own row;
//   3. the same held cover, carried to another shelf, lands *between* two of its
//      books rather than on the end of them;
//   4. that receiving row parts to show where, before the finger is lifted;
//   5. carrying it to the bottom of the pane scrolls the library, so the shelf it
//      belongs on does not have to be on screen when the drag starts;
//   6. the read-books sheet is off the screen for the whole of it, because the
//      shelves under it are ones a drag has to be able to reach;
//   7. the book in the air is turned out by the same angle on the same timings
//      as a book being held, then unwinds again as it is set down;
//   8. and the hold that turns edit mode *on* leaves that same book already being
//      carried, so one gesture both enters edit mode and reorders.
//
// `pumpAndSettle` is unusable throughout: `Wiggle` repeats forever in edit mode.
// See `home_page_harness.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

import 'support/home_page_harness.dart';

/// Records what the library was asked to persist, since there is no database
/// here to ask. The real notifier's optimistic half is skipped on purpose: what
/// is under test is the edit the *gesture* produces, and leaving state alone
/// keeps the covers where the assertions can find them.
class _RecordingLibrary extends FakeLibraryNotifier {
  _RecordingLibrary(super.shelves);

  /// `'<shelfId>: <id>,<id>'` — flattened because a record holding a `List`
  /// compares by identity, so the obvious tuple never matches a literal.
  final List<String> reorders = [];

  /// `'<bookId> -> <shelfId>: <id>,<id>'`.
  final List<String> moves = [];

  @override
  Future<void> reorderBooksInShelf(String shelfId, List<String> bookIds) async {
    reorders.add('$shelfId: ${bookIds.join(',')}');
  }

  @override
  Future<void> moveBookToShelf(
    String bookId,
    String targetShelfId,
    List<String> orderedBookIds,
  ) async {
    moves.add('$bookId -> $targetShelfId: ${orderedBookIds.join(',')}');
  }
}

/// Applies the edit the way the real notifier's optimistic half does, so the row
/// actually changes shape when a book lands.
///
/// [_RecordingLibrary] deliberately does not, which is what kept a whole class of
/// bug out of reach: the covers only get rebuilt into a *new* arrangement when the
/// state behind them really moves, and that rebuild is when a keyed slot can be
/// caught mid-reparent.
class _ApplyingLibrary extends FakeLibraryNotifier {
  _ApplyingLibrary(super.shelves);

  @override
  Future<void> reorderBooksInShelf(String shelfId, List<String> bookIds) async {
    final shelves = [...?state.value];
    final i = shelves.indexWhere((shelf) => shelf.id == shelfId);
    final books = [...shelves[i].books]
      ..sort((a, b) => bookIds.indexOf(a.id).compareTo(bookIds.indexOf(b.id)));
    shelves[i] = shelves[i].copyWith(books: books);
    state = AsyncData(shelves);
  }
}

List<Shelf> _twoShelves() => [
  testShelf('s1', [
    testBook('a1', 's1', position: 0, title: 'A one'),
    testBook('a2', 's1', position: 1, title: 'A two'),
  ], name: 'Dev'),
  testShelf('s2', [
    testBook('b1', 's2', position: 0, title: 'B one'),
    testBook('b2', 's2', position: 1, title: 'B two'),
  ], name: 'Fiction'),
];

/// More shelves than the pane can hold, so the library has somewhere to scroll.
List<Shelf> _deepLibrary() => [
  for (var i = 0; i < 6; i++)
    testShelf('s$i', [
      testBook('s${i}b0', 's$i', position: 0, title: 'Shelf $i one'),
      testBook('s${i}b1', 's$i', position: 1, title: 'Shelf $i two'),
    ], name: 'Shelf $i'),
];

/// The cover standing on a shelf, told apart from the one flying under the
/// finger by its hero tag — the feedback and the placeholder left behind both
/// go untagged.
Finder _cover(String bookId) => find.byWidgetPredicate(
  (widget) => widget is BookWidget && widget.heroTag == 'book_$bookId',
);

/// The library's own vertical scroller, which is the one a drag at the bottom of
/// the pane is asking to move.
ScrollableState _pane(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .firstWhere((s) => s.position.axisDirection == AxisDirection.down);

/// The cover in flight, told apart from the ones standing on shelves by having no
/// hero tag *and* a turn driven from outside the book.
Finder _flyingCover() => find.byWidgetPredicate(
  (widget) =>
      widget is BookWidget &&
      widget.heroTag == null &&
      widget.turnDrive != null,
);

/// How far through its turn the book at [finder] is: 0 upright, 1 fully turned
/// out to [kBookTurnAngle].
double _turnOf(WidgetTester tester, Finder finder) =>
    tester.widget<BookWidget>(finder).turnDrive!.value;

Future<_RecordingLibrary> _pumpEditing(
  WidgetTester tester, {
  List<Shelf>? shelves,
}) async {
  final library = _RecordingLibrary(shelves ?? _twoShelves());
  await pumpHome(
    tester,
    extraOverrides: [libraryProvider.overrideWith(() => library)],
  );
  await enterEditMode(tester);
  return library;
}

/// Holds [bookId] long enough for it to lift, and leaves the finger down.
Future<TestGesture> _lift(WidgetTester tester, String bookId) async {
  final gesture = await tester.startGesture(tester.getCenter(_cover(bookId)));
  await tester.pump(kShelfLiftDelay + const Duration(milliseconds: 50));
  return gesture;
}

void main() {
  testWidgets(
    'Given view mode, When a book is held, Then edit mode arrives with that book already in the air and the same gesture reorders it',
    (tester) async {
      final library = _RecordingLibrary(_twoShelves());
      await pumpHome(
        tester,
        extraOverrides: [libraryProvider.overrideWith(() => library)],
      );

      // Measured in view mode, which the two rows now share the geometry of.
      final a1 = tester.getCenter(_cover('a1'));
      final pastA2 = tester.getCenter(_cover('a2')) + const Offset(20, 0);

      // The hold that used to do nothing but switch edit mode on. Two pumps for the
      // reason `enterEditMode` documents: `onTapDown` waits on the tap arena, so a
      // single long pump schedules the hold too late for it to fire.
      final gesture = await tester.startGesture(a1);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(kBookStageTwoDelay + const Duration(milliseconds: 50));

      // Still holding, and both things have happened at once.
      expect(isEditing(), isTrue);
      expect(
        _flyingCover(),
        findsOneWidget,
        reason: 'the held book should already be the one being carried',
      );

      // The proof that it is *one* drag and not a new one: carrying on from here
      // reorders, with no second press anywhere in the gesture.
      await gesture.moveTo(pastA2);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(library.reorders, ['s1: a2,a1']);
    },
  );

  testWidgets(
    'Given a book held in view mode, When edit mode arrives, Then the shelf it left stays as it was',
    (tester) async {
      final library = _RecordingLibrary(_twoShelves());
      await pumpHome(
        tester,
        extraOverrides: [libraryProvider.overrideWith(() => library)],
      );

      final a2Before = tester.getCenter(_cover('a2')).dx;

      final gesture = await tester.startGesture(tester.getCenter(_cover('a1')));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(kBookStageTwoDelay + const Duration(milliseconds: 50));
      // Long enough for a parting to have run, the point being that there is none
      // to run: the gap the held book left is still standing open under the finger.
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.getCenter(_cover('a2')).dx,
        closeTo(a2Before, 2),
        reason:
            'the book to the right must not slide over the held book\'s slot',
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'Given a drop that really reorders the shelf, When the row rebuilds around it, Then the shelf survives the frame',
    (tester) async {
      await pumpHome(
        tester,
        extraOverrides: [
          libraryProvider.overrideWith(() => _ApplyingLibrary(_twoShelves())),
        ],
      );
      final plank = find.byType(ShelfWidget).first;
      final plankWidth = tester.getSize(plank).width;

      await enterEditMode(tester);
      final gesture = await _lift(tester, 'a1');
      await gesture.moveTo(
        tester.getCenter(_cover('a2')) + const Offset(20, 0),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();

      // Frame by frame across the landing. Measuring a slot through its global key
      // used to throw here — the reordering list leaves the old arrangement
      // deactivated for part of the frame — and an exception in `build` costs the
      // whole shelf, which showed up as the plank losing its width.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'frame ${i + 1}');
        expect(tester.getSize(plank).width, plankWidth);
      }
    },
  );

  testWidgets(
    'Given edit mode, When a cover is dragged without being held, Then nothing moves',
    (tester) async {
      final library = await _pumpEditing(tester);

      // The exact gesture that used to throw a book onto another shelf: straight
      // down onto it, with no hold at all.
      final travel =
          tester.getCenter(_cover('b1')) - tester.getCenter(_cover('a1'));
      await tester.drag(_cover('a1'), travel);
      await tester.pump(const Duration(milliseconds: 300));

      expect(library.moves, isEmpty);
      expect(library.reorders, isEmpty);
    },
  );

  testWidgets(
    'Given a held cover, When it is carried past its neighbour, Then its own shelf is reordered',
    (tester) async {
      final library = await _pumpEditing(tester);
      final pastA2 = tester.getCenter(_cover('a2')) + const Offset(20, 0);

      final gesture = await _lift(tester, 'a1');
      await gesture.moveTo(pastA2);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(library.reorders, ['s1: a2,a1']);
      expect(library.moves, isEmpty);
    },
  );

  testWidgets(
    'Given a held cover, When it is dropped between two books on another shelf, Then it lands between them',
    (tester) async {
      final library = await _pumpEditing(tester);
      final betweenBs =
          (tester.getCenter(_cover('b1')) + tester.getCenter(_cover('b2'))) / 2;

      final gesture = await _lift(tester, 'a1');
      await gesture.moveTo(betweenBs);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      // The whole row as the reader was shown it, not an append: the arriving
      // book sits where the gap was.
      expect(library.moves, ['a1 -> s2: b1,a1,b2']);
      expect(library.reorders, isEmpty);
    },
  );

  testWidgets(
    'Given a held cover over another shelf, When it hovers between two books, Then they part to show where it would land',
    (tester) async {
      await _pumpEditing(tester);
      // Centres, not corners: the covers wiggle, and a rotated box's corner is not
      // where its edge is.
      final b2Before = tester.getCenter(_cover('b2')).dx;
      final betweenBs =
          (tester.getCenter(_cover('b1')) + tester.getCenter(_cover('b2'))) / 2;

      final gesture = await _lift(tester, 'a1');
      await gesture.moveTo(betweenBs);
      // Two pumps: the first frame is where the parting *starts* (the tween is
      // still at zero), the second is where the whole of it has run.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.getCenter(_cover('b2')).dx,
        greaterThan(b2Before + 20),
        reason: 'the book after the gap should have slid out of the way',
      );

      // And closes again when the finger leaves the shelf without dropping.
      await gesture.moveTo(tester.getCenter(_cover('a2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getCenter(_cover('b2')).dx, closeTo(b2Before, 2));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'Given a cover held away from its middle, When it lifts, Then the book is picked up where it stood rather than under the fingertip',
    (tester) async {
      await _pumpEditing(tester);

      final coverCentre = tester.getCenter(_cover('a1'));
      // Deliberately off-centre. A finger on the middle of a cover cannot tell the
      // two anchorings apart, which is exactly how a cover leaping up to the
      // fingertip goes unnoticed in a test that presses the centre.
      final gesture = await tester.startGesture(
        coverCentre + const Offset(0, 28),
      );
      await tester.pump(kShelfLiftDelay + const Duration(milliseconds: 50));
      await tester.pump();

      expect(
        tester.getCenter(_flyingCover()),
        offsetMoreOrLessEquals(coverCentre, epsilon: 2),
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'Given a cover that has just lifted, When the drag runs, Then the book in the air turns out and stays out',
    (tester) async {
      await _pumpEditing(tester);

      final gesture = await _lift(tester, 'a1');
      // Two pumps, as everywhere here: the first is the turn's opening frame, the
      // second is where 80ms of it has run. That it is *between* the ends is the
      // whole assertion — the cover animates out rather than appearing turned.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        _turnOf(tester, _flyingCover()),
        allOf(greaterThan(0), lessThan(1)),
      );

      await tester.pump(kBookTurnDuration);
      expect(_turnOf(tester, _flyingCover()), 1);

      // Held out for as long as the book is off the shelf. A hold's turn lets go at
      // stage two; this one means something else, and must not.
      await tester.pump(kBookStageTwoDelay);
      expect(_turnOf(tester, _flyingCover()), 1);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'Given a book released over a shelf, When it comes to rest, Then the cover that lands unwinds the turn',
    (tester) async {
      await _pumpEditing(tester);
      final pastA2 = tester.getCenter(_cover('a2')) + const Offset(20, 0);

      final gesture = await _lift(tester, 'a1');
      await gesture.moveTo(pastA2);
      await tester.pump();
      await tester.pump(kBookTurnDuration);
      await gesture.up();
      await tester.pump();

      // There is no flying cover left to unwind — Flutter took it out of the overlay
      // on release — so the turn carries on on the one standing in the row.
      expect(_flyingCover(), findsNothing);
      expect(_turnOf(tester, _cover('a1')), greaterThan(0.8));

      await tester.pump(const Duration(milliseconds: 90));
      expect(_turnOf(tester, _cover('a1')), lessThan(1));

      // Down, and handed back to its own hold rather than left driven from outside.
      // The second pump is the rebuild the unwind's completion schedules.
      await tester.pump(kBookReleaseDuration);
      await tester.pump();
      expect(tester.widget<BookWidget>(_cover('a1')).turnDrive, isNull);
    },
  );

  testWidgets(
    'Given a held cover, When it is put back where it was, Then nothing is written',
    (tester) async {
      final library = await _pumpEditing(tester);

      final gesture = await _lift(tester, 'a1');
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(library.reorders, isEmpty);
      expect(library.moves, isEmpty);
    },
  );

  testWidgets(
    'Given a library taller than the pane, When a held cover is carried to the bottom of it, Then the library scrolls',
    (tester) async {
      await _pumpEditing(tester, shelves: _deepLibrary());
      final pane = _pane(tester);
      expect(pane.position.pixels, 0);
      expect(
        pane.position.maxScrollExtent,
        greaterThan(0),
        reason: 'the fixture has to overflow or there is nothing to test',
      );

      final screen = tester.getSize(find.byType(MaterialApp));
      // A cover on the *first* shelf, carried down to the bottom edge — the
      // gesture for putting a book on a shelf that is not on screen yet.
      final gesture = await _lift(tester, 's0b0');
      await gesture.moveTo(Offset(screen.width / 2, screen.height - 16));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(pane.position.pixels, greaterThan(0));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'Given edit mode, Then the read-books sheet is off the screen and back again when it ends',
    (tester) async {
      await pumpHome(tester, shelves: _twoShelves());
      final screen = tester.getSize(find.byType(MaterialApp));
      final sheet = find.byType(LibrarySheet);
      expect(tester.getRect(sheet).top, lessThan(screen.height));

      await enterEditMode(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getRect(sheet).top,
        greaterThanOrEqualTo(screen.height - 0.5),
        reason:
            'a collapsed sheet still covers the shelves a drag has to reach',
      );

      // Left mounted throughout, so the detent it was resting at survives the edit.
      expect(sheet, findsOneWidget);

      await tester.tap(libraryDoneButton());
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).top, lessThan(screen.height));
    },
  );
}
