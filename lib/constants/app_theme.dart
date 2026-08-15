import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/constants.dart';

/// Semantic, mode-dependent colors for the app.
///
/// Brand/semantic accents that stay constant across light and dark
/// (e.g. [greenThemeColor], [softRedColor]) continue to live in
/// `constants.dart`. Everything that must flip between light and dark
/// (backgrounds, surfaces, text, fills) lives here and is resolved from the
/// active [Theme] via `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// The base page background (Scaffold background).
  final Color pageBackground;

  /// Elevated surfaces: cards, app bars, sheets, "white" areas.
  final Color surface;

  /// Subtle filled areas: chips, avatars, input fills (was `lightGrayColor`).
  final Color surfaceVariant;

  /// Primary text and icons (was `darkPrimaryColor`).
  final Color primaryText;

  /// Secondary/muted text and icons (was `grayColor`).
  final Color secondaryText;

  /// Hairline dividers and subtle borders.
  final Color divider;

  /// Brand accent for **decoration only**: tints, fills and shapes that nothing
  /// has to be legible against (book spines, avatar rings' fill, drag-target
  /// highlights, low-opacity borders).
  ///
  /// This is the vivid brand green, which scores 2.45:1 on a light surface — so
  /// never use it for text, for small icons, or as a fill behind text. Reach for
  /// [brandText] or [brandFill] there.
  final Color brand;

  /// Brand accent for anything that must be **read**: green text, small icons,
  /// selection indicators and state borders.
  ///
  /// Light mode darkens the brand green to clear 4.5:1 on every light surface
  /// (surfaceVariant is the tightest); the dark theme keeps the vivid green,
  /// which already scores 6.8:1 on its surface. See
  /// `test/color_contrast_test.dart`.
  final Color brandText;

  /// Brand accent for **fills that carry white text** (primary buttons, the Poke
  /// pill, selected chips, switch tracks).
  ///
  /// Dark in both themes, because white-on-vivid-green is only 2.45:1 no matter
  /// what is behind it.
  final Color brandFill;

  /// Background for modal bottom sheets.
  ///
  /// Pinned rather than left to Material's default
  /// (`colorScheme.surfaceContainerLow`), which is derived *tonally* from the
  /// brand-green seed and so drifts whenever the seed changes or Flutter
  /// retunes its palette algorithm. These are the exact values that default
  /// produced, so pinning them is a no-op visually — the faint mint tint on
  /// light is deliberate and now stable. See `test/sheet_theme_test.dart`.
  final Color sheetBackground;

  /// Highlight color for shimmer loading sweeps (always lighter than
  /// [surfaceVariant], which is used as the shimmer base).
  final Color shimmerHighlight;

  const AppColors({
    required this.pageBackground,
    required this.surface,
    required this.surfaceVariant,
    required this.primaryText,
    required this.secondaryText,
    required this.divider,
    required this.brand,
    required this.brandText,
    required this.brandFill,
    required this.sheetBackground,
    required this.shimmerHighlight,
  });

  static const AppColors light = AppColors(
    pageBackground: Color(0xffF8F9FA),
    surface: Color(0xffFFFFFF),
    surfaceVariant: Color(0xffE9ECEF),
    primaryText: Color(0xff212529),
    secondaryText: Color(0xffADB5BD),
    divider: Color(0xffE9ECEF),
    brand: Color(0xff09BC8A),
    // 5.6:1 on white and 4.7:1 on surfaceVariant — AA for normal text on every
    // light surface. surfaceVariant is the binding constraint, not white.
    brandText: Color(0xff067657),
    brandFill: Color(0xff067657),
    sheetBackground: Color(0xffEFF5EF),
    shimmerHighlight: Color(0xffF8F9FA),
  );

  static const AppColors dark = AppColors(
    pageBackground: Color(0xff121212),
    surface: Color(0xff1E1E1E),
    surfaceVariant: Color(0xff2C2C2E),
    primaryText: Color(0xffF1F3F5),
    secondaryText: Color(0xff8E8E93),
    divider: Color(0xff3A3A3C),
    brand: Color(0xff09BC8A),
    // 6.8:1 on the dark surface, so the vivid green needs no adjustment.
    brandText: Color(0xff09BC8A),
    brandFill: Color(0xff067657),
    sheetBackground: Color(0xff171D1A),
    shimmerHighlight: Color(0xff3A3A3C),
  );

  @override
  AppColors copyWith({
    Color? pageBackground,
    Color? surface,
    Color? surfaceVariant,
    Color? primaryText,
    Color? secondaryText,
    Color? divider,
    Color? brand,
    Color? brandText,
    Color? brandFill,
    Color? sheetBackground,
    Color? shimmerHighlight,
  }) {
    return AppColors(
      pageBackground: pageBackground ?? this.pageBackground,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      divider: divider ?? this.divider,
      brand: brand ?? this.brand,
      brandText: brandText ?? this.brandText,
      brandFill: brandFill ?? this.brandFill,
      sheetBackground: sheetBackground ?? this.sheetBackground,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandText: Color.lerp(brandText, other.brandText, t)!,
      brandFill: Color.lerp(brandFill, other.brandFill, t)!,
      sheetBackground: Color.lerp(sheetBackground, other.sheetBackground, t)!,
      shimmerHighlight: Color.lerp(
        shimmerHighlight,
        other.shimmerHighlight,
        t,
      )!,
    );
  }
}

/// Convenient access to the active [AppColors] from any widget.
///
/// Falls back to the brightness-appropriate defaults when the extension isn't
/// registered on the ambient theme (e.g. a widget pumped under a bare
/// [MaterialApp] in tests, or beneath a nested [Theme] that drops extensions),
/// so callers never have to null-check and never crash.
extension AppColorsContext on BuildContext {
  AppColors get colors {
    final theme = Theme.of(this);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark
            ? AppColors.dark
            : AppColors.light);
  }
}

/// Light and dark [ThemeData] for the app.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppColors.light);
  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: greenThemeColor,
      brightness: brightness,
      surface: colors.surface,
    );

    // Apple platforms don't use Material's expanding ink ripple, but they DO
    // show a press indicator: a uniform, subtle tint that fades in while the
    // finger is down. So we drop the ripple (NoSplash) but keep a highlight.
    final isApplePlatform =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final pressTint = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.black.withValues(alpha: 0.055);

    final pressOverlay = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.pressed) ? pressTint : null,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.pageBackground,
      canvasColor: colors.surface,
      dividerColor: colors.divider,
      // Ripple off, press tint on (Apple only). `highlightColor` drives
      // InkWell/ListTile feedback; M3 buttons use overlayColor instead, so
      // those are themed separately.
      splashFactory: isApplePlatform ? NoSplash.splashFactory : null,
      highlightColor: isApplePlatform ? pressTint : null,
      iconButtonTheme: isApplePlatform
          ? IconButtonThemeData(style: ButtonStyle(overlayColor: pressOverlay))
          : const IconButtonThemeData(),
      textButtonTheme: isApplePlatform
          ? TextButtonThemeData(style: ButtonStyle(overlayColor: pressOverlay))
          : const TextButtonThemeData(),
      iconTheme: IconThemeData(color: colors.primaryText),
      // Both slots are set because `showModalBottomSheet` prefers
      // `modalBackgroundColor` and falls back to `backgroundColor`; pinning one
      // only would leave the other path on Material's tonal default.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.sheetBackground,
        modalBackgroundColor: colors.sheetBackground,
        surfaceTintColor: Colors.transparent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.primaryText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.primaryText),
      ),
      extensions: <ThemeExtension<dynamic>>[colors],
    );
  }
}
