import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_state_line.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_track.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_percent_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_total_pages_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/date_field_row.dart';
import 'app_sheet.dart';

/// Everything one Save carries out of [showBookStatusBottomSheet].
///
/// **A record rather than a handful of positional arguments**, which is what it was on
/// the way to becoming. Two of these fields are nullable dates and three more are a
/// `double?`, an `int?` and a `bool`, so a caller transposing any pair would compile —
/// and the one thing this sheet must never do is smear one of these facts into another.
typedef BookStatusEdit = ({
  int status,
  DateTime? startDate,
  DateTime? finishDate,
  double? progress,

  /// Which unit [progress] was given in: a page number when the reader typed one,
  /// null when they answered in percent or by dragging the track.
  ///
  /// **Only meaningful when [progress] is non-null**, and read only there. It rides
  /// alongside rather than inside it because a record cannot express "these two move
  /// together"; the provider is where that is enforced.
  int? progressPage,

  /// Whether the position should be erased rather than written.
  ///
  /// Set by a drag to the track's origin, which means *Not started*. Separate from a
  /// null [progress] because null already means "leave the column alone" — see
  /// `LibraryActions.updateBookStatus`, which documents why that asymmetry exists and
  /// why erasing had to become its own instruction.
  bool clearProgress,

  /// A new total page count, or null when the reader did not change it.
  ///
  /// **Rides out with the rest but is written by a different method.** `page_count` is
  /// not part of a book's reading state — it is a fact about the object — so it goes
  /// through `recordTotalPages`, which exists to write it without touching `progress`.
  /// It is in this record only because it leaves through the same Save.
  int? totalPages,
});

/// Edits everything about a book's reading state: where the reader is, what that makes
/// the book's status, and the dates either side.
///
/// **One sheet with one control, replacing a status picker and a position field.** The
/// status used to be chosen from a three-segment selector while the position was a
/// separate row that opened a second sheet on top of this one. Those were two controls
/// for one fact: a book with no position is *Not started*, one part-way through is
/// *Reading*, and one at the end is *Finished*. So the position is now the only thing
/// the reader sets, the status is a **read-out** of it, and the sheet is shorter than
/// either of the two it replaces.
///
/// **Status is largely a function of position, and `Set aside` is where "largely" bites.**
/// Nothing in a position can distinguish "at 46% and still going" from "closed at 46%" —
/// the number is identical — so that one state needs a second bit, which is why
/// [bookStatusSetAside] exists as a status value and why this sheet has exactly one text
/// action. Everything else is the track.
///
/// **Save is the only writer.** The track does not persist on release, the three
/// sub-sheets hand their answers back rather than writing them, and dismissing the sheet
/// discards. That is what makes the drag safe to make live on first movement: an earlier
/// design of the same control was rejected because *"a stray touch could silently rewrite
/// your position"*, and the answer here is that nothing this sheet does is written until
/// the reader says so.
///
/// **What this sheet no longer does, and the rule survives anyway:** it used to carry an
/// "I read today" checkbox. Moving a position already stamps the day on the path readers
/// actually use, so the row restated an act the reader had just performed. The rule it
/// implemented — *saving a position does not stamp a reading day by accident, and
/// stamping a day does not move a position* — is about the two writes not triggering each
/// other **unintentionally**; moving a position is a deliberate assertion that the reader
/// read today, and the caller is where that is turned into a `reading_days` row. The cost
/// is that nothing in the app can now un-record a day; that is accepted, and the reason is
/// in `AGENTS.md` under the undo footer.
Future<void> showBookStatusBottomSheet(
  BuildContext context, {

  /// Drawn as the sheet's heading, and **always left-aligned** so the row does not
  /// re-centre when Save appears beside it.
  required String bookTitle,
  required int currentStatus,
  required DateTime? startDate,
  required DateTime? finishDate,

  /// The book's stored position, or null when nothing has been recorded. Handed back
  /// untouched unless the reader moves the track or answers a sub-sheet, so opening this
  /// sheet to change a date cannot rewrite a position.
  double? progress,

  /// The page the reader typed last time, or null if they answered in percent.
  /// Handed back untouched for the reason [progress] is.
  int? progressPage,

  /// The book's total, which the read-out needs to print a page at all — and which this
  /// sheet can now *change*, unlike every previous version of it.
  int? pageCount,
  required void Function(BookStatusEdit edit) onSave,
}) {
  int status = currentStatus;
  DateTime? start = startDate;
  DateTime? finish = finishDate;
  double? position = progress;
  int? positionPage = progressPage;
  int? total = pageCount;

  return AppSheet.show(
    context: context,
    isScrollControlled: true,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        final l10n = AppLocalizations.of(context);
        final colors = context.colors;
        final chip = BookStatusBadge.presentation(l10n, colors, status);

        // **Nothing is written until this is true and the reader presses Save**, so it is
        // also the whole of the sheet's unsaved-changes model. Compared against the
        // values the sheet opened with rather than tracked with a flag per field: a
        // reader who drags the thumb away and back has changed nothing, and a Save button
        // that stayed behind would be claiming otherwise.
        final dirty =
            status != currentStatus ||
            start != startDate ||
            finish != finishDate ||
            position != progress ||
            positionPage != progressPage ||
            total != pageCount;

        // The reader answered in percent, by dragging or by the wheel. Clearing the page
        // is news rather than an omission: a book last set to p.200 and then dragged to
        // 46% must stop claiming the reader said p.200.
        void takePercentAnswer(double? value, {int? page}) {
          position = value;
          positionPage = page;
          // Set aside is the one status a position cannot imply, so it is the one status
          // a drag has to be able to leave. Moving the thumb resumes the book, which is
          // why there is no "start reading again" link anywhere on this sheet.
          status = value == null
              ? 0
              : (value >= 1 ? bookStatusFinished : bookStatusReading);
          // Fill in the dates the new status needs, never clear the ones it does not:
          // the book may already have a real start date and a stray drag must not throw
          // it away. What is *saved* is filtered by status below instead.
          if (status >= bookStatusReading) start ??= DateTime.now();
          if (status == bookStatusFinished) finish ??= start ?? DateTime.now();
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: AnimatedSize(
            // Save arriving and the date rows appearing both change the sheet's height.
            // Animating it keeps the sheet from snapping.
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // Expanded rather than a bare Text so the title holds the left edge
                    // whether or not Save is drawn next to it.
                    Expanded(
                      child: Text(
                        bookTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.subtitle,
                      ),
                    ),
                    // **Its arrival is the dirty indicator**, which is why there is no
                    // other unsaved marker on the sheet and no disabled Save to explain.
                    if (dirty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: ElevatedActionButton(
                          width: 92,
                          height: 32,
                          buttonText: l10n.save,
                          onPressed: () {
                            Navigator.pop(context);
                            onSave((
                              status: status,
                              // Only the dates the status has meaning for, so a book put
                              // back to Not started does not keep the dates the form was
                              // holding for its own benefit.
                              startDate: status >= bookStatusReading
                                  ? start
                                  : null,
                              finishDate:
                                  status == bookStatusFinished ||
                                      status == bookStatusSetAside
                                  ? finish
                                  : null,
                              progress: position,
                              progressPage: positionPage,
                              // A position the reader erased, which is a different
                              // instruction from one they did not touch. See the record.
                              clearProgress:
                                  position == null && progress != null,
                              totalPages: total != pageCount ? total : null,
                            ));
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // The whole state in one line: the status word, the percent, and the page
                // inside the total. Three of its parts are doors; the track below is for
                // coarse work and these are for exact answers.
                ReadingStateLine(
                  statusLabel: chip.label,
                  statusColor: chip.textColor,
                  progress: position,
                  progressPage: positionPage,
                  pageCount: total,
                  onPercentTap: () => showSelectPercentBottomSheet(
                    context,
                    initialProgress: position,
                    initialPage: positionPage,
                    pageCount: total,
                    onProgressSelected: (answer) => setState(
                      () =>
                          takePercentAnswer(answer.progress, page: answer.page),
                    ),
                  ),
                  // Only a book with a total has a page to edit. Opened straight into
                  // Page mode, because tapping the page has already said "pages".
                  onPageTap: total == null
                      ? null
                      : () => showSelectPercentBottomSheet(
                          context,
                          initialProgress: position,
                          initialPage: positionPage,
                          pageCount: total,
                          openInPageMode: true,
                          title: l10n.currentPageTitle,
                          onProgressSelected: (answer) => setState(
                            () => takePercentAnswer(
                              answer.progress,
                              page: answer.page,
                            ),
                          ),
                        ),
                  // Present whether or not the book has a count: with one it edits the
                  // total, without one it is the `Add total pages` offer, and that offer
                  // is the largest single thing this sheet adds — about two books in
                  // three have no count at all.
                  onTotalTap: () => showSelectTotalPagesBottomSheet(
                    context,
                    initialTotalPages: total,
                    onTotalPagesSelected: (value) =>
                        setState(() => total = value),
                  ),
                ),
                const SizedBox(height: 12),
                // The control. Drag-only: a tap on it does nothing, deliberately.
                ReadingTrack(
                  progress: position,
                  semanticsLabel: l10n.howFarIn,
                  onChanged: (value) =>
                      setState(() => takePercentAnswer(value)),
                ),
                if (status >= bookStatusReading) ...[
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
                          // Moving the start past the finish would leave the book
                          // finished before it was started.
                          if (finish != null && finish!.isBefore(d)) finish = d;
                        }),
                      );
                    },
                  ),
                ],
                // Set aside has a finish date too, and it is the day the book was
                // *closed* rather than completed. That is what keeps the read view's
                // month grouping and year rail working untouched: both read the date and
                // neither cares why the book ended.
                if (status == bookStatusFinished ||
                    status == bookStatusSetAside) ...[
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
                // **The sheet's only text action, and only while the book is open.**
                //
                // Nothing has been started at Not started; a finished book cannot be
                // given up on; and a set-aside book resumes by moving the thumb, so a
                // resume link would be a second affordance for a gesture the sheet
                // already has.
                //
                // `secondaryText`, not `flame`: giving up on a book is an ordinary thing
                // to do and not a destructive one, and this must not be the loudest thing
                // on the sheet. It leaves the position exactly where it is, which is the
                // whole point of the status existing — the read-out keeps saying 46%.
                if (status == bookStatusReading) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        status = bookStatusSetAside;
                        finish ??= DateTime.now();
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          l10n.stopReadingThis,
                          style: AppTextStyles.label.copyWith(
                            color: colors.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}
