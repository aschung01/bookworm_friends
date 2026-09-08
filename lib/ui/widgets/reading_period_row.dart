import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';

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
/// Laid out as a [Wrap] so a long range (or a longer localized label) moves to
/// the next line instead of overflowing or truncating — every value stays
/// readable at any width.
class ReadingPeriodRow extends StatelessWidget {
  const ReadingPeriodRow({
    super.key,
    required this.status,
    this.startDate,
    this.finishDate,
  });

  final int status;

  /// Null below status 1, where a book has no dates yet.
  final DateTime? startDate;
  final DateTime? finishDate;

  static String _formatDate(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final start = startDate;

    // No dates means no card. Wrapping a lone chip in a full-width white slab
    // was drawn at real scale and looked worse than the corner it replaced, so
    // at status 0 the badge sits in the band bare. The rule that matters —
    // status lives here, under the author — holds either way; the card is a
    // container for dates, and when there are none there is no card.
    //
    // Aligned rather than returned directly: `BookStatusBadge` is a `Container`
    // with no width of its own, so a caller passing tight constraints stretches
    // it edge to edge. The band happens to pass loose ones, which hid this — but
    // a chip that is 333pt wide in one parent and shrink-wrapped in another is
    // the sort of thing that only shows up on device.
    if (start == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: BookStatusBadge(status: status),
      );
    }

    final range =
        '${_formatDate(start)} ~ ${finishDate != null ? _formatDate(finishDate!) : ''}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          BookStatusBadge(status: status),
          Text(range, style: AppTextStyles.label),
          Text(
            l10n.daysCount(
              (finishDate ?? DateTime.now()).difference(start).inDays,
            ),
            // Same token as the range beside it: `brandText` is what marks the
            // duration as the row's answer, so emphasising it twice would only
            // make one line of small print look like a different size.
            style: AppTextStyles.label.copyWith(
              color: context.colors.brandText,
            ),
          ),
        ],
      ),
    );
  }
}
