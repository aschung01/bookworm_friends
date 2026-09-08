import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';

/// Who reacted to a book, and with what.
///
/// This is what capping the capsule buys. Detail moves somewhere it has room
/// instead of being crammed into a 217pt column, and every reaction gets the one
/// thing an emoji alone cannot carry: whose it is.
///
/// It is also the only route to your own reaction. The alternative is to
/// recognise your own emoji among three and a half thousand in the picker and
/// know that tapping it takes it back — which works, and is unfindable. Your row
/// leads the list and is the only tappable one, marked with [reactionYours] and a
/// trailing chevron.
///
/// The chevron is left to carry that on its own rather than being captioned. A
/// line of help text under a single tappable row explains a control the row's own
/// disclosure already announces, and it was the one string here that had to be
/// translated to say anything at all.
///
/// And because the capsule that opens this belongs to the record rather than to
/// the button, this route survives a book going back to *Reading* or *Interested*
/// — the states where the button returns an empty box and used to take the only
/// way in with it.
///
/// This sheet pops itself before handing over, so the picker replaces it rather
/// than stacking on it. Putting it back when the picker is dismissed without a
/// choice is the caller's job — see `_onReactionsPressed`.
Future<void> showReactionsSheet(
  BuildContext context, {
  required List<BookCompliment> compliments,
  required String? currentUserId,

  /// Opens the emoji picker on your own reaction. Called after this sheet has
  /// been popped, so the picker replaces it rather than stacking on top.
  required VoidCallback onEditMine,
}) {
  final l10n = AppLocalizations.of(context);
  final ordered = orderedReactions(compliments, currentUserId);

  return CNBottomSheet.show(
    context: context,
    builder: (context) => Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 24, bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.reactionsTitle, style: AppTextStyles.subtitle),
          const SizedBox(height: 8),
          for (final c in ordered)
            _ReactionRow(
              compliment: c,
              isMine: c.fromUserId == currentUserId,
              onTap: c.fromUserId == currentUserId
                  ? () {
                      Navigator.pop(context);
                      onEditMine();
                    }
                  : null,
            ),
        ],
      ),
    ),
  );
}

/// One row: who, what they left, and — if it is yours — the way to change it.
class _ReactionRow extends StatelessWidget {
  const _ReactionRow({
    required this.compliment,
    required this.isMine,
    this.onTap,
  });

  final BookCompliment compliment;
  final bool isMine;

  /// Null for everyone else's rows, which are not tappable. Passing null rather
  /// than an empty callback matters: an `InkWell` with `onTap: null` shows no
  /// press feedback, so the row does not pretend to be interactive.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            AvatarCircle(
              emoji: compliment.reactorEmoji,
              avatarPath: compliment.reactorAvatarPath,
              diameter: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                // A profile the viewer is not allowed to read has no name to
                // show, so it is said rather than left blank — a nameless row
                // beside an avatar placeholder reads as a bug.
                compliment.reactorIsKnown
                    ? compliment.reactorName!
                    : l10n.reactorUnknown,
                style: AppTextStyles.body.copyWith(
                  color: compliment.reactorIsKnown
                      ? colors.primaryText
                      : colors.secondaryText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isMine) ...[
              Text(
                l10n.reactionYours,
                style: AppTextStyles.label.copyWith(color: colors.brandText),
              ),
              const SizedBox(width: 8),
            ],
            // `titleUser` for its 22pt metrics only: this is a single emoji
            Text(
              compliment.compliment,
              style: const TextStyle(fontSize: kEmojiGlyphSize),
            ),
            if (isMine)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.primaryText,
              ),
          ],
        ),
      ),
    );
  }
}
