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
import 'package:bookworm_friends/ui/widgets/bottom_sheets/stop_reading_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/date_field_row.dart';
import 'app_sheet.dart';

/// The sheet's content height, above [AppSheet]'s own 48pt of chrome.
///
/// **The tallest state the sheet has, so that no other state resizes it**: a set-aside book
/// with a dirty Save, which draws the read-out, the track, *both* date rows, `Start reading
/// again` and the Save button at once. Measured at 375×667 with the app's faces loaded, not
/// summed from the widgets — `book_status_bottom_sheet_test.dart` pins it and will fail if a
/// row is added that does not fit.
///
/// The other states, for the record: Not started 122, Reading clean 227, Reading dirty 287,
/// set aside clean 276.
///
/// **287 → 336 when Save moved to the foot**, which is the cost of that move and is worth
/// having in one place. The title row gave back 11 (it no longer holds a 32pt button beside a
/// ~21pt heading) and the commit row costs 60 (44 plus its 16pt gap), and the frame follows the
/// tallest state, so every state pays the 60 whether or not it draws the buttons.
///
/// **What this costs is a void on `Not started`** — 214pt of it, on a state whose content is
/// 122. Over half that sheet is empty cream, and it is the state a reader meets first. The
/// trade it buys is in [AnimatedSize]'s comment: the reader's first interaction with a new book
/// is a drag off the origin, which is exactly the transition that moved the track out from
/// under their finger. It was 165 before the commit row moved down here.
///
/// Two ways to close it, neither taken yet: draw the start-date row at the origin, which fills
/// 60 and closes a real gap — a start date cannot currently be set without first inventing a
/// position by dragging the thumb — or frame only the states a *drag* moves between (Not
/// started → Reading → Finished, 288) and let the confirmed set-aside transition resize the
/// sheet, which halves the void and costs a resize on two deliberate taps.
const double _kContentHeight = 336;

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
            // **Almost nothing left to animate, and that is the point.** This used to be
            // the answer to the sheet changing height: Save arriving and each date row
            // appearing all resized it, and the case that pinned the animation said why it
            // mattered — *"both happen on the same gesture, so without the animation the
            // sheet would jump twice under the reader's thumb."*
            //
            // That was treating the symptom. A bottom sheet is anchored to the bottom of
            // the screen, so growing moves its *top* edge up and every child with it —
            // including the track, which is above both date rows. Dragging off the origin
            // therefore slid the control out from under the finger that was dragging it,
            // 220ms of easing or not. [_kContentHeight] below removes the resize instead of
            // smoothing it.
            //
            // Kept for the one case the frame cannot absorb: at large accessibility text
            // sizes, or in a locale that wraps a row, the content exceeds the frame and the
            // sheet does grow. Rare, and better eased than snapped.
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              // **A minimum, not a fixed height.** Every state the sheet has is shorter
              // than this or equal to it, so in practice the frame is fixed and the sheet
              // never resizes — while a state that genuinely needs more room still gets it
              // rather than overflowing. A `SizedBox` here would trade a moving control for
              // a clipped one.
              constraints: const BoxConstraints(minHeight: _kContentHeight),
              // **[IntrinsicHeight] is what lets the [Spacer] below exist**, and the frame
              // is useless without it: the slack has to fall *above* the commit row, not
              // below it.
              //
              // Top-aligned, the buttons sat wherever the content ended and left 49pt of
              // cream under them on a Reading book — asked for "at the bottom of the sheet"
              // and drawn most of the way up it. A `Spacer` fixes that and needs a bounded
              // height, which neither of the obvious spellings gives: `MainAxisSize.max`
              // inside this `ConstrainedBox` fills the *maximum*, which here is most of the
              // screen, and a plain `SizedBox(height: _kContentHeight)` is bounded but
              // clips instead of growing — the thing `minHeight` is here to avoid.
              //
              // `IntrinsicHeight` tightens the child to its own intrinsic height, and
              // `BoxConstraints.tighten` clamps that against the incoming minimum: so the
              // column is handed a tight `max(natural, 336)`. Bounded, so `Spacer` works;
              // still at least the frame; still free to grow past it. The `Spacer`
              // contributes nothing to the intrinsic measurement, which is what makes
              // `natural` the real content height rather than a fixed point.
              child: IntrinsicHeight(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // **The sheet's own title, not the book's.** The book's title was tried
                    // first, on the reasoning that the row should never re-centre; it read as a
                    // page header rather than as a sheet title, and it told the reader something
                    // they already knew — they arrived from that book's page, and the book is
                    // still on screen behind this sheet. What a sheet title owes them is what
                    // this sheet *does*.
                    //
                    // **It was a `Row` holding the title and Save, inside a `SizedBox` pinned to
                    // 32.** Both are gone because Save moved to the foot: the `Row` had one child
                    // left, and the pin existed only because Save is 32 where the title is ~21, so
                    // the row grew 11pt the instant the sheet went dirty and pushed the track
                    // down. The cause moved rather than the rule changing — the commit buttons now
                    // arrive *below* the track, where [_kContentHeight] absorbs them.
                    Text(
                      l10n.readingProgressTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.subtitle,
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
                          () => takePercentAnswer(
                            answer.progress,
                            page: answer.page,
                          ),
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
                              if (finish != null && finish!.isBefore(d))
                                finish = d;
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
                    // **One text action, and which one depends on the status.** Nothing has
                    // been started at Not started, and a finished book can be neither given up
                    // on nor resumed, so those two states offer none.
                    //
                    // `secondaryText`, not `flame`, for both: neither giving up on a book nor
                    // picking it back up is destructive, and neither must be the loudest thing
                    // on the sheet. Stopping leaves the position exactly where it is, which is
                    // the whole point of the status existing — the read-out keeps saying 46%.
                    if (status == bookStatusReading) ...[
                      const SizedBox(height: 16),
                      _SheetTextAction(
                        label: l10n.stopReadingThis,
                        // **Confirmed, and the confirmation does not write.** See
                        // `stop_reading_bottom_sheet.dart` for why an action this ordinary is
                        // confirmed at all — it is the band's size, not the act's weight — and
                        // for why committing straight from there was rejected.
                        onTap: () => showStopReadingBottomSheet(
                          context,
                          onConfirmed: () => setState(() {
                            status = bookStatusSetAside;
                            finish ??= DateTime.now();
                          }),
                        ),
                      ),
                    ] else if (status == bookStatusSetAside) ...[
                      const SizedBox(height: 16),
                      _SheetTextAction(
                        label: l10n.startReadingAgain,
                        // **This reverses a decision recorded three times in this file, and
                        // the premise was wrong rather than the conclusion.** The claim was
                        // that a set-aside book resumes by moving the thumb, so a link here
                        // would be a second affordance for a gesture the sheet already has.
                        // But the thumb resumes only by *changing the position* — a reader who
                        // set a book aside at 46% and wants to carry on from 46% had no move
                        // available at all, short of dragging away and back to land on the same
                        // percent. The one status a position cannot imply is the one status
                        // that therefore needs a control of its own.
                        //
                        // **No confirmation, unlike its opposite**, and the asymmetry is the
                        // point: `showStopReadingBottomSheet` exists because a wide grey band
                        // is easy to hit by accident, and an accidental *resume* costs a reader
                        // nothing. Confirming both would make the pair look like a matched set
                        // of consequential acts, which is exactly the judgement these strings
                        // are written to avoid.
                        onTap: () => setState(() {
                          status = bookStatusReading;
                          // The finish date is deliberately kept, not cleared. Save filters it
                          // out for a reading book, so nothing wrong is written; keeping it
                          // means a reader who resumes and stops again does not lose the day
                          // they first closed the book. Same rule as `start` above — fill in
                          // what the new status needs, never clear what it does not.
                          start ??= DateTime.now();
                        }),
                      ),
                    ],
                    // **The commit row, at the foot of the sheet.**
                    //
                    // Save used to sit in the title row beside the heading, at 92×32. It was
                    // asked for down here, and the move brings two things with it. `Reset`
                    // becomes possible — a 92pt slot next to a title has room for one button,
                    // a full-width row has room for a pair — and the sheet stops putting its
                    // only write control in the corner furthest from the reader's thumb, on a
                    // sheet whose whole argument for being a sheet was that the control is in
                    // the thumb's arc.
                    //
                    // **Its arrival is still the dirty indicator**, which is why there is no
                    // other unsaved marker on the sheet and no disabled Save to explain.
                    // Arriving *below* the track rather than above it is also what let the
                    // title row's pinned height go: [_kContentHeight] absorbs anything that
                    // appears down here, where a taller title row pushed the track down.
                    //
                    // The delete sheet's geometry — two `Expanded` buttons at 44 with a 12pt
                    // gap, recessive on the left — because that is the app's existing button
                    // pair and a second arrangement would be a new thing to learn.
                    // **The slack, and it goes here rather than at the end.** Everything above
                    // keeps its place under the track; everything below is pinned to the foot.
                    // A reader asked for the buttons "at the bottom of the sheet" and got them
                    // 49pt up it, because the frame's spare room fell after the last child.
                    //
                    // Above the text action rather than below it: `Stop reading this` changes
                    // the pending status, so it belongs with the form it edits, and the commit
                    // row is the only thing that belongs to the sheet's edge. In a clean state
                    // there is no commit row and this simply absorbs the tail, which is the
                    // top-aligned behaviour it replaced.
                    const Spacer(),
                    if (dirty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedActionButton(
                              height: 44,
                              buttonText: l10n.reset,
                              backgroundColor: colors.surfaceVariant,
                              textStyle: AppTextStyles.label,
                              // **Not `Cancel`, and the difference is that this one stays.**
                              // Dismissing the sheet already discards — that is the invariant
                              // Save is the other half of — so a button that dismissed would
                              // be a second spelling of a gesture the reader already has. This
                              // puts every field back to what the sheet opened with and leaves
                              // them on it, which is what someone who over-dragged the track
                              // wants: the old value back, and to carry on.
                              //
                              // Reset to the *arguments*, not to a snapshot taken later, so it
                              // restores exactly the values `dirty` compares against and the
                              // row cannot survive its own press.
                              onPressed: () => setState(() {
                                status = currentStatus;
                                start = startDate;
                                finish = finishDate;
                                position = progress;
                                positionPage = progressPage;
                                total = pageCount;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedActionButton(
                              height: 44,
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
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// The sheet's one text action: `Stop reading this` while a book is open, `Start reading
/// again` once it is set aside.
///
/// **Centred, and full width.** Left-aligned it sat under the start-date row's own left
/// inset and read as a third field in the form rather than as an action on the book.
/// Centring is also what the app does with every other standalone text action.
///
/// The [GestureDetector] takes the whole width so the target is a band rather than the
/// glyphs: the label is short, grey and the least important thing on the sheet, which is
/// exactly the combination that makes a text-sized hit box hard to land on. **That width is
/// also why the destructive direction is confirmed** — see
/// `showStopReadingBottomSheet`. An opaque band under a tappable date row is easy to hit
/// without meaning to, and the two of these cannot be told apart by a stray thumb.
///
/// One widget rather than two call sites, because the pair must be the same object in
/// different words. Drawn differently they would read as an action and a *correction*.
class _SheetTextAction extends StatelessWidget {
  const _SheetTextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  /// The vertical padding, which is the target rather than decoration: 8 above and below a
  /// 20pt line is a 36pt band across the sheet's full width.
  static const double _padding = 8;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _padding),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.label.copyWith(
            color: context.colors.secondaryText,
          ),
        ),
      ),
    );
  }
}
