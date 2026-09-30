import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/read_pile.dart' show spineToneOf;
import 'package:bookworm_friends/ui/widgets/shelf/delete_book_badge.dart';

/// How wide [book] stands on a shelf drawn at `ShelfDensity.spines`.
///
/// The book's own thickness, so a long book is a visibly fat spine and a novella a
/// thin one. About **29\u201347pt** at a shelf's `bookHeight` \u2014 see [spineMetricsFor],
/// which is where that band comes from and why `BookVertical`'s 26pt default is not
/// it.
///
/// Public and separate from the widget because the row needs the number *before* it
/// builds the child: a slot's width and the drawing that goes in it are decided in
/// two different places, and the drag machinery measures the slot.
double shelfSpineWidth(Book book, double baseHeight) =>
    spineMetricsFor(book, baseHeight: baseHeight).metrics.thickness;

/// One book on a shelf, seen along its spine.
///
/// The whole drawing is [BookVertical], which the read pile already uses \u2014 this only
/// resolves the four things a shelf has to decide differently from the pile.
///
/// **Cheaper than a cover.** Its width comes from the page count rather than from a
/// decoded image, so a row of these needs no network and no decode to lay out — and
/// the row stays a lazy `ListView`, which builds about four tiles rather than one per
/// book. Both are true despite this looking like the more elaborate drawing.
///
/// **In edit mode a spine carries the remove badge but holds still — the one way it
/// deliberately differs from a cover.**
///
/// It had neither for a while, and the row's own note explained why: a 44pt disc offset
/// 22pt outside a ~37pt spine "would blanket the spines either side of it", so the badge
/// was pinned to the one book the reader had turned out instead. That reasoning held for
/// the *placement* and was then read as a verdict on the affordance, which left a
/// compressed shelf in edit mode saying nothing at all: every spine here is a
/// `LongPressDraggable` that can be reordered or moved to another shelf, and a reader
/// entering edit mode with nothing turned out had no badge anywhere on the row, and could
/// not make one, because a spine's tap is null while editing. See [deleteBadge] for the
/// placement that answers the original objection.
///
/// **The wiggle came with the badge and was then taken back out, on a report of it
/// causing dizziness.** That is not a preference to be second-guessed, and the geometry
/// says why this row is the worst case for it rather than an average one: `Wiggle` rotates
/// about a box's centre, so the displacement it produces scales with how far a point is
/// from that centre and with how *narrow* the box is relative to its height. A spine is
/// 29–47pt wide and 110–124pt tall, so the same amplitude that reads as a gentle rock on
/// an 80pt cover throws a spine's head about a third of its own width — and there are two
/// to three times as many of them in view, touching, all moving on independent random
/// phases. Covers on the planks and the Reading shelf still wiggle; this density does not.
///
/// The affordance does not depend on it. The wiggle was never the thing that said a book
/// could be removed — the badge is — and the badge is now on every spine, which is the half
/// that was actually missing. What is lost is the *reorderable* cue, and it was never
/// legible here anyway: a compressed row is dragged by holding a spine, and nothing about
/// a row of wobbling books said which of them would come loose.
class ShelfSpineTile extends StatelessWidget {
  const ShelfSpineTile({
    super.key,
    required this.book,
    required this.baseHeight,
    this.isEditMode = false,
    this.deleteBadge,
    this.onTap,
  });

  final Book book;

  /// The shelf's pre-jitter book height, not the resolved one. [spineMetricsFor]
  /// applies the jitter, which is what keeps a spine the same height as the same
  /// book's cover.
  final double baseHeight;

  /// Whether the spine shows [deleteBadge]. It does not move either way; see the note on
  /// this class.
  final bool isEditMode;

  /// The delete badge, already built, or null for a book that should not show one.
  ///
  /// A widget rather than a flag for the reason `ShelfBookTile` takes one: the badge is
  /// the row's own shape and carries a key this tile has no reason to know about.
  ///
  /// **Centred on the head of the spine, not on its top-left corner.** A cover's badge
  /// straddles a corner because a cover has 15pt of air on either side for it to hang
  /// into; a spine has none — its neighbours touch it — so a disc on the corner would sit
  /// half over the book beside it and there would be no telling which of the two it
  /// belonged to. Centred, the disc is 22pt on a 29–47pt spine, so it is wholly over its
  /// own book and no two discs can meet. That the badge is [DeleteBookBadge.targetWidth]
  /// wide rather than 44 is the other half of the same fix.
  final Widget? deleteBadge;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = spineMetricsFor(book, baseHeight: baseHeight);
    final tone = spineToneOf(book);
    final badge = isEditMode ? deleteBadge : null;

    final spine = BookVertical(
      title: book.title,
      width: size.metrics.thickness,
      height: size.metrics.height,
      fill: tone.fill,
      titleColor: tone.title,
      // **`surfaceVariant`, not the default.** `LibraryPane` paints the library
      // `#E9ECEF`; the plank a spine stands on is `surface`, but what is *behind* a
      // spine is the library. `BookVertical.background` decides whether a pale spine
      // needs an outline to be a shape at all, and measuring that against white
      // would clear the threshold for a fill that has no edge here.
      background: context.colors.surfaceVariant,
      // Two books with similar covers otherwise stand side by side as one wide
      // block. Spines in this density touch, so there is no gap to separate them.
      separator: true,
      onTap: onTap,
    );

    if (badge == null) return spine;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        spine,
        // `left`/`right` at 0 rather than a centring `Align`: the badge is already
        // exactly the spine's width, so pinning both edges is what centres the disc,
        // and it does so without giving the badge a chance to lay out wider than the
        // book and take taps over its neighbour.
        //
        // `-halfTarget` puts the disc's centre on the spine's top edge, which is the
        // same relationship a cover's badge has to its corner. The half above the spine is
        // outside this `Stack` and therefore outside its hit test — what makes it
        // tappable is [DeleteBadgeTapScope], not this box.
        Positioned(
          top: -DeleteBookBadge.halfTarget,
          left: 0,
          right: 0,
          child: badge,
        ),
      ],
    );
  }
}
