// Does the "Books read" sheet cover the library, or compress it?
//
// **It covers it, and this file is the record of the change.** It used to assert the
// opposite, and said so at the top: the two were siblings in a `Column` with the
// library inside an `Expanded`, so the sheet could not overlap anything -- it took
// its height from layout and the library was given what was left. The comment ended
// "if the shell adopts [floating], this test should fail and be rewritten", and the
// shell has: the sheet has to be able to rise over the shell's bar, and nothing in a
// `Column` can be drawn over a widget that is not in it.
//
// So the invariants moved rather than disappeared, and the new ones are worth more:
//
//   overlap        the sheet is drawn over the library, up to the middle of the
//                  library bar when fully expanded -- over most of the bar, which
//                  is the point.
//   nothing lost   the library no longer shrinks to make room, so the shelf list is
//                  inset by the height of a collapsed sheet instead. That number is a
//                  measurement the sheet publishes (`onRestingExtent`); if it is ever
//                  wrong, the last shelf is stranded behind the sheet with no way to
//                  scroll it clear, which is exactly what the `Column` used to make
//                  impossible.
//   stable         the library's box does not change when the sheet moves. What
//                  changes is how much of it you can see.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

import 'support/home_page_harness.dart';

/// The library's scroll area. `RefreshIndicator` wraps exactly the shelf list,
/// which makes it a stable handle on the part the sheet is accused of covering.
final _library = find.byType(RefreshIndicator);
final _sheet = find.byType(FinishedBooksSheet);

/// The shelf list itself, whose bottom padding is what keeps the last shelf
/// reachable now that a sheet floats over it.
final _shelfList = find.descendant(
  of: _library,
  matching: find.byType(SingleChildScrollView),
);

/// Read books, so the sheet has a natural height worth collapsing. With an empty
/// pile its two snap positions are the same height and nothing moves.
List<Book> _readBooks() => [
  testBook('r1', 's1', position: 1, title: 'Dune', status: bookStatusFinished),
  testBook('r2', 's1', position: 2, title: 'Circe', status: bookStatusFinished),
  testBook(
    'r3',
    's1',
    position: 3,
    title: 'Beloved',
    status: bookStatusFinished,
  ),
];

Future<void> _pumpWithPile(WidgetTester tester) => pumpHome(
  tester,
  extraOverrides: [
    finishedBooksProvider.overrideWith((ref) async => _readBooks()),
  ],
);

double _listBottomPadding(WidgetTester tester) =>
    (tester.widget<SingleChildScrollView>(_shelfList).padding as EdgeInsets)
        .bottom;

void main() {
  group('Books read sheet vs the library under it', () {
    testWidgets(
      'Given the library and the sheet, When laid out, Then the sheet is drawn '
      'over the library rather than beside it',
      (tester) async {
        await _pumpWithPile(tester);

        final library = tester.getRect(_library);
        final sheet = tester.getRect(_sheet);

        expect(
          library.overlaps(sheet),
          isTrue,
          reason:
              'siblings in a Column could not overlap; these are stacked, which '
              'is what lets the sheet rise over the bar. library $library, '
              'sheet $sheet',
        );
        expect(
          sheet.bottom,
          closeTo(library.bottom, 0.5),
          reason: 'both reach the bottom of the screen',
        );
      },
    );

    testWidgets(
      'Given a sheet floating over the shelves, When laid out, Then the list is '
      'inset by exactly the height the sheet rests at',
      (tester) async {
        // The invariant that replaces "the library is given what is left". Nothing
        // shrinks for the sheet now, so if this number is wrong the bottom shelf is
        // unreachable -- and it cannot be computed, only measured, because the
        // sheet's collapsed height is its header's height.
        await _pumpWithPile(tester);

        expect(
          _listBottomPadding(tester),
          closeTo(16 + tester.getRect(_sheet).height, 0.5),
          reason:
              'the 16 the list always had, plus the band the collapsed sheet '
              'covers',
        );
      },
    );

    testWidgets(
      'Given the sheet springs shut, When it collapses, Then the library keeps its '
      'box and only the visible band changes',
      (tester) async {
        await _pumpWithPile(tester);
        final expandedLibrary = tester.getRect(_library);
        final expandedSheet = tester.getRect(_sheet);

        // Edit mode is the one way to move the sheet without simulating a drag:
        // it springs shut and goes inert. The spring is under-damped, so it
        // overshoots and needs time to settle -- and `pumpAndSettle` is not an
        // option, because the covers wiggle on a repeating animation in edit mode.
        await enterEditMode(tester);
        await tester.pump(const Duration(seconds: 2));

        final collapsedSheet = tester.getRect(_sheet);

        expect(
          collapsedSheet.height,
          lessThan(expandedSheet.height),
          reason: 'edit mode should have collapsed the sheet',
        );
        expect(
          tester.getRect(_library),
          expandedLibrary,
          reason:
              'the library is not laid out around the sheet any more, so moving '
              'the sheet must not resize it',
        );
        expect(
          collapsedSheet.top,
          greaterThan(expandedSheet.top),
          reason: 'what the collapse gives back is visible library, not layout',
        );
      },
    );

    testWidgets(
      'Given the sheet is expanded, When it reaches its cap, Then it covers the '
      "shell's bar as well as the library",
      (tester) async {
        // The whole reason the `Column` had to go. The bar is behind the pager in
        // the stack, so a sheet inside a page paints over it -- and the expanded cap
        // is the middle of the library bar row, not the top of the screen: a fully
        // expanded sheet still leaves the top half of "My Library" visible.
        await _pumpWithPile(tester);
        await tester.tap(find.byType(SheetGrabHandle));
        await tester.pumpAndSettle();

        final sheet = tester.getRect(_sheet);

        expect(sheet.top, closeTo(28, 1));
        expect(
          sheet.top,
          lessThan(tester.getRect(_library).top),
          reason:
              'above where the library starts is above the bar, which is what '
              '"fully expandable" had to mean',
        );
        expect(
          find.text('My Library'),
          findsOneWidget,
          reason:
              'the bar is covered, not dismantled -- it comes back with the sheet',
        );
      },
    );
    testWidgets(
      'Given the pager is drawn over the bar, When one of the bar\'s own buttons is '
      'tapped, Then the tap still reaches it',
      (tester) async {
        // The bar is behind the pager so that a sheet inside a page can cover it,
        // and that only works because the pager *defers* the hit tests it does not
        // want: `PageView` swallows them by default, and with the default every
        // button in the bar would be dead. Nothing about the layout looks wrong when
        // it is, which is why this is a tap and not a rect.
        await _pumpWithPile(tester);
        await enterEditMode(tester);
        await tester.pump(const Duration(seconds: 2));
        expect(libraryDoneButton(), findsOneWidget, reason: 'an edit is on');

        await tester.tap(libraryDoneButton());
        await tester.pump(const Duration(seconds: 2));

        expect(
          isEditing(),
          isFalse,
          reason: "Done is in the bar, under the pager, and it has to work",
        );
      },
    );
  });
}
