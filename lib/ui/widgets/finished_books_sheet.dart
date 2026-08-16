import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

/// The Library tab's sheet: the pile of books read in the filtered period,
/// standing on a shelf.
///
/// Contents only — the drag handle, the snap positions and the spring belong to
/// [LibrarySheet], which every tab's sheet shares.
class FinishedBooksSheet extends StatelessWidget {
  final List<Book> books;

  /// Springs the sheet shut and goes inert while the library is being edited.
  final bool isEditMode;
  final int filterYear;
  final int filterMonth;
  final VoidCallback onFilterPressed;

  /// See [LibrarySheet.bottomReserve].
  final double bottomReserve;

  const FinishedBooksSheet({
    super.key,
    required this.books,
    required this.isEditMode,
    required this.filterYear,
    required this.filterMonth,
    required this.onFilterPressed,
    this.bottomReserve = 0,
  });

  String _filterText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (filterYear == 0) return l10n.all;
    if (filterMonth == 0) return l10n.yearLabel(filterYear);
    return l10n.yearMonthLabel(filterYear, filterMonth);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LibrarySheet(
      isEditMode: isEditMode,
      bottomReserve: bottomReserve,
      header: Row(
        children: [
          Expanded(
            child: LibrarySheetTitle(
              title: l10n.finishedBooksTitle,
              count: books.length,
            ),
          ),
          GestureDetector(
            // Inert with the rest of the sheet during an edit: the pile is not
            // what is being edited, and re-filtering it mid-edit is noise.
            onTap: isEditMode ? null : onFilterPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _filterText(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down, size: 18),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (books.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14, left: 25, right: 25),
              child: SizedBox(
                height: 124 + 13,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final opacityList = bookOpacityList;
                    final opacity = opacityList[index % opacityList.length];
                    return BookVertical(
                      title: books[index].title,
                      opacity: opacity,
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.details,
                        arguments: books[index],
                      ),
                    );
                  },
                ),
              ),
            )
          else
            SizedBox(
              height: 124 + 14 + 13,
              child: Center(
                child: Text(
                  l10n.noFinishedBooks,
                  style: TextStyle(
                    color: context.colors.secondaryText,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 25),
            child: ShelfWidget(),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
