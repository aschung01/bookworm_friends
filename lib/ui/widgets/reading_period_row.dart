import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';

/// Minimum height of the card once it is a door. The card draws 42, so reaching the
/// platform's touch floor costs **2pt** — not nothing, and not the 14 a 30pt row
/// would have cost.
const double _kTouchFloor = 44;

/// How far the card's chevron is pulled out of the card to reach the column the
/// progress row's chevron already sits in.
///
/// The card is inset 10pt inside the band, so its chevron naturally lands at x352
/// while the row's lands at x362. **The card's glyph moves; the row never does** —
/// the row was settled first, and bringing them into column by padding the row would
/// be redrawing a decided thing to fix an undecided one. Aligned, two chevrons read
/// as the right edge of a list; staggered they read as a mistake (`ch-stagger`).
const double _kChevronColumnPull = 10;

/// How far the status-0 line's tap target reaches below its own ink.
///
/// 14, taken out of the band's 16pt bottom padding rather than added to the layout, so
/// the band's height is unchanged by making the line tappable.
///
/// **This used to read `= kBandProgressRowSpill`, and the contention it arbitrated is
/// gone.** There were two rows below the cover that could reach past their own ink — this
/// line and `BandProgressRow` — competing for one bottom padding, and a `spillsBelow`
/// predicate existed to prove only one of them ever spent it. The band is one card now:
/// the period row carries the position as well, so there is one row, no contention, and
/// the figure belongs to this file.
///
/// The target this buys is **40pt rather than 44**, and that is the one deliberate
/// shortfall in the band. The alternative was 18pt of permanent band height on every
/// Not-started book to seat a 26pt line in a 44pt box, on the one screen whose last
/// redesign was about lifting content above the tab strip. 40×110 is not a glyph
/// button in a corner; it is a labelled row two thirds the width of the band.
const double kStatusVerbSpill = 14;

/// What is left of the band's 16pt bottom padding once [kStatusVerbSpill] is taken out of
/// it. 16 − 14.
///
/// Lives here rather than in the deleted `band_progress_row.dart`, which owned it while
/// that row was the one reaching below its own ink.
const double kBandResidualPadding = 2;

/// The reading facts about a book: its status, the dates, and the elapsed day
/// count.
///
/// The status badge leads the row and **stands in for the old "Reading period"
/// label** rather than being added beside it. Status, dates and duration are one
/// class of fact and belong in one place, and the badge does more work than the
/// label did — so this removed a string rather than adding one.
///
/// It also retired an oddity. The badge used to sit in the hero's bottom-right
/// corner on a friend's book and at the top of the right-hand column on your
/// own, two places for one thing, because the corner belonged to a button the
/// owner is never shown. Here there is one rule for both viewers.
///
/// ## The card is a door, when [onTap] is given — and so is the line without it
///
/// It opens `showBookStatusBottomSheet`, which edits status, start and finish —
/// **exactly what this card displays**. That is what retired the app bar's
/// `edit_outlined`: once the thing you tap to change a fact is the fact itself, a
/// pencil 400pt away in the top-right corner has no job.
///
/// **At status 0 there is no card, and for a while that meant no door at all.** This
/// widget returned a bare chip, `onTap` was dropped on the floor, and
/// `showBookStatusBottomSheet` has exactly one caller in the app — this one. So an
/// *Interested* book, 133 of 472 in production, could not be moved to *Reading* or
/// *Read* from here **or from anywhere else**. The comment that used to sit in the
/// `start == null` branch, claiming such a book was edited "from the library's own
/// sheets", described sheets that do not exist.
///
/// The repair is [_ChangeStatusButton]: one neutral verb at the trailing end of the
/// line, in the slot the dates will occupy once there are any. Three things about it
/// are decisions rather than defaults.
///
/// **The word is `Change status`, not `Start reading`.** A verb that names a
/// destination is one tap instead of three, and it was drawn and rejected: a reader
/// who only opens the app *after* finishing a book would be sent to status 1 and have
/// to edit again. `Change status` promises a choice and the sheet it opens contains
/// `BookStatusSelector`, so one target reaches all three states.
///
/// **The badge does not become a chip you can tap, and the distinction is not
/// pedantic.** The *line* is the target — badge included, exactly as the card at
/// status 1 and 2 is a target with the badge inside it — but the badge grows no
/// chevron and no press state of its own. Making [BookStatusBadge] itself the control
/// was the other candidate (`menu-only` in `docs/mockups/book-details-edit`); it is
/// drawn on the read pile, in the month grid and on a friend's book, where it is never
/// a control, and a chip that is inert in four places and a button in the fifth is a
/// worse thing to learn than a word that only appears where it works.
///
/// **It is a word, not an icon.** There is no pencil to restore here: see the
/// headstone in `book_details_tab_view.dart`.
///
/// **A chevron alone was not enough, and that is the finding.** The card's three
/// pieces were packed left, so a chevron added at the right floated with a void
/// between and read as an ornament rather than as a handle (`pd-naive` is that
/// version drawn). The fix is one rule — the value is pushed right — which turns the
/// card into *label left, value right, chevron last*: `DateFieldRow`'s shape
/// verbatim, which is the app's own tap-to-edit row rather than a new pattern.
/// Nothing was added. No words, no icon, no second ground.
///
/// **And note what does not apply here.** Putting the progress row on a white card
/// failed partly because a white card on this band already meant "read-only" — and
/// this card was that read-only card. Once it is itself a door there is no read-only
/// white card left in the band to be confused with — and since the merge there is no
/// second row either, so the band has one ground and one door.
///
/// Laid out as a [Wrap] so a long value (or a longer localized label) moves to
/// the next line instead of overflowing or truncating — every value stays
/// readable at any width. That survives the door treatment: the value group is
/// pushed right *and* still wraps, rather than being pinned to one line.
///
/// **It is a safety valve and no longer a working layout, which is the point of the
/// two-slot rule in `build`.** The card wrapped in normal use for one round, on a
/// finished book, and a wrap that happens at the default text size on the widest phone
/// is not a valve opening — it is four values in a space for two. The `Wrap` stays for
/// accessibility sizes and for a locale that needs the room.
class ReadingPeriodRow extends StatefulWidget {
  const ReadingPeriodRow({
    super.key,
    required this.status,
    this.startDate,
    this.finishDate,
    this.onTap,
    this.progress,
    this.spillsIntoBandPadding = false,
  });

  final int status;

  /// Null below status 1, where a book has no dates yet.
  final DateTime? startDate;
  final DateTime? finishDate;

  /// Opens the change-status sheet. **Null on a friend's book**, which leaves the
  /// card exactly as it shipped before this became a door: no chevron, no touch
  /// floor, no press state. A handle on a door nobody can open is a lie.
  ///
  /// With no dates it is also what decides whether the line carries the
  /// `Change status` verb at all, for the same reason.
  final VoidCallback? onTap;

  /// The book's stored position, or null when nothing has been recorded.
  ///
  /// **Drawn here because the band is one card now.** It used to live in a second row
  /// below this one, `BandProgressRow`, which was also a second door — it opened the
  /// percent wheel directly while this card opened the status sheet. The merge deleted the
  /// row, and deleting the row without moving its numerals would have left the band
  /// silent about the one fact that changes most often.
  ///
  /// Null draws nothing rather than `0%`: "never asked" and "at the very start" are
  /// different states, and a band that printed `0%` for every unread book would be
  /// claiming the reader had opened all of them.
  final double? progress;

  // There is no `pageCount` here, and there was for two rounds.
  //
  // The card printed `71% · p.307 / 432`, and the page pair was withdrawn on instruction:
  // *"no need to show total page count or current page index from the tappable row."* Both
  // numbers are derived from the percent and the total, so the card was spending two thirds
  // of its widest value restating its first third with more precision than a glance wants.
  //
  // The precision is not lost, it moved to where it is asked for: the sheet this card opens
  // draws `ReadingStateLine`, whose page and total are each a tappable span onto the wheel.
  // A reader who wants the page number is one tap from editing it; a reader glancing at the
  // band gets `71%`.
  //
  // This is also what finally made the first slot narrow. The two-slot rule below fixed the
  // *count* of values; `71% · p.307 / 432` was still 120pt of the card's 333, and it is the
  // reason a finished book's closed range would not fit beside it.

  /// Whether the caller has taken [kStatusVerbSpill] out of the band's bottom
  /// padding for this row, so the status-0 verb may reach below its own ink.
  ///
  /// False by default, which is the safe answer: the target is then the line's own
  /// height and nothing overhangs a neighbour. The band passes a literal `true`; it used
  /// to pass `!showsProgressRow`, because a second row below this one had first claim on
  /// the single bottom padding. That row is deleted, so there is one claimant.
  final bool spillsIntoBandPadding;

  /// Whether a row with these inputs wants the band's bottom padding.
  ///
  /// Exported so the band can size its padding from the same condition this widget
  /// branches on, rather than from a copy of it that can drift.
  static bool spillsBelow({
    required DateTime? startDate,
    required bool tappable,
  }) => startDate == null && tappable;

  static String _formatDate(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

  @override
  State<ReadingPeriodRow> createState() => _ReadingPeriodRowState();
}

class _ReadingPeriodRowState extends State<ReadingPeriodRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final start = widget.startDate;

    // No dates means no card. Wrapping a lone chip in a full-width white slab
    // was drawn at real scale and looked worse than the corner it replaced, so
    // at status 0 the badge sits in the band bare. The rule that matters —
    // status lives here, under the author — holds either way; the card is a
    // container for dates, and when there are none there is no card.
    //
    // **What there is instead of a card is a verb**, at the trailing end of the
    // line, in the slot the dates will occupy once there are any. See the class
    // doc for why it is a neutral word rather than `Start reading`, and why the
    // badge beside it is still not a control.
    //
    // Aligned rather than returned directly: `BookStatusBadge` is a `Container`
    // with no width of its own, so a caller passing tight constraints stretches
    // it edge to edge. The band happens to pass loose ones, which hid this — but
    // a chip that is 333pt wide in one parent and shrink-wrapped in another is
    // the sort of thing that only shows up on device.
    if (start == null) {
      final onTap = widget.onTap;
      if (onTap == null) {
        return Align(
          alignment: Alignment.centerLeft,
          child: BookStatusBadge(status: widget.status),
        );
      }

      return GestureDetector(
        onTap: onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        // Opaque, or the spill below the ink is not hit-testable and the target is
        // back to the height of one chip.
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          button: true,
          // The verb is the action and the badge is the value, which is exactly the
          // pair `Semantics` wants. Without this the line announces "Interested,
          // Change status" as two unrelated labels.
          label: l10n.changeStatus,
          excludeSemantics: true,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: widget.spillsIntoBandPadding ? kStatusVerbSpill : 0,
            ),
            // Tight width, so `spaceBetween` has the band to distribute rather than
            // shrink-wrapping onto its two children and having none.
            child: SizedBox(
              width: double.infinity,
              // A [Wrap] for the same reason the card below is one: at accessibility
              // text sizes, or in a locale where either string is longer, the verb
              // moves to the next line instead of overflowing. It is a safety valve
              // rather than a layout — `Interested` and `Change status` together
              // measure about 200 of the band's 333pt, and their Korean counterparts
              // about 115 — but `flutter_test` draws every glyph as a square of the
              // font size, which is how the version without it was caught.
              //
              // The spill is on the padding above rather than on the verb, so that
              // `center` here aligns the verb's ink with the chip's and not with the
              // bottom of an invisible 14pt tail.
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BookStatusBadge(status: widget.status),
                  // The press state lands on the verb rather than on the whole line:
                  // the line is the target, but the verb is what says so, and dimming
                  // an inert chip alongside it would suggest the chip did something.
                  Opacity(
                    opacity: _pressed ? 0.55 : 1,
                    child: _changeStatusVerb(context, l10n),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final finish = widget.finishDate;
    final position = widget.progress;

    // **Two slots, and no date the day count already implies.**
    //
    // Four values fitted here for one round — the range, the position and the day count
    // beside the badge — and a reader called it messy, correctly. The count was not the
    // whole of it. Two of the four said the same thing twice:
    //
    //  * `71%` and `p.307 / 432` are one fact, given the total. The page pair has since
    //    been withdrawn from the card altogether — see the headstone where `pageCount`
    //    used to be — so the first slot is now a bare percent.
    //  * the **start** date and the elapsed day count are one fact. `15 days` *is*
    //    `2026.09.13 ~` measured from today, and it is the half that keeps moving.
    //
    // So the card has two slots and a rule for each. The second is always the day count —
    // *how long* — because it is the one thing neither the position nor the sheet behind
    // this card states. The first is *where or when*, and it takes the most specific fact
    // available:
    //
    // | state                     | where / when   | how long  |
    // | ------------------------- | -------------- | --------- |
    // | Reading, with a position  | `71%`          | `15 days` |
    // | Reading, no position yet  | —              | `15 days` |
    // | Set aside, with one       | `46%`          | `15 days` |
    // | Finished                  | `2026.09.28`   | `15 days` |
    //
    // **The start date is gone from the card, and that is the reversal here.** The card
    // used to lead with `2026.09.13 ~`, which is the fact the day count already carries in
    // the form a reader wants it — nobody subtracts dates to learn a book has been open a
    // fortnight. The *finish* date survives because nothing else on the card implies it:
    // when this landed is a memory anchor, and it is the one date the day count cannot
    // reconstruct without the other. Both dates are still one tap away and still editable
    // in the sheet this card opens, which is the reason the loss is affordable.
    //
    // **A finished book prints that date rather than the range, and the range is what
    // wrapped.** `2026.09.13 ~ 2026.09.28` plus `15 days` does not fit beside a badge at
    // 333pt, so the one state whose period is *complete* was the one drawing two lines —
    // and it was spending both on a closed range whose duration was printed underneath it.
    // Dropping `15 days` there instead would have fixed the wrap too, and costs more: a
    // settled "it took me 15 days" is the satisfying number on a book you have finished,
    // where two ISO dates are a database row.
    //
    // **Finished is excluded from the position explicitly, and the first version of this
    // forgot to**: a finished book has a non-null position of exactly 1, so `position !=
    // null` alone let it print `100%` beside a badge already reading *Finished*. Two ways
    // of saying "the end", where the date is the thing that slot has left to say.
    final hasPosition = position != null && widget.status != bookStatusFinished;

    // **One green thing, and it is whichever slot holds the answer.** Two `brandText`
    // values beside a green badge is what made three greens on one line, so the slot that
    // is only context recedes to `secondaryText`.
    final answerStyle = AppTextStyles.label.copyWith(
      color: context.colors.brandText,
    );

    final Widget? anchor = hasPosition
        // Not localized: a numeral and a percent sign, which sit the same way round in
        // both supported locales.
        ? Text('${(position * 100).round()}%', style: answerStyle)
        : finish != null
        ? Text(ReadingPeriodRow._formatDate(finish), style: answerStyle)
        : null;

    final values = [
      if (anchor != null) anchor,
      Text(
        l10n.daysCount((finish ?? DateTime.now()).difference(start).inDays),
        // Green only when it is the whole answer, which is a book that has been opened
        // and has neither a position nor a finish date.
        style: anchor == null
            ? answerStyle
            : AppTextStyles.label.copyWith(color: context.colors.secondaryText),
      ),
    ];

    final onTap = widget.onTap;
    if (onTap == null) {
      return _card(
        context,
        child: Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BookStatusBadge(status: widget.status),
            ...values,
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      // The press confirms the card the instant it is touched, which is the half of
      // "does it look tappable" that no resting frame can show — and it is what
      // teaches a reader the *card* is the target rather than the chevron in it.
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: _card(
        context,
        pressed: _pressed,
        minHeight: _kTouchFloor,
        child: Row(
          children: [
            BookStatusBadge(status: widget.status),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Align(
                  // The one rule that is most of the fix.
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: values,
                  ),
                ),
              ),
            ),
            // Translated rather than given a negative margin, which Flutter has no
            // spelling for. The glyph is the last child and the card has 10pt of
            // right padding for it to move into, so this paints where CSS
            // `margin-right: -10px` would and changes no layout.
            Transform.translate(
              offset: const Offset(_kChevronColumnPull, 0),
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: context.colors.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required Widget child,
    bool pressed = false,
    double minHeight = 0,
  }) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: pressed
            // Toward the band without reaching it. It must **not** darken to the
            // band's own `surfaceVariant`, or the card vanishes into what it is
            // sitting on — the same collision that made a `surfaceVariant` field on
            // a `surfaceVariant` band invisible. In light mode this lands on
            // #F1F3F5, which is distinguishable from both white and #E9ECEF;
            // expressed as a blend so the dark theme gets the same relationship
            // instead of a hard-coded light-mode grey.
            ? Color.lerp(
                context.colors.surface,
                context.colors.surfaceVariant,
                0.63,
              )
            : context.colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

/// The status-0 line's door: `Change status ›`.
///
/// Styled as the band's own prompt rather than as a button. [AppTextStyles.label] in
/// `brandText` with the same `chevron_right` at 20 the period card carries — there is no
/// fill, no border and no second ground, because furniture on it would make it the
/// loudest thing on the page.
///
/// **`brandText` rather than `secondaryText`, unlike `How far in?`.** That row's
/// prompt is in the no-value-yet tone because it will be *replaced by* a value in the
/// same slot at the same size, and the app's green is what marks the answer. This one
/// is an offer to act rather than a blank waiting to be filled, so it takes the colour
/// the app gives to things you can do.
///
/// **This used to add "and what replaces it is not green either", and that was never
/// true.** The value group that fills this slot at status 1 has always had a green
/// answer in it — the day count, back when the card printed a range beside it, and the
/// day count again now that a just-started book's card prints nothing else. So green
/// here is not doing the work of distinguishing the verb from its successor, and the
/// reason above is the whole reason.
///
/// The opacity is the press state, and on a wordmark with no fill it is the only one
/// available: there is no ground to darken the way the card darkens toward the band.
Widget _changeStatusVerb(BuildContext context, AppLocalizations l10n) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        l10n.changeStatus,
        style: AppTextStyles.label.copyWith(color: context.colors.brandText),
      ),
      // The same 2pt lead-in and the same 20pt glyph as both of the band's other
      // rows. No `_kChevronColumnPull`: that exists to drag the *card's* glyph out of
      // its 10pt inset into the x362 column, and this line has no inset to escape —
      // it is already in that column.
      Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Icon(
          Icons.chevron_right,
          size: 20,
          color: context.colors.brandText,
        ),
      ),
    ],
  );
}
