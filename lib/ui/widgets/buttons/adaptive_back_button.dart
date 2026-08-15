import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:flutter/material.dart';

/// Navigation back button.
///
/// Renders a native Liquid Glass circular icon button on iOS 26+ / macOS 26+,
/// and falls back to the themed Material [IconButton] everywhere else.
class AdaptiveBackButton extends StatelessWidget {
  /// Defaults to popping the current route.
  final VoidCallback? onPressed;

  const AdaptiveBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final handler = onPressed ?? () => Navigator.maybePop(context);

    final button = AdaptiveIconButton(
      symbol: 'chevron.backward',
      icon: Icons.arrow_back_ios,
      onPressed: handler,
      diameter: 36,
      symbolSize: 17,
      // Material's own BackButton uses this; an icon-only control is otherwise
      // announced as just "button".
      semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
    );

    // The glass pill needs a little inset inside AppBar's 56pt leading slot;
    // the Material chevron already carries its own padding.
    if (useNativeGlass) {
      return Center(
        child: Padding(padding: const EdgeInsets.only(left: 8), child: button),
      );
    }

    return button;
  }
}
