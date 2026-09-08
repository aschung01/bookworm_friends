import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_shelf_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/update_shelf_name_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';

/// Shelf-scope management: reorder, rename and delete shelves.
///
/// Presented as a sheet *over* the library's edit mode rather than as a
/// page-level mode swap, so dismissing it returns the user exactly where they
/// were. Every action persists immediately, so the sheet has no save step.
///
/// **`isScrollControlled` is what makes [_kMaxSheetHeightFraction] mean
/// anything.** Left at its default, `showModalBottomSheet` clamps the sheet to
/// `scrollControlDisabledMaxHeightRatio` — 9/16 of the screen — and the taller
/// cap below is then silently unreachable. That was the bug: the sheet asked for
/// 70% and was held at 56%.
Future<void> showManageShelvesBottomSheet(BuildContext context) {
  return CNBottomSheet.show<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _ManageShelvesSheet(),
  );
}

/// How much of the screen the sheet may fill.
///
/// A cap, not a height: the sheet is a `min`-sized column, so a reader with three
/// shelves still gets a short sheet. It matters for the reader with twenty, who
/// was previously scrolling a list through a third of a screen — and it matters
/// more now that each row carries covers and is therefore taller.
const double _kMaxSheetHeightFraction = 0.8;

class _ManageShelvesSheet extends ConsumerStatefulWidget {
  const _ManageShelvesSheet();

  @override
  ConsumerState<_ManageShelvesSheet> createState() =>
      _ManageShelvesSheetState();
}

class _ManageShelvesSheetState extends ConsumerState<_ManageShelvesSheet> {
  /// Owned here rather than by the caller so the sheet is self-contained.
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _rename(Shelf shelf) {
    _nameController.text = shelf.name;
    showUpdateShelfNameBottomSheet(
      context,
      controller: _nameController,
      onSavePressed: () async {
        // Pops the rename sheet only, leaving this one open underneath.
        Navigator.pop(context);
        final name = _nameController.text.trim();
        if (name.isNotEmpty && name != shelf.name) {
          await ref
              .read(libraryActionsProvider)
              .updateShelfName(shelf.id, name);
        }
      },
    );
  }

  void _delete(Shelf shelf) {
    showDeleteShelfBottomSheet(
      context,
      onDeletePressed: () async {
        Navigator.pop(context);
        await ref.read(libraryActionsProvider).deleteShelf(shelf.id);
      },
    );
  }

  void _reorder(List<Shelf> shelves, int oldIndex, int newIndex) {
    final ids = shelves.map((s) => s.id).toList();
    ids.insert(newIndex, ids.removeAt(oldIndex));
    ref.read(libraryProvider.notifier).reorderShelves(ids);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Read straight from the provider: reorder, rename and delete are all
    // optimistic, so the list stays in sync without a local copy that could go
    // stale mid-drag.
    //
    // **Filtered exactly as the library filters it.** A finished book keeps its
    // `shelf_id` but is drawn in the read pile rather than on the plank, so a row
    // built from the raw list would preview covers that — in the words of
    // [shelvedBookCount] — are provably not there: a shelf whose books are all read
    // showed three covers here and an empty plank in the library. Running the
    // library's own [withoutFinishedBooks] over them once makes the covers *and* the
    // count agree with the shelf the reader is looking at, and makes
    // `shelf.books.length` the count [shelvedBookCount] would have returned.
    final shelves = withoutFinishedBooks(
      ref.watch(libraryProvider).valueOrNull ?? const <Shelf>[],
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * _kMaxSheetHeightFraction,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // 20 rather than 25, so the title shares a left edge with the grips
              // below it. The header used to hang 5pt inside a list whose own
              // content started 37pt further in, which read as two unrelated blocks.
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.manageShelves, style: AppTextStyles.subtitle),
                        if (shelves.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              l10n.dragToReorder,
                              // `body`, not `label`: this is an instruction read as
                              // a sentence, and `label` is the semibold token for
                              // things you tap. w600 grey made it look like a
                              // disabled control.
                              style: AppTextStyles.body.copyWith(
                                color: context.colors.secondaryText,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // A close button, not "Done": every action in this sheet is
                  // already persisted, so there is nothing to commit and
                  // nothing a Cancel could discard. On iOS 26 this renders as
                  // the native glass circle, which is the platform's own idiom
                  // for dismissing a sheet that presents content rather than a
                  // form. (Unlike the library sub-header, a sheet corner is the
                  // right place for glass: it is the sheet's only action, so it
                  // can't invert the hierarchy.)
                  AdaptiveIconButton(
                    symbol: 'xmark',
                    icon: Icons.close,
                    // [kIconButtonDiameter] also keeps the touch target the Done
                    // button had.
                    diameter: kIconButtonDiameter,
                    symbolSize: kIconButtonSymbolSize,
                    iconSize: kIconButtonIconSize,
                    semanticLabel: l10n.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (shelves.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 12, 25, 28),
                child: Text(
                  l10n.emptyList,
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.secondaryText,
                  ),
                ),
              )
            else
              Flexible(
                // Transparent Material so the pencil and the bin can show ink
                // feedback. Nothing else in a row takes a tap — see
                // [_ManageShelfRow.onRename].
                child: Material(
                  type: MaterialType.transparency,
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    // Dragging starts from the grip, immediately.
                    buildDefaultDragHandles: false,
                    itemCount: shelves.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        _reorder(shelves, oldIndex, newIndex),
                    proxyDecorator: (child, index, animation) => Material(
                      color: context.colors.surface,
                      elevation: 4,
                      child: child,
                    ),
                    itemBuilder: (context, index) {
                      final shelf = shelves[index];
                      return _ManageShelfRow(
                        key: ValueKey(shelf.id),
                        shelf: shelf,
                        index: index,
                        canReorder: shelves.length > 1,
                        onRename: () => _rename(shelf),
                        onDelete: () => _delete(shelf),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ManageShelfRow extends StatelessWidget {
  final Shelf shelf;
  final int index;
  final bool canReorder;

  /// Reached by the pencil alone.
  ///
  /// **The name used to be a second way in, and it was worse than having none.**
  /// It gave the row a full-width `InkWell`, and the theme's press tint then lit
  /// the whole row as a grey slab on touch — including on a *drag*, since the grip
  /// sits inside that row. So the one gesture this sheet is built around flashed a
  /// highlight that belonged to a different action. The pencil is explicit, it is
  /// already a 48pt target, and it is the only affordance that says "rename" — so
  /// the row is now inert everywhere except its three controls.
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ManageShelfRow({
    super.key,
    required this.shelf,
    required this.index,
    required this.canReorder,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        if (canReorder)
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: l10n.dragToReorder,
              child: ColoredBox(
                color: Colors.transparent,
                child: Padding(
                  // Tighter horizontally than it was (20) to buy the name back the
                  // width the covers now take on this side; 13 vertical keeps the
                  // grip's own target at 48pt regardless of the row's height.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  child: Icon(
                    Icons.drag_handle,
                    size: 22,
                    color: context.colors.secondaryText,
                  ),
                ),
              ),
            ),
          )
        else
          // Matches the header's inset rather than the grip's width: with one shelf
          // there is no second row to line up with, so the covers may as well start
          // where the title does.
          const SizedBox(width: 20),
        // Padded rather than bare: the grip is 48pt tall, so an unpadded 42pt stack
        // left 3pt between one row's covers and the next's and the column read as a
        // single ladder. 12 sets the row at 66pt — the artwork-row height Apple's own
        // lists use — and gives the stacks air to be separate objects.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _ShelfCoverStack(books: shelf.books),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            // Structured as `ShelfLabel` structures the plank's tab, and for the
            // same reason: the name is what gives way when the row runs out of
            // width. In a single text run the count trails the name and is
            // therefore the first thing an ellipsis eats — losing the only number
            // on the row exactly on the long-named shelves where it is most
            // useful.
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    shelf.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: AppTextStyles.body,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  // The same key the library plank uses, so the two cannot phrase
                  // the same shelf differently: `7` in English, `7권` in Korean.
                  // It is also what stops the three-cover cap from lying — a shelf
                  // of seven and a shelf of three drew the same stack and there was
                  // nothing on the row to tell them apart.
                  l10n.bookCountLabel(shelf.books.length),
                  maxLines: 1,
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
        // **Both glyphs are neutral, and the red lives in the confirmation.**
        // A bin drawn in `softRedColor` on every row put eleven alarm-coloured
        // marks down the right edge of a list whose content is the shelf names,
        // so the most destructive control outranked the thing it acts on. The
        // danger has not been hidden — it has been moved to where the decision is
        // actually taken, and `showDeleteShelfBottomSheet` still presents it as a
        // destructive action.
        IconButton(
          onPressed: onRename,
          tooltip: l10n.edit,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(
            Icons.edit_outlined,
            size: 21,
            color: context.colors.secondaryText,
          ),
        ),
        IconButton(
          onPressed: onDelete,
          tooltip: l10n.delete,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(
            Icons.delete_outline,
            size: 22,
            color: context.colors.secondaryText,
          ),
        ),
      ],
    );
  }
}

/// Covers a row shows before it stops adding them.
///
/// Three, not four: the stack is on the leading edge now and shares the row with
/// the name, and three larger faces identify a shelf better than four slivers. The
/// count beside the name is what carries "and more" — see [_ManageShelfRow].
const int _kMaxPreviewCovers = 3;

/// Preview cover geometry. 2:3 is the proportion the shelves draw books at, so a
/// cover here is the same shape as the one it stands for.
const double _kPreviewCoverHeight = 42;
const double _kPreviewCoverWidth = _kPreviewCoverHeight * 2 / 3;

/// How far each cover is offset from the one beneath it.
///
/// Two thirds of a cover, so what shows of each is a strip wide enough to read as
/// a cover rather than as a stripe. Tighter than this and a shelf of coverless
/// books — which are flat colour blocks — turns into a barcode; the render preview
/// at `test/manage_shelves_render_preview.dart` is where that was caught.
const double _kPreviewCoverStep = 18;

/// Width the stack occupies whatever it holds — a full stack, one cover, or none.
///
/// **Fixed, and that is the whole point.** The stack used to size to its contents
/// on the *trailing* edge, so its left edge landed wherever the book count put it
/// and no two rows agreed: a one-book shelf's cover sat marooned against the
/// buttons while a four-book shelf's began much further left. A constant slot at
/// the leading edge gives the list one spine, and lets the name column start at the
/// same x on every row.
const double _kPreviewSlotWidth =
    _kPreviewCoverWidth + (_kMaxPreviewCovers - 1) * _kPreviewCoverStep;

/// Prefix for the per-cover keys, which is how tests count what a row drew: at
/// this size a cover is a colour block with no text to match on.
const String kShelfCoverKeyPrefix = 'shelf-cover-';

/// Key for the placeholder an empty shelf draws in place of covers.
///
/// Deliberately *not* under [kShelfCoverKeyPrefix]: a test counting covers matches
/// on that prefix, and a placeholder sharing it would be counted as a cover — so an
/// empty shelf would have reported one book.
const Key kShelfCoverEmptyKey = ValueKey('shelf-empty-slot');

/// The first few books on a shelf, overlapping, as a way of telling one shelf
/// from another without reading its name.
///
/// **Front cover on top.** The list is painted back-to-front so index 0 ends up
/// unobstructed: it is the one the reader sees whole, and the shelves themselves
/// order books left to right.
///
/// [books] must already be the plank's books rather than the shelf's whole row —
/// see the note in `_ManageShelvesSheetState.build` on [withoutFinishedBooks].
class _ShelfCoverStack extends StatelessWidget {
  final List<Book> books;

  const _ShelfCoverStack({required this.books});

  @override
  Widget build(BuildContext context) {
    final shown = books.take(_kMaxPreviewCovers).toList();

    return ExcludeSemantics(
      // Decoration, and the row already announces the shelf by name and count. A
      // screen reader reading three unlabelled images per shelf would bury both.
      child: SizedBox(
        width: _kPreviewSlotWidth,
        height: _kPreviewCoverHeight,
        child: shown.isEmpty
            // An outline rather than nothing: it holds the row's alignment and says
            // "this shelf is empty" in the place the reader is already looking for
            // what is on it. Blank space here read as a rendering fault.
            ? const Align(
                alignment: Alignment.centerLeft,
                child: _EmptyCoverSlot(),
              )
            : Stack(
                children: [
                  for (var i = shown.length - 1; i >= 0; i--)
                    Positioned(
                      left: i * _kPreviewCoverStep,
                      top: 0,
                      child: _PreviewCover(book: shown[i]),
                    ),
                ],
              ),
      ),
    );
  }
}

class _EmptyCoverSlot extends StatelessWidget {
  const _EmptyCoverSlot();

  @override
  Widget build(BuildContext context) => Container(
    key: kShelfCoverEmptyKey,
    width: _kPreviewCoverWidth,
    height: _kPreviewCoverHeight,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: context.colors.divider),
    ),
  );
}

class _PreviewCover extends StatelessWidget {
  final Book book;

  const _PreviewCover({required this.book});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      key: ValueKey('$kShelfCoverKeyPrefix${book.id}'),
      width: _kPreviewCoverWidth,
      height: _kPreviewCoverHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Stands in until a cover decodes, so the stack never flashes holes.
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(3),
        // A ring in the sheet's *own* colour, which is what separates a cover
        // from the one it overlaps. A border in `divider` would read as four
        // outlined chips; this reads as depth, and it is the only thing keeping
        // two dark covers from merging into one shape.
        border: Border.all(color: colors.sheetBackground),
      ),
      child: _face(),
    );
  }

  /// The cover art, or the colour block that stands for it.
  ///
  /// **Never a [GeneratedCover] here.** That draws its title at 13.5% of the
  /// cover's width, which at [_kPreviewCoverWidth] is under 4pt of unreadable
  /// smudge — see [kGeneratedCoverMinWidth], which documents this exact floor and
  /// says to draw the colour block alone below it. The hue is still the book's
  /// own, so a coverless book keeps the identity it has on the shelf.
  Widget _face() {
    final block = ColoredBox(color: generatedCoverColor(book.isbn));
    if (book.thumbnail.isEmpty) return block;

    return Image.network(
      book.thumbnail,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => block,
    );
  }
}
