import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

/// One selectable row in [showMenuBottomSheet].
class MenuAction {
  final String label;
  final IconData? icon;

  /// Renders the label in the destructive style (red).
  final bool isDestructive;

  /// Marks the current choice with a trailing check.
  final bool isSelected;

  /// Runs *after* the sheet has been dismissed, so it's safe to immediately
  /// present another sheet or dialog from here.
  final VoidCallback onPressed;

  const MenuAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isDestructive = false,
    this.isSelected = false,
  });
}

/// Presents a menu of choices as a Material bottom sheet.
///
/// Deliberately Material on every platform: Flutter draws its own Cupertino
/// action sheets, so they can't pick up the OS's Liquid Glass material anyway —
/// a consistent Material sheet reads as intentional rather than half-native.
/// (Truly native, glass-capable menus come from [CNPopupMenuButton] instead.)
///
/// Uses [CNBottomSheet] rather than [showModalBottomSheet] so native glass
/// widgets on the page behind stay position-aware while the sheet is up.
Future<void> showMenuBottomSheet({
  required BuildContext context,
  required String title,
  required List<MenuAction> actions,
}) {
  return CNBottomSheet.show<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          for (final action in actions)
            ListTile(
              leading: action.icon != null ? Icon(action.icon) : null,
              title: Text(
                action.label,
                style: action.isDestructive
                    ? const TextStyle(color: cancelRedColor)
                    : null,
              ),
              trailing: action.isSelected
                  ? Icon(Icons.check, color: ctx.colors.brandText)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                action.onPressed();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
