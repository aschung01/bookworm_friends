import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

class ElevatedActionButton extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final String buttonText;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final Widget? leading;
  final VoidCallback? onPressed;
  final bool activated;
  final bool disabledStyleOutline;
  final bool isDestructive;
  final Color? overlayColor;

  const ElevatedActionButton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 50,
    required this.buttonText,
    this.backgroundColor,
    this.textStyle,
    this.leading,
    this.onPressed,
    this.activated = true,
    this.disabledStyleOutline = false,
    this.isDestructive = false,
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    // Liquid Glass needs content behind it to refract. Inside a bottom sheet the
    // backdrop is an opaque surface, so glass degrades into a flat gray pill —
    // and it's also the one context the package's modal z-order coordination
    // has to actively work around. Use the themed Material button there.
    final inBottomSheet = ModalRoute.of(context) is ModalBottomSheetRoute;

    // On iOS 26+ (and macOS 26+) render a native Liquid Glass button, but only
    // for the enabled, label-only case. Buttons with a custom [leading] widget
    // or a disabled/outline state keep the themed Material rendering below,
    // which the native glass API can't reproduce. Falls back automatically on
    // every other platform/version (useNativeGlass is false there).
    final useGlass =
        activated && leading == null && !inBottomSheet && useNativeGlass;
    if (useGlass) {
      return _buildGlass(context);
    }
    return _buildMaterial(context);
  }

  Widget _buildGlass(BuildContext context) {
    // Primary CTAs and destructive actions use prominent glass. Destructive
    // actions additionally receive an explicit red tint; secondary actions keep
    // the lighter neutral glass with the app's green accent text.
    final isPrimary =
        backgroundColor == null || backgroundColor == context.colors.brandFill;
    return SizedBox(
      width: width,
      height: height,
      child: CNButton(
        label: buttonText,
        tint: isDestructive ? (backgroundColor ?? softRedColor) : null,
        config: CNButtonConfig(
          style: isDestructive || isPrimary
              ? CNButtonStyle.prominentGlass
              : CNButtonStyle.glass,
          labelColor: isDestructive ? Colors.white : null,
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildMaterial(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: activated ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: activated
              ? (isDestructive
                    ? (backgroundColor ?? softRedColor)
                    : (backgroundColor ?? colors.brandFill))
              : (disabledStyleOutline ? colors.surface : colors.surfaceVariant),
          foregroundColor: isDestructive
              ? Colors.white
              : (overlayColor ?? colors.brandText),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: disabledStyleOutline && !activated
                ? BorderSide(color: colors.secondaryText)
                : BorderSide.none,
          ),
          padding: EdgeInsets.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            // Flexible + scaleDown so a fixed [width] can never overflow: label
            // lengths vary by locale ("Confirm" vs "\ud655\uc778"), and the label shrinks
            // to fit rather than throwing a RenderFlex overflow or truncating.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  buttonText,
                  maxLines: 1,
                  style:
                      textStyle ??
                      TextStyle(
                        color: activated ? Colors.white : colors.secondaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TextActionButton extends StatelessWidget {
  final String buttonText;
  final Widget? icon;
  final bool isUnderlined;
  final Color? textColor;
  final FontWeight fontWeight;
  final double fontSize;
  final VoidCallback? onPressed;

  const TextActionButton({
    super.key,
    required this.buttonText,
    this.icon,
    this.isUnderlined = true,
    this.textColor,
    this.fontWeight = FontWeight.normal,
    this.fontSize = 14,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? context.colors.primaryText;
    return GestureDetector(
      onTap: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            buttonText,
            style: TextStyle(
              color: color,
              fontWeight: fontWeight,
              fontSize: fontSize,
              decoration: isUnderlined
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
          ),
          if (icon != null) icon!,
        ],
      ),
    );
  }
}
