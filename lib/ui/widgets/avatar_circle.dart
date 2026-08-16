import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';

/// A friend (or your own) avatar in the friend rail: an emoji in a circle,
/// ringed and tinted when selected.
class AvatarCircle extends StatelessWidget {
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const AvatarCircle({
    super.key,
    required this.emoji,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? context.colors.brand.withValues(alpha: 0.15)
              : context.colors.surfaceVariant,
          border: Border.all(
            color: isSelected ? context.colors.brandText : Colors.transparent,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
