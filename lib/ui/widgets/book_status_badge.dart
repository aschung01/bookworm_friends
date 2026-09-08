import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The reading status of a book, as a small chip.
///
/// The three statuses read as a **progression of weight** — an empty outline for
/// *Interested*, a green tint for *Reading*, a dark tint for *Read* — rather than
/// as three hues. That is not decoration; it is the fix for a real defect.
///
/// Every status used to derive its text, fill and border from one colour, which
/// worked for two of them and failed badly for the third. Measured against its
/// own composited fill on `surfaceVariant`:
///
/// | status     | colour          | text : own fill |
/// |------------|-----------------|-----------------|
/// | Read       | `primaryText`   | 10.78:1         |
/// | Reading    | `brandText`     |  4.14:1         |
/// | Interested | `secondaryText` |  **1.66:1**     |
///
/// *Interested* was effectively invisible, with a 1.23:1 border to match, on 133
/// of 472 books. Dropping its fill and taking the text to [AppColors.primaryText]
/// is the repair, and dropping the fill is the half that matters: the old
/// *Interested* and *Read* tints composite to `#E3E6EA` and `#D5D8DB`, two
/// near-identical greys, so the two ends of the progression were only ever
/// separated by a text colour nobody could read. Darkening the text alone was
/// tried and rejected for exactly that — legible, but it made *Interested* look
/// like *Read*.
///
/// With no fill, the border is what identifies the chip as a chip rather than as
/// loose text, so it is held to WCAG 1.4.11's 3:1 bar: `primaryText` at 55%
/// measures 3.41:1, where the 35% first drawn was 2.06:1.
///
/// *Reading* is left exactly as it shipped despite missing AA by a little, and
/// that is a decision rather than an oversight. [AppColors.brandText] genuinely
/// is 4.74:1 on `surfaceVariant` — the figure `app_theme.dart` documents and
/// `color_contrast_test.dart` asserts — and it is this chip's own 10% tint
/// darkening the background under it that drops it to 4.14:1. Fixing it costs
/// either the green text or the green fill, and green-means-reading is
/// load-bearing across the app. Pinned by a test rather than left to drift.
class BookStatusBadge extends StatelessWidget {
  final int status;
  const BookStatusBadge({super.key, required this.status});

  /// Alpha for the outline of a chip that has no fill.
  ///
  /// 0.55 rather than the 0.4 the filled chips use: with nothing behind it, this
  /// border has to clear 3:1 on its own.
  static const double unfilledBorderAlpha = 0.55;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    final (label, textColor, fillColor, borderColor) = switch (status) {
      0 => (
        l10n.statusInterested,
        colors.primaryText,
        Colors.transparent,
        colors.primaryText.withValues(alpha: unfilledBorderAlpha),
      ),
      1 => (
        l10n.statusReading,
        colors.brandText,
        colors.brandText.withValues(alpha: 0.1),
        colors.brandText.withValues(alpha: 0.4),
      ),
      2 => (
        l10n.statusFinished,
        colors.primaryText,
        colors.primaryText.withValues(alpha: 0.1),
        colors.primaryText.withValues(alpha: 0.4),
      ),
      _ => (
        l10n.statusOther,
        colors.primaryText,
        Colors.transparent,
        colors.primaryText.withValues(alpha: unfilledBorderAlpha),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Text(label, style: AppTextStyles.label.copyWith(color: textColor)),
    );
  }
}
