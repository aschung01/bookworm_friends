import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';

/// A library — shelves scrolling behind a sheet.
///
/// This is the layer the shell keeps persistent, so it takes everything it draws
/// as parameters and reads no shell state itself.
///
/// [sheet] is supplied by the caller rather than built here, because a tab switch
/// changes the sheet and must leave this untouched. Passing it in is what makes
/// "the library is never drawn twice" structural instead of a convention: there is
/// one instance of this widget per page and three possible sheets above it.
class LibraryPane extends StatelessWidget {
  final List<Shelf> shelves;

  /// Needed by the library itself, not only by the sheet: read books are kept off
  /// the shelves, and the "add your first book" state depends on whether there are
  /// any at all.
  final List<Book> finishedBooks;

  final LibraryMode mode;

  /// Whose library this is. Only the empty state cares: "Your library is empty…"
  /// with a hint about adding a book is the wrong sentence to show over somebody
  /// else's shelves.
  ///
  /// One pane draws both readers now that a visit is a state of the shell rather
  /// than a page of a pager, so this is the only thing left that has to be told.
  final bool isSelf;

  /// Fades the shelves because they belong to the library you are leaving, not the
  /// one you asked for.
  ///
  /// Held rather than blanked: switching whose library is on screen re-points two
  /// queries, and the frame after the tap has no data for the new reader. See
  /// `_HomePageState._onScreen`, which holds the pair, and the chip that names what
  /// is arriving.
  final bool stale;

  /// Floats over the library, pinned to the bottom of the screen. Expected to be a
  /// [LibrarySheet].
  ///
  /// It used to be the second child of a `Column` whose first was an [Expanded]
  /// library, so the sheet could never overlap anything: it took its height from
  /// layout and the library got what was left. It floats now, which is what lets it
  /// rise over the shell's bar — and what makes [bottomInset] necessary, since
  /// nothing shrinks to make room for it any more.
  final Widget sheet;

  /// Room kept clear at the top for the shell's bar, which this pane is painted
  /// *under* so that [sheet] can rise over it.
  ///
  /// Nothing is painted in it — not even the library's own background — because the
  /// bar is behind the pane in the stack and a background of ours would hide it.
  final double topInset;

  /// Room added below the shelves so the last one can be scrolled clear of a
  /// collapsed [sheet]. Comes from `LibrarySheet.onRestingExtent`, which measures it.
  final double bottomInset;

  final void Function(String shelfId, String name) onEditShelfName;
  final void Function(String shelfId) onDeleteShelf;
  final VoidCallback onEnterEditMode;
  final VoidCallback? onAddShelf;
  final void Function(
    String bookId,
    String targetShelfId,
    List<String> orderedBookIds,
  )?
  onMoveBook;
  final void Function(String shelfId, List<String> bookIds)? onReorderBooks;
  final void Function(String bookId)? onDeleteBook;
  final Future<void> Function()? onRefresh;

  const LibraryPane({
    super.key,
    required this.shelves,
    required this.finishedBooks,
    required this.mode,
    required this.sheet,
    required this.onEditShelfName,
    required this.onDeleteShelf,
    required this.onEnterEditMode,
    this.isSelf = true,
    this.stale = false,
    this.topInset = 0,
    this.bottomInset = 0,
    this.onAddShelf,
    this.onMoveBook,
    this.onReorderBooks,
    this.onDeleteBook,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Read books live in the "Books read" pile at the bottom of this library, so
    // they are kept off the shelves above it: showing both listed every read
    // book twice.
    //
    // Then the in-progress books are pulled to the head of each row. Both are
    // display transforms over the same list and neither writes a position, so they
    // belong in one place — here — rather than one here and one inside a widget.
    // Order between them is a readability choice only: one filters status 2, the
    // other promotes status 1.
    final shelvesOnDisplay = withReadingFirst(withoutFinishedBooks(shelves));
    // Deliberately measured against the *unfiltered* shelves. `finishedBooks` is
    // only the books matching the pile's year/month filter, so a library made up
    // entirely of read books must not offer to add a first book just because the
    // filter happens to exclude them all.
    final bool hasNoBooks =
        (shelves.isEmpty || shelves.every((s) => s.books.isEmpty)) &&
        finishedBooks.isEmpty;

    // **The empty state is library *content*, not a different screen.**
    //
    // This used to `return` here, and that was the bug: an empty library rendered no
    // sheet at all, so inside a visit to someone whose shelves are empty the Friends
    // tab had nothing to switch and the tab bar looked dead. It cost nothing while a
    // visit hid the bar and the sheet was only ever the read view — now that the sheet
    // is the shell's one switcher and the bar is on screen throughout, the sheet has to
    // be there whatever the library behind it contains.
    //
    // So it goes in the same slot the shelves do, and everything below — the refresh
    // gesture, the stale fade, the background, the sheet floating over it — applies
    // uniformly.
    Widget content;
    if (hasNoBooks) {
      content = LayoutBuilder(
        // Centred in the band the reader can actually see: the collapsed sheet floats
        // over the bottom [bottomInset] of this box, and art centred in the whole box
        // would sit half behind it.
        //
        // In a scroll view rather than a bare `Center` so the pull-to-refresh above
        // still has something to report — `RefreshIndicator` needs a `Scrollable`, and
        // a friend's empty library is exactly the one you want to be able to re-check.
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - bottomInset).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SadCharacter(height: 100),
                  const SizedBox(height: 16),
                  Text(
                    isSelf ? l10n.libraryEmptySelf : l10n.libraryEmptyOther,
                    style: AppTextStyles.body.copyWith(
                      color: context.colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Only your own empty library is an invitation. There is nothing a
                  // reader can do about somebody else's.
                  if (isSelf)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add,
                          size: 20,
                          color: context.colors.secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.addBookHintSuffix,
                          style: AppTextStyles.body.copyWith(
                            color: context.colors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      content = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        // The bottom inset is the collapsed sheet floating over this list: without it
        // the last shelf could never be scrolled out from behind the sheet.
        padding: EdgeInsets.only(top: 16, bottom: 16 + bottomInset),
        child: Column(
          children: [
            ...shelvesOnDisplay.map(
              (shelf) => ShelfRow(
                shelf: shelf,
                mode: mode,
                onEditName: () => onEditShelfName(shelf.id, shelf.name),
                onDelete: () => onDeleteShelf(shelf.id),
                onLongPress: onEnterEditMode,
                onBookDropped: onMoveBook != null
                    ? (bookId, orderedBookIds) =>
                          onMoveBook!(bookId, shelf.id, orderedBookIds)
                    : null,
                onReorderBooks: onReorderBooks != null
                    ? (bookIds) => onReorderBooks!(shelf.id, bookIds)
                    : null,
                onDeleteBook: mode == LibraryMode.editLibrary
                    ? onDeleteBook
                    : null,
              ),
            ),
            if (mode == LibraryMode.editLibrary && onAddShelf != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: TextButton.icon(
                  onPressed: onAddShelf,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(l10n.addShelf, style: AppTextStyles.label),
                ),
              ),
          ],
        ),
      );
    }

    Widget shelfList = content;

    if (onRefresh != null) {
      shelfList = RefreshIndicator(
        color: context.colors.brandText,
        onRefresh: onRefresh!,
        child: shelfList,
      );
    }

    // Outside the `RefreshIndicator` on purpose, so the clearance tests keep
    // measuring the same box, and inside the background below, so only the shelves
    // fade and never the surface they stand on.
    shelfList = AnimatedOpacity(
      opacity: stale ? 0.4 : 1,
      duration: const Duration(milliseconds: 150),
      child: shelfList,
    );

    // NOTE: the background has to live *outside* RefreshIndicator. That widget
    // wraps its child in a loose Stack, which would let the container shrink to
    // the shelves' height and leave the rest of the library unpainted.
    final library = Container(
      width: double.infinity,
      color: context.colors.surfaceVariant,
      child: shelfList,
    );

    // The sheet floats over the library rather than sitting above it, which is what
    // lets it rise over the shell's bar. The library keeps the whole pane below
    // [topInset] and insets its own content instead — so the shelves scroll *behind*
    // the sheet, and [bottomInset] is what keeps the last of them reachable.
    return LibraryPaneFrame(topInset: topInset, sheet: sheet, library: library);
  }
}

/// The shell's one arrangement: library content below the bar, a sheet floating over
/// it, and the bar's shadow between them.
///
/// **Extracted so that “there is always a sheet” is structural rather than a habit.**
/// It was inlined in [LibraryPane], which made the sheet the privilege of one state:
/// every other thing the shell can show — an empty library, a library still loading, a
/// library whose query failed — was returned instead of the pane, and took the sheet
/// with it. That cost nothing while the sheet was only the read view and the tab bar
/// hid itself during a visit. It costs a great deal now: the sheet *is* the friend
/// switcher and the bar is on screen throughout, so a state with no sheet is a tab bar
/// that does nothing when tapped. Two bugs of exactly that shape were reported before
/// this was pulled out.
///
/// So the rule this widget exists to enforce: whatever the library is doing, the chrome
/// over it is the same chrome. Only [library] changes.
class LibraryPaneFrame extends StatelessWidget {
  /// Whatever the library is right now: shelves, an empty state, a skeleton, an error.
  final Widget library;

  /// Floats at the bottom, over [library] and over the shell's bar.
  final Widget sheet;

  /// Room kept clear at the top for the shell's bar, which this frame is painted
  /// behind. Nothing paints in it — a background of ours would hide the bar — and
  /// [library] is positioned below it, which is what keeps a skeleton or an error from
  /// drawing over the title.
  final double topInset;

  const LibraryPaneFrame({
    super.key,
    required this.library,
    required this.sheet,
    this.topInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: topInset,
          left: 0,
          right: 0,
          bottom: 0,
          child: ColoredBox(
            color: context.colors.surfaceVariant,
            child: library,
          ),
        ),
        // Over the library, under the sheet — which is the whole of why it is here
        // rather than on the bar. See [_BarShadow].
        if (topInset > 0)
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            child: const _BarShadow(key: kBarShadowKey),
          ),
        Positioned(left: 0, right: 0, bottom: 0, child: sheet),
      ],
    );
  }
}

/// The bar's shadow, for tests that assert it is present.
@visibleForTesting
const Key kBarShadowKey = Key('library-bar-shadow');

/// The shell bar's shadow, re-cast onto the library from the library's own top edge.
///
/// `_LibraryBar` used to be the `Scaffold`'s app bar, painted *after* the body, so the
/// elevation on its `Material` fell across the shelves and nothing here had to think
/// about it. The bar is behind the pager now — which is what lets a sheet rise over it
/// — and a shadow cast from back there lands *under* this page, where the library's
/// own opaque background paints straight over it.
///
/// So the bar no longer carries elevation at all, and its shadow is drawn here
/// instead: the one place it can still be seen, over the shelves and under the sheet.
///
/// **Constant, not driven by scroll offset.** It was briefly faded in with the
/// library's offset, on the reasoning that an iOS nav bar earns its separator by having
/// content pass under it. That is the wrong model for this screen and the change was
/// reverted. The shadow here is the bottom edge of *the encasing* — the design record's
/// name for the fixed frame this shell is built from: "white surface bar with elevation
/// 4 above, `#F8F9FA` well between, white sheet with an upward shadow below". The sheet
/// below casts its shadow upward whatever the library is doing, and the bar is the same
/// structure at the other end. An encasing that comes and goes is not an encasing, and
/// the library at rest looked unfinished without it.
///
/// This draws the *same* shadow rather than something that looks like it. A
/// `LinearGradient` was tried first and cannot be made to match — measured at 3x, the
/// real shadow is a blur reaching ~10pt with a long Gaussian tail (alpha 44 at the
/// edge, still 13 nine points down), and a linear ramp fitted to its start is visibly
/// heavy through the middle. `Canvas.drawShadow` is the call `RenderPhysicalShape`
/// makes on a `Material`'s behalf, so handing it the bar's rect and elevation is not
/// an approximation of the bar's shadow, it *is* the bar's shadow.
class _BarShadow extends StatelessWidget {
  const _BarShadow({super.key});

  /// How deep a strip to reserve. Only a bound: whatever the shadow does not reach
  /// stays transparent, and anything past the strip is clipped away, so this is set
  /// comfortably beyond the ~10pt an elevation of 4 actually covers.
  static const double _extent = 14;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _extent,
    // Without this the shadow blurs *upward* out of the strip too, onto the bar
    // behind us — which is the dark band along the bar's bottom edge that this whole
    // widget exists to get rid of.
    child: ClipRect(
      child: CustomPaint(
        painter: _BarShadowPainter(
          // What `Material` resolves its own shadow colour to under Material 3.
          color: Theme.of(context).colorScheme.shadow,
        ),
      ),
    ),
  );
}

class _BarShadowPainter extends CustomPainter {
  const _BarShadowPainter({required this.color});

  final Color color;

  /// The bar row that casts the shadow, mirroring `_HomePageState._libraryBarRow`.
  ///
  /// `drawShadow` places its light relative to the caster's bounds — 600pt above the
  /// *top* edge — so the caster's height changes the result. It has to be the elevated
  /// row on its own, not the whole of [LibraryPane.topInset]: the status bar and the
  /// visit rail above it belong to an `AppBar` that carries no elevation.
  static const double _casterHeight = 56;

  /// `_LibraryBar`'s former `Material` elevation.
  static const double _elevation = 4;

  @override
  void paint(Canvas canvas, Size size) {
    // The caster sits directly above us: same width as the bar, bottom edge on our
    // top edge. Only its downward spill lands inside the strip; the rest is clipped.
    final caster = Path()
      ..addRect(Rect.fromLTWH(0, -_casterHeight, size.width, _casterHeight));
    // `transparentOccluder: false` because the bar's surface is opaque, which is the
    // same conclusion `RenderPhysicalShape` reaches from `color.alpha != 0xFF`.
    canvas.drawShadow(caster, color, _elevation, false);
  }

  @override
  bool shouldRepaint(_BarShadowPainter oldDelegate) =>
      oldDelegate.color != color;
}
