import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

/// A circular icon button that renders as a native Liquid Glass button on
/// iOS 26+ / macOS 26+, and as a themed Material [IconButton] everywhere else.
class AdaptiveIconButton extends StatelessWidget {
  /// Whether icon buttons currently render as native Liquid Glass.
  static bool get usesNativeGlass => useNativeGlass;

  /// SF Symbol name used for the native glass rendering.
  final String symbol;

  /// Material icon used on every other platform / OS version.
  final IconData icon;

  final VoidCallback? onPressed;

  /// Overall diameter of the button.
  final double diameter;

  /// Size of the SF Symbol inside the native glass button.
  final double symbolSize;

  /// Size of the Material icon in the fallback.
  final double iconSize;

  /// Gives the Material fallback a circular `surfaceVariant` fill. The glass
  /// rendering always supplies its own material, so this only affects fallback.
  final bool filledFallback;

  /// Accessible name for the button. Required in practice for icon-only
  /// controls: neither an SF Symbol nor an [IconData] carries a label, so
  /// without this the button is announced as just "button".
  final String? semanticLabel;

  const AdaptiveIconButton({
    super.key,
    required this.symbol,
    required this.icon,
    this.onPressed,
    this.diameter = 40,
    this.symbolSize = 18,
    this.iconSize = 22,
    this.filledFallback = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (usesNativeGlass) {
      // CNButton.icon already defaults to CNButtonStyle.glass.
      // The native button is a PlatformView, so the label has to be attached
      // from the Flutter side rather than via a tooltip.
      return SizedBox(
        width: diameter,
        height: diameter,
        child: Semantics(
          label: semanticLabel,
          button: true,
          container: true,
          child: CNButton.icon(
            icon: CNSymbol(symbol, size: symbolSize),
            onPressed: onPressed,
          ),
        ),
      );
    }

    final button = IconButton(
      onPressed: onPressed,
      // Doubles as the semantic label on Material.
      tooltip: semanticLabel,
      splashRadius: 20,
      icon: Icon(icon, size: iconSize),
    );

    return SizedBox(
      width: diameter,
      height: diameter,
      child: filledFallback
          ? Material(
              type: MaterialType.circle,
              color: context.colors.surfaceVariant,
              child: button,
            )
          : button,
    );
  }
}

/// Gap to place between two adjacent [AdaptiveIconButton]s.
///
/// A glass button fills its whole diameter, so neighbours would otherwise touch
/// edge to edge. The Material fallback is an [IconButton], which already insets
/// its icon, so it needs no extra gap and gets none.
class AdaptiveIconButtonGap extends StatelessWidget {
  const AdaptiveIconButtonGap({super.key, this.width = 8});

  /// Gap applied when the buttons render as native glass.
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: AdaptiveIconButton.usesNativeGlass ? width : 0);
  }
}
