import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:flutter/material.dart';

/// Navigation back button.
///
/// Renders a native Liquid Glass circular icon button on iOS 26+ / macOS 26+,
/// and falls back to the themed Material [IconButton] everywhere else.
///
/// **The disc is [kIconButtonDiameter], the same target every ✕ in the app gets.**
/// It was 36 — the size the library bar uses for a ✕ crowded in beside Poke — which
/// left the app's most-used navigation control under the 44pt floor while sitting
/// alone in a 56pt `AppBar` leading slot with nothing to crowd it. The glyph stays at
/// [kBackButtonSymbolSize]/[kBackButtonIconSize] rather than shrinking to the ✕'s,
/// because a chevron is the thinner mark; see [kBackButtonSymbolSize].
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
      diameter: kIconButtonDiameter,
      symbolSize: kBackButtonSymbolSize,
      // Set explicitly. This is the value the constructor default already supplied
      // when the parameter was omitted, and it is the right one — but a glyph size
      // nobody passed is a glyph size nobody can see is deliberate.
      iconSize: kBackButtonIconSize,
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
