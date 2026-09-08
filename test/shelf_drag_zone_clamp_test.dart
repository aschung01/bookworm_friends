// A shelf is drawn as two regions — the books in progress, then everything else —
// and a drag cannot cross between them.
//
// `clampDropIndex` is that rule, kept as a pure function rather than buried in the
// row's pointer arithmetic. What it buys is that **the gap never opens where the
// book cannot land**: the index it returns drives the gap previewing the drop, so a
// value that had to be corrected on release would be a preview that lied and a book
// that visibly springs elsewhere.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/providers/library_provider.dart';

import 'support/home_page_harness.dart';

/// The rule applied to a row of [rowLength] whose first [headCount] books are in
/// progress.
int _clamp(
  int index, {
  int headCount = 2,
  int rowLength = 5,
  bool reading = false,
}) => clampDropIndex(
  index,
  headCount: headCount,
  rowLength: rowLength,
  reading: reading,
);

void main() {
  group('clampDropIndex, book not in progress', () {
    test(
      'Given an index inside the head, When clamped, Then it lands at the head '
      'boundary',
      () {
        // Without this the gap would open at 0 and the book would spring back on
        // release, which is the whole failure being prevented.
        expect(_clamp(0), 2);
        expect(_clamp(1), 2);
      },
    );

    test(
      'Given an index at or past the boundary, When clamped, Then it is left '
      'alone',
      () {
        expect(_clamp(2), 2);
        expect(_clamp(3), 3);
        expect(_clamp(5), 5);
      },
    );

    test(
      'Given an index past the row, When clamped, Then it stops at the end',
      () {
        expect(_clamp(9), 5);
      },
    );
  });

  group('clampDropIndex, book in progress', () {
    test(
      'Given an index past the head, When clamped, Then it stays in the head',
      () {
        expect(_clamp(4, reading: true), 2);
        expect(_clamp(9, reading: true), 2);
      },
    );

    test(
      'Given an index inside the head, When clamped, Then it is left alone',
      () {
        expect(_clamp(0, reading: true), 0);
        expect(_clamp(1, reading: true), 1);
      },
    );

    test('Given the head boundary itself, When clamped, Then it is allowed', () {
      // `headCount` puts the book last among those in progress, which is a legal
      // place for it to be.
      expect(_clamp(2, reading: true), 2);
    });
  });

  group('clampDropIndex degenerate rows', () {
    test(
      'Given no book in progress, When clamped, Then nothing is constrained',
      () {
        // The ordinary shelf. The clamp has to be invisible here or it would change
        // behaviour that predates it.
        for (var i = 0; i <= 5; i++) {
          expect(_clamp(i, headCount: 0), i);
        }
      },
    );

    test(
      'Given every book in progress, When clamped, Then nothing is constrained',
      () {
        for (var i = 0; i <= 5; i++) {
          expect(_clamp(i, headCount: 5, reading: true), i);
        }
      },
    );

    test(
      'Given every book in progress, When a plain book arrives, Then it lands at '
      'the end',
      () {
        // Cross-shelf: a book that is not in progress cannot enter a row that is all
        // head, so the only legal place is after it.
        expect(_clamp(0, headCount: 5, rowLength: 5), 5);
      },
    );

    test('Given an empty row, When clamped, Then it is zero either way', () {
      expect(_clamp(0, headCount: 0, rowLength: 0), 0);
      expect(_clamp(3, headCount: 0, rowLength: 0, reading: true), 0);
    });
  });

  group('readingHeadCount feeds the clamp', () {
    test('Given a promoted shelf, When measured, Then the boundary matches the '
        'drawing', () {
      // The row draws its head from `readingHeadCount` and clamps against the same
      // number, which is what stops the gap and the drop disagreeing.
      final shelf = withReadingFirst([
        testShelf('s1', [
          testBook('plain', 's1'),
          testBook('r1', 's1', status: bookStatusReading),
          testBook('r2', 's1', status: bookStatusReading),
        ]),
      ]).first;

      expect(readingHeadCount(shelf), 2);
      expect(_clamp(0, headCount: readingHeadCount(shelf), rowLength: 3), 2);
    });
  });
}
