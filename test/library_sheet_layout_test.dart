// Does the "Books read" sheet cover the library, or compress it?
//
// It reads as covering -- the sheet's top edge advances up the screen and the
// shelves disappear behind it -- but the two are siblings in a `Column`, the
// library inside an `Expanded`, so the sheet cannot overlap anything: it takes
// its height from layout and the library is given whatever is left. Nothing is
// ever hidden underneath it.
//
// The distinction is invisible in the common case, because the shelf list is
// top-anchored: a viewport shrinking from the bottom looks exactly like a panel
// sliding over it. It stops being invisible when it matters -- the library's
// scrollable extent changes with the sheet, and there is no band of library
// hiding under the panel to scroll into view.
//
// Pinned because Phase 1 rebuilds this screen around a persistent background,
// and "the sheet floats over the library" is a change of behaviour, not a
// refactor. If the shell adopts it, this test should fail and be rewritten.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';

import 'support/home_page_harness.dart';

/// The library's scroll area. `RefreshIndicator` wraps exactly the shelf list,
/// which makes it a stable handle on the part the sheet is accused of covering.
final _library = find.byType(RefreshIndicator);
final _sheet = find.byType(FinishedBooksSheet);

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

void main() {
  group('Books read sheet vs the library above it', () {
    testWidgets(
      'Given the library and the sheet, When laid out, Then their boxes meet '
      'without overlapping',
      (tester) async {
        await _pumpWithPile(tester);

        final library = tester.getRect(_library);
        final sheet = tester.getRect(_sheet);

        expect(
          library.overlaps(sheet),
          isFalse,
          reason:
              'a covering sheet would paint over the library; these are '
              'siblings in a Column, so library $library must stop where '
              'sheet $sheet starts',
        );
        // Flush, not merely disjoint: no gap, no overlap.
        expect(library.bottom, closeTo(sheet.top, 0.5));
      },
    );

    testWidgets(
      'Given the sheet springs shut, When it collapses, Then the library grows '
      'into the space it freed',
      (tester) async {
        await _pumpWithPile(tester);
        final expanded = tester.getRect(_library);
        final expandedSheet = tester.getRect(_sheet);

        // Edit mode is the one way to move the sheet without simulating a drag:
        // it springs shut and goes inert. The spring is under-damped, so it
        // overshoots and needs time to settle -- and `pumpAndSettle` is not an
        // option, because the covers wiggle on a repeating animation in edit mode.
        await enterEditMode(tester);
        await tester.pump(const Duration(seconds: 2));

        final collapsed = tester.getRect(_library);
        final collapsedSheet = tester.getRect(_sheet);

        expect(
          collapsedSheet.height,
          lessThan(expandedSheet.height),
          reason: 'edit mode should have collapsed the sheet',
        );
        expect(
          collapsed.height,
          greaterThan(expanded.height),
          reason:
              'the library is Expanded, so every pixel the sheet gives up '
              'becomes library viewport -- it is compressed by the sheet, not '
              'covered by it',
        );
        // The freed pixels all went to the library, none to a gap.
        expect(
          collapsed.height - expanded.height,
          closeTo(expandedSheet.height - collapsedSheet.height, 0.5),
        );
      },
    );
  });
}
