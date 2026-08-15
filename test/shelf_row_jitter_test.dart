// Guards the shelf row against two ways the height jitter can be silently
// destroyed.
//
//   1. The row must reserve `baseHeight * maxHeightFactor`. Sized to the base,
//      it clips every book that hashes tall.
//   2. Each item must be laid out under LOOSENED constraints. A horizontal
//      ListView hands its children a tight cross-axis height, and a SizedBox
//      under a tight constraint is stretched to fill it — which would snap every
//      book back to identical heights with no error and no visual clue beyond
//      "the jitter isn't working".
//
// Both are checked by measuring rendered geometry, because neither failure
// throws.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

import 'support/home_page_harness.dart';

/// Picks the ISBN with the most extreme height factor from a candidate sweep, so
/// the test keeps testing the extremes even if the hash is ever changed.
String _extremeIsbn({required bool tallest}) {
  String best = '9781000000000';
  var bestFactor = BookJitter.fromIsbn(best).heightFactor;
  for (var i = 0; i < 600; i++) {
    final candidate = '978${1000000000 + i * 7919}';
    final factor = BookJitter.fromIsbn(candidate).heightFactor;
    if (tallest ? factor > bestFactor : factor < bestFactor) {
      best = candidate;
      bestFactor = factor;
    }
  }
  return best;
}

Finder _chassisOf(String isbn) => find.descendant(
  of: find.byWidgetPredicate((w) => w is BookWidget && w.isbn == isbn),
  matching: find.byType(BookChassis),
);

double _baseHeightOf(WidgetTester tester, String isbn) => tester
    .widget<BookWidget>(
      find.byWidgetPredicate((w) => w is BookWidget && w.isbn == isbn),
    )
    .height!;

void main() {
  test('bookRowExtent reserves the maximum the jitter can produce', () {
    expect(bookRowExtent(100), closeTo(100 * BookJitter.maxHeightFactor, 1e-9));
    expect(bookRowExtent(100), greaterThan(100));
  });

  testWidgets('books keep their jittered heights inside the shelf row', (
    tester,
  ) async {
    final tall = _extremeIsbn(tallest: true);
    final short = _extremeIsbn(tallest: false);
    // Sanity: the sweep found genuinely different books.
    expect(
      BookJitter.fromIsbn(tall).heightFactor,
      greaterThan(BookJitter.fromIsbn(short).heightFactor + 0.05),
    );

    Book book(String isbn, int position) => Book(
      id: isbn,
      userId: 'u',
      shelfId: 's1',
      isbn: isbn,
      title: 'Book $position',
      thumbnail: '',
      status: 0,
      position: position,
      createdAt: DateTime(2024),
    );

    await pumpHome(
      tester,
      shelves: [
        testShelf('s1', [book(tall, 0), book(short, 1)], name: 'Shelf'),
      ],
    );

    for (final isbn in [tall, short]) {
      final expected =
          _baseHeightOf(tester, isbn) * BookJitter.fromIsbn(isbn).heightFactor;
      expect(
        tester.getSize(_chassisOf(isbn)).height,
        closeTo(expected, 0.5),
        reason:
            'book $isbn was resized by its parent, which means the row is '
            'imposing a tight height constraint and the jitter is lost',
      );
    }
  });

  testWidgets('books of different heights sit on the same shelf line', (
    tester,
  ) async {
    // Bottom-aligned, not top-aligned: a short book must rest on the shelf
    // rather than hang from the top of the row.
    final tall = _extremeIsbn(tallest: true);
    final short = _extremeIsbn(tallest: false);

    Book book(String isbn, int position) => Book(
      id: isbn,
      userId: 'u',
      shelfId: 's1',
      isbn: isbn,
      title: 'Book $position',
      thumbnail: '',
      status: 0,
      position: position,
      createdAt: DateTime(2024),
    );

    await pumpHome(
      tester,
      shelves: [
        testShelf('s1', [book(tall, 0), book(short, 1)], name: 'Shelf'),
      ],
    );

    final tallBottom = tester.getBottomLeft(_chassisOf(tall)).dy;
    final shortBottom = tester.getBottomLeft(_chassisOf(short)).dy;
    expect(shortBottom, closeTo(tallBottom, 0.5));

    // And the tall one really is taller, so the alignment isn't passing by
    // virtue of both books being the same size.
    expect(
      tester.getSize(_chassisOf(tall)).height,
      greaterThan(tester.getSize(_chassisOf(short)).height + 2),
    );
  });
}
