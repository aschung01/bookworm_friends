import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

/// A floating action button.
///
/// On iOS 26+ / macOS 26+ this renders a native Liquid Glass circular button.
/// A control floating *above scrolling content* is the canonical Liquid Glass
/// placement: the material has content passing beneath it to refract and react
/// to, which is precisely what it's designed for — unlike glass sitting on an
/// opaque surface, where it degrades into a flat pill.
///
/// Everywhere else it falls back to a Material [FloatingActionButton].
class AdaptiveFab extends StatelessWidget {
  /// SF Symbol used for the native glass rendering.
  final String symbol;

  /// Material icon used in the fallback.
  final IconData icon;

  final VoidCallback? onPressed;

  final double diameter;
  final double symbolSize;
  final double iconSize;

  const AdaptiveFab({
    super.key,
    required this.symbol,
    required this.icon,
    this.onPressed,
    this.diameter = 56,
    this.symbolSize = 22,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (useNativeGlass) {
      return SizedBox(
        width: diameter,
        height: diameter,
        child: CNButton.icon(
          icon: CNSymbol(symbol, size: symbolSize),
          // brandText rather than brand: the glyph has to stay legible.
          tint: colors.brandText,
          onPressed: onPressed,
        ),
      );
    }

    return FloatingActionButton(
      backgroundColor: colors.pageBackground,
      onPressed: onPressed,
      child: Icon(icon, color: colors.brandText, size: iconSize),
    );
  }
}
