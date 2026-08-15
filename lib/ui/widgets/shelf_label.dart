import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:flutter/material.dart';

/// The small "tab" that names the shelf a book sits on.
///
/// Renders nothing for an empty [label] so callers don't have to special-case
/// a book whose shelf can't be resolved. Long shelf names are capped and
/// ellipsized instead of running past the edge of the screen.
class ShelfLabel extends StatelessWidget {
  final String label;

  /// Widest the tab may grow before its text ellipsizes.
  final double maxWidth;

  const ShelfLabel({super.key, required this.label, this.maxWidth = 140});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      // No `alignment` here: a Container with an alignment expands to fill the
      // space it is offered, which stretched the tab across the cover. Without
      // it the tab shrink-wraps its label, as it does in the library.
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          topRight: Radius.circular(3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
