import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

/// Air either side of a book that has been turned out, at full turn.
///
/// Zero at rest, so a resting row's density is exactly what it was. Flush was the
/// first answer and it took seeing it to reject: the turned cover sat hard against
/// the spines on both sides, which reads as a book wedged in place rather than one
/// taken off the shelf, and it clipped the stacked shadows that are the only thing
/// separating a cover from the plank behind it.
const double kTurnMargin = 8;

/// The pose a book at rest in a spine row sits at: spine-on, cover edge-on.
///
/// Negative because positive turn exposes the fore-edge. See [bookParentMatrix].
const double kSpineOnPose = -math.pi / 2;

/// The projected width of a book at [pose] — what the row lays out against.
///
/// `cover×|cos| + thickness×|sin|`, the silhouette of two perpendicular faces.
/// Non-monotonic by ~3pt near cover-on, because a book at 80° is very slightly wider
/// than one at 90° — which is what a real book does, and is accepted.
double turningBookSlotWidth(BookMetrics m, double pose) =>
    m.width * math.cos(pose).abs() + m.thickness * math.sin(pose).abs();

/// The same projection as a **fraction of the book's cover width**.
///
/// `|cos| + thicknessFactor·|sin|` — [turningBookSlotWidth] divided through by
/// `m.width`, which cancels the one term a caller may not know.
///
/// **That cancellation is the whole point.** A cover's width follows its *decoded*
/// aspect ratio, so nothing above layout knows it until an image arrives; every caller
/// that needed an absolute width has had to approximate at [kDefaultCoverAspect] and
/// document the approximation. A ratio needs only [BookJitter.thicknessFactor], which
/// is hashed from the ISBN and the page count and is therefore known before anything
/// loads. Hand it to `Align.widthFactor` and the box collapses to the true projection
/// of whatever width the cover turned out to be.
///
/// The matching paint offset is [turningBookHingeFraction].
double turningBookWidthFactor(double pose, double thicknessFactor) =>
    math.cos(pose).abs() + thicknessFactor * math.sin(pose).abs();

/// How far right a turning book must be nudged, as a fraction of its cover width.
///
/// The hinge is the chassis box's left edge at every angle, and at a negative pose the
/// spine hangs a thickness to the *left* of it — so without this the drawing starts
/// outside its own box. `thickness·|sin|` over `m.width`, to pair with
/// [turningBookWidthFactor]; feed it to a `FractionalTranslation`, which is the one
/// translation that also needs no absolute width.
double turningBookHingeFraction(double pose, double thicknessFactor) =>
    thicknessFactor * math.sin(pose).abs();

/// A book hinged on its spine, turning from spine-on to cover-on as [progress] runs
/// 0 \u2192 1.
///
/// **One widget for the read pile and for a shelf drawn at `ShelfDensity.spines`**,
/// because a spine has to mean the same thing in both places: [BookVertical]'s own
/// doc says it "has to match what the chassis renders at a turn of `-\u03c0/2`, because
/// tapping a spine swaps one for the other in place". Two implementations of that
/// swap is how the two surfaces come to disagree about it.
///
/// The pile drew this inline first; it moved here when the shelves gained a spine
/// density rather than being copied, which is the only way the claim above stays
/// true.
class TurningBook extends StatelessWidget {
  const TurningBook({
    super.key,
    required this.book,
    required this.progress,
    required this.baseHeight,
    required this.spineBackground,
    required this.tone,
    this.onTap,
    this.onCoverSampled,
    this.heroTag,
  });

  final Book book;

  /// 0 is spine-on and at rest; 1 is fully turned out to the cover.
  final Animation<double> progress;

  /// The pre-jitter book height this row draws at. [spineMetricsFor] applies the
  /// jitter, so a turned cover is exactly as thick as the spine that was tapped.
  final double baseHeight;

  /// The colour behind the spine, for deciding whether it needs an outline.
  ///
  /// Required rather than defaulted, because [BookVertical]'s own default is right
  /// nowhere in this app \u2014 the pile sits on `sheetBackground` and a shelf on
  /// `surfaceVariant`. See that parameter's doc.
  final Color spineBackground;

  /// The spine's fill and its title ink, resolved together. Use `spineToneOf`.
  final ({Color fill, Color title}) tone;

  final VoidCallback? onTap;
  final ValueChanged<Color>? onCoverSampled;

  /// Set only while this book is the one turned out, so a flight has one source.
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final size = spineMetricsFor(book, baseHeight: baseHeight);
    final m = size.metrics;

    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value;
        final pose = kSpineOnPose * (1 - t);
        final slot = turningBookSlotWidth(m, pose);
        // The hinge is the chassis box's left edge at every angle, and at a negative
        // pose the spine hangs a thickness to the *left* of it. Offset the box by
        // that much so the drawing's leftmost point is the slot's, and a resting row
        // is laid out exactly as flat spines are.
        final hinge = m.thickness * math.sin(pose).abs();
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: kTurnMargin * t),
          child: SizedBox(
            width: slot,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: hinge,
                  bottom: 0,
                  width: m.width,
                  height: m.height,
                  child: child!,
                ),
              ],
            ),
          ),
        );
      },
      // Built once, outside the builder: it owns an ImageStream, and rebuilding it
      // every frame of the turn would re-resolve the cover 16 times.
      child: BookWidget(
        imageUrl: book.thumbnail,
        isbn: book.isbn,
        title: book.title,
        height: baseHeight,
        pageCount: book.pageCount,
        // The same jitter the flat spine was drawn at, handed over rather than
        // recomputed, so the cover is exactly as thick as the spine that was tapped.
        jitterOverride: size.jitter,
        turnRadians: progress.drive(Tween<double>(begin: kSpineOnPose, end: 0)),
        pivot: Alignment.centerLeft,
        spine: BookVertical(
          title: book.title,
          width: m.thickness,
          height: m.height,
          fill: tone.fill,
          titleColor: tone.title,
          background: spineBackground,
          separator: true,
          // A face of a solid object cannot have a notch in its head that the faces
          // beside it do not. See [BookVertical.arch].
          arch: false,
        ),
        heroTag: heroTag,
        onCoverSampled: onCoverSampled,
        onTap: onTap,
      ),
    );
  }
}
