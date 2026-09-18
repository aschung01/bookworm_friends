import 'package:flutter/animation.dart';

import 'package:bookworm_friends/ui/widgets/book/turning_book.dart'
    show kSpineOnPose;
import 'package:bookworm_friends/ui/widgets/book_widget.dart'
    show kBookTurnDuration;

/// The timing of a shelf changing density, and the wave it changes in.
///
/// **The books turn.** Switching between `covers` and `spines` is not a change of
/// picture, it is the same books seen from another angle — so the transition is every
/// compressed book rotating on its spine, hinged at its left edge, from cover-on to
/// spine-on. The row narrows as they turn, because a book seen edge-on takes a third of
/// the width, and that narrowing *is* the answer to "why is this state denser".
///
/// The first version faded the row out, swapped the drawing while nothing was visible,
/// and faded back in. It was honest about being a cop-out: nothing moved, so nothing
/// was explained. A reader saw one shelf replaced by a different shelf and had to work
/// out what had happened to their books.
///
/// This costs nothing new to build. `BookWidget` already takes a `turnRadians` pose and
/// a `spine` face, `BookChassis` already renders a book at any angle, and the read pile
/// has turned single books out of a row of spines since it was written — this is that
/// same turn, applied to every book at once instead of to one.

/// How long one book takes to turn.
///
/// [kBookTurnDuration] exactly, which is what a book turning takes everywhere else in
/// this app. A shelf changing density is not a special kind of turn and should not have
/// a special speed.
const Duration kShelfDensityBookTurn = kBookTurnDuration;

/// How much of the row's total the last book's turn is delayed by.
///
/// The books do not turn in unison — each starts a little after the one to its left, so
/// the change runs across the shelf as a wave. Unison is the same information delivered
/// as a jolt; a wave says *these are separate objects, and each one turned*.
///
/// 0.35 of the total, so the last staggered book starts a third of the way in and the
/// whole row is still one gesture rather than a queue.
const double kShelfDensityStaggerSpan = 0.35;

/// How many books the wave is spread across before it gives up and moves them together.
///
/// Five, because a `covers` row shows about 3.6 books and a `spines` row about nine, so
/// the wave only has to be a wave over the handful a reader is looking at. Unbounded
/// stagger on a sixty-book shelf would put the tail's turn minutes-of-frames after the
/// head's.
///
/// **Counted from the start of the shelf, so a reader scrolled past book five sees the
/// books move in unison.** Known, and accepted for now, because that is the smaller half
/// of a problem the row has anyway: turning to `spines` shrinks the scrollable content to
/// about a quarter, so a deep scroll offset is clamped and the reader is looking at
/// different books regardless of how they turned. Fixing the wave there means bucketing
/// by distance from the leftmost *visible* book, which makes the pose depend on scroll
/// position and so cannot be cached the way [shelfDensityStaggerCurve] is. Do that
/// together with preserving the reading position, not before it.
///
/// Bucketing by `index % 6` was considered and is worse: adjacent books either side of a
/// boundary get delays of 0.35 and 0, so the later book finishes first and the wave
/// visibly runs backwards once every six books.
const int kShelfDensityStaggerBooks = 5;

/// How long the whole row takes.
///
/// Derived, not chosen: one book's turn plus the wave that carries it across the row.
/// **400ms** — longer than the 90ms fade it replaces, and it should be. The fade was
/// short because there was nothing to watch.
Duration get kShelfDensityTurnDuration => Duration(
  microseconds:
      (kShelfDensityBookTurn.inMicroseconds / (1 - kShelfDensityStaggerSpan))
          .round(),
);

/// Where in the row's total the book at [index] does its own turning.
///
/// [index] counts from the first *compressed* book, not from the start of the shelf, so
/// the wave begins at the first book that actually turns rather than at whichever slot
/// the reading books left free.
Curve shelfDensityStaggerCurve(int index) {
  const step =
      kShelfDensityStaggerSpan /
      // The last bucket must *start* at the span, so the steps divide the span into
      // that many gaps rather than into that many buckets.
      kShelfDensityStaggerBooks;
  final start = step * index.clamp(0, kShelfDensityStaggerBooks);
  return Interval(
    start,
    start + (1 - kShelfDensityStaggerSpan),
    // Eased at both ends. A book that stops turning at full speed reads as a book that
    // was cut off rather than one that came to rest against its neighbour.
    curve: Curves.easeInOutCubic,
  );
}

/// The pose a book sits at when the row is [t] of the way to `spines`.
///
/// 0 is cover-on and 1 is spine-on, which is the read pile's [kSpineOnPose]. Negative,
/// because a positive turn exposes the fore-edge instead.
double shelfDensityPose(double t) => kSpineOnPose * t;
