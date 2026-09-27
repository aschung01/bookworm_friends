import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/band_progress_row.dart';
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
/// The same 14 as [kBandProgressRowSpill], taken out of the band's 16pt bottom
/// padding in the same way and for the same reason: the band's height is unchanged
/// by making the line tappable. The figure is shared rather than restated because
/// there is only one bottom padding to take it out of.
///
/// **Only one of the two rows can ever spend it, and that is provable rather than
/// arranged.** This line spills only when there is no start date; [BandProgressRow]
/// exists only at `bookStatusReading`, which the status sheet cannot leave without
/// defaulting a start date. The `spillsIntoBandPadding` flag is what settles the
/// legacy row that manages to be both — a status-1 book with a null start — by
/// handing the padding to the progress row, which is the lower of the two.
///
/// The target this buys is **40pt rather than 44**, and that is the one deliberate
/// shortfall in the band. The alternative was 18pt of permanent band height on every
/// Interested book to seat a 26pt line in a 44pt box, on the one screen whose last
/// redesign was about lifting content above the tab strip. 40×110 is not a glyph
/// button in a corner; it is a labelled row two thirds the width of the band.
const double kStatusVerbSpill = kBandProgressRowSpill;

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
/// white card left in the band to be confused with. The two doors are told apart by
/// what they say, not by their grounds.
///
/// Laid out as a [Wrap] so a long range (or a longer localized label) moves to
/// the next line instead of overflowing or truncating — every value stays
/// readable at any width. That survives the door treatment: the value group is
/// pushed right *and* still wraps, rather than being pinned to one line.
class ReadingPeriodRow extends StatefulWidget {
  const ReadingPeriodRow({
    super.key,
    required this.status,
    this.startDate,
    this.finishDate,
    this.onTap,
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

  /// Whether the caller has taken [kStatusVerbSpill] out of the band's bottom
  /// padding for this row, so the status-0 verb may reach below its own ink.
  ///
  /// False by default, which is the safe answer: the target is then the line's own
  /// height and nothing overhangs a neighbour. The band passes `!showsProgressRow`,
  /// because there is one bottom padding and [BandProgressRow] has first claim on it.
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
    final range =
        '${ReadingPeriodRow._formatDate(start)} ~ ${finish != null ? ReadingPeriodRow._formatDate(finish) : ''}';

    final values = [
      Text(range, style: AppTextStyles.label),
      Text(
        l10n.daysCount((finish ?? DateTime.now()).difference(start).inDays),
        // Same token as the range beside it: `brandText` is what marks the
        // duration as the row's answer, so emphasising it twice would only
        // make one line of small print look like a different size.
        style: AppTextStyles.label.copyWith(color: context.colors.brandText),
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
/// `brandText` with the same `chevron_right` at 20 that the period card and
/// [BandProgressRow] carry — there is no fill, no border and no second ground, because
/// the band already has two doors and a third with furniture on it would be the
/// loudest thing on the page.
///
/// **`brandText` rather than `secondaryText`, unlike `How far in?`.** That row's
/// prompt is in the no-value-yet tone because it will be *replaced by* a value in the
/// same slot at the same size, and the app's green is what marks the answer. This one
/// is replaced by a date range, which is not green either — it is an offer to act, not
/// a blank waiting to be filled, so it takes the colour the app gives to things you
/// can do.
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
