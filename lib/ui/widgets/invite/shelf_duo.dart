import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';

/// Two libraries, interleaving.
///
/// **The mark on the consent and success screens, and it is deliberately not two
/// portraits joined by a line.** Flighty draws exactly that, because what their two
/// people share is a flight — one object, in the middle, belonging to both. Libstack's
/// subject is a *stack*: it is the name, and `assets/branding/app_icon.svg` is fanned
/// covers. So what meets in the middle here is two shelves rather than a path, one in
/// [AppColors.surfaceVariant] and one washed in brand, with their spines interleaving
/// at the seam.
///
/// **Drawn rather than illustrated.** No asset: the two people are named at run time
/// and their emoji come from their profiles, so anything pre-rendered would either
/// omit them or need six variants. The spines are plain rounded rectangles because
/// this is a diagram of a relationship, not a picture of a bookshelf — real covers
/// here would invite the reader to try to read titles that mean nothing.
class ShelfDuo extends StatelessWidget {
  /// The inviter's glyph and name.
  final String? emoji;
  final String? avatarPath;
  final String name;

  /// The reader's own side. Usually their own emoji; the label is theirs to supply,
  /// because "YOU" is a string the l10n owns.
  final String? myEmoji;
  final String? myAvatarPath;
  final String myLabel;

  /// Drops a brand-filled check at the seam.
  ///
  /// The one difference between the consent mark and the success mark, and the only
  /// thing allowed to differ: the two screens are the same moment before and after,
  /// so a second illustration would make them look like two unrelated events.
  final bool sealed;

  const ShelfDuo({
    super.key,
    required this.emoji,
    required this.avatarPath,
    required this.name,
    required this.myEmoji,
    required this.myAvatarPath,
    required this.myLabel,
    this.sealed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Side(
                emoji: emoji,
                avatarPath: avatarPath,
                label: name,
                // The inviter's side leans on the neutral fill, the reader's on
                // brand. Which way round is arbitrary and consistent: the reader is
                // always the green one, on both screens, so the mark reads the same
                // way each time it appears.
                spineColor: colors.surfaceVariant,
                leaning: _Lean.right,
              ),
              _Side(
                emoji: myEmoji,
                avatarPath: myAvatarPath,
                label: myLabel,
                spineColor: colors.brand.withValues(alpha: 0.55),
                leaning: _Lean.left,
              ),
            ],
          ),
          if (sealed)
            Positioned(
              // Sits on the seam, a little above the plank, so it reads as dropped
              // between the two stacks rather than resting on the shelf.
              bottom: 54,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.brandFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.pageBackground, width: 3),
                ),
                child: const Icon(Icons.check, size: 18, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

enum _Lean { left, right }

class _Side extends StatelessWidget {
  final String? emoji;
  final String? avatarPath;
  final String label;
  final Color spineColor;
  final _Lean leaning;

  const _Side({
    required this.emoji,
    required this.avatarPath,
    required this.label,
    required this.spineColor,
    required this.leaning,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Ragged on purpose. A row of identical bars is a bar chart; books are not the
    // same height, and four heights is enough to say so without the shape becoming
    // the subject.
    const heights = <double>[62, 78, 54, 70];
    final ordered = leaning == _Lean.right
        ? heights
        : heights.reversed.toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AvatarCircle(emoji: emoji, avatarPath: avatarPath, diameter: 40),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final height in ordered)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 12,
                  height: height,
                  decoration: BoxDecoration(
                    color: spineColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // The plank. Both sides draw their own half, so the two meet flush at the
        // seam without either needing to know the other's width.
        Container(height: 3, width: 60, color: colors.divider),
        const SizedBox(height: 8),
        SizedBox(
          width: 76,
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(color: colors.secondaryText),
          ),
        ),
      ],
    );
  }
}
