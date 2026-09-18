import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// A row of short, mutually exclusive options.
///
/// **Native [CNSegmentedControl] on iOS 26+** — Liquid Glass, the system selection
/// animation and its haptics — falling back to the app's pill chips everywhere else.
/// This is the whole of that split, in one place, because there are now two callers
/// and duplicating the fallback would let the two drift into different controls.
///
/// **The fallback is what widget tests drive**, and that is load-bearing rather than
/// incidental: [useNativeGlass] is false under `flutter test`, which reports Android,
/// so the chips render and can be tapped. A native segmented control is a platform
/// view with no Flutter hit target and is untappable in a test — which for a while
/// looked like a reason not to use it at all. It is not; it is a reason the fallback
/// has to stay tappable.
///
/// [labels] is ordered by value: [selectedIndex] indexes into it.
class GlassSegmentedControl extends StatelessWidget {
  const GlassSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    if (useNativeGlass) {
      return SizedBox(
        width: double.infinity,
        child: CNSegmentedControl(
          labels: labels,
          selectedIndex: selectedIndex.clamp(0, labels.length - 1),
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
          _SegmentChip(
            label: labels[i],
            selected: i == selectedIndex,
            onTap: () => onChanged(i),
          ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

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
          // One token for both states. The fill and the white-on-brand label are
          // already the whole of what marks the selection, and the row is three
          // chips wide — bolding the chosen one made it read as a fourth size.
          style: AppTextStyles.label.copyWith(
            color: selected ? Colors.white : context.colors.primaryText,
          ),
        ),
      ),
    );
  }
}
