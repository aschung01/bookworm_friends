import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

import 'app_sheet.dart';

/// Confirms `Stop reading this`, the merged status sheet's grey text action.
///
/// ## Why an action this ordinary is confirmed at all
///
/// Not because setting a book aside is dangerous — it is reversible in one tap by
/// `startReadingAgain`, and every string around it is written to keep judgement out of
/// it. It is confirmed because of what the control physically is: a **full-width
/// `HitTestBehavior.opaque` band of grey text** at the bottom of a sheet, with no fill, no
/// border and no button furniture, sitting directly under a date row that is also tappable.
/// The band is deliberately wide — a text-sized target for the least important label on the
/// sheet is hard to land on — and the cost of that width is that it is easy to hit without
/// meaning to. The confirmation is what makes the tap legible, not what makes it safe.
///
/// ## It does not write, and that is the whole reason it fits here
///
/// Like `showSelectDateBottomSheet` and `showSelectPercentBottomSheet`, this hands an answer
/// back and the status sheet holds it until **Save**. That was the live question when it was
/// added: a confirmation that returns you to a form with a Save button in it looks like being
/// asked twice, so committing straight from here was the obvious alternative.
///
/// It was rejected, on two grounds. `Save` is the only writer anywhere in that sheet, and
/// that invariant is the entire answer to the objection which killed the drag control the
/// first time it was drawn — _"a stray touch could silently rewrite your position"_ — so a
/// second commit path would have to be argued against the reason the sheet exists. And the
/// symmetry is with the sheet's other sub-sheets rather than with the app's delete sheets:
/// answering the date sheet does not save a date either. So this is one more question the
/// form asks, and dismissing the status sheet still discards it.
///
/// [onConfirmed] fires after this sheet is popped, so the caller runs against the status
/// sheet, which is still below.
Future<void> showStopReadingBottomSheet(
  BuildContext context, {
  required VoidCallback onConfirmed,
}) {
  final l10n = AppLocalizations.of(context);
  return AppSheet.show(
    context: context,
    // The delete sheet's geometry, because this is the app's confirmation shape and a
    // second one would be a new thing to learn for no gain.
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.stopReadingConfirmTitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.stopReadingConfirmBody,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: context.colors.secondaryText,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedActionButton(
                  height: 44,
                  buttonText: l10n.cancel,
                  backgroundColor: context.colors.surfaceVariant,
                  textStyle: AppTextStyles.label,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedActionButton(
                  height: 44,
                  buttonText: l10n.stopReadingConfirmAction,
                  // **Not `isDestructive`, and not `softRedColor`.** The delete sheet's
                  // affirmative is red because a deleted book is gone; this one moves a
                  // book between two shelves it can move back from, and dressing it in
                  // the delete colour would contradict every string in it.
                  onPressed: () {
                    Navigator.pop(context);
                    onConfirmed();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
