import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A dialog action that renders as a [CupertinoDialogAction] on Apple platforms
/// and a [TextButton] elsewhere.
///
/// Pair this with [AlertDialog.adaptive] / `showAdaptiveDialog`: those pick the
/// right dialog shell per platform, but pass `actions` through untouched, so
/// Material [TextButton]s would otherwise end up inside a Cupertino alert.
class AdaptiveDialogAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// Renders the label in the platform's destructive style (red).
  final bool isDestructive;

  /// Emphasises this action as the default choice (bold on Apple platforms).
  final bool isDefaultAction;

  /// Optional label color used on non-Apple platforms only.
  final Color? textColor;

  const AdaptiveDialogAction({
    super.key,
    required this.label,
    this.onPressed,
    this.isDestructive = false,
    this.isDefaultAction = false,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return CupertinoDialogAction(
          onPressed: onPressed,
          isDestructiveAction: isDestructive,
          isDefaultAction: isDefaultAction,
          child: Text(label),
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return TextButton(
          onPressed: onPressed,
          child: Text(
            label,
            style: TextStyle(
              color: isDestructive ? cancelRedColor : textColor,
              fontWeight: isDefaultAction ? FontWeight.bold : null,
            ),
          ),
        );
    }
  }
}
