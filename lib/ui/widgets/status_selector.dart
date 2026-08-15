import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// Picks a book's reading status: interested / reading / finished.
///
/// Three short, mutually exclusive options, which is exactly what a segmented
/// control is for — so on iOS 26+ this is a native [CNSegmentedControl] (Liquid
/// Glass, system selection animation and haptics). Everywhere else it falls back
/// to the app's pill chips.
///
/// [labels] is ordered by status value: index 0 is "interested", 1 "reading",
/// 2 "finished".
class BookStatusSelector extends StatelessWidget {
  const BookStatusSelector({
    super.key,
    required this.labels,
    required this.status,
    required this.onChanged,
  });

  final List<String> labels;

  /// Currently selected status, as an index into [labels].
  final int status;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    if (useNativeGlass) {
      return SizedBox(
        width: double.infinity,
        child: CNSegmentedControl(
          labels: labels,
          selectedIndex: status.clamp(0, labels.length - 1),
          // Deliberately untinted. `CNSegmentedControl` exposes a single tint
          // and no label color, so tinting the selected segment with the brand
          // green left the system's dark label on a dark thumb. The system
          // appearance (light thumb, dark label) stays legible in both themes.
          onValueChanged: onChanged,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < labels.length; i++)
          _StatusChip(
            label: labels[i],
            selected: i == status,
            onTap: () => onChanged(i),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.brandFill
              : context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : context.colors.primaryText,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
