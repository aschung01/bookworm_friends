import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

import 'app_sheet.dart';

/// Confirms the merged status sheet's one grey text action, in whichever direction it
/// currently points: `Stop reading this`, or `Start reading again`.
///
/// ## Why an action this ordinary is confirmed at all
///
/// Not because setting a book aside is dangerous — it is reversible in one tap, and every
/// string around it is written to keep judgement out of it. It is confirmed because of
/// what the control physically is: a **full-width `HitTestBehavior.opaque` band of text**
/// at the bottom of a sheet, sitting directly under a date row that is also tappable. The
/// band is deliberately wide — a text-sized target for the least important label on the
/// sheet is hard to land on — and the cost of that width is that it is easy to hit without
/// meaning to.
///
/// **Both directions are confirmed now, and only one was.** Resuming was deliberately
/// unconfirmed, on the reasoning that _an accidental resume costs a reader nothing_ and
/// that confirming both would make the pair look like a matched set of consequential acts.
/// The first half stopped being true the moment confirming began to write (below): an
/// accidental resume now costs a write, and that write clears the day the book was closed.
/// The second half was answered by making this **one function in two sets of words** rather
/// than two sheets — the same reasoning `_SheetTextAction` uses for the action itself, that
/// a pair drawn differently reads as an action and a _correction_.
///
/// ## It writes, and it did not
///
/// **This reverses the section that used to stand here**, which read: _"Like
/// `showSelectDateBottomSheet` and `showSelectPercentBottomSheet`, this hands an answer
/// back and the status sheet holds it until Save ... `Save` is the only writer anywhere in
/// that sheet, and that invariant is the entire answer to the objection which killed the
/// drag control the first time it was drawn — 'a stray touch could silently rewrite your
/// position'."_ It also recorded the argument that lost, and that argument is now the
/// instruction: _a confirmation that returns you to a form with a Save button in it looks
/// like being asked twice._
///
/// **What makes the reversal safe is the thing being reversed.** The old invariant existed
/// to stop a *stray touch* writing, and a confirmation is a different, stronger answer to
/// exactly that problem: nothing reaches the database without a deliberate second tap. So
/// the protection did not go away, it moved — from "nothing writes until Save" to "this
/// writes only because you were asked". Every other sub-sheet still hands its answer back,
/// because a date and a percent are values the reader is composing rather than acts they
/// are committing.
///
/// **What it costs, stated:** a reader who confirms and then dismisses the status sheet has
/// changed their library, where dismissing used to discard everything. That is why the
/// affirmative buttons name the act (`Stop reading`, `Start reading`) rather than saying
/// `Confirm` — the button is now the commit.
///
/// [onConfirmed] fires after this sheet is popped, so the caller runs against the status
/// sheet, which is still below.
Future<void> showStopReadingBottomSheet(
  BuildContext context, {
  required VoidCallback onConfirmed,
}) {
  final l10n = AppLocalizations.of(context);
  return _show(
    context,
    title: l10n.stopReadingConfirmTitle,
    body: l10n.stopReadingConfirmBody,
    action: l10n.stopReadingConfirmAction,
    onConfirmed: onConfirmed,
  );
}

/// The same sheet, pointing the other way. See the class doc for why this exists at all —
/// it did not until confirming started to write.
Future<void> showStartReadingAgainBottomSheet(
  BuildContext context, {
  required VoidCallback onConfirmed,
}) {
  final l10n = AppLocalizations.of(context);
  return _show(
    context,
    title: l10n.startReadingAgainConfirmTitle,
    body: l10n.startReadingAgainConfirmBody,
    action: l10n.startReadingAgainConfirmAction,
    onConfirmed: onConfirmed,
  );
}

Future<void> _show(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  required VoidCallback onConfirmed,
}) {
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
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: 8),
          Text(
            body,
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
                  buttonText: AppLocalizations.of(context).cancel,
                  backgroundColor: context.colors.surfaceVariant,
                  textStyle: AppTextStyles.label,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedActionButton(
                  height: 44,
                  buttonText: action,
                  // **Not `isDestructive`, and not `softRedColor`.** The delete sheet's
                  // affirmative is red because a deleted book is gone; this one moves a
                  // book between two states it can move back from, and dressing it in
                  // the delete colour would contradict every string in it. That holds
                  // even now that the button commits: reversible in one tap is still
                  // reversible in one tap.
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
