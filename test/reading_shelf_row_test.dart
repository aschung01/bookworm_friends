// The Reading shelf: the row at the top of the library holding every book the reader has
// open, taken off the shelf each one belongs to.
//
// Three kinds of claim are pinned here, and the geometry is the part worth understanding.
//
//   1. **Membership.** A book at `bookStatusReading` is on this shelf and *not* on its
//      own, and the shelf is absent entirely when nothing is in progress. Both directions
//      matter: a book drawn twice was the bug the filter exists to prevent, and an empty
//      plank with a `Reading` tab would promise a state the reader is not in while
//      pushing every real shelf ~170pt down the page.
//   2. **Geometry.** The covers stand upright, both bottom corners on the board, and
//      the row's leading cover shares a left edge with every queue shelf's leading cover.
//      They leaned at −6.5° when this shipped; the frames overturned that, and the note
//      at the top of `reading_shelf_row.dart` records why. None of it is visible in a
//      widget tree, so it is measured from rendered rects here.
//   3. **What edit mode can and cannot do to it.** A hold enters edit mode, the covers
//      wobble, each carries the remove badge, and they can be dragged into a new order
//      among themselves. What cannot happen is a book leaving the row by drag — nothing can
//      be dropped onto this shelf and nothing lifted off it can land anywhere else — and the
//      shelf itself cannot be renamed or deleted, because the reader did not make it. A book
//      gets onto this shelf by having its status set in `book_info_bottom_sheet`, and that
//      is still the only way in.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_day_stamp.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/reading_shelf_lamp.dart';
import 'package:bookworm_friends/ui/widgets/reading_shelf_row.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_book_tile.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:bookworm_friends/ui/widgets/wiggle.dart';

import 'support/home_page_harness.dart';

/// A 393x852 phone — the size every measured number here is derived for.
const Size _phone = Size(393, 852);

Future<void> _pump(WidgetTester tester, List<Shelf> shelves) async {
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpHome(tester, shelves: shelves, surfaceSize: _phone);
}

/// A shelf holding [reading] open books followed by [waiting] that are not.
Shelf _shelf({int reading = 1, int waiting = 2, String name = 'Dev'}) =>
    testShelf('s1', [
      for (var i = 0; i < reading; i++)
        testBook(
          'r$i',
          's1',
          position: i,
          title: 'Open $i',
          status: bookStatusReading,
          startDate: DateTime.now().subtract(const Duration(days: 4)),
        ),
      for (var i = 0; i < waiting; i++)
        testBook('w$i', 's1', position: reading + i, title: 'Waiting $i'),
    ], name: name);

Finder _readingShelf() => find.byType(ReadingShelfRow);

/// The books standing on the Reading shelf.
Finder _readingCovers() =>
    find.descendant(of: _readingShelf(), matching: find.byType(ShelfBookTile));

/// The Reading shelf's own plank.
Finder _readingPlank() =>
    find.descendant(of: _readingShelf(), matching: find.byType(ShelfWidget));

/// A book's height, as the row derives it.
double get _bookHeight => _phone.height * 0.15;

void main() {
  group('which books stand on it', () {
    testWidgets(
      'Given a shelf with one open book, Then it is on the Reading shelf and not on '
      'its own',
      (tester) async {
        await _pump(tester, [_shelf()]);

        expect(_readingShelf(), findsOne);
        expect(_readingCovers(), findsOne);
        // The whole point of the filter. Two covers for one book was the state this
        // replaced, on the shelves the promotion left it on.
        expect(
          find.descendant(
            of: find.byType(ShelfRow),
            matching: find.text('Open 0'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: _readingShelf(), matching: find.text('Open 0')),
          findsOne,
        );
      },
    );

    testWidgets('Given open books on two shelves, Then one Reading shelf holds '
        'both', (tester) async {
      await _pump(tester, [
        _shelf(),
        testShelf('s2', [
          testBook(
            'r9',
            's2',
            title: 'Open 9',
            status: bookStatusReading,
            startDate: DateTime.now(),
          ),
        ], name: 'Fic'),
      ]);

      // One place to look, which is the argument for the shelf: the promotion gave a
      // reader with eight shelves eight first slots to scan.
      expect(_readingShelf(), findsOne);
      expect(_readingCovers(), findsNWidgets(2));
    });

    testWidgets(
      'Given nothing in progress, Then there is no Reading shelf at all',
      (tester) async {
        await _pump(tester, [_shelf(reading: 0, waiting: 3)]);

        // `vanish`, not an empty plank. The shelf arriving when a book is opened is
        // itself the feedback.
        expect(_readingShelf(), findsNothing);
        expect(find.text('Reading'), findsNothing);
      },
    );

    testWidgets('Given the Reading shelf, Then it is above every other shelf', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      expect(
        tester.getRect(_readingPlank()).top,
        lessThan(
          tester
              .getRect(
                find.descendant(
                  of: find.byType(ShelfRow),
                  matching: find.byType(ShelfWidget),
                ),
              )
              .top,
        ),
      );
    });

    testWidgets("Given an open book, Then its own shelf's count drops by one", (
      tester,
    ) async {
      await _pump(tester, [_shelf(reading: 1, waiting: 2)]);

      // Correct rather than surprising: the count is the number a reader checks by
      // scrolling the row to its end, and the book has left the queue.
      final label = tester.widget<ShelfLabel>(
        find
            .descendant(
              of: find.byType(ShelfRow),
              matching: find.byType(ShelfLabel),
            )
            .first,
      );
      expect(label.count, 2);
    });
  });

  group('the tab', () {
    testWidgets('Given the shelf, Then its tab names it', (tester) async {
      await _pump(tester, [_shelf()]);

      final label = tester.widget<ShelfLabel>(
        find.descendant(of: _readingShelf(), matching: find.byType(ShelfLabel)),
      );
      expect(label.label, 'Reading');
    });

    testWidgets('Given the shelf, Then its tab counts every book standing on it', (
      tester,
    ) async {
      await _pump(tester, [_shelf(reading: 3, waiting: 1)]);

      // `books.length` rather than `shelvedBookCount`: every book handed to this
      // widget is on this plank, with no finished/reading exclusion to apply. It is
      // also the one honest answer to "how many" once the row itself clips —
      // `ShelfEdgeFades` starts fading well before the count would.
      final label = tester.widget<ShelfLabel>(
        find.descendant(of: _readingShelf(), matching: find.byType(ShelfLabel)),
      );
      expect(label.count, 3);
      expect(find.text('3'), findsOne);
    });

    testWidgets("Given the shelf, Then its tab is in the app's own colour", (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      final label = tester.widget<ShelfLabel>(
        find.descendant(of: _readingShelf(), matching: find.byType(ShelfLabel)),
      );
      // The app's shelf rather than one the reader named, said in colour instead of in
      // words. `test/color_contrast_test.dart` pins the 4.5:1 floor this clears at
      // 5.62:1 on `surface`.
      expect(label.labelColor, AppColors.light.brandText);
    });

    testWidgets('Given the shelf, Then neither the plank nor the tab is a hero', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      // The details page names the shelf a book *belongs* to, so there is no partner
      // over there for this plank to fly to. `book_details_tab_view.dart` withholds
      // its own tags for an open book, for the same reason from the other end.
      expect(tester.widget<ShelfWidget>(_readingPlank()).heroTag, isNull);
      expect(
        tester
            .widget<ShelfLabel>(
              find.descendant(
                of: _readingShelf(),
                matching: find.byType(ShelfLabel),
              ),
            )
            .heroTag,
        isNull,
      );
    });
  });

  group('the books stand on the board', () {
    testWidgets('Given a cover, Then it stands squarely on the plank', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      final plank = tester.getRect(_readingPlank());
      final cover = _readingCovers().first;

      // **Both bottom corners on the board, which is what "upright" means and what the
      // lean this shelf briefly carried could not say.** A tipped cover stood on one
      // corner, and the pitfall there was that pivoting anywhere right of it swung the
      // other corner *below* the plank — the book pierced the shelf it was standing on.
      // There is no pivot to get wrong now, and these two assertions are what says so.
      expect(tester.getBottomLeft(cover).dy, closeTo(plank.top, 0.01));
      expect(tester.getBottomRight(cover).dy, closeTo(plank.top, 0.01));
    });

    testWidgets('Given a cover, Then its sides are vertical', (tester) async {
      await _pump(tester, [_shelf()]);
      final cover = _readingCovers().first;

      // The other half of "upright": no horizontal sweep between a cover's top and its
      // base. This is the assertion that fails first if a rotation ever comes back
      // without the padding and row height that go with it.
      expect(
        tester.getTopLeft(cover).dx,
        closeTo(tester.getBottomLeft(cover).dx, 0.01),
      );
      expect(
        tester.getTopRight(cover).dx,
        closeTo(tester.getBottomRight(cover).dx, 0.01),
      );
    });

    testWidgets('Given the leading cover, Then it starts where every other row does', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      // **The reason the lean was removed, as a number.** A tipped cover overhangs its
      // slot to the left by h·sinθ, which the row's leading padding had to absorb — so
      // this row's first cover stood ~15pt right of every queue shelf's first cover and
      // the Reading shelf read as indented from the library. Upright, the two share a
      // left edge.
      final open = tester.getTopLeft(_readingCovers().first).dx;
      final queued = tester
          .getTopLeft(
            find
                .descendant(
                  of: find.byType(ShelfRow),
                  matching: find.byType(ShelfBookTile),
                )
                .first,
          )
          .dx;
      expect(open, closeTo(queued, 0.01));
      expect(open, greaterThan(tester.getRect(_readingPlank()).left));
    });

    testWidgets('Given the row, Then it reserves exactly what any other row does', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      final plank = tester.getRect(_readingPlank());
      // `bookRowExtent` and nothing more. The lean needed ~9pt of extra headroom for the
      // top corner it lifted; standing the books up gives that back, so the Reading
      // shelf costs the library exactly what a shelf costs.
      final top = tester.getTopLeft(_readingCovers().first).dy;
      expect(plank.top - top, lessThanOrEqualTo(bookRowExtent(_bookHeight)));
      expect(plank.top - top, greaterThan(_bookHeight * 0.9));
    });

    testWidgets('Given two open books, Then 15pt separates their covers', (
      tester,
    ) async {
      await _pump(tester, [_shelf(reading: 2, waiting: 1)]);

      final covers = _readingCovers();
      // `kShelfSlotMargin` each side, the same as two covers on any shelf below — which
      // is what makes the two rows read as the same piece of furniture.
      expect(
        tester.getTopLeft(covers.at(1)).dx -
            tester.getTopRight(covers.at(0)).dx,
        closeTo(kShelfSlotMargin * 2, 0.01),
      );
    });
  });

  group('the lamp is a fixture, not part of the scrolling shelves', () {
    // **Regression coverage for the bug this shelf got wrong twice.** The lamp lived
    // inside `ReadingShelfRow` in both earlier drafts, which meant it was part of the
    // scrolling content and travelled up the screen with the books. A lamp is a fixture:
    // the shelves move under it and it does not move. It is a fixed layer in
    // `LibraryPane` now, behind the scroll view.
    //
    // The first draft also painted the reach *outside* the row's box with a negative
    // `Positioned.top` under `Clip.none`, on the reasoning that it fell into "the 26pt
    // gap the shelf above already leaves" — fiction for this shelf, which is always the
    // first in the library. The second fixed that and left a strip of bare
    // `surfaceVariant` visible above the light instead. Both are invisible at rest and
    // obvious the moment the list is scrolled, so both are measured here.
    testWidgets('Given the shelf, Then the lamp is not inside it', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      // Structural, not cosmetic: anything inside this widget is inside the scroll view.
      expect(find.byType(ReadingShelfLamp), findsOne);
      expect(
        find.descendant(
          of: _readingShelf(),
          matching: find.byType(ReadingShelfLamp),
        ),
        findsNothing,
      );
    });

    testWidgets('Given the shelf, Then the lamp is outside the scroll view', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(ReadingShelfLamp),
        ),
        findsNothing,
      );
    });

    testWidgets('Given the library is scrolled, Then the light does not move', (
      tester,
    ) async {
      // The assertion the reader actually asked for, twice. Enough shelves to have
      // somewhere to scroll to.
      await _pump(tester, [
        _shelf(reading: 2, waiting: 6),
        testShelf('s2', [
          for (var i = 0; i < 6; i++) testBook('x$i', 's2', position: i),
        ], name: 'Fic'),
        testShelf('s3', [
          for (var i = 0; i < 6; i++) testBook('y$i', 's3', position: i),
        ], name: 'Biz'),
      ]);

      final before = tester.getRect(find.byType(ReadingShelfLamp));
      final shelfBefore = tester.getTopLeft(_readingShelf()).dy;

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      // The shelves moved...
      expect(
        tester.getTopLeft(_readingShelf()).dy,
        lessThan(shelfBefore - 100),
        reason: 'the drag has to have actually scrolled the library',
      );
      // ...and the light did not.
      expect(tester.getRect(find.byType(ReadingShelfLamp)), before);
    });

    testWidgets(
      "Given the library, Then the light starts at the library's own top edge",
      (tester) async {
        await _pump(tester, [_shelf()]);

        // No gap above it. The strip of bare `surfaceVariant` that used to show between
        // the bar and the start of the light is what made the wash read as a rectangle,
        // so the lamp is pinned to the top of the box `LibraryPaneFrame` has already
        // placed at `topInset` — the same box the scroll view fills, which is why that is
        // the reference here rather than the pane (whose own top is behind the bar).
        final lamp = tester.getRect(find.byType(ReadingShelfLamp));
        final libraryTop = tester
            .getRect(find.byType(SingleChildScrollView).first)
            .top;
        expect(lamp.top, closeTo(libraryTop, 0.01));
      },
    );

    testWidgets('Given nothing open, Then the library is unlit', (
      tester,
    ) async {
      // The lamp is the Reading shelf's light even though it is not inside it, so it
      // has to come and go with that shelf rather than with the library.
      await _pump(tester, [_shelf(reading: 0, waiting: 3)]);

      expect(find.byType(ReadingShelfLamp), findsNothing);
    });
  });

  group('what is drawn on a cover', () {
    testWidgets('Given an open book, Then it wears the ribbon and a day stamp', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      // Two marks saying two different things: the ribbon says the book is open, the
      // stamp says how long it has been. The fixture started four days ago, and the
      // count is inclusive of today.
      expect(
        find.descendant(
          of: _readingShelf(),
          matching: find.byType(ReadingBookmark),
        ),
        findsOne,
      );
      expect(
        find.descendant(
          of: _readingShelf(),
          matching: find.byType(ReadingDayStamp),
        ),
        findsOne,
      );
      expect(find.text('D+5'), findsOne);
    });

    testWidgets('Given a book with no start date, Then no stamp is invented', (
      tester,
    ) async {
      await _pump(tester, [
        testShelf('s1', [
          testBook('r', 's1', title: 'Open', status: bookStatusReading),
        ], name: 'Dev'),
      ]);

      // "D+0" and "we don't know" are different statements, and only one is true.
      expect(_readingCovers(), findsOne);
      expect(
        find.descendant(
          of: _readingShelf(),
          matching: find.byType(ReadingDayStamp),
        ),
        findsNothing,
      );
    });

    testWidgets('Given the shelf, Then the pool is on its plank and on no other', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      // The lamp itself is a fixed layer outside this row — see the group above. What
      // the row owns is what the light *lands on*: the board's own warm pool. Every
      // other plank in the library takes no glow, which is what makes this one read as
      // lit rather than just differently coloured.
      expect(
        tester.widget<ShelfWidget>(_readingPlank()).glow,
        kReadingLampPlankGlow,
      );
      expect(
        tester
            .widget<ShelfWidget>(
              find
                  .descendant(
                    of: find.byType(ShelfRow),
                    matching: find.byType(ShelfWidget),
                  )
                  .first,
            )
            .glow,
        isNull,
      );
    });

    testWidgets(
      'Given a lit cover, Then the light scales it rather than tinting it',
      (tester) async {
        await _pump(tester, [_shelf()]);

        // `card_lighting.dart`'s rule: a warm source multiplies what a surface already
        // reflects, so covers keep their hue. A translucent warm layer would flatten
        // them all toward one colour.
        expect(
          find.descendant(
            of: _readingShelf(),
            matching: find.byType(ReadingLampWash),
          ),
          findsOne,
        );
      },
    );
  });

  group('the shelf reorders and removes, and is inert in every other way', () {
    testWidgets('Given the shelf, Then its covers do not carry the shelves own '
        'drag', (tester) async {
      await _pump(tester, [_shelf()]);

      // The covers *are* draggable now — but as `ReadingBookDrag`, which no plank can
      // accept, and which cannot be satisfied by a book lifted off one. That type is the
      // whole enforcement: a `ShelfBookDrag` here would be accepted by every shelf below,
      // and `moveBookToShelf` would rewrite `shelf_id` without touching `status`, so the
      // book would bounce straight back onto this shelf with nothing visibly changed.
      expect(
        find.descendant(
          of: _readingShelf(),
          matching: find.byType(LongPressDraggable<ShelfBookDrag>),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _readingShelf(),
          matching: find.byType(LongPressDraggable<ReadingBookDrag>),
        ),
        findsOne,
      );
    });

    testWidgets('Given the shelf, Then no queue book can be dropped on it', (
      tester,
    ) async {
      await _pump(tester, [_shelf()]);

      // A drop from a plank would mean "start reading this", which is a claim about the
      // book rather than about where it is filed — and `book_info_bottom_sheet` owns that
      // claim behind an explicit tap, where a slightly overshot drag cannot reach it.
      expect(
        find.descendant(
          of: _readingShelf(),
          matching: find.byType(DragTarget<ShelfBookDrag>),
        ),
        findsNothing,
      );
    });

    testWidgets('Given a long press on an open cover, Then edit mode is entered', (
      tester,
    ) async {
      // **Reversed, deliberately.** This shelf shipped refusing to enter edit mode, on
      // the grounds that nothing about it was editable. Its *arrangement* is, now, and
      // the arrangement is the reader's rather than the app's — so a hold here does what
      // a hold on any other row does. Two rows on one screen answering the same gesture
      // differently is the kind of thing that reads as a bug.
      //
      // One hold, not two: the draggable exists in view mode as well, keyed so its
      // element survives the rebuild, because a drag cannot adopt a pointer that is
      // already down. So the hold that opens edit mode also leaves the cover carried.
      await _pump(tester, [_shelf()]);

      final gesture = await tester.startGesture(
        tester.getCenter(
          find
              .descendant(
                of: _readingShelf(),
                matching: find.byType(BookWidget),
              )
              .first,
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 900));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 600));

      expect(isEditing(), isTrue);
    });

    testWidgets(
      'Given edit mode, Then every open cover wobbles and carries a remove badge',
      (tester) async {
        // **Inverted, deliberately, and this is the second reversal on this shelf.** It
        // pinned `findsNothing` for `delete_book_r0` on the reasoning that the Reading shelf
        // "is not a place the reader arranges" — a sentence that had already stopped being
        // true when the reorder landed. A cover that wobbles under a hold and then answers
        // half the gestures a wobbling cover answers on every other row is not a restraint
        // a reader can learn; it reads as the badge having failed to draw.
        await _pump(tester, [_shelf(reading: 2)]);
        await enterEditMode(tester);

        expect(isEditing(), isTrue);
        expect(find.byKey(const ValueKey('delete_book_r0')), findsOne);
        expect(find.byKey(const ValueKey('delete_book_r1')), findsOne);
        // Still true of the shelves below, which is the whole point: the two rows behave
        // the same.
        expect(find.byKey(const ValueKey('delete_book_w0')), findsOne);

        // The wobble comes from the tile rather than from this row, so the honest assertion
        // is that the tile has been told it is editing — and then that the `Wiggle` it wraps
        // itself in is actually running.
        for (final tile in tester.widgetList<ShelfBookTile>(_readingCovers())) {
          expect(tile.isEditMode, isTrue);
          expect(tile.deleteBadge, isNotNull);
        }
        expect(
          tester
              .widgetList<Wiggle>(
                find.descendant(
                  of: _readingShelf(),
                  matching: find.byType(Wiggle),
                ),
              )
              .every((w) => w.enabled),
          isTrue,
        );
      },
    );

    testWidgets(
      'Given the resting shelf, Then no cover wobbles or carries a badge',
      (tester) async {
        await _pump(tester, [_shelf()]);

        expect(isEditing(), isFalse);
        expect(find.byKey(const ValueKey('delete_book_r0')), findsNothing);
        expect(
          tester.widget<ShelfBookTile>(_readingCovers().first).isEditMode,
          isFalse,
        );
      },
    );

    testWidgets(
      'Given edit mode, When an open cover\'s badge is tapped, Then the delete '
      'confirmation is asked for',
      (tester) async {
        await _pump(tester, [_shelf()]);
        await enterEditMode(tester);

        // Off-centre by 6pt for the reason `library_delete_book_test` does the same: the
        // badge is a 44pt target around a 22pt disc and the row's own gesture arena sits
        // under its middle.
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('delete_book_r0'))) +
              const Offset(6, 6),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // The badge is not the delete — it opens the same confirmation a queue book's does,
        // and `_onDeleteBook` is shelf-agnostic, so an open book needs no second path.
        expect(find.text('Delete this?'), findsOne);
      },
    );
  });
}
