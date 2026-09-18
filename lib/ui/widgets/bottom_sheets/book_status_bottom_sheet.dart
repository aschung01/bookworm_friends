import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_percent_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/date_field_row.dart';
import 'package:bookworm_friends/ui/widgets/progress_field_row.dart';
import 'package:bookworm_friends/ui/widgets/read_today_field_row.dart';
import 'package:bookworm_friends/ui/widgets/status_selector.dart';

/// Everything one Save carries out of [showBookStatusBottomSheet].
///
/// **A record rather than five positional arguments**, which is what it was on the
/// way to becoming. Two of these fields are nullable dates and two more are a
/// `double?` and a `bool`, so a caller transposing any pair would compile — and the
/// one thing this sheet must never do is smear one of these facts into another.
typedef BookStatusEdit = ({
  int status,
  DateTime? startDate,
  DateTime? finishDate,
  double? progress,

  /// Which unit [progress] was given in: a page number when the reader typed one,
  /// null when they answered in percent.
  ///
  /// **Only meaningful when [progress] is non-null**, and read only there. It rides
  /// alongside rather than inside it because a record cannot express "these two move
  /// together"; the provider is where that is enforced.
  int? progressPage,

  /// Whether today should have a `reading_days` row when this returns.
  ///
  /// **Independent of every other field here.** It is in the same record because it
  /// leaves through the same Save, not because it is connected: saving a position
  /// does not stamp a day and stamping a day does not move a bookmark.
  bool readToday,
});

/// Edits the reading status (and reading dates, and the reading position) of a
/// book already in the library.
///
/// Intentionally the same form as the add-book sheet — [BookStatusSelector] for
/// the status and [DateFieldRow] for the dates — minus the book header and shelf
/// picker, which aren't being changed here. Editing a status should feel like the
/// step the user already went through when adding the book.
///
/// **This sheet is the home of the reading position**, added as a
/// [ProgressFieldRow] beside the dates rather than as a control of its own
/// somewhere else. Nine drawn versions put it on the cover, in the band, or behind a
/// long press; all of them lost to the observation that this sheet already *is*
/// "update this book's state", so a position is one more field in a form the reader
/// has already filled in once.
///
/// **What this sheet does not do, and it is the load-bearing half:** saving a
/// position does not stamp a reading day, and stamping a day does not move the
/// position. The two facts share a screen and are constantly confused for each
/// other; keeping them apart is the single rule the whole design rests on.
Future<void> showBookStatusBottomSheet(
  BuildContext context, {
  required int currentStatus,
  required DateTime? startDate,
  required DateTime? finishDate,

  /// The book's stored position, or null when nothing has been recorded. Passed in
  /// and handed back untouched unless the reader spins the wheel, so opening this
  /// sheet to change a date cannot silently rewrite a position.
  double? progress,

  /// The page the reader typed last time, or null if they answered in percent.
  /// Handed back untouched for the reason [progress] is.
  int? progressPage,

  /// Enables the wheel's Page mode and its derived-page rider, and lets the row
  /// print a page at all. Never written.
  int? pageCount,

  /// Whether today already has a `reading_days` row.
  bool readToday = false,
  required void Function(BookStatusEdit edit) onSave,
}) {
  int status = currentStatus;
  DateTime? start = startDate;
  DateTime? finish = finishDate;
  double? position = progress;
  int? positionPage = progressPage;
  bool readTonight = readToday;

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
                Text(l10n.changeReadingStatus, style: AppTextStyles.subtitle),
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
                // Only while the book is open. A finished book's position is 100%
                // by definition and an interested one has none, so on both of
                // those the row would be a field with one legal answer.
                //
                // Inside the same `AnimatedSize` as the date rows above, which is
                // why there is nothing to do here for the reveal: this is one more
                // field of the kind the sheet already grows and shrinks by.
                if (status == 1) ...[
                  const SizedBox(height: 8),
                  ProgressFieldRow(
                    progress: position,
                    progressPage: positionPage,
                    pageCount: pageCount,
                    onTap: () {
                      showSelectPercentBottomSheet(
                        context,
                        initialProgress: position,
                        // Only to resume Page mode where the reader left it. The
                        // wheel still opens on Percent either way.
                        initialPage: positionPage,
                        // A book with no count still gets the wheel; it just gets no
                        // page under it and no mode segment above it.
                        pageCount: pageCount,
                        onProgressSelected: (answer) => setState(() {
                          // Both halves of one answer, always assigned together: a
                          // position kept with the previous answer's unit would print
                          // a page the reader never gave.
                          position = answer.progress;
                          positionPage = answer.page;
                        }),
                      );
                    },
                  ),
                  // Under the position row, and only while the book is open: a day
                  // is recorded against reading, and a finished or unstarted book
                  // has no tonight to record. Inside the same `AnimatedSize`, so it
                  // arrives the way the rows above it do.
                  const SizedBox(height: 8),
                  ReadTodayFieldRow(
                    read: readTonight,
                    onChanged: (value) => setState(() => readTonight = value),
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
                      //
                      // The position is passed through **unchanged** when the
                      // reader did not touch the wheel, including when it is null.
                      // It is deliberately *not* zeroed at status 0 or filled to
                      // 100% at status 2 the way the dates are derived: a position
                      // is a fact about the text, not about the status, and a book
                      // put back on the shelf and reopened should be where the
                      // reader left it.
                      onSave((
                        status: status,
                        startDate: status >= 1 ? start : null,
                        finishDate: status == 2 ? finish : null,
                        progress: position,
                        progressPage: positionPage,
                        // Passed through when the book is no longer open, for the
                        // reason the position is: a day the reader recorded is not
                        // the status's to withdraw. Unticking is how it is undone.
                        readToday: readTonight,
                      ));
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
