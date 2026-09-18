import 'package:flutter/material.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/book/turning_book.dart'
    show kSpineOnPose;
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/wiggle.dart';

/// One book on a shelf, drawn face-out: its cover, the ribbon if it is in
/// progress, and in edit mode the badge that deletes it.
///
/// Lifted out of `_ShelfRowState` when the shelf gained more than one way to draw a
/// book. The row still owns the slot, the draggable, the shift animation and every
/// gesture; this owns only what goes *inside* a slot, which is what makes it
/// swappable for a spine or a shingled cover.
///
/// **It takes what it needs rather than reaching for it.** [turnDrive], the badge
/// and the callbacks all arrive as parameters, because the values behind them live
/// in the row's `State` and a widget that read them from there could not have been
/// moved out of it. The row is still the only thing that knows which book is in the
/// air.
class ShelfBookTile extends StatelessWidget {
  const ShelfBookTile({
    super.key,
    required this.book,
    required this.height,
    required this.isEditMode,
    this.withHero = true,
    this.turnDrive,
    this.pose,
    this.spine,
    this.deleteBadge,
    this.onTap,
    this.onCoverSampled,
  });

  final Book book;
  final double height;
  final bool isEditMode;

  /// Suppressed on the cover left behind by a lift, so the flight has one source.
  final bool withHero;

  /// The turn this cover carries, when it is the one being set down. Null for every
  /// other book on the row, whose own hold this would otherwise replace.
  final Animation<double>? turnDrive;

  /// Where this book has been *put*, in radians — 0 cover-on, [kSpineOnPose] spine-on.
  ///
  /// What turns the shelf between densities. Distinct from [turnDrive] in both of the
  /// ways `BookWidget.turnRadians` documents: it can express `-π/2`, and it *adds to*
  /// the press hold rather than replacing it — so a book caught half-way through the
  /// change still answers a finger, from wherever it currently stands.
  ///
  /// May not be combined with [turnDrive], which owns the hold outright. The row passes
  /// one or the other; see `_ShelfRowState._densityPose`.
  final Animation<double>? pose;

  /// The face seen along the binding, for a book turned far enough to show one.
  ///
  /// Required whenever [pose] can reach [kSpineOnPose], and unused at rest cover-on.
  /// Without it the chassis turns to show nothing, and the book vanishes edge-on.
  final Widget? spine;

  /// The delete badge, already built, or null for a book that should not show one.
  ///
  /// A widget rather than a flag, because the badge is the row's own private shape
  /// and carries a key this tile has no reason to know about. Null in
  /// `ShelfDensity.spines` for every book except the one turned out: a 44pt disc
  /// offset 22pt outside a ~37pt spine covers the spines either side of it, and in
  /// that density they are touching.
  final Widget? deleteBadge;

  final VoidCallback? onTap;
  final ValueChanged<Color>? onCoverSampled;

  @override
  Widget build(BuildContext context) {
    final badge = deleteBadge;
    return Wiggle(
      enabled: isEditMode,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          BookWidget(
            imageUrl: book.thumbnail,
            isbn: book.isbn,
            title: book.title,
            height: height,
            pageCount: book.pageCount,
            heroTag: withHero ? 'book_${book.isbn}' : null,
            pressEffect: !isEditMode,
            turnDrive: turnDrive,
            turnRadians: pose,
            spine: spine,
            // Hinged on the binding, so a book turning between densities pivots where a
            // real one would rather than about its middle. Only meaningful with [pose];
            // `Alignment.center` is `BookWidget`'s own default and is what the press
            // hold wants when nothing has been posed.
            pivot: pose == null ? Alignment.center : Alignment.centerLeft,
            // The shelves are where a cover is most likely to decode first, so
            // this is the path that fills `books.cover_color` in for most books.
            // The action declines anything that is not the signed-in reader's.
            onCoverSampled: onCoverSampled,
            onTap: onTap,
            // Null, always. The hold on a shelved book is answered by the
            // draggable's own recognizer, because a book has to *already be in a
            // drag* by the time edit mode appears, and a timer beside that
            // recognizer only raced it.
            onLongPress: null,
          ),
          if (book.status == 1)
            Positioned(
              top: 0,
              // Slid in from the fore-edge by how far through the book the reader
              // is — display only, and it writes nothing. The mark reads; a sheet
              // asks. A book with no recorded position keeps the shipped pin, so a
              // shelf of unanswered books looks exactly as it did before the
              // column existed.
              right: readingBookmarkInsetFor(
                book.progress,
                coverWidth: height * kDefaultCoverAspect,
              ),
              // The ribbon and its shadow, from `reading_bookmark.dart` — which is
              // also what the Library Card draws, scaled. It was drawn inline here
              // and the card drew a red rectangle instead; one state deserves one
              // mark.
              child: const ReadingBookmark(),
            ),
          if (isEditMode && badge != null)
            Positioned(top: -22, left: -22, child: badge),
        ],
      ),
    );
  }
}
