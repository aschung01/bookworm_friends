// The ribbon reads the reading position.
//
// The mark slides **across the cover's top edge, gutter to fore-edge** — which is
// what a bookmark in a closed book does, and the one encoding of position that never
// leaves the cover. Earlier versions made the mark's *length* carry the value,
// hanging it further down the page the deeper in you were; that had a dead zone at
// the low end (the asset's height is a floor) and, worse, it reached the shelf label
// and the band and covered them. This track cannot, because it stops at the cover.
//
// **Display only.** Nothing here writes anything. Field research settled that: Fable,
// Goodreads and Life Reset all show a position on a cover and none of them makes the
// cover the input device. The mark reads, a sheet asks.
//
// The property worth guarding hardest is the **null** one. Every book in the library
// has a null position on the day the column ships, so null must be the shipped pin
// and not the gutter — otherwise the release redraws every reading shelf to announce
// that the app knows nothing.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';

void main() {
  // A shelf cover: 126.6pt tall at the app's 2:3 aspect.
  const shelfCover = 84.4;

  group('the track', () {
    test('Given no position, Then the ribbon keeps the shipped pin', () {
      // The whole compatibility story. Not the gutter, not the middle — exactly
      // where readers already know it.
      expect(
        readingBookmarkInsetFor(null, coverWidth: shelfCover),
        kReadingBookmarkInset,
      );
    });

    test('Given 100%, Then the ribbon is at the shipped pin too', () {
      // The far end of the track *is* the pin, so a book being finished does not
      // move the mark anywhere new.
      expect(
        readingBookmarkInsetFor(1, coverWidth: shelfCover),
        closeTo(kReadingBookmarkInset, 1e-9),
      );
    });

    test('Given 0%, Then the ribbon sits at the gutter, not over it', () {
      // A bookmark cannot be inside the binding. The near end is the drawn binding
      // band, 8.2% of the cover's width.
      final inset = readingBookmarkInsetFor(0, coverWidth: shelfCover);
      final ribbonLeft = shelfCover - inset - 4.5 - 13.5;
      expect(ribbonLeft, closeTo(shelfCover * 0.082, 0.01));
    });

    test('moves monotonically in from the fore-edge as the position falls', () {
      // Deeper into the book means further right, which is the direction a real
      // bookmark moves. Expressed as insets, so the numbers *fall*.
      var previous = double.infinity;
      for (var stop = 0; stop <= 100; stop++) {
        final inset = readingBookmarkInsetFor(
          stop / 100,
          coverWidth: shelfCover,
        );
        expect(inset, lessThan(previous));
        previous = inset;
      }
    });

    test('Given 46%, Then the ribbon is about 46% of the way along', () {
      final gutter = readingBookmarkInsetFor(0, coverWidth: shelfCover);
      final pin = readingBookmarkInsetFor(1, coverWidth: shelfCover);
      final mid = readingBookmarkInsetFor(0.46, coverWidth: shelfCover);
      expect(mid, closeTo(pin + 0.54 * (gutter - pin), 1e-9));
    });
  });

  group('the Library Card draws the same track, smaller', () {
    // The card's ribbon is scaled by cover height over the shelf book's 124, and its
    // track has to shrink with it — or the card's mark reads a different value at a
    // different size, which is precisely the two-marks-for-one-state failure the
    // shared `ReadingBookmark` exists to have ended.
    const cardCover = 28.0;
    final scale = cardCover / kDefaultCoverAspectForTest / kReadingBookmarkBook;

    test('Given no position, Then the pin scales with the ribbon', () {
      expect(
        readingBookmarkInsetFor(null, coverWidth: cardCover, scale: scale),
        closeTo(kReadingBookmarkInset * scale, 1e-9),
      );
    });

    test('a position lands at the same fraction of the smaller track', () {
      double fraction(double coverWidth, double s) {
        final gutter = readingBookmarkInsetFor(
          0,
          coverWidth: coverWidth,
          scale: s,
        );
        final pin = readingBookmarkInsetFor(
          1,
          coverWidth: coverWidth,
          scale: s,
        );
        final mid = readingBookmarkInsetFor(
          0.46,
          coverWidth: coverWidth,
          scale: s,
        );
        return (gutter - mid) / (gutter - pin);
      }

      expect(
        fraction(cardCover, scale),
        closeTo(fraction(shelfCover, 1), 1e-9),
      );
    });
  });

  group('degenerate covers', () {
    test('Given a cover too narrow for a track, Then the pin is used', () {
      // The ribbon is 13.5 wide with 4.5 of bleed, so below roughly 26pt there is
      // no travel to distribute. Falling back to the pin keeps the mark on the
      // cover rather than pushing it off the left edge.
      expect(readingBookmarkInsetFor(0, coverWidth: 20), kReadingBookmarkInset);
    });

    test('clamps a value outside 0..1 rather than leaving the cover', () {
      // The column's CHECK makes these unreachable through the app, but a value
      // read from a row is still a value from outside this file.
      expect(
        readingBookmarkInsetFor(1.5, coverWidth: shelfCover),
        readingBookmarkInsetFor(1, coverWidth: shelfCover),
      );
      expect(
        readingBookmarkInsetFor(-0.5, coverWidth: shelfCover),
        readingBookmarkInsetFor(0, coverWidth: shelfCover),
      );
    });
  });
}

/// The app's cover aspect, restated here rather than imported, so this file does not
/// pull the whole geometry library in for one ratio.
const double kDefaultCoverAspectForTest = 2 / 3;
