import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';

/// The reactions a book has collected, as one capped capsule beside the cover.
///
/// Replaces a `Wrap` of one 28pt circle per reaction. Three things were wrong
/// with that, and the capsule answers all of them at once:
///
/// 1. **It grew without limit.** N reactions meant N circles in a 217pt column,
///    wrapping into rows that pushed toward the status badge below.
/// 2. **It was anonymous.** A circle cannot say whose reaction it is, which is
///    precisely why the button had to carry a copy of yours on its face — the
///    duplication this whole change exists to remove.
/// 3. **It was not a control.** Loose circles read as decoration, so the only
///    route to changing or withdrawing your reaction was the button, and the
///    button hides below status 2. A reaction on a book that went back to
///    *Reading* was visible and unreachable.
///
/// So: at most [kVisibleReactions] emoji, then `+N`, in a single tappable
/// capsule that opens the who-reacted sheet. Same material as the chips it
/// replaces — `pageBackground` fill, `brand` at 30% hairline — so it reads as
/// the same kind of object rather than as something new to learn.
///
/// When one of the reactions is yours the capsule takes the emoji picker's own
/// **this one is yours** treatment: `brand` at 25% with a [AppColors.brandText]
/// border. That is deliberately the same language `PraiseEmojiPicker` marks your
/// cell with, so the record and the sheet say the same thing the same way. The
/// numbers are better than they look: the two fills are only 1.37:1 apart in
/// luminance, but the border goes from 1.3:1 to 3.88:1, so the cue that survives
/// a dim screen is the border becoming visible rather than the hue changing.
///
/// The tint means *you are in this set*, not *this emoji is yours*. With two
/// reactions the whole capsule tints rather than marking which of the two is
/// yours — yours is pinned first by [orderedReactions], so per-emoji marking
/// would repeat what the order already says at a size too small to read.
class ReactionCapsule extends StatelessWidget {
  const ReactionCapsule({
    super.key,
    required this.compliments,
    required this.currentUserId,
    required this.onTap,
  });

  final List<BookCompliment> compliments;

  /// Whose reaction to pin first and tint for. Null when signed out.
  final String? currentUserId;

  /// Opens the who-reacted sheet. Required, not optional: the capsule is the
  /// only route to changing or withdrawing your reaction now that the button
  /// hides as soon as you have one, so a capsule that answered no taps would
  /// strand every reaction on the book.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (compliments.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final ordered = orderedReactions(compliments, currentUserId);
    final shown = ordered.take(kVisibleReactions).toList();
    final overflow = ordered.length - shown.length;
    final isMine =
        currentUserId != null &&
        ordered.first.fromUserId ==
            currentUserId; // pinned first, so first wins

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: isMine
                ? colors.brand.withValues(alpha: 0.25)
                : colors.pageBackground,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isMine
                  ? colors.brandText
                  : colors.brand.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in shown) ...[
                // `body` rather than `label`: this is the capsule's content, not a
                // caption on it, and an emoji shrunk to label size sits smaller
                // than the chevron beside it.
                Text(c.compliment, style: AppTextStyles.body),
                const SizedBox(width: 5),
              ],
              // `+1` is information; a bare `1` is not, so the count only appears
              // when something is actually hidden behind it.
              if (overflow > 0) ...[
                Text(
                  '+$overflow',
                  style: AppTextStyles.label.copyWith(
                    // Not secondaryText: that measures 2.0:1 on
                    // pageBackground, which is unreadable.
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              // Load-bearing rather than decorative. Once the button hides, this
              // capsule is the only way to reach your own reaction, and on a book
              // that is not finished it is the only interactive thing in the
              // hero — so the affordance has to be stated rather than implied.
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colors.primaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
