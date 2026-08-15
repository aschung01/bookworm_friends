// Verifies the 3D composition numerically, so the sign conventions are pinned
// by a test rather than by eyeballing a device.
//
// Flutter's depth axis is inverted relative to CSS and `rotateY`'s sign follows
// suit, so the reference component's transforms cannot be transliterated. The
// two invariants that matter:
//
//   1. The page block sits on the RIGHT of the cover, never the left.
//   2. The back board RECEDES — it must never paint outside the cover.
//
// Everything is projected through the same matrix chain `Transform` applies,
// including its `alignment: Alignment.center` pivot, so these are the real
// on-screen coordinates.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

BookMetrics _metrics({double baseHeight = 130, double aspect = 0.66}) =>
    BookMetrics.from(
      baseHeight: baseHeight,
      coverAspect: aspect,
      jitter: const BookJitter(1.0, 0.29),
    );

/// Reproduces `Transform(transform: m, alignment: Alignment.center)` for a child
/// box of the book's size: translate to centre, apply, translate back.
Offset _project(BookMetrics metrics, Matrix4 local, double turn, Offset point) {
  final cx = metrics.width / 2;
  final cy = metrics.height / 2;
  final full = Matrix4.identity()
    ..setEntry(0, 3, cx)
    ..setEntry(1, 3, cy);
  final composed = full
      .multiplied(bookParentMatrix(metrics, turn))
      .multiplied(local)
      .multiplied(
        Matrix4.identity()
          ..setEntry(0, 3, -cx)
          ..setEntry(1, 3, -cy),
      );
  return MatrixUtils.transformPoint(composed, point);
}

/// Rightmost projected x of the cover.
double _coverRight(BookMetrics m, double turn) =>
    _project(m, Matrix4.identity(), turn, Offset(m.width, m.height / 2)).dx;

/// Rightmost projected x of the page block's outer edge. In the face box the
/// strip spans x from 0 (touching the cover) to `thickness`.
double _pagesOuter(BookMetrics m, double turn) => _project(
  m,
  bookPageLocalMatrix(m),
  turn,
  Offset(m.thickness, m.height / 2),
).dx;

/// Rightmost projected x of the back board.
double _backRight(BookMetrics m, double turn) =>
    _project(m, bookBackLocalMatrix(m), turn, Offset(m.width, m.height / 2)).dx;

void main() {
  group('page block placement', () {
    test('is hinged at the cover right edge, not the left', () {
      final m = _metrics();
      // Inner edge of the strip coincides with the cover's right edge.
      final inner = _project(
        m,
        bookPageLocalMatrix(m),
        0,
        Offset(0, m.height / 2),
      ).dx;
      expect(inner, closeTo(_coverRight(m, 0), 0.01));
    });

    test('grows away from the viewer, not toward it', () {
      // Receding means shrinking toward the projection centre, so the outer
      // edge lands INSIDE the cover's right edge. If the sign were flipped the
      // strip would balloon outward instead.
      final m = _metrics();
      expect(_pagesOuter(m, 0), lessThan(_coverRight(m, 0)));
    });

    test('emerges to the right once the book turns', () {
      // Turning brings the right edge toward the viewer, swinging the fore-edge
      // into view beyond the cover's silhouette.
      final m = _metrics();
      expect(
        _pagesOuter(m, kBookTurnAngle),
        greaterThan(_coverRight(m, kBookTurnAngle)),
      );
    });

    test('exposes more fore-edge the further it turns', () {
      final m = _metrics();
      double exposed(double turn) =>
          _pagesOuter(m, turn) - _coverRight(m, turn);
      expect(exposed(kBookTurnAngle), greaterThan(exposed(kBookTurnAngle / 2)));
    });
  });

  group('back board placement', () {
    test('recedes at rest so it never paints outside the cover', () {
      final m = _metrics();
      expect(_backRight(m, 0), lessThan(_coverRight(m, 0)));
    });

    test('shares its right edge with the page block, leaving no gap', () {
      // The back board's right edge and the page block's outer edge are the same
      // edge of the same solid. If they diverged, a turned book would show
      // either a gray sliver of board past the pages or a gap between cover and
      // pages.
      final m = _metrics();
      for (var deg = 0; deg <= 25; deg++) {
        final turn = deg * 3.1415926535897932 / 180;
        expect(
          _backRight(m, turn),
          closeTo(_pagesOuter(m, turn), 0.01),
          reason: 'board and pages disagreed on the outer edge at $deg°',
        );
      }
    });

    test('keeps its spine edge inside the cover at every turn angle', () {
      // The left side recedes as the book turns, so the board's left edge should
      // move inward. If it escaped, gray would show along the spine.
      final m = _metrics();
      double coverLeft(double turn) =>
          _project(m, Matrix4.identity(), turn, Offset(0, m.height / 2)).dx;
      double backLeft(double turn) =>
          _project(m, bookBackLocalMatrix(m), turn, Offset(0, m.height / 2)).dx;
      for (var deg = 0; deg <= 25; deg++) {
        final turn = deg * 3.1415926535897932 / 180;
        expect(
          backLeft(turn),
          greaterThan(coverLeft(turn) - 0.001),
          reason: 'back board escaped past the spine at $deg°',
        );
      }
    });
  });

  group('depth at rest', () {
    test('is hidden behind the cover when the book is flat', () {
      // This is what the reference actually looks like at `rotate-0`: the page
      // block projects inside the cover's edge, so the cover occludes it and no
      // depth is visible. Depth is a reward for holding, not a resting state.
      final m = _metrics();
      expect(_pagesOuter(m, 0) - _coverRight(m, 0), lessThan(0));
    });

    test('scales with width so the turn looks the same at any size', () {
      // The reason perspective is width-proportional. With a fixed 900 the
      // fore-edge would nearly vanish on an 86px book.
      final small = _metrics(baseHeight: 130);
      final large = _metrics(baseHeight: 300);
      double exposedFraction(BookMetrics m) =>
          (_pagesOuter(m, kBookTurnAngle) - _coverRight(m, kBookTurnAngle)) /
          m.width;
      expect(exposedFraction(small), closeTo(exposedFraction(large), 1e-6));
    });
  });
}
