import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/date_field_row.dart';
import 'package:bookworm_friends/ui/widgets/status_selector.dart';

/// Edits the reading status (and reading dates) of a book already in the
/// library.
///
/// Intentionally the same form as the add-book sheet — [BookStatusSelector] for
/// the status and [DateFieldRow] for the dates — minus the book header and shelf
/// picker, which aren't being changed here. Editing a status should feel like the
/// step the user already went through when adding the book.
Future<void> showBookStatusBottomSheet(
  BuildContext context, {
  required int currentStatus,
  required DateTime? startDate,
  required DateTime? finishDate,
  required void Function(int status, DateTime? start, DateTime? finish) onSave,
}) {
  int status = currentStatus;
  DateTime? start = startDate;
  DateTime? finish = finishDate;

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
                Text(
                  l10n.changeReadingStatus,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                BookStatusSelector(
                  labels: [
                    l10n.statusInterested,
                    l10n.statusReading,
                    l10n.statusFinished,
                  ],
                  status: status,
                  onChanged: (value) => setState(() {
                    status = value;
                    // Default the dates a status needs so the user isn't left
                    // with an empty field they have to discover. Dates are only
                    // filled in, never cleared: the book may already have a real
                    // start date, and a stray tap on another status shouldn't
                    // throw it away. What gets saved is derived from the status
                    // below instead.
                    if (value >= 1) start ??= DateTime.now();
                    if (value == 2) finish ??= start ?? DateTime.now();
                  }),
                ),
                if (status >= 1) ...[
                  const SizedBox(height: 16),
                  DateFieldRow(
                    label: l10n.startDate,
                    date: start,
                    onTap: () {
                      showSelectDateBottomSheet(
                        context,
                        initialDate: start ?? DateTime.now(),
                        title: l10n.selectStartDate,
                        onDateSelected: (d) => setState(() {
                          start = d;
                          // Moving the start past the finish would leave the
                          // book finished before it was started.
                          if (finish != null && finish!.isBefore(d)) finish = d;
                        }),
                      );
                    },
                  ),
                ],
                if (status == 2) ...[
                  const SizedBox(height: 8),
                  DateFieldRow(
                    label: l10n.finishDate,
                    date: finish,
                    onTap: () {
                      showSelectDateBottomSheet(
                        context,
                        initialDate: finish ?? DateTime.now(),
                        title: l10n.selectFinishDate,
                        // A book can't be finished before it was started.
                        minimumDate: start,
                        onDateSelected: (d) => setState(() => finish = d),
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
                    onPressed: () {
                      Navigator.pop(context);
                      // Only the dates the status actually has meaning for are
                      // persisted, so an interested book never keeps the dates
                      // that were kept around for the form's benefit.
                      onSave(
                        status,
                        status >= 1 ? start : null,
                        status == 2 ? finish : null,
                      );
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
