import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/read_pile.dart' show spineToneOf;

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
/// decoded image, so a row of these needs no network and no decode to lay out. That
/// is the reason `ShelfDensity.spines` costs less than `ShelfDensity.leaning`
/// despite looking like the more elaborate drawing.
class ShelfSpineTile extends StatelessWidget {
  const ShelfSpineTile({
    super.key,
    required this.book,
    required this.baseHeight,
    this.onTap,
  });

  final Book book;

  /// The shelf's pre-jitter book height, not the resolved one. [spineMetricsFor]
  /// applies the jitter, which is what keeps a spine the same height as the same
  /// book's cover.
  final double baseHeight;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = spineMetricsFor(book, baseHeight: baseHeight);
    final tone = spineToneOf(book);

    return BookVertical(
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
  }
}
