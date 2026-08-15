import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_shelf_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/update_shelf_name_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';

/// Shelf-scope management: reorder, rename and delete shelves.
///
/// Presented as a sheet *over* the library's edit mode rather than as a
/// page-level mode swap, so dismissing it returns the user exactly where they
/// were. Every action persists immediately, so the sheet has no save step.
Future<void> showManageShelvesBottomSheet(BuildContext context) {
  return CNBottomSheet.show<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _ManageShelvesSheet(),
  );
}

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
    final shelves = ref.watch(libraryProvider).valueOrNull ?? const <Shelf>[];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 20, 12, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.manageShelves,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (shelves.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              l10n.dragToReorder,
                              style: TextStyle(
                                fontSize: 13,
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
                    // 44 keeps the touch target the Done button had.
                    diameter: 44,
                    symbolSize: 15,
                    iconSize: 20,
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
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.secondaryText,
                  ),
                ),
              )
            else
              Flexible(
                // Transparent Material so the rows can show ink feedback.
                child: Material(
                  type: MaterialType.transparency,
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    // Dragging starts from the grip, immediately \u2014 the rest of
                    // the row is a rename target.
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
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
          const SizedBox(width: 25),
        Expanded(
          child: InkWell(
            onTap: onRename,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                shelf.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onRename,
          tooltip: l10n.edit,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(
            Icons.edit_outlined,
            size: 21,
            color: context.colors.primaryText,
          ),
        ),
        IconButton(
          onPressed: onDelete,
          tooltip: l10n.delete,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.delete_outline, size: 22, color: softRedColor),
        ),
      ],
    );
  }
}
