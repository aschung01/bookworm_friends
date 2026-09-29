import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// What [BookStatusBadge] draws for one status, and what the merged status sheet
/// borrows the first two fields of.
///
/// A named record rather than four positional returns for the reason `BookStatusEdit`
/// is one: three of the four are a `Color`, so a caller transposing any pair would
/// compile and the mistake would be a wrong-coloured chip rather than an error.
typedef BookStatusPresentation = ({
  String label,
  Color textColor,
  Color fillColor,
  Color borderColor,
});

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

  /// The word for a status and the ink it is drawn in, without the chip around it.
  ///
  /// **Exposed so the merged status sheet can borrow it.** That sheet prints the status
  /// as running text in a one-line read-out rather than as a chip, and the two must not
  /// be able to disagree about either the word or the colour. The app has already paid
  /// for that mistake once, with two different flame drawings for one streak; a second
  /// status vocabulary would be the same defect in words.
  ///
  /// The caller takes `label` and `textColor` and ignores the two fills.
  static BookStatusPresentation presentation(
    AppLocalizations l10n,
    AppColors colors,
    int status,
  ) => switch (status) {
    0 => (
      label: l10n.statusInterested,
      textColor: colors.primaryText,
      fillColor: Colors.transparent,
      borderColor: colors.primaryText.withValues(alpha: unfilledBorderAlpha),
    ),
    1 => (
      label: l10n.statusReading,
      textColor: colors.brandText,
      fillColor: colors.brandText.withValues(alpha: 0.1),
      borderColor: colors.brandText.withValues(alpha: 0.4),
    ),
    2 => (
      label: l10n.statusFinished,
      textColor: colors.primaryText,
      fillColor: colors.primaryText.withValues(alpha: 0.1),
      borderColor: colors.primaryText.withValues(alpha: 0.4),
    ),
    // Set aside: closed short of the end.
    //
    // **Not green, and not status 0's treatment either**, which are the two ways this
    // arm could have gone wrong. Green means *reading* across the whole app and a test
    // pins that; and an unfilled chip with a `primaryText` rim is exactly what status 0
    // draws two arms up, which would have made "Not started" and "Set aside" one chip.
    // So it takes status 2's filled shape — the book is over — in `secondaryText`,
    // which is this app's tone for something finished with that is not an achievement.
    3 => (
      label: l10n.statusSetAside,
      textColor: colors.secondaryText,
      fillColor: colors.secondaryText.withValues(alpha: 0.1),
      borderColor: colors.secondaryText.withValues(alpha: 0.4),
    ),
    // **Unreachable, and kept as a guard rather than as a label.**
    //
    // Until status 3 existed this arm caught it and drew "Other", which is the failure
    // mode worth naming: it fails *soft*. A set-aside book wore a chip reading "Other"
    // while nothing threw, nothing logged and no test went red — the same class of
    // defect as `selectedIndex: status.clamp(...)` silently showing "Read". If a fifth
    // status is ever added, this `switch` is the thing to fix, and the symptom will
    // again be a correct-looking chip with the wrong word in it.
    _ => (
      label: l10n.statusOther,
      textColor: colors.primaryText,
      fillColor: Colors.transparent,
      borderColor: colors.primaryText.withValues(alpha: unfilledBorderAlpha),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final p = presentation(
      AppLocalizations.of(context),
      context.colors,
      status,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.fillColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.borderColor),
      ),
      child: Text(
        p.label,
        style: AppTextStyles.label.copyWith(color: p.textColor),
      ),
    );
  }
}
