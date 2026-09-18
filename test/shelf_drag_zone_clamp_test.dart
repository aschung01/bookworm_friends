// Where a dragged book is allowed to land in a row.
//
// `clampDropIndex` is that rule, kept as a pure function rather than buried in the
// row's pointer arithmetic. What it buys is that **the gap never opens where the
// book cannot land**: the index it returns drives the gap previewing the drop, so a
// value that had to be corrected on release would be a preview that lied and a book
// that visibly springs elsewhere.
//
// **This file used to be four times as long, and the deletion is the point.** A shelf
// was drawn as two regions — the books in progress, then everything else — and a drag
// could not cross between them, so the clamp took a head count and a flag for whether
// the book being carried belonged in that head. `withoutReadingBooks` moved the open
// books onto the Reading shelf entirely, so a shelf row is one homogeneous region and
// the only thing left to clamp against is its own two ends. Everything that used to be
// asserted here about the barrier is now asserted by there being no barrier: see
// `shelf_reading_out_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/providers/library_provider.dart';

/// The rule applied to a row of [rowLength] books.
int _clamp(int index, {int rowLength = 5}) =>
    clampDropIndex(index, rowLength: rowLength);

void main() {
  group('clampDropIndex', () {
    test(
      'Given an index inside the row, When clamped, Then it is left alone',
      () {
        for (var i = 0; i <= 5; i++) {
          expect(_clamp(i), i);
        }
      },
    );

    test('Given an index past the end of the row, When clamped, Then it stops at the '
        'end', () {
      // `rowLength` rather than `rowLength - 1`: the index is an *insertion* point
      // into the row with the dragged book taken out, so one past the last book is
      // the legal "append" position.
      expect(_clamp(6), 5);
      expect(_clamp(99), 5);
    });

    test('Given a negative index, When clamped, Then it stops at the start', () {
      // Reachable from the row's own pointer arithmetic when a finger is left of the
      // first slot, which happens on every drag that starts at the leading edge.
      expect(_clamp(-1), 0);
      expect(_clamp(-40), 0);
    });

    test('Given an empty row, When clamped, Then everything lands at zero', () {
      // An empty shelf is a legitimate destination in edit mode, so this is a real
      // case rather than a degenerate one.
      expect(_clamp(0, rowLength: 0), 0);
      expect(_clamp(3, rowLength: 0), 0);
      expect(_clamp(-3, rowLength: 0), 0);
    });
  });
}
