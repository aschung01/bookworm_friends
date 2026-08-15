// Guards for the deterministic book size variation.
//
// The golden values below are the whole point of this file. Book heights are
// derived from a hash of the ISBN, so if that hash ever changes, every book on
// every shelf silently changes shape — a regression with no error message and
// no crash. Pinning the hash output means any change to `bookHash` fails loudly
// here instead.
//
// The goldens were produced by running the implementation, not derived by hand.
// If a deliberate change to the jitter ranges is made, these must be
// regenerated in the same commit.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

/// Deterministic pseudo-ISBNs, so the range sweeps don't depend on a seed.
Iterable<String> _syntheticIsbns(int count) =>
    Iterable.generate(count, (i) => '978${(1000000000 + i * 7919)}');

void main() {
  group('bookHash', () {
    test('is pinned to known values', () {
      // Given a fixed set of ISBNs, When hashed, Then the output never moves.
      expect(bookHash('9788936434120'), 848182861);
      expect(bookHash('9780451524935'), 1030674525);
      expect(bookHash('9780141439518'), 3499888009);
      expect(bookHash('9791188331796'), 1196771503);
      expect(bookHash('9788954682152'), 753300405);
      expect(bookHash('OL12345W'), 3637877494);
    });

    test('stays inside 32 bits', () {
      // The web target computes this in doubles; anything above 2^32 means the
      // split multiply has lost its mask.
      for (final isbn in _syntheticIsbns(2000)) {
        final hash = bookHash(isbn);
        expect(hash, greaterThanOrEqualTo(0));
        expect(hash, lessThan(0x100000000));
      }
    });

    test('handles multi-byte code units without collapsing', () {
      // Not expected for ISBNs, but a Google Books volume id or a stray title
      // must not all hash to the same value.
      final hashes = {bookHash('아몬드'), bookHash('소년이 온다'), bookHash('책')};
      expect(hashes.length, 3);
    });

    test('is order sensitive', () {
      expect(bookHash('9780451524935'), isNot(bookHash('9780451524953')));
    });
  });

  group('BookJitter', () {
    test('is pinned to known values', () {
      // Given the same ISBNs, When jitter is derived, Then a book keeps its
      // exact proportions across releases.
      void expectJitter(String isbn, double height, double thickness) {
        final jitter = BookJitter.fromIsbn(isbn);
        expect(jitter.heightFactor, closeTo(height, 1e-9));
        expect(jitter.thicknessFactor, closeTo(thickness, 1e-9));
      }

      expectJitter('9788936434120', 0.9692039368, 0.2436978714);
      expectJitter('9780451524935', 1.0414218357, 0.2487956054);
      expectJitter('9780141439518', 0.9463447013, 0.3177871366);
      expectJitter('9791188331796', 0.9740709545, 0.2534373999);
      expectJitter('9788954682152', 0.9942384985, 0.2410464637);
      expectJitter('OL12345W', 1.0126390478, 0.3216415656);
    });

    test('stays within the declared ranges', () {
      // ±6% height is the ceiling agreed in the design — beyond it the shelf
      // stops reading as a shelf.
      for (final isbn in _syntheticIsbns(5000)) {
        final jitter = BookJitter.fromIsbn(isbn);
        expect(
          jitter.heightFactor,
          inInclusiveRange(
            BookJitter.minHeightFactor,
            BookJitter.maxHeightFactor,
          ),
        );
        expect(
          jitter.thicknessFactor,
          inInclusiveRange(
            BookJitter.minThicknessFactor,
            BookJitter.maxThicknessFactor,
          ),
        );
      }
    });

    test('uses the full range rather than clustering', () {
      // A hash that only ever produced mid-range values would technically pass
      // the range check while producing a visually uniform shelf.
      final factors = _syntheticIsbns(
        500,
      ).map((i) => BookJitter.fromIsbn(i).heightFactor).toList();
      expect(factors.reduce((a, b) => a < b ? a : b), lessThan(0.95));
      expect(factors.reduce((a, b) => a > b ? a : b), greaterThan(1.05));
    });

    test('falls back to neutral for an empty ISBN', () {
      expect(BookJitter.fromIsbn(''), BookJitter.neutral);
      expect(BookJitter.neutral.heightFactor, 1.0);
    });

    test('is stable across repeated calls', () {
      final first = BookJitter.fromIsbn('9788936434120');
      final second = BookJitter.fromIsbn('9788936434120');
      expect(first, second);
    });

    test('decorrelates height from thickness', () {
      // Drawn from disjoint bit ranges. If they shared bits, tall books would
      // also always be thick ones.
      final samples = _syntheticIsbns(1000).map(BookJitter.fromIsbn).toList();
      final meanHeight =
          samples.map((s) => s.heightFactor).reduce((a, b) => a + b) /
          samples.length;
      final meanThickness =
          samples.map((s) => s.thicknessFactor).reduce((a, b) => a + b) /
          samples.length;
      var covariance = 0.0;
      for (final sample in samples) {
        covariance +=
            (sample.heightFactor - meanHeight) *
            (sample.thicknessFactor - meanThickness);
      }
      covariance /= samples.length;
      expect(covariance.abs(), lessThan(1e-3));
    });
  });

  group('BookMetrics', () {
    BookMetrics metrics({double baseHeight = 130, double aspect = 0.66}) =>
        BookMetrics.from(
          baseHeight: baseHeight,
          coverAspect: aspect,
          jitter: BookJitter.neutral,
        );

    test('derives width from the cover aspect ratio', () {
      final m = metrics();
      expect(m.height, closeTo(130, 1e-9));
      expect(m.width, closeTo(130 * 0.66, 1e-9));
    });

    test('applies the height factor and lets width follow', () {
      // A book that hashes tall must also be proportionally wider, otherwise
      // the cover would be stretched.
      final m = BookMetrics.from(
        baseHeight: 130,
        coverAspect: 0.66,
        jitter: const BookJitter(1.06, 0.28),
      );
      expect(m.height, closeTo(137.8, 1e-9));
      expect(m.width / m.height, closeTo(0.66, 1e-9));
    });

    test('scales perspective with width so depth is size invariant', () {
      final small = metrics(baseHeight: 130);
      final large = metrics(baseHeight: 260);
      expect(
        small.perspective / small.width,
        closeTo(large.perspective / large.width, 1e-9),
      );
      expect(
        small.perspective,
        closeTo(small.width * kBookPerspectiveRatio, 1e-9),
      );
    });

    test('floors corner radii so small books keep a visible curve', () {
      final tiny = metrics(baseHeight: 20);
      expect(tiny.leftRadius, 2.0);
      expect(tiny.rightRadius, 2.0);
    });

    test('caps corner radii at the reference values', () {
      final huge = metrics(baseHeight: 2000);
      expect(huge.leftRadius, 6.0);
      expect(huge.rightRadius, 4.0);
    });

    test('keeps the spine corner rounder than the fore-edge corner', () {
      final m = metrics(baseHeight: 300);
      expect(m.leftRadius, greaterThan(m.rightRadius));
    });

    test('floors the shadow scale so shadows never vanish', () {
      expect(metrics(baseHeight: 10).shadowScale, 0.35);
    });

    test('derives the binding band from the reference 8.2%', () {
      final m = metrics();
      expect(m.bindingWidth, closeTo(m.width * 0.082, 1e-9));
    });
  });
}
