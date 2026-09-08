// A spine's size is one calculation with three callers now: the read pile's flat
// spine, the chassis that replaces it at a turn, and a shelf drawing at
// `ShelfDensity.spines`. `spineMetricsFor` is that calculation.
//
// The first group is a **regression guard on the extraction**, not a test of the
// design: it recomputes what `readSpineMetrics` did before `spineMetricsFor` existed,
// independently, so that moving the body cannot quietly change a number. It is
// written to pass against the old code and the new alike.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/read_pile.dart';

import 'support/home_page_harness.dart';

/// What `readSpineMetrics` did before the extraction, spelled out here so the
/// extraction has something independent to be checked against.
({BookJitter jitter, BookMetrics metrics}) _expected(
  String isbn, {
  int? pageCount,
  required double baseHeight,
}) {
  final jitter = BookJitter.fromIsbn(isbn, pageCount: pageCount);
  return (
    jitter: jitter,
    metrics: BookMetrics.from(
      baseHeight: baseHeight,
      coverAspect: kDefaultCoverAspect,
      jitter: jitter,
    ),
  );
}

/// A spread of shapes: no page count, both ends of the credible range, one below
/// it, and an empty ISBN.
const _cases = <(String, int?)>[
  ('9788901234567', null),
  ('9788901234567', 300),
  ('9791162241234', 100),
  ('9791162241234', 900),
  ('9788934972464', 15),
  ('', 250),
];

void main() {
  group('readSpineMetrics after the extraction', () {
    test(
      'Given the pile\'s own base height, When resolved, Then every value is what '
      'it was',
      () {
        for (final (isbn, pageCount) in _cases) {
          final book = testBook(isbn, 's1', pageCount: pageCount);
          final want = _expected(
            isbn,
            pageCount: pageCount,
            baseHeight: ReadPile.spineBase,
          );
          final got = readSpineMetrics(book);

          expect(got.metrics.height, want.metrics.height, reason: isbn);
          expect(got.metrics.width, want.metrics.width, reason: isbn);
          expect(got.metrics.thickness, want.metrics.thickness, reason: isbn);
          expect(got.jitter, want.jitter, reason: isbn);
        }
      },
    );
  });

  group('spineMetricsFor', () {
    test('Given the pile\'s base height, When resolved, Then it agrees with '
        'readSpineMetrics', () {
      // The whole point of the extraction: one calculation, so a spine drawn on a
      // shelf and one drawn in the pile cannot disagree about thickness.
      for (final (isbn, pageCount) in _cases) {
        final book = testBook(isbn, 's1', pageCount: pageCount);
        final viaPile = readSpineMetrics(book);
        final direct = spineMetricsFor(book, baseHeight: ReadPile.spineBase);

        expect(direct.metrics.thickness, viaPile.metrics.thickness);
        expect(direct.metrics.height, viaPile.metrics.height);
      }
    });

    test(
      'Given a shelf base height, When resolved, Then the spine is as tall as the '
      'same book face-out',
      () {
        // A spine and its turned-out cover have to be the same height, or the swap
        // between them is a change of size. Both come from one `BookJitter`.
        const shelfBase = 126.6;
        for (final (isbn, pageCount) in _cases) {
          final book = testBook(isbn, 's1', pageCount: pageCount);
          final jitter = BookJitter.fromIsbn(isbn, pageCount: pageCount);
          final spine = spineMetricsFor(book, baseHeight: shelfBase);

          expect(
            spine.metrics.height,
            shelfBase * jitter.heightFactor,
            reason: isbn,
          );
        }
      },
    );

    test('Given a shelf base height, When resolved, Then thickness lands in the '
        '29-47pt band', () {
      // The number the design's arithmetic rests on, and the reason a spine is a
      // viable drag target at all. `BookVertical`'s 26pt default is not a width any
      // real spine takes: thickness is 0.36-0.52 of a cover's width, and a cover is
      // 0.94-1.06 of the base height times `kDefaultCoverAspect`.
      const shelfBase = 126.6;
      const lo =
          shelfBase *
          BookJitter.minHeightFactor *
          kDefaultCoverAspect *
          BookJitter.minThicknessFactor;
      const hi =
          shelfBase *
          BookJitter.maxHeightFactor *
          kDefaultCoverAspect *
          BookJitter.maxThicknessFactor;

      expect(lo, closeTo(28.6, 0.5));
      expect(hi, closeTo(46.6, 0.5));

      for (final (isbn, pageCount) in _cases) {
        final book = testBook(isbn, 's1', pageCount: pageCount);
        final thickness = spineMetricsFor(
          book,
          baseHeight: shelfBase,
        ).metrics.thickness;

        expect(thickness, greaterThanOrEqualTo(lo), reason: isbn);
        expect(thickness, lessThanOrEqualTo(hi), reason: isbn);
      }
    });

    test(
      'Given two base heights, When resolved, Then thickness scales with the base',
      () {
        final book = testBook('9788901234567', 's1', pageCount: 300);
        final small = spineMetricsFor(book, baseHeight: 100).metrics.thickness;
        final large = spineMetricsFor(book, baseHeight: 200).metrics.thickness;

        expect(large, closeTo(small * 2, 0.001));
      },
    );
  });
}
