// Verifies the 3D composition numerically, so the sign conventions are pinned
// by a test rather than by eyeballing a device.
//
// Flutter's depth axis is inverted relative to CSS and `rotateY`'s sign follows
// suit, so the reference component's transforms cannot be transliterated. The
// invariants that matter:
//
//   1. The page block sits on the RIGHT of the cover, never the left.
//   2. The back board RECEDES — it must never paint outside the cover.
//   3. The boards OVERHANG the page block, by a flat number of pixels at every
//      book size. This is the only thing that makes the back board visible on a
//      turned book, and it is measured here because it cannot be seen by reading
//      the widget: an earlier version of this file asserted the exact opposite,
//      that board and pages share an outer edge, which is what kept the back
//      board invisible on the shelves.
//   4. The spine stands on the cover's LEFT edge, perpendicular to the other
//      three faces, and a NEGATIVE turn is what reveals it. Positive exposes the
//      fore-edge, so the read pile's books rest at -π/2 and turn forward.
//   5. A book hinged on its spine turns IN PLACE: the hinge edge does not move,
//      and the spine projects at exactly its thickness. The pile's layout is
//      built on both.
//
// Everything is projected through the same matrix chain `Transform` applies,
// including its `alignment: Alignment.center` pivot, so these are the real
// on-screen coordinates. That alignment is not the book's own pivot and never
// changes — see `bookParentMatrix` for why the two are separate.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

BookMetrics _metrics({double baseHeight = 130, double aspect = 0.66}) =>
    BookMetrics.from(
      baseHeight: baseHeight,
      coverAspect: aspect,
      jitter: const BookJitter(1.0, 0.36),
    );

/// Reproduces `Transform(transform: m, alignment: Alignment.center)` for a child
/// box of the book's size: translate to centre, apply, translate back.
///
/// [pivot] is passed straight through to [bookParentMatrix] and defaults to the
/// centre, which is what every caller written before the read pile wants. It is
/// deliberately a separate axis from `Transform`'s own alignment, which stays on
/// the centre no matter what the book hinges about — see [bookParentMatrix].
Offset _project(
  BookMetrics metrics,
  Matrix4 local,
  double turn,
  Offset point, {
  Alignment pivot = Alignment.center,
}) {
  final cx = metrics.width / 2;
  final cy = metrics.height / 2;
  final full = Matrix4.identity()
    ..setEntry(0, 3, cx)
    ..setEntry(1, 3, cy);
  final composed = full
      .multiplied(bookParentMatrix(metrics, turn, pivot: pivot))
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
/// strip spans x from 0 (nearest the cover) to `pageBlockThickness`.
double _pagesOuter(BookMetrics m, double turn) => _project(
  m,
  bookPageLocalMatrix(m),
  turn,
  Offset(m.pageBlockThickness, m.height / 2),
).dx;

/// Rightmost projected x of the back board.
double _backRight(BookMetrics m, double turn) =>
    _project(m, bookBackLocalMatrix(m), turn, Offset(m.width, m.height / 2)).dx;

/// Depth the page block's [xBox] edge lands at in the book's own 3D space,
/// before any projection. Positive z recedes, so the cover is at 0 and the back
/// board at `thickness`.
///
/// Read straight off row 2 of the local matrix rather than via a Vector3, and
/// evaluated on the vertical centre line where the y term drops out. The centre
/// pivot `Transform` applies only shifts x and y, so it cannot affect this.
double _pageDepthAt(BookMetrics m, double xBox) {
  final local = bookPageLocalMatrix(m);
  return local.entry(2, 0) * (xBox - m.width / 2) + local.entry(2, 3);
}

/// x of the page block's plane in the book's own space, relative to centre.
///
/// The strip collapses to a single plane, so row 0 of the local matrix is
/// constant for flat content: `x_out = -z_in + entry(0, 3)`, and `z_in` is 0.
double _pagePlaneX(BookMetrics m) => bookPageLocalMatrix(m).entry(0, 3);

/// How much of the back board is exposed above the page block's top edge, in the
/// region beyond the cover's silhouette. This is the square, projected.
double _squareExposed(BookMetrics m, double turn) {
  final boardTop = _project(
    m,
    bookBackLocalMatrix(m),
    turn,
    Offset(m.width, 0),
  ).dy;
  final pagesTop = _project(
    m,
    bookPageLocalMatrix(m),
    turn,
    Offset(m.pageBlockThickness, m.boardSquare),
  ).dy;
  return pagesTop - boardTop;
}

/// The hinge a book in the read pile turns about: its spine edge.
const Alignment _hinge = Alignment.centerLeft;

/// Depth the spine's [xBox] edge lands at, before projection. Read the same way
/// as [_pageDepthAt] and for the same reason.
double _spineDepthAt(BookMetrics m, double xBox) {
  final local = bookSpineLocalMatrix(m);
  return local.entry(2, 0) * (xBox - m.width / 2) + local.entry(2, 3);
}

/// x of the spine's plane in the book's own space, relative to centre. As with
/// [_pagePlaneX], the strip collapses to one plane so row 0 is constant.
double _spinePlaneX(BookMetrics m) => bookSpineLocalMatrix(m).entry(0, 3);

/// Projected width of the cover, hinged on the spine.
double _coverSpan(BookMetrics m, double turn) =>
    (_project(
              m,
              Matrix4.identity(),
              turn,
              Offset(m.width, m.height / 2),
              pivot: _hinge,
            ).dx -
            _project(
              m,
              Matrix4.identity(),
              turn,
              Offset(0, m.height / 2),
              pivot: _hinge,
            ).dx)
        .abs();

/// Projected width of the spine, hinged on the spine. In the face box the strip
/// spans x from 0 (the cover's hinge) to `thickness` (the back board's).
double _spineSpan(BookMetrics m, double turn) =>
    (_project(
              m,
              bookSpineLocalMatrix(m),
              turn,
              Offset(m.thickness, m.height / 2),
              pivot: _hinge,
            ).dx -
            _project(
              m,
              bookSpineLocalMatrix(m),
              turn,
              Offset(0, m.height / 2),
              pivot: _hinge,
            ).dx)
        .abs();

void main() {
  group('page block placement', () {
    test('sits a fore-edge square inside the cover, on the right', () {
      // The reference's strip plane lands at `W - 4`, not at `W`. That inset is
      // not written down in the reference — it falls out of the strip being
      // `29cqw - 2px` wide (so its transform-origin is `t/2 - 1` from its own
      // left edge) composed with `translateX(W - 29cqw/2 - 3px)`. Getting it
      // wrong puts the pages flush with the boards, which hides the back board
      // completely on a turned book.
      final m = _metrics();
      expect(
        m.width / 2 - _pagePlaneX(m),
        closeTo(m.foreEdgeSquare, 0.01),
        reason: 'the page block plane is not inset from the fore-edge',
      );
      // Still on the right of centre, which is the sign error this group has
      // always existed to catch.
      expect(_pagePlaneX(m), greaterThan(0));
    });

    test('is recessed a clearance from the cover and from the back board', () {
      // The reference's strip spans `z ∈ [-(t - 1), -1]` rather than the full
      // `[0, -t]`, so neither board is flush against the pages.
      final m = _metrics();
      expect(_pageDepthAt(m, 0), closeTo(m.depthClearance, 0.01));
      expect(
        _pageDepthAt(m, m.pageBlockThickness),
        closeTo(m.thickness - m.depthClearance, 0.01),
      );
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

    test('overhangs the page block, so a turned book shows board', () {
      // The point of the whole square. The back board's top edge must sit above
      // the page block's, otherwise the fore-edge and the board project to one
      // silhouette and the book reads as a solid slab. Checked at the resting
      // turn angle and beyond.
      final m = _metrics();
      for (final turn in [kBookTurnAngle, kBookTurnAngle * 1.5]) {
        expect(
          _squareExposed(m, turn),
          greaterThan(m.boardSquare * 0.8),
          reason: 'the back board is not visible past the pages at $turn rad',
        );
      }
    });

    test('overhangs by the same fraction of height at every book size', () {
      // Every square is proportional, so the overhang is a constant fraction of
      // the book rather than a constant pixel count. It was briefly flat 3px,
      // which is 1.25% of the reference's 240pt book but 1.6% of a 180pt one —
      // visibly over-cut. Before that it scaled off `shadowScale`, whose 0.35
      // floor pinned it near 1px on the shelves.
      final fractions = [
        _metrics(baseHeight: 86),
        _metrics(baseHeight: 180),
        _metrics(baseHeight: kBookReferenceHeight),
      ].map((m) => _squareExposed(m, kBookTurnAngle) / m.height).toList();
      for (final f in fractions) {
        expect(
          f,
          closeTo(fractions.first, 1e-6),
          reason: 'the square is not a constant fraction of height: $fractions',
        );
      }
    });

    test('stands proud of the pages on the fore-edge', () {
      // The band the reference shows and we were missing: past the cover's edge
      // you see pages first, then a strip of back board beyond them. Ours used
      // to put the two on exactly the same edge, so the board was never visible
      // at any angle. An earlier version of this file asserted that coincidence
      // was correct.
      final m = _metrics();
      for (final turn in [kBookTurnAngle, kBookTurnAngle * 1.5]) {
        final board = _backRight(m, turn);
        final pages = _pagesOuter(m, turn);
        expect(
          board - pages,
          greaterThan(m.foreEdgeSquare * 0.8),
          reason: 'no back board visible past the pages at $turn rad',
        );
        // And the pages must still emerge from behind the cover, or the depth
        // reads as a plain grey slab with no page stack in it.
        expect(pages, greaterThan(_coverRight(m, turn)));
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
        final turn = deg * math.pi / 180;
        expect(
          backLeft(turn),
          greaterThan(coverLeft(turn) - 0.001),
          reason: 'back board escaped past the spine at $deg°',
        );
      }
    });
  });

  group('spine placement', () {
    test('stands on the cover\'s left edge, not inside it', () {
      // The page block is held a fore-edge square inside the cover so the boards
      // overhang it. The spine is the opposite case and must sit exactly on the
      // edge: it *is* the hinge, and there is nothing for it to stand back from.
      // Inset by even a point and the cover's left edge stops being the axis the
      // whole turn is built around.
      final m = _metrics();
      expect(_spinePlaneX(m), closeTo(-m.width / 2, 1e-9));
      // Stated as a contrast, because the two faces really do differ here and a
      // reader who knows one will assume the other.
      expect(_pagePlaneX(m), lessThan(m.width / 2));
    });

    test('spans the whole depth, cover edge to back board edge', () {
      // No depth clearance, unlike the page block. A clearance at either end
      // would open a gap between the spine and a board that shows through at
      // every negative turn angle -- and negative is the pile's resting state, so
      // it would be visible all the time rather than only while held.
      //
      // Note *which* end is which: the face's **right** edge is the hinge, at
      // z = 0, and its left edge is the back board at z = thickness. That is not
      // an arbitrary convention -- it is what keeps the face unmirrored, which the
      // test below is the guard for.
      final m = _metrics();
      expect(_spineDepthAt(m, m.thickness), closeTo(0, 1e-9));
      expect(_spineDepthAt(m, 0), closeTo(m.thickness, 1e-9));
      // And for comparison, the page block's near end is pulled in.
      expect(_pageDepthAt(m, 0), greaterThan(0));
    });

    test('grows away from the viewer, not toward it', () {
      // The sign that renders a book inside out if it is wrong: the spine would
      // stand out of the *front* of the cover, in front of the artwork, instead
      // of running back to the board. Positive z recedes.
      final m = _metrics();
      expect(_spineDepthAt(m, 0), greaterThan(_spineDepthAt(m, m.thickness)));
    });

    test('is not mirrored', () {
      // **The bug this file exists to catch, and the one measurement that catches
      // it.** Compose the strip the other way round and it lands in exactly the
      // same place, spans exactly the same depth, and is reflected about its
      // vertical axis -- so every spine title reads backwards and the hairline
      // down its edge appears on the wrong side. Every assertion about *where* the
      // face is passes either way; only the order of two points on screen tells
      // them apart.
      //
      // Found by rendering a red block at the face's top-left and a blue one at
      // its bottom-right, and seeing them come out top-right and bottom-left.
      final m = _metrics();
      double screenX(double xBox) => _project(
        m,
        bookSpineLocalMatrix(m),
        -math.pi / 2,
        Offset(xBox, m.height / 2),
        pivot: _hinge,
      ).dx;
      expect(
        screenX(m.thickness),
        greaterThan(screenX(0)),
        reason: 'the spine face is reflected: its content will read backwards',
      );
    });
  });

  group('a book standing spine-out', () {
    test('shows its spine at exactly its thickness', () {
      // The property the pile's layout rests on. With the camera on the hinge, a
      // spine-on face lands at w = 1, so it projects 1:1 and a row can allocate
      // `thickness` per book and be right to the pixel rather than approximately
      // right. If this drifts, every gap in the pile is subtly wrong and nothing
      // else says so.
      final m = _metrics();
      expect(_spineSpan(m, -math.pi / 2), closeTo(m.thickness, 1e-9));
    });

    test('shows no cover at all', () {
      // Zero, not "nearly zero", and it is only zero because `bookParentMatrix`
      // folds the pivot around the *projection* rather than around the rotation
      // alone. Fold it around the rotation only and the camera stays on the
      // book's centre line, which leaves a cover hinged off that line not edge-on
      // to the camera at all: it projects to a sliver of squashed artwork beside
      // every spine in the pile -- 6.96pt on this 78pt cover, 8.9% of its width.
      // This assertion is the guard for that composition order.
      final m = _metrics();
      expect(_coverSpan(m, -math.pi / 2), closeTo(0, 1e-9));
    });

    test('shows all of its cover and none of its spine once turned out', () {
      // The other end of the range, and the reverse of the two above.
      final m = _metrics();
      expect(_coverSpan(m, 0), closeTo(m.width, 1e-9));
      expect(_spineSpan(m, 0), closeTo(0, 1e-9));
    });

    test('reveals more spine the further back it turns', () {
      // Monotone, so there is no angle at which the turn appears to reverse.
      final m = _metrics();
      var previous = -1.0;
      for (var deg = 0; deg <= 90; deg++) {
        final span = _spineSpan(m, -deg * math.pi / 180);
        expect(
          span,
          greaterThan(previous),
          reason: 'the spine stopped widening at -$deg\u00b0',
        );
        previous = span;
      }
    });

    test('keeps its hinge edge still through the whole turn', () {
      // What the pivot is for. The book has to turn out *in place*: its spine
      // edge is where the pile put it and must not move, or the book walks
      // sideways out of its slot as it opens.
      final m = _metrics();
      double hingeX(double turn) => _project(
        m,
        Matrix4.identity(),
        turn,
        Offset(0, m.height / 2),
        pivot: _hinge,
      ).dx;
      final atRest = hingeX(-math.pi / 2);
      for (var deg = 0; deg <= 90; deg++) {
        expect(
          hingeX(-deg * math.pi / 180),
          closeTo(atRest, 1e-9),
          reason: 'the hinge moved at -$deg\u00b0',
        );
      }
      // And the size of the mistake a centre pivot would make: half a cover
      // width, straight through the neighbouring book.
      final centred = _project(
        m,
        Matrix4.identity(),
        -math.pi / 2,
        Offset(0, m.height / 2),
      ).dx;
      expect((centred - atRest).abs(), closeTo(m.width / 2, 1e-9));
    });

    test('hides its spine inside the cover once it turns forward', () {
      // The case that fixes the paint order, and it is not the intuitive one.
      // Past 0 the spine crosses to the same side of the hinge as the cover and
      // projects *within* the cover's silhouette, so it has to be occluded rather
      // than merely out of the way -- which is why BookChassis paints it under
      // the cover and not over it. Both signs happen to the same book: the pile
      // turns one out to 0 and a hold takes it on to +kBookTurnAngle.
      final m = _metrics();
      final hinge = _project(
        m,
        Matrix4.identity(),
        kBookTurnAngle,
        Offset(0, m.height / 2),
        pivot: _hinge,
      ).dx;
      final spineOuter = _project(
        m,
        bookSpineLocalMatrix(m),
        kBookTurnAngle,
        // xBox 0 is the *back board* end of the face; xBox thickness is the hinge.
        // See the depth test above.
        Offset(0, m.height / 2),
        pivot: _hinge,
      ).dx;
      final coverOuter = _project(
        m,
        Matrix4.identity(),
        kBookTurnAngle,
        Offset(m.width, m.height / 2),
        pivot: _hinge,
      ).dx;
      // Inside the hinge, on the cover's side of it, and well short of the
      // cover's far edge -- i.e. wholly covered.
      expect(spineOuter, greaterThan(hinge));
      expect(spineOuter, lessThan(coverOuter));
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
      //
      // Exact for both the board and the pages, because every length in the
      // chassis is now a ratio: perspective, thickness, and all three squares.
      // While the fore-edge square and the depth clearance were flat pixels this
      // could only be asserted on the board, and the pages' own fraction drifted
      // by ~0.1% of width between an 86pt book and a 198pt one.
      final small = _metrics(baseHeight: 130);
      final large = _metrics(baseHeight: 300);
      double boardFraction(BookMetrics m) =>
          (_backRight(m, kBookTurnAngle) - _coverRight(m, kBookTurnAngle)) /
          m.width;
      double pagesFraction(BookMetrics m) =>
          (_pagesOuter(m, kBookTurnAngle) - _coverRight(m, kBookTurnAngle)) /
          m.width;
      expect(boardFraction(small), closeTo(boardFraction(large), 1e-6));
      expect(pagesFraction(small), closeTo(pagesFraction(large), 1e-6));
    });
  });
}
