import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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

/// Per-book size variation, derived deterministically from the ISBN.
///
/// Neither value is real data. Cover aspect ratio already gives books their
/// true relative widths, but nothing in the catalogue tells us a book's height
/// or thickness — Kakao returns no page count, and it is the primary provider
/// for Korean titles. So both are fabricated, kept small enough that they read
/// as natural shelf variation rather than as information, and hashed so a given
/// book looks the same forever.
@immutable
class BookJitter {
  /// Multiplier on the base height. Range `[0.94, 1.06]`.
  final double heightFactor;

  /// Book thickness as a fraction of its width. Range `[0.22, 0.34]`.
  final double thicknessFactor;

  const BookJitter(this.heightFactor, this.thicknessFactor);

  /// Used for books with no ISBN, so they render at exactly the base height
  /// with mid-range thickness rather than picking up the hash of an empty
  /// string.
  static const BookJitter neutral = BookJitter(1.0, 0.28);

  static const double minHeightFactor = 0.94;
  static const double maxHeightFactor = 1.06;
  static const double minThicknessFactor = 0.22;
  static const double maxThicknessFactor = 0.34;

  factory BookJitter.fromIsbn(String isbn) {
    if (isbn.isEmpty) return neutral;
    final hash = bookHash(isbn);
    // Two draws from disjoint 16-bit ranges, so height and thickness don't
    // correlate — otherwise every tall book would also be a thick one.
    final a = (hash & 0xFFFF) / 0xFFFF;
    final b = ((hash >> 16) & 0xFFFF) / 0xFFFF;
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
Matrix4 bookParentMatrix(BookMetrics metrics, double turn) {
  final projection = Matrix4.identity()
    ..setEntry(3, 2, 1 / metrics.perspective);
  return projection.multiplied(Matrix4.rotationY(turn));
}

/// Places the page block hinged at the cover's right edge, laid back along +z.
///
/// Reads right-to-left: shift the strip so its inner edge sits on the book's
/// centre line, swing it 90° into the depth axis, then push it out to the right
/// edge. `-π/2` and not `+π/2`, because `rotateY` maps `+x` to `-z` and `-z` is
/// toward the viewer — the wrong way for a page block to grow.
Matrix4 bookPageLocalMatrix(BookMetrics metrics) {
  final half = metrics.width / 2;
  return _translation(half, 0, 0)
      .multiplied(Matrix4.rotationY(-math.pi / 2))
      .multiplied(_translation(half, 0, 0));
}

/// Pushes the back board behind the cover by the book's thickness.
Matrix4 bookBackLocalMatrix(BookMetrics metrics) =>
    _translation(0, 0, metrics.thickness);
