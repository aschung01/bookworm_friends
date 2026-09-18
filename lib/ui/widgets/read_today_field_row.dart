import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';

/// "I read today", as one more row of the change-status form.
///
/// **The third sibling of `DateFieldRow` and `ProgressFieldRow`** — same
/// `surfaceVariant` ground, radius 10, `symmetric(h14, v10)`, 15pt body on the left.
/// Where those two show a value on the right, this shows a mark, because the value it
/// carries has only two states.
///
/// **Not a `Switch` and not a Material `Checkbox`.** A switch reads as a setting that
/// stays on, and this is a statement about one night; the ring-and-tick is the app's
/// own vocabulary at the size the other two rows are. It also means the whole row is
/// the target, which a 20pt checkbox at the end of a 342pt row is not.
///
/// ## What ticking this does not do
///
/// The load-bearing half, and the one the drawings kept getting wrong: it writes one
/// `reading_days` row and **nothing else**. It does not move the reading position,
/// does not write `start_date` or `finish_date`, does not take the book off the
/// Reading shelf, and posts nothing to the friends feed. A day and a bookmark are two
/// different facts that happen to share a sheet.
///
/// ## Why "I read today" and not "Mark as read"
///
/// In a library app "read" is a *status* — the pile at the bottom of the library is
/// books read — so "mark as read" would read as finishing the book, which is the one
/// thing this control must not be mistaken for. First person and past tense, because
/// the reader is reporting something that happened rather than setting a preference.
class ReadTodayFieldRow extends StatelessWidget {
  const ReadTodayFieldRow({
    super.key,
    required this.read,
    required this.onChanged,
  });

  /// Whether today already has a row.
  ///
  /// **Set membership, not a counter.** `reading_days` is keyed on `(user_id, day)`,
  /// so this is the whole of the state: a day is in the set or it is not, and there is
  /// nothing here that can drift out of step with a stored total.
  final bool read;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return GestureDetector(
      onTap: () => onChanged(!read),
      // Opaque so the whole row is the target, including the gap between the label
      // and the mark.
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.readToday, style: AppTextStyles.body),
            _Mark(read: read),
          ],
        ),
      ),
    );
  }
}

/// The ring, and the ring filled in.
///
/// 22pt, which is the same box in both states — an unticked ring that grew when it was
/// ticked would nudge the label beside it. `brandFill` rather than `brand` because it
/// carries a white tick; `brand` is 2.45:1 against white and the tick would disappear
/// into it.
class _Mark extends StatelessWidget {
  const _Mark({required this.read});

  final bool read;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      // Short, and only on the fill: the mark confirms a tap that has already
      // happened, so anything longer reads as the row thinking about it.
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: read ? colors.brandFill : Colors.transparent,
        border: Border.all(
          color: read ? colors.brandFill : colors.secondaryText,
          width: 1.5,
        ),
      ),
      child: read
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}
