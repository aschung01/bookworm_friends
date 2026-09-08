import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';

/// A tappable "label / date" field, as used for the start and finish dates.
///
/// Shared by the add-book and change-status sheets so the two read as the same
/// form: the sheets differ in what they save, not in how a date is picked.
///
/// Deliberately *not* a glass control. The row sits on an opaque sheet surface
/// with nothing behind it to refract, which is the same reason
/// `ElevatedActionButton` drops back to Material inside a sheet.
class DateFieldRow extends StatelessWidget {
  const DateFieldRow({
    super.key,
    required this.label,
    required this.date,
    required this.onTap,
  });

  /// Field label, e.g. "Start date".
  final String label;

  /// Currently picked day, or null when nothing has been chosen yet.
  final DateTime? date;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.body),
            Text(
              date != null
                  ? DateFormat('yyyy.MM.dd').format(date!)
                  : l10n.select,
              style: AppTextStyles.body.copyWith(
                color: date != null
                    ? context.colors.primaryText
                    : context.colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
