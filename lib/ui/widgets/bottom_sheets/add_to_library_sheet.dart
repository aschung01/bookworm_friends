import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_info_bottom_sheet.dart';

/// Opens the book-info sheet wired to write the book into the library.
///
/// Extracted because two different things now reach this same sheet — tapping a
/// result in Add Book's grid, and a barcode that resolved to exactly one book —
/// and the save side is not the trivial part: it maps a shelf *name* back to its
/// id, forwards eight fields, and then unwinds the whole stack rather than
/// popping once. Two copies of that would drift, and the copy that drifted would
/// be the scanner's, because it is the one nobody exercises by hand.
///
/// [BookInfoBottomSheet] itself stays presentation-only; the library write lives
/// here so the sheet can go on being used for a book the user is only looking at.
Future<void> showAddToLibrarySheet(
  BuildContext context,
  WidgetRef ref, {
  required BookSearchResult book,
  required List<Shelf> shelves,
}) {
  return showBookInfoBottomSheet(
    context,
    book: book,
    shelfNames: shelves.map((s) => s.name).toList(),
    onSavePressed:
        (shelfName, status, {DateTime? startDate, DateTime? finishDate}) async {
          final shelf = shelves.firstWhere((s) => s.name == shelfName);
          await ref
              .read(libraryActionsProvider)
              .addBook(
                shelfId: shelf.id,
                isbn: book.isbn,
                title: book.title,
                thumbnail: book.thumbnail,
                status: status,
                startDate: startDate,
                finishDate: finishDate,
                authors: book.authors,
                pageCount: book.pageCount,
              );
          // `popUntil` rather than `pop`, and it is load-bearing for the scan
          // path: what sits between here and the shell is one sheet when the
          // book came from the grid, but a sheet *over a camera page over* the
          // Add Book sheet when it came from a barcode. Unwinding to the shell
          // is the only exit that is right for both, and it is also the one that
          // lands the user back where the book now is.
          //
          // `context.mounted`, not a State's `mounted`: this is a function, and
          // the sheet it is popping can be gone by the time the write returns.
          if (context.mounted) {
            Navigator.popUntil(
              context,
              (route) => route.isFirst || route.settings.name == '/home',
            );
          }
        },
  );
}
