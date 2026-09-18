import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
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
/// ## The card is a door, when [onTap] is given
///
/// It opens `showBookStatusBottomSheet`, which edits status, start and finish —
/// **exactly what this card displays**. That is what retired the app bar's
/// `edit_outlined`: once the thing you tap to change a fact is the fact itself, a
/// pencil 400pt away in the top-right corner has no job.
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
  });

  final int status;

  /// Null below status 1, where a book has no dates yet.
  final DateTime? startDate;
  final DateTime? finishDate;

  /// Opens the change-status sheet. **Null on a friend's book**, which leaves the
  /// card exactly as it shipped before this became a door: no chevron, no touch
  /// floor, no press state. A handle on a door nobody can open is a lie.
  final VoidCallback? onTap;

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
    // Which also means there is nothing to make a door of: with no card there is no
    // shape for a chevron to sit at the end of, and the bare badge is not a control.
    // The app bar is not an escape hatch for this any more, so an Interested book is
    // edited from the library's own sheets — see the note on the retired pencil in
    // `book_details_tab_view.dart`.
    //
    // Aligned rather than returned directly: `BookStatusBadge` is a `Container`
    // with no width of its own, so a caller passing tight constraints stretches
    // it edge to edge. The band happens to pass loose ones, which hid this — but
    // a chip that is 333pt wide in one parent and shrink-wrapped in another is
    // the sort of thing that only shows up on device.
    if (start == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: BookStatusBadge(status: widget.status),
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
