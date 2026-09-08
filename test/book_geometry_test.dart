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
      //
      // Pinned as each book's *normalised position* within the range rather than
      // as the resolved factor. What must never drift is the hash: if
      // `String.hashCode` or this FNV implementation changed, every book on every
      // shelf would silently resize, which is the regression worth a golden test.
      // The ranges themselves are design values that get tuned by eye — thickness
      // has moved three times — and asserting resolved factors made every one of
      // those tweaks look like a hash regression and cost a golden rewrite. This
      // form is invariant to retuning min/max and still fails loudly if the hash
      // moves.
      void expectJitter(String isbn, double heightAt, double thicknessAt) {
        final jitter = BookJitter.fromIsbn(isbn);
        expect(
          (jitter.heightFactor - BookJitter.minHeightFactor) /
              (BookJitter.maxHeightFactor - BookJitter.minHeightFactor),
          closeTo(heightAt, 1e-9),
          reason: '$isbn moved within the height range',
        );
        expect(
          (jitter.thicknessFactor - BookJitter.minThicknessFactor) /
              (BookJitter.maxThicknessFactor - BookJitter.minThicknessFactor),
          closeTo(thicknessAt, 1e-9),
          reason: '$isbn moved within the thickness range',
        );
      }

      expectJitter('9788936434120', 0.243366140230, 0.197482261387);
      expectJitter('9780451524935', 0.845181963836, 0.239963378347);
      expectJitter('9780141439518', 0.052872510872, 0.814892805371);
      expectJitter('9791188331796', 0.283924620432, 0.278644998856);
      expectJitter('9788954682152', 0.451987487602, 0.175387197681);
      expectJitter('OL12345W', 0.605325398642, 0.847013046464);
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

    group('thickness from page count', () {
      // Page count decides where a book sits in the thickness range, replacing the
      // hash. Coverage is low — Kakao reports none at all — but a reader cannot
      // distinguish a hashed thickness from a measured one, so partial data makes
      // part of the shelf correct and worsens nothing.

      double thickness(int? pages) => BookJitter.fromIsbn(
        '9788936434120',
        pageCount: pages,
      ).thicknessFactor;

      test('maps 300 pages to the middle of the range', () {
        // The archetypal trade book lands mid-range by construction: the curve is
        // logarithmic between 100 and 900, and 300 is their geometric mean.
        expect(bookThicknessPositionFromPages(300), closeTo(0.5, 1e-9));
      });

      test('anchors the ends of the range', () {
        expect(
          bookThicknessPositionFromPages(kBookMinPageCount),
          closeTo(0, 1e-9),
        );
        expect(
          bookThicknessPositionFromPages(kBookMaxPageCount),
          closeTo(1, 1e-9),
        );
      });

      test('compresses the long tail instead of letting it dominate', () {
        // A 1,500-page reference book must not be able to pin the top of the range
        // and squash every novel toward the bottom.
        expect(bookThicknessPositionFromPages(1500), 1.0);
        expect(bookThicknessPositionFromPages(3000), 1.0);
        // And a short book clamps rather than going negative.
        expect(bookThicknessPositionFromPages(40), 0.0);
      });

      test('thickness rises monotonically with page count', () {
        var previous = thickness(kBookMinCrediblePageCount);
        for (final pages in [50, 120, 200, 300, 450, 700, 900]) {
          final next = thickness(pages);
          expect(
            next,
            greaterThanOrEqualTo(previous),
            reason: 'at $pages pages',
          );
          previous = next;
        }
      });

      test('stays inside the design range at every page count', () {
        for (final pages in [20, 100, 300, 900, 5000]) {
          expect(
            thickness(pages),
            inInclusiveRange(
              BookJitter.minThicknessFactor,
              BookJitter.maxThicknessFactor,
            ),
            reason: 'at $pages pages',
          );
        }
      });

      test('treats a zero page count as absent, not as a thin book', () {
        // Google Books returns `pageCount: 0` rather than omitting the key. Trusting
        // it would draw the thinnest book on the shelf and call it data.
        expect(bookThicknessPositionFromPages(0), isNull);
        expect(bookThicknessPositionFromPages(null), isNull);
        expect(thickness(0), thickness(null));
      });

      test(
        'leaves height alone, so gaining a page count only changes thickness',
        () {
          // A book that is backfilled later must not jump height on the shelf.
          const isbn = '9780141439518';
          expect(
            BookJitter.fromIsbn(isbn, pageCount: 640).heightFactor,
            BookJitter.fromIsbn(isbn).heightFactor,
          );
        },
      );

      test('uses a page count even when there is no ISBN to hash', () {
        // `bookHash('')` is just the FNV offset basis, identical for every such
        // book, so height stays neutral — but the page count is still real.
        final j = BookJitter.fromIsbn('', pageCount: 900);
        expect(j.heightFactor, BookJitter.neutral.heightFactor);
        expect(j.thicknessFactor, closeTo(BookJitter.maxThicknessFactor, 1e-9));
      });
    });

    test('is stable across repeated calls', () {
      final first = BookJitter.fromIsbn('9788936434120');
      final second = BookJitter.fromIsbn('9788936434120');
      expect(first, second);
    });

    group('atNeutralHeight', () {
      // Half the variation, for a caller — the read view's month grid — whose cells
      // are uniform but whose books still turn far enough to show a fore-edge.

      test('keeps the thickness and flattens the height', () {
        final full = BookJitter.fromIsbn('9780141439518');
        expect(full.heightFactor, isNot(BookJitter.neutral.heightFactor));

        final flat = full.atNeutralHeight;
        expect(flat.thicknessFactor, full.thicknessFactor);
        expect(flat.heightFactor, BookJitter.neutral.heightFactor);
      });

      test('keeps a thickness that came from a page count', () {
        // The point of the whole thing: a long book stays a thick one.
        final short = BookJitter.fromIsbn(
          '9788936434120',
          pageCount: 120,
        ).atNeutralHeight;
        final long = BookJitter.fromIsbn(
          '9788936434120',
          pageCount: 850,
        ).atNeutralHeight;

        expect(long.thicknessFactor, greaterThan(short.thicknessFactor));
        expect(long.heightFactor, short.heightFactor);
      });

      test('is a no-op on neutral', () {
        expect(BookJitter.neutral.atNeutralHeight, BookJitter.neutral);
      });
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
        jitter: const BookJitter(1.06, 0.36),
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
