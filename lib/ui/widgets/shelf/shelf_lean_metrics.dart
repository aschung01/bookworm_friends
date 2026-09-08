import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

/// How far one shingled book is offset from the one in front of it, as a fraction
/// of the shelf's base book height.
///
/// 0.16 \u2014 about **20.3pt** on a 390\u00d7844 phone, where a cover is ~84.4pt, so a
/// reader sees about a quarter of each compressed book. At that width recognition is
/// being done by **colour**, not by type, which is why a quarter is enough and why
/// the strip revealed is the cover's right edge rather than its left.
///
/// **A fraction of the book height, not of the cover's width.** `shelf_row.dart`
/// records that a cover's width follows its decoded aspect ratio and its jittered
/// height, so nothing above layout knows how wide a book is. A step in absolute
/// points needs no width at all, and it gives the row a uniform rhythm where a
/// proportional step would be ragged for a reason no reader could see.
///
/// It scales with the device the same way `bookHeight = screenHeight * 0.15` does.
///
/// **What it costs, so the trade is on the record.** At this step a shelf with one
/// book in progress shows about **9.7** books against `covers`' 3.57. Dropping to
/// 0.124 (15.7pt, 19% of a cover) would fit twelve, and was considered and declined:
/// 24% is the figure the \"colour, not type\" argument was made about.
const double kShelfLeanStep = 0.16;

/// The offset of the shingled book at [index] within its group, in logical pixels.
double shelfLeanOffset(int index, double baseHeight) =>
    index * baseHeight * kShelfLeanStep;

/// How wide the shingled group of [count] books is.
///
/// Every book but the last shows only [kShelfLeanStep] of itself; the last is
/// overlapped by nothing and draws its whole cover.
///
/// **The last cover's true width is not knowable before it decodes**, so this
/// resolves it at [kDefaultCoverAspect]. That is the same approximation
/// [spineMetricsFor] makes and documents \u2014 no caller can know a real aspect ratio
/// without decoding every cover \u2014 so it is a precedent being followed rather than a
/// liberty being taken. A cover that decodes wider than nominal overhangs into the
/// trailing slack instead of being clipped, which is why the group is drawn with
/// `Clip.none`.
double shelfLeanGroupWidth(int count, double baseHeight) {
  if (count <= 0) return 0;
  final nominalCover = baseHeight * kDefaultCoverAspect;
  return shelfLeanOffset(count - 1, baseHeight) + nominalCover;
}

/// How wide the *hit* area of the shingled book at [index] of [count] should be.
///
/// **The exposed strip, not the whole cover \u2014 and this is the part that is easy to
/// get wrong.** A `RenderBox` hit-tests its entire rect regardless of what is painted
/// there. The group paints front-to-back left to right, so the frontmost book is also
/// the first one hit-tested; if its slot were a full cover wide it would claim taps
/// landing on the visible strip of the book three along, which sits well inside its
/// rect. Sizing each slot to the strip a reader can actually see makes the hit area
/// and the drawing agree.
///
/// The last book is the exception: nothing overlaps it, so all of it is visible and
/// all of it should be tappable.
double shelfLeanSlotWidth(int index, int count, double baseHeight) =>
    index == count - 1
    ? baseHeight * kDefaultCoverAspect
    : baseHeight * kShelfLeanStep;
