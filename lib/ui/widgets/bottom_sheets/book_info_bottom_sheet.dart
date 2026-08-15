import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/date_field_row.dart';
import 'package:bookworm_friends/ui/widgets/shelf_selector.dart';
import 'package:bookworm_friends/ui/widgets/status_selector.dart';
import 'package:flutter/material.dart';

Future<void> showBookInfoBottomSheet(
  BuildContext context, {
  required BookSearchResult book,
  required List<String> shelfNames,
  required void Function(
    String shelfName,
    int status, {
    DateTime? startDate,
    DateTime? finishDate,
  })
  onSavePressed,
}) {
  String? selectedShelf = shelfNames.isNotEmpty ? shelfNames.first : null;
  int status = 0;
  DateTime? startDate;
  DateTime? finishDate;

  return CNBottomSheet.show(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        final l10n = AppLocalizations.of(context);
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: AnimatedSize(
            // Picking a status shows/hides the date rows, which changes the
            // sheet's height. Animating it keeps the sheet from snapping.
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BookWidget(
                      imageUrl: book.thumbnail,
                      isbn: book.isbn,
                      title: book.title,
                      height: 120,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (book.authors.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                book.authors.join(', '),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.colors.secondaryText,
                                ),
                              ),
                            ),
                          if (book.publisher != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                book.publisher!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.colors.secondaryText,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (shelfNames.isNotEmpty) ...[
                  ShelfSelector(
                    label: l10n.selectShelf,
                    shelves: shelfNames,
                    selected: selectedShelf,
                    onChanged: (shelf) => setState(() => selectedShelf = shelf),
                  ),
                  const SizedBox(height: 12),
                ],
                BookStatusSelector(
                  labels: [
                    l10n.statusInterested,
                    l10n.statusReading,
                    l10n.statusFinished,
                  ],
                  status: status,
                  onChanged: (value) => setState(() {
                    status = value;
                    switch (value) {
                      case 0:
                        startDate = null;
                        finishDate = null;
                      case 1:
                        startDate ??= DateTime.now();
                        finishDate = null;
                      default:
                        startDate ??= DateTime.now();
                        finishDate ??= DateTime.now();
                    }
                  }),
                ),
                if (status >= 1) ...[
                  const SizedBox(height: 16),
                  DateFieldRow(
                    label: l10n.startDate,
                    date: startDate,
                    onTap: () {
                      showSelectDateBottomSheet(
                        context,
                        initialDate: startDate ?? DateTime.now(),
                        title: l10n.selectStartDate,
                        onDateSelected: (d) => setState(() {
                          startDate = d;
                          // Moving the start past the finish would leave the
                          // book finished before it was started.
                          if (finishDate != null && finishDate!.isBefore(d)) {
                            finishDate = d;
                          }
                        }),
                      );
                    },
                  ),
                ],
                if (status == 2) ...[
                  const SizedBox(height: 8),
                  DateFieldRow(
                    label: l10n.finishDate,
                    date: finishDate,
                    onTap: () {
                      showSelectDateBottomSheet(
                        context,
                        initialDate: finishDate ?? DateTime.now(),
                        title: l10n.selectFinishDate,
                        // A book can't be finished before it was started.
                        minimumDate: startDate,
                        onDateSelected: (d) => setState(() => finishDate = d),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedActionButton(
                    height: 44,
                    buttonText: l10n.save,
                    activated: selectedShelf != null,
                    onPressed: () {
                      if (selectedShelf != null) {
                        Navigator.pop(context);
                        onSavePressed(
                          selectedShelf!,
                          status,
                          startDate: startDate,
                          finishDate: finishDate,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
