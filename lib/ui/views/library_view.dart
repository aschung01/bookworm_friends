import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';

/// A library: shelves scrolling behind the "Books read" sheet.
///
/// This is the layer the shell keeps persistent, so it takes everything it
/// draws as parameters and reads no shell state itself.
class LibraryWithFinishedBooks extends StatelessWidget {
  final List<Shelf> shelves;
  final List<Book> finishedBooks;
  final LibraryMode mode;
  final int filterYear;
  final int filterMonth;
  final VoidCallback onFilterPressed;
  final void Function(String shelfId, String name) onEditShelfName;
  final void Function(String shelfId) onDeleteShelf;
  final VoidCallback onEnterEditMode;
  final VoidCallback? onAddShelf;
  final void Function(String bookId, String targetShelfId)? onMoveBook;
  final void Function(String shelfId, List<String> bookIds)? onReorderBooks;
  final void Function(String bookId)? onDeleteBook;
  final Future<void> Function()? onRefresh;

  const LibraryWithFinishedBooks({
    super.key,
    required this.shelves,
    required this.finishedBooks,
    required this.mode,
    required this.filterYear,
    required this.filterMonth,
    required this.onFilterPressed,
    required this.onEditShelfName,
    required this.onDeleteShelf,
    required this.onEnterEditMode,
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
    final shelvesOnDisplay = withoutFinishedBooks(shelves);
    // Deliberately measured against the *unfiltered* shelves. `finishedBooks` is
    // only the books matching the pile's year/month filter, so a library made up
    // entirely of read books must not offer to add a first book just because the
    // filter happens to exclude them all.
    final bool hasNoBooks =
        (shelves.isEmpty || shelves.every((s) => s.books.isEmpty)) &&
        finishedBooks.isEmpty;

    if (hasNoBooks) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SadCharacter(height: 100),
            const SizedBox(height: 16),
            Text(
              l10n.libraryEmptySelf,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 20, color: context.colors.secondaryText),
                const SizedBox(width: 4),
                Text(
                  l10n.addBookHintSuffix,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.secondaryText,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget shelfList = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 16, bottom: 16),
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
                  ? (bookId) => onMoveBook!(bookId, shelf.id)
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
                label: Text(
                  l10n.addShelf,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (onRefresh != null) {
      shelfList = RefreshIndicator(
        color: context.colors.brandText,
        onRefresh: onRefresh!,
        child: shelfList,
      );
    }

    // NOTE: the background has to live *outside* RefreshIndicator. That widget
    // wraps its child in a loose Stack, which would let the container shrink to
    // the shelves' height and leave the rest of the library unpainted.
    final library = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        boxShadow: [
          BoxShadow(
            blurRadius: 4,
            offset: const Offset(0, -4),
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ],
      ),
      child: shelfList,
    );

    // The library only gets the height left over by the "Books read" sheet, so
    // the sheet is always fully visible without scrolling to the bottom. As the
    // sheet is dragged down the library grows into the freed space. The library
    // colour also backs the whole area so it shows through the sheet's rounded
    // top corners.
    return ColoredBox(
      color: context.colors.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: library),
          FinishedBooksSheet(
            books: finishedBooks,
            isEditMode: mode == LibraryMode.editLibrary,
            filterYear: filterYear,
            filterMonth: filterMonth,
            onFilterPressed: onFilterPressed,
          ),
        ],
      ),
    );
  }
}
