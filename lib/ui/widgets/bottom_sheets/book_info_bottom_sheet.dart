import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
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

/// The "save a book" sheet: a cover, its catalogue details, and the shelf, status and
/// dates to file it under.
///
/// Presentation only. [onSavePressed] is where the library write lives, so this sheet is
/// equally usable for a book the reader is merely looking at — see `add_to_library_sheet.dart`.
///
/// ### Why it reports a colour
///
/// [onSavePressed] carries a `coverColor`, and it costs nothing to produce: this sheet
/// already draws the chosen cover through [BookWidget], which samples every image it
/// decodes in order to tone its own back board. Before this, that sample was computed and
/// dropped, `addBook` inserted `cover_color: null` for every book ever added, and the
/// column was filled in later by whichever screen happened to render the book next.
///
/// That was worst exactly where it showed most. A book saved as *finished* is kept off
/// the shelves by `withoutFinishedBooks`, so the densest backfill path never saw it; it
/// went straight into the read pile wearing one of six ISBN-hashed brand swatches, and
/// `recordCoverColor` deliberately does not invalidate, so it kept that swatch until the
/// next fetch even after something did sample it.
///
/// **Null stays ordinary.** The reader can tap Save before the thumbnail has resolved, and
/// a book with no thumbnail never samples at all. Both cases insert null and fall back to
/// the ISBN swatch until the backfill reaches them, which is exactly the behaviour that
/// existed for every book before.
Future<void> showBookInfoBottomSheet(
  BuildContext context, {
  required BookSearchResult book,
  required List<String> shelfNames,
  required void Function(
    String shelfName,
    int status, {
    DateTime? startDate,
    DateTime? finishDate,
    Color? coverColor,
  })
  onSavePressed,
}) {
  String? selectedShelf = shelfNames.isNotEmpty ? shelfNames.first : null;
  int status = 0;
  DateTime? startDate;
  DateTime? finishDate;

  /// Set from the cover's own decode, if one lands before the reader saves.
  ///
  /// No `setState`: nothing on the sheet draws this, and rebuilding the subtree from an
  /// image callback would re-resolve the very image that produced it.
  Color? coverColor;

  return CNBottomSheet.show(
    context: context,
    isScrollControlled: true,
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
                      // The sample is the same `coverToneColor` value a shelf or the
                      // backfill tool would resolve, because it is the same call on the
                      // same decoded image — the widget's drawn size does not reach the
                      // sampler. So a book coloured here and one coloured later cannot
                      // disagree, which matters because `recordCoverColor` skips any book
                      // that already has a colour and would never revisit it.
                      onCoverSampled: (sampled) => coverColor = sampled,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: AppTextStyles.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (book.authors.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                book.authors.join(', '),
                                style: AppTextStyles.label.copyWith(
                                  color: context.colors.secondaryText,
                                ),
                              ),
                            ),
                          if (book.publisher != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                book.publisher!,
                                style: AppTextStyles.label.copyWith(
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
                          coverColor: coverColor,
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
