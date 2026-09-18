// Where a dragged book would land, which both rows have to answer the same way.
//
// `ShelfRow` and `ReadingShelfRow` run different drags — a `ShelfBookDrag` can cross
// shelves, a `ReadingBookDrag` cannot leave its row — but "which slot is the finger over"
// is one question, and this file exists because two implementations of it would drift.
//
// The rule that matters most is the clamp, and it is a claim about honesty rather than
// about bounds: the index drives the gap the row opens to *preview* the drop, so an index
// the drop cannot honour is a gap that lies, and the book visibly springs elsewhere on
// release.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/shelf_drop_index.dart';

void main() {
  group('the finger is measured against each cover s centre', () {
    // Three covers 100 wide, centres at 50, 150, 250.
    const centres = <double?>[50, 150, 250];

    test(
      'Given a finger before the first centre, Then the book lands first',
      () {
        expect(dropIndexForPointer(pointerX: 0, slotCentres: centres), 0);
        expect(dropIndexForPointer(pointerX: 49, slotCentres: centres), 0);
      },
    );

    test(
      'Given a finger exactly on a centre, Then that cover is not stepped over',
      () {
        // `>=` on purpose: a finger resting precisely on the boundary must resolve to one
        // side and stay there, or the gap flickers between two slots on sub-pixel movement.
        expect(dropIndexForPointer(pointerX: 50, slotCentres: centres), 0);
        expect(dropIndexForPointer(pointerX: 150, slotCentres: centres), 1);
      },
    );

    test('Given a finger past a centre, Then the cover is stepped over', () {
      expect(dropIndexForPointer(pointerX: 51, slotCentres: centres), 1);
      expect(dropIndexForPointer(pointerX: 151, slotCentres: centres), 2);
    });

    test('Given a finger past every cover, Then the book lands last', () {
      expect(dropIndexForPointer(pointerX: 9999, slotCentres: centres), 3);
    });
  });

  group('covers with no laid-out box are placed by which end they are off', () {
    // A row builds lazily, so a long row has boxes only for what is on screen. Which end
    // an unmeasured cover is off is enough to place it, and getting this wrong would
    // compute the index against only the built covers.

    test(
      'Given unmeasured covers before the built ones, Then they count as behind '
      'the finger',
      () {
        // Two scrolled off to the left, then covers at 50 and 150.
        const centres = <double?>[null, null, 50, 150];
        // Before the first *measured* centre, so the finger is at the start of what is
        // built — but two covers precede it.
        expect(dropIndexForPointer(pointerX: 10, slotCentres: centres), 2);
        expect(dropIndexForPointer(pointerX: 100, slotCentres: centres), 3);
      },
    );

    test('Given unmeasured covers after the built ones, Then the walk stops', () {
      // Once a cover has been measured, an unmeasured one is off the *far* end and
      // everything from there on is ahead of the finger.
      const centres = <double?>[50, 150, null, null];
      expect(dropIndexForPointer(pointerX: 100, slotCentres: centres), 1);
      expect(dropIndexForPointer(pointerX: 9999, slotCentres: centres), 2);
    });

    test('Given nothing laid out at all, Then the book lands at the end', () {
      // Reachable on the frame a row is first built. Every slot counts as behind the
      // finger, and the clamp keeps that inside the row.
      expect(
        dropIndexForPointer(pointerX: 100, slotCentres: const [null, null]),
        2,
      );
    });
  });

  group('the result is clamped to the row', () {
    test('Given an empty row, Then the only index is 0', () {
      expect(dropIndexForPointer(pointerX: 100, slotCentres: const []), 0);
    });

    test('Given any pointer, Then the index is a valid insertion point', () {
      // The invariant the clamp exists for: whatever the pointer, the gap opens somewhere
      // the book can actually be inserted.
      const centres = <double?>[50, 150, 250];
      for (final x in [-9999.0, -1.0, 0.0, 75.0, 200.0, 9999.0]) {
        final index = dropIndexForPointer(pointerX: x, slotCentres: centres);
        expect(index, greaterThanOrEqualTo(0));
        expect(index, lessThanOrEqualTo(centres.length));
      }
    });
  });
}
