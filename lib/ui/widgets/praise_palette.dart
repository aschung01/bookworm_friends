import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:flutter/material.dart';

/// The fixed set of praise emoji. Praise is a one-tap reaction from this
/// palette, not free text — which is why `book_compliments.compliment` is a
/// `varchar(6)` (❤️ alone is two code points).
const List<String> praiseEmojis = [
  '👏',
  '🎉',
  '❤️',
  '🔥',
  '⭐',
  '💪',
  '😍',
  '🥰',
  '👍',
  '✨',
  '🎊',
  '💯',
  '🙌',
  '😎',
  '🤩',
  '💐',
];

/// The emoji grid, with the caller's current pick marked.
///
/// [selected] is what makes toggle-and-replace legible. One person can hold only
/// one praise per book, so re-opening the palette has to say which emoji is
/// already yours: tapping it again takes it back, tapping another swaps it, and
/// neither reads as "add a second one" once the grid shows where you stand.
///
/// Extracted from the bottom sheet so the highlight can be tested without
/// driving a modal, and so the profile-emoji picker in settings — the same grid,
/// same one-of-many choice — can mark its current value too.
class PraisePalette extends StatelessWidget {
  const PraisePalette({super.key, required this.onPick, this.selected});

  /// The emoji the viewer has already chosen, if any.
  final String? selected;

  final void Function(String emoji) onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: praiseEmojis.length,
      itemBuilder: (_, i) {
        final emoji = praiseEmojis[i];
        final isSelected = emoji == selected;

        return Semantics(
          button: true,
          selected: isSelected,
          child: GestureDetector(
            onTap: () => onPick(emoji),
            child: Container(
              key: ValueKey('praise-$emoji'),
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.brand.withValues(alpha: 0.25)
                    : colors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: isSelected
                    ? Border.all(color: colors.brandFill, width: 2)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
          ),
        );
      },
    );
  }
}
