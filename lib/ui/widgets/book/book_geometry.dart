import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:bookworm_friends/models/book.dart';

/// Ratio between a book's rendered width and its CSS-equivalent perspective
/// depth.
///
/// The reference component hardcodes `perspective: 900` for a 196px-wide book.
/// A constant is wrong for us: perspective is measured from the book's centre,
/// so the visible fore-edge depends on how far the right edge sits off-axis —
/// which scales with width. At our ~86px shelf size a fixed 900 collapses the
/// depth to roughly 1px. Holding `perspective / width` constant instead keeps
/// the effect identical at every size. 900 / 196 == 4.59.
const double kBookPerspectiveRatio = 4.6;

/// How far a book turns during stage one of the hold gesture, in radians.
///
/// 16° is the angle the reference rotates to on hover.
const double kBookTurnAngle = 16 * math.pi / 180;

/// Aspect ratio (width / height) used for generated covers, and as the
/// placeholder for real covers until the image has been decoded and its
/// intrinsic ratio is known.
const double kDefaultCoverAspect = 2 / 3;

/// The width, in logical pixels, that the reference component's design values
/// were authored against. Corner radii and shadow metrics scale off this.
const double kBookReferenceWidth = 196.0;

/// The height those same values were authored against.
///
/// The reference is `aspect-[49/60]`, so 196 × 60 / 49 == 240. We draw books at
/// 2/3 instead, which matters here: a square keyed to width would land at a
/// different fraction of the height than the reference's does, because the two
/// aspects differ. The vertical square is calibrated against this.
const double kBookReferenceHeight = kBookReferenceWidth * 60 / 49;

/// Fraction of the book's *height* by which the boards overhang the text block
/// at the head and tail.
///
/// A case-bound book's boards are cut larger than its text block, and that margin
/// — the binder's "square" — is why the fore-edge reads as pages inside a cover
/// rather than as a solid slab. The reference writes it as a flat `top-[3px]` and
/// `h-[calc(100% - 2 * 3px)]` on a 240pt-tall book: 3 / 240 == 1.25%.
///
/// Keyed to height, not width, and proportional, not flat. Both matter:
///
///  * Flat 3px was measurably wrong. It is 1.25% of the reference's 240pt book
///    but 1.6% of a 180pt one, which reads as an over-cut board. An earlier
///    revision of this file argued for flat on the grounds that a proportional
///    square collapses to ~1px on an 86pt shelf book and cannot be seen. That
///    reasoning is now obsolete: the board is visible via
///    [kBookForeEdgeSquareRatio], a full-height band, so this no longer carries
///    the job of making it visible on its own.
///  * Keyed to width it would drift, because our 2/3 aspect is not the
///    reference's 49/60.
///
/// It doubles as the reason the strip clears the cover's rounded corners rather
/// than poking past them.
const double kBookBoardSquareRatio = 3 / kBookReferenceHeight;

/// Fraction of the cover's width of depth clearance between the text block and
/// each board.
///
/// The reference's strip is `29cqw - 2px` wide and its transform lands it at
/// `z ∈ [-(t - 1), -1]`: 1px short of the cover at one end, 1px short of the back
/// board at the other, so the boards overhang the pages in depth as well.
///
/// Worth being honest about how little this buys. Against a perspective of
/// `4.6 × width` a 1px recess moves the projected fore-edge by under 0.35px at
/// any turn angle used here. It is here for the correctness of the solid, not for
/// the look — and proportional so that it does not break the scale invariance the
/// `depth at rest` tests pin.
const double kBookDepthClearanceRatio = 1 / kBookReferenceWidth;

/// Fraction of the cover's width by which the boards overhang the text block on
/// the fore-edge.
///
/// The largest of the reference's three squares, and the one that makes the back
/// board read as a distinct band beyond the pages on a turned book. It is easy
/// to miss in the source, because it is not written down anywhere — it falls out
/// of composing two things. The strip is `29cqw - 2px` wide, so its
/// `transform-origin` sits `t/2 - 1` from its own left edge; adding the
/// `translateX(W - 29cqw/2 - 3px)` that follows puts the strip's plane at
/// `(t/2 - 1) + (W - t/2 - 3)` = **`W - 4`**. Four pixels inside the boards'
/// fore-edge, not flush with it.
///
/// 4px on the reference's 196px cover is 2% of the width. Held flat it would be
/// 7% of an 86pt shelf book, enough to push the fore-edge back behind the cover
/// at every turn angle used here and leave nothing visible but grey board.
///
/// Set to 6, not the reference's 4: at the sizes this app draws (a 131pt shelf
/// book, a 180pt hero) the reference's value put the board band at about 5 device
/// pixels, which is present but easy to miss. 6 / 196 == 0.0306.
const double kBookForeEdgeSquareRatio = 6 / kBookReferenceWidth;

/// 32-bit FNV-1a.
///
/// Used instead of [Object.hashCode] because Dart makes no guarantee that
/// `String.hashCode` is stable across SDK versions. If it ever shifted, every
/// book on every shelf would silently change height after a Flutter upgrade.
/// This is pinned by golden values in `test/book_geometry_test.dart`.
int bookHash(String input) {
  var hash = 0x811C9DC5;
  for (final unit in input.codeUnits) {
    hash = _mulFnvPrime(hash ^ (unit & 0xFF));
    if (unit > 0xFF) {
      hash = _mulFnvPrime(hash ^ ((unit >> 8) & 0xFF));
    }
  }
  return hash;
}

/// `hash * 0x01000193 mod 2^32`, split so no intermediate exceeds 2^53.
///
/// This project has a `web/` target, where `int` is a JS double. A direct
/// `hash * 0x01000193` reaches ~2^56 and silently loses precision before the
/// mask is applied. Since `0x01000193 == (1 << 24) + 403`, the product can be
/// rewritten so the largest intermediate is `hash * 403 < 2^41`.
int _mulFnvPrime(int hash) => (((hash & 0xFF) << 24) + hash * 403) & 0xFFFFFFFF;

/// Page counts that map to the ends of the thickness range.
///
/// Log-scaled between them rather than linear, for two reasons: page counts are
/// long-tailed, and a linear map would let one 1,500-page reference book pin the
/// top of the range while every novel bunched near the bottom. On this curve 300
/// pages — the archetypal trade book — lands exactly mid-range.
const int kBookMinPageCount = 100;
const int kBookMaxPageCount = 900;

/// Page counts below this are treated as absent.
///
/// Google Books returns `pageCount: 0` for volumes it has no count for, rather
/// than omitting the key, so a reader that trusts the field banks a zero as
/// knowledge and draws the thinnest book on the shelf. Anything under 20 pages is
/// a pamphlet, not a record worth believing.
const int kBookMinCrediblePageCount = 20;

/// Where [pageCount] sits in the thickness range, or null if there is no usable
/// count and the hash should decide instead.
///
/// Deliberately returns a *position*, not a thickness. A physically derived
/// thickness is around 0.12–0.25 of the width (a 300-page trade paperback is
/// ~20mm on a ~145mm page), and [BookJitter.minThicknessFactor] is tuned well
/// above that on purpose — see its doc. So real data chooses where a book sits
/// within the stylised range; it does not get to set the range.
double? bookThicknessPositionFromPages(int? pageCount) {
  if (pageCount == null || pageCount < kBookMinCrediblePageCount) return null;
  final lo = math.log(kBookMinPageCount);
  final hi = math.log(kBookMaxPageCount);
  return ((math.log(pageCount) - lo) / (hi - lo)).clamp(0.0, 1.0);
}

/// The size of one book seen along its spine, at [baseHeight].
///
/// **One** function, used by the read pile's flat spine, by the chassis that
/// replaces it at a turn, by the row that lays both out, and by a shelf drawing at
/// `ShelfDensity.spines`. Two call sites computing this is how the spine and the
/// cover come to disagree about thickness, and the disagreement is visible
/// precisely at the moment of the swap.
///
/// [baseHeight] is a parameter because the pile and a shelf draw books at different
/// sizes — `ReadPile.spineBase` (~117) against the shelf's `screenHeight * 0.15`
/// (~127). It was hardcoded to the pile's constant while the pile was the only
/// caller; `readSpineMetrics` is the same function with that value bound.
///
/// Resolved at [kDefaultCoverAspect] rather than at the cover's true ratio, which
/// no caller could know without decoding every cover — the thing the flat spine
/// exists to avoid. The consequence is worth stating: once an opened book's jacket
/// decodes, its own [BookMetrics] picks up the real ratio and its thickness moves
/// with it, a few percent either way. That lands *after* the turn, on a book whose
/// spine is by then edge-on and whose cover is the thing being looked at, which is
/// where a change of shape belongs.
///
/// **The thickness this returns is 0.36–0.52 of the cover's width** — about 29–47pt
/// at a shelf's base height. `BookVertical.width` defaults to 26, which is a value
/// no real spine ever takes; reading that default instead of this function is a
/// mistake the design record made twice.
({BookJitter jitter, BookMetrics metrics}) spineMetricsFor(
  Book book, {
  required double baseHeight,
}) {
  final jitter = BookJitter.fromIsbn(book.isbn, pageCount: book.pageCount);
  return (
    jitter: jitter,
    metrics: BookMetrics.from(
      baseHeight: baseHeight,
      coverAspect: kDefaultCoverAspect,
      jitter: jitter,
    ),
  );
}

/// Per-book size variation.
///
/// Height is always fabricated: nothing in the catalogue reports a book's trim
/// size, and cover aspect ratio already gives books their true relative widths.
/// It is hashed from the ISBN, kept small enough to read as natural shelf
/// variation rather than as information, and stable so a book looks the same
/// forever.
///
/// Thickness prefers real data. When the catalogue supplied a credible page count
/// it decides where the book sits in the thickness range; otherwise the hash does.
/// Coverage is low — Kakao, the primary provider for Korean titles, reports no page
/// count at all, and Google Books covers roughly a third of this corpus — and the
/// design record originally rejected page count for exactly that reason, on the
/// grounds that a mix of real and fabricated values "reads as a bug".
///
/// That argument does not survive contact with the alternative. A reader cannot
/// tell a hashed thickness from a measured one, so partial coverage introduces no
/// visible inconsistency; what it does is make a third of the shelf *correct*. The
/// fully hashed shelf is the one where a 1,200-page novel has even odds of being
/// drawn thinner than a novella. Partial data strictly reduces the number of
/// visibly wrong books and worsens nothing.
@immutable
class BookJitter {
  /// Multiplier on the base height. Range `[0.94, 1.06]`.
  final double heightFactor;

  /// Book thickness as a fraction of its width. Range `[0.36, 0.52]`.
  ///
  /// Derived from the book's page count where one is known, and from the ISBN hash
  /// otherwise. Nothing downstream can tell which.
  final double thicknessFactor;

  const BookJitter(this.heightFactor, this.thicknessFactor);

  /// Used for books with no ISBN, so they render at exactly the base height
  /// with mid-range thickness rather than picking up the hash of an empty
  /// string.
  ///
  /// NOTE: 0.36 is no longer mid-range — it is now the range *minimum*, so an
  /// ISBN-less book is currently the thinnest on the shelf rather than an average
  /// one. Mid-range for `[0.36, 0.52]` would be 0.44.
  static const BookJitter neutral = BookJitter(1.0, 0.36);

  /// This book's own thickness, at [neutral]'s height.
  ///
  /// For a caller that must draw every book the same height but still wants each
  /// one's real depth. The read view's month grid is the case, and the two halves
  /// are genuinely separable: height jitter there reads as misalignment rather than
  /// as character (see [BookWidget.jitter]), while thickness is only ever visible
  /// edge-on and contributes no layout width at all (see [BookMetrics.thickness]) —
  /// so a book held in a uniform cell can show the fore-edge its page count says it
  /// has without moving a single cover.
  ///
  /// Dropping the two together, which is what `jitter: false` does, is what made
  /// every book in the grid [minThicknessFactor] — the thinnest on the shelf,
  /// uniformly, including the 800-page ones.
  BookJitter get atNeutralHeight =>
      BookJitter(neutral.heightFactor, thicknessFactor);

  static const double minHeightFactor = 0.94;
  static const double maxHeightFactor = 1.06;

  /// The reference is a fixed `29cqw`, and this is deliberately well above it.
  ///
  /// Two reasons, neither of them realism — 0.44 of the width is a ~75mm trade
  /// hardback, which is a doorstop. First, the fore-edge is only a handful of
  /// device pixels wide at the sizes this app draws, so a reference-accurate
  /// thickness reads as a hairline rather than a stack of paper. Second, it
  /// rebalances against [kBookForeEdgeSquareRatio]: raising that to 6 widened the
  /// board band by taking width from the pages, which inverted the reference's
  /// proportions (pages ~1.4x the board). Thickening restores the ratio from the
  /// other side.
  ///
  /// Retuned by eye several times from `[0.22, 0.34]`, including a widening of the
  /// span from 0.12 to 0.16. `test/book_geometry_test.dart` pins each book's
  /// normalised *position* in this range rather than its resolved factor, so this
  /// pair can be tuned freely without rewriting goldens — what that test guards is
  /// the stability of the hash, not the design value.
  static const double minThicknessFactor = 0.36;
  static const double maxThicknessFactor = 0.52;

  /// Resolves a book's jitter.
  ///
  /// [pageCount] is used for thickness when it is credible (see
  /// [bookThicknessPositionFromPages]); the hash covers it otherwise. Height is
  /// always hashed, so a book that later gains a page count keeps its height and
  /// only its thickness changes.
  factory BookJitter.fromIsbn(String isbn, {int? pageCount}) {
    final fromPages = bookThicknessPositionFromPages(pageCount);
    if (isbn.isEmpty) {
      // No ISBN means no hash worth taking — `bookHash('')` is just the FNV offset
      // basis, identical for every such book. Height falls back to neutral, but a
      // page count is still real data and still worth using.
      return fromPages == null
          ? neutral
          : BookJitter(
              neutral.heightFactor,
              minThicknessFactor +
                  fromPages * (maxThicknessFactor - minThicknessFactor),
            );
    }
    final hash = bookHash(isbn);
    // Two draws from disjoint 16-bit ranges, so height and thickness don't
    // correlate — otherwise every tall book would also be a thick one.
    final a = (hash & 0xFFFF) / 0xFFFF;
    final b = fromPages ?? ((hash >> 16) & 0xFFFF) / 0xFFFF;
    return BookJitter(
      minHeightFactor + a * (maxHeightFactor - minHeightFactor),
      minThicknessFactor + b * (maxThicknessFactor - minThicknessFactor),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookJitter &&
      other.heightFactor == heightFactor &&
      other.thicknessFactor == thicknessFactor;

  @override
  int get hashCode => Object.hash(heightFactor, thicknessFactor);

  @override
  String toString() =>
      'BookJitter(height: $heightFactor, thickness: $thicknessFactor)';
}

/// Every dimension needed to lay out one book, resolved from a base height, the
/// cover's aspect ratio, and the book's [BookJitter].
@immutable
class BookMetrics {
  /// Base height after jitter. This is the book's real rendered height.
  final double height;

  /// Cover width, from the cover's own aspect ratio — the one genuinely real
  /// size signal available.
  final double width;

  /// Spine depth. Only visible edge-on, so it contributes no layout width.
  final double thickness;

  /// Perspective distance for the 3D composition.
  final double perspective;

  const BookMetrics({
    required this.height,
    required this.width,
    required this.thickness,
    required this.perspective,
  });

  factory BookMetrics.from({
    required double baseHeight,
    required double coverAspect,
    required BookJitter jitter,
  }) {
    final resolvedHeight = baseHeight * jitter.heightFactor;
    final resolvedWidth = resolvedHeight * coverAspect;
    return BookMetrics(
      height: resolvedHeight,
      width: resolvedWidth,
      thickness: resolvedWidth * jitter.thicknessFactor,
      perspective: resolvedWidth * kBookPerspectiveRatio,
    );
  }

  /// Spine-side corners are rounder than the fore-edge side, matching how a
  /// bound book actually looks: the spine is a fold, the page edge is cut.
  double get leftRadius =>
      (6 * width / kBookReferenceWidth).clamp(2.0, 6.0).toDouble();

  double get rightRadius =>
      (4 * width / kBookReferenceWidth).clamp(2.0, 4.0).toDouble();

  BorderRadius get radius => BorderRadius.only(
    topLeft: Radius.circular(leftRadius),
    bottomLeft: Radius.circular(leftRadius),
    topRight: Radius.circular(rightRadius),
    bottomRight: Radius.circular(rightRadius),
  );

  /// Scales shadow offsets and blur radii, so an 86px book doesn't carry the
  /// shadow authored for a 196px one. Floored so the shadow never vanishes.
  double get shadowScale =>
      (width / kBookReferenceWidth).clamp(0.35, 1.0).toDouble();

  /// Width of the binding band — 8.2% of the cover, from the reference.
  double get bindingWidth => width * 0.082;

  /// How far the boards overhang the text block at the head and tail. See
  /// [kBookBoardSquareRatio].
  double get boardSquare => height * kBookBoardSquareRatio;

  /// Depth clearance between the text block and each board. See
  /// [kBookDepthClearanceRatio].
  double get depthClearance => width * kBookDepthClearanceRatio;

  /// How far the boards overhang the text block on the fore-edge. See
  /// [kBookForeEdgeSquareRatio].
  double get foreEdgeSquare => width * kBookForeEdgeSquareRatio;

  /// Depth of the text block: [thickness] less a [depthClearance] at each
  /// end, so both boards overhang it. The reference's equivalent is
  /// `w-[calc(29cqw - 2px)]`.
  ///
  /// Floored far below any thickness a real book here reaches — the thinnest is
  /// `0.22 × width` and the narrowest book is ~57px — purely so the strip can
  /// never be handed a negative width.
  double get pageBlockThickness =>
      math.max(thickness - 2 * depthClearance, 1.0);

  @override
  String toString() =>
      'BookMetrics(${width.toStringAsFixed(1)}×${height.toStringAsFixed(1)}, '
      't: ${thickness.toStringAsFixed(1)})';
}

/// A pure translation. Built by hand rather than via `Matrix4.translate`, whose
/// signature is mid-deprecation across vector_math versions.
Matrix4 _translation(double x, double y, double z) => Matrix4.identity()
  ..setEntry(0, 3, x)
  ..setEntry(1, 3, y)
  ..setEntry(2, 3, z);

/// Perspective projection followed by the book's turn.
///
/// Applied to a point, the rotation happens first and the projection second.
/// `setEntry(3, 2, k)` yields `w' = 1 + k·z`, so **positive z recedes** —
/// dividing by a larger w shrinks the projection. That is the opposite of CSS,
/// where +z is toward the viewer.
///
/// `vector_math` rotates as `x' = c·x + s·z`, `z' = -s·x + c·z`, so a positive
/// [turn] sends the right edge to negative z, toward the viewer. That is the
/// direction that exposes the fore-edge.
///
/// The useful range is `[-π/2, +kBookTurnAngle]`. Positive is the hold gesture,
/// bounded by the small angle the reference rotates to; **negative exposes the
/// spine**, because it swings the left edge forward instead, and it runs all the
/// way to `-π/2` where the cover is edge-on and only the spine is left facing the
/// viewer. That is how a book stands in the read pile.
///
/// [pivot]'s horizontal component chooses what the rotation turns about, as a
/// fraction of half the book's width: `Alignment.center` spins it about its own
/// centre line, `Alignment.centerLeft` hinges it on the spine. Only the
/// horizontal component is read — a Y-rotation leaves y untouched, so a vertical
/// pivot would cancel itself out.
///
/// The pivot is folded in here rather than handed to `Transform.alignment`, and
/// that is not a stylistic choice: every local matrix in this library is written
/// in a frame whose origin is the face's **centre** (see [bookPageLocalMatrix]'s
/// `half` terms), and `Transform` applies its matrix in a frame centred on its
/// alignment point. Moving that alignment would silently reinterpret all of those
/// offsets.
///
/// Note *where* it is folded: `T(p) · projection · Ry · T(-p)`, around the
/// projection and not just around the rotation. The pivot therefore moves the
/// **vanishing point** as well as the hinge, which is the whole difference
/// between a clean spine and a broken one. Wrapping the rotation alone leaves the
/// camera on the book's centre line, and a cover swung to `-π/2` about an edge
/// that is off that line is then not edge-on to the camera at all: it projects to
/// a sliver of squashed artwork — measured at **6.96pt on a 78pt cover**, i.e.
/// 8.9% of the book's width, beside every single spine in the pile. Moving the
/// camera with the hinge collapses it to exactly zero.
///
/// The same move buys the property the pile's layout depends on: with the camera
/// on the hinge, a spine-on book's [bookSpineLocalMatrix] face lands at `w = 1`,
/// so it projects to exactly [BookMetrics.thickness] wide. A row can allocate
/// that much space per book and be right to the pixel rather than approximately
/// right. (This one holds under either model — it is the cover that breaks.)
Matrix4 bookParentMatrix(
  BookMetrics metrics,
  double turn, {
  Alignment pivot = Alignment.center,
}) {
  final projection = Matrix4.identity()
    ..setEntry(3, 2, 1 / metrics.perspective);
  final rotation = Matrix4.rotationY(turn);
  final px = pivot.x * metrics.width / 2;
  if (px == 0) return projection.multiplied(rotation);
  return _translation(px, 0, 0)
      .multiplied(projection)
      .multiplied(rotation)
      .multiplied(_translation(-px, 0, 0));
}

/// Places the page block behind the cover's fore-edge, laid back along +z.
///
/// Reads right-to-left: shift the strip so its inner edge sits on the book's
/// centre line, swing it 90° into the depth axis, then push it out to the
/// fore-edge and recess it by [BookMetrics.depthClearance]. `-π/2` and not
/// `+π/2`, because `rotateY` maps `+x` to `-z` and `-z` is toward the viewer —
/// the wrong way for a page block to grow.
///
/// The plane lands [BookMetrics.foreEdgeSquare] *inside* the cover's right edge,
/// not on it, so both boards stand proud of the pages. Combined with a strip
/// [BookMetrics.pageBlockThickness] wide and the depth recess, the text block
/// ends up spanning `z ∈ [clearance, thickness - clearance]` and sitting clear
/// of the boards on all four sides.
Matrix4 bookPageLocalMatrix(BookMetrics metrics) {
  final half = metrics.width / 2;
  return _translation(half - metrics.foreEdgeSquare, 0, metrics.depthClearance)
      .multiplied(Matrix4.rotationY(-math.pi / 2))
      .multiplied(_translation(half, 0, 0));
}

/// Pushes the back board behind the cover by the book's thickness.
Matrix4 bookBackLocalMatrix(BookMetrics metrics) =>
    _translation(0, 0, metrics.thickness);

/// Stands the spine on the plane `x = -width/2`, spanning the book's depth.
///
/// The mirror of [bookPageLocalMatrix], and it reads the same way: swing a strip
/// 90° into the depth axis and push it out to the hinge. Two differences from the
/// page block, both deliberate:
///
///  * it lands on the cover's left edge rather than inside it, because a spine
///    *is* the hinge — there is no square to hold back from;
///  * it spans the full `z ∈ [0, thickness]`, with no depth clearance, so its far
///    long edge is exactly the back board's hinge edge. A clearance here would
///    open a gap that shows through at every negative turn angle.
///
/// **The face's right edge is the hinge, and its left edge is the back board.**
/// That is the whole reason this is `+π/2` where [bookPageLocalMatrix] is `-π/2`,
/// and getting it wrong is not a subtle error: at `-π/2` the strip lands in exactly
/// the same place, spans exactly the same depth, and passes every measurement of
/// where it is — while being **mirrored**. Its content is reflected about the
/// vertical axis, so a spine title reads backwards and the hairline down its edge
/// appears on the wrong side. The drawing in `docs/mockups/read-pile-turn/` hit the
/// same wall from the CSS side and its `frame.css` records it: "a back-facing plane
/// in CSS renders mirrored, so the +90 version drew every spine title in reverse".
/// The frameworks disagree about which sign is the mirrored one, which is why the
/// port could not simply be transliterated — and why the guard for it is a test
/// that composes the whole chain and checks the *order* of two points on screen,
/// rather than anything about this matrix's entries.
///
/// Which end is the hinge also decides where [BookVertical]'s separator lands:
/// on its right edge, i.e. at the fold where the spine meets the cover. That is
/// where the drawing puts it too.
Matrix4 bookSpineLocalMatrix(BookMetrics metrics) {
  final half = metrics.width / 2;
  return _translation(
    -half,
    0,
    metrics.thickness - half,
  ).multiplied(Matrix4.rotationY(math.pi / 2));
}
