import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';

/// "Reading period" summary: the label, the date range and the elapsed day
/// count.
///
/// Laid out as a [Wrap] so a long range (or a longer localized label) moves to
/// the next line instead of overflowing or truncating — every value stays
/// readable at any width.
class ReadingPeriodRow extends StatelessWidget {
  const ReadingPeriodRow({super.key, required this.startDate, this.finishDate});

  final DateTime startDate;
  final DateTime? finishDate;

  static String _formatDate(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final range =
        '${_formatDate(startDate)} ~ ${finishDate != null ? _formatDate(finishDate!) : ''}';

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
          Text(
            l10n.readingPeriod,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          Text(range, style: const TextStyle(fontSize: 14)),
          Text(
            l10n.daysCount(
              (finishDate ?? DateTime.now()).difference(startDate).inDays,
            ),
            style: TextStyle(
              color: context.colors.brandText,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
