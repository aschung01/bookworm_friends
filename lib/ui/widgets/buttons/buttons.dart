import 'package:bookworm_friends/constants/constants.dart';
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
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: activated ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: activated
              ? (backgroundColor ?? greenThemeColor)
              : (disabledStyleOutline ? Colors.white : lightGrayColor),
          foregroundColor: overlayColor ?? greenThemeColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: disabledStyleOutline && !activated
                ? const BorderSide(color: grayColor)
                : BorderSide.none,
          ),
          padding: EdgeInsets.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 6),
            ],
            Text(
              buttonText,
              style: textStyle ??
                  TextStyle(
                    color: activated ? Colors.white : grayColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
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
  final Color textColor;
  final FontWeight fontWeight;
  final double fontSize;
  final VoidCallback? onPressed;

  const TextActionButton({
    super.key,
    required this.buttonText,
    this.icon,
    this.isUnderlined = true,
    this.textColor = darkPrimaryColor,
    this.fontWeight = FontWeight.normal,
    this.fontSize = 14,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            buttonText,
            style: TextStyle(
              color: textColor,
              fontWeight: fontWeight,
              fontSize: fontSize,
              decoration:
                  isUnderlined ? TextDecoration.underline : TextDecoration.none,
            ),
          ),
          if (icon != null) icon!,
        ],
      ),
    );
  }
}
