import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// Picks the shelf a book is saved to.
///
/// On iOS 26+ this is a settings-style row whose trailing control is a native
/// [CNPopupMenuButton]: a real `UIMenu` with Liquid Glass, system haptics and a
/// checkmark against the current shelf. Everywhere else it falls back to the
/// themed Material dropdown.
///
/// Renders nothing when there are no shelves to choose from, so callers don't
/// have to special-case an empty library.
class ShelfSelector extends StatelessWidget {
  const ShelfSelector({
    super.key,
    required this.label,
    required this.shelves,
    required this.selected,
    required this.onChanged,
  });

  /// Field label, e.g. "Select shelf".
  final String label;

  final List<String> shelves;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (shelves.isEmpty) return const SizedBox.shrink();
    return useNativeGlass ? _buildGlass(context) : _buildMaterial(context);
  }

  Widget _buildGlass(BuildContext context) {
    final current = selected ?? shelves.first;

    return Semantics(
      label: label,
      value: current,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.secondaryText,
              ),
            ),
          ),
          ConstrainedBox(
            // Long shelf names are common, so cap the button and let the native
            // label truncate rather than pushing the row's label out.
            constraints: const BoxConstraints(maxWidth: 220),
            child: CNPopupMenuButton(
              buttonLabel: current,
              buttonStyle: CNButtonStyle.glass,
              height: 36,
              shrinkWrap: true,
              items: [
                for (final shelf in shelves)
                  CNPopupMenuItem(label: shelf, checked: shelf == current),
              ],
              onSelected: (index) {
                if (index >= 0 && index < shelves.length) {
                  onChanged(shelves[index]);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterial(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: context.colors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        for (final shelf in shelves)
          DropdownMenuItem(value: shelf, child: Text(shelf)),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
