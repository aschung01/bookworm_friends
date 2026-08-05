import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class BookWidget extends StatefulWidget {
  final double? height;
  final String imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? heroTag;
  const BookWidget({
    super.key,
    this.height,
    required this.imageUrl,
    this.onTap,
    this.onLongPress,
    this.heroTag,
  });

  @override
  State<BookWidget> createState() => _BookWidgetState();
}

class _BookWidgetState extends State<BookWidget> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bookHeight = widget.height ?? MediaQuery.of(context).size.height * 0.15;
    Widget child = GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              blurRadius: _isPressed ? 8 : 4,
              offset: _isPressed ? const Offset(3, 4) : const Offset(2, 2),
              color: Colors.black.withValues(alpha: _isPressed ? 0.35 : 0.2),
            ),
          ],
        ),
        transform: _isPressed
            ? (Matrix4.identity()..translate(0.0, -2.0))
            : Matrix4.identity(),
        child: widget.imageUrl.isNotEmpty
            ? Image.network(
                widget.imageUrl,
                height: bookHeight,
                fit: BoxFit.fitHeight,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => _placeholder(bookHeight),
              )
            : _placeholder(bookHeight),
      ),
    );

    if (widget.heroTag != null) {
      child = Hero(tag: widget.heroTag!, child: child);
    }

    return child;
  }

  Widget _placeholder(double h) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: h,
      width: h / 1.6,
      color: lightGrayColor,
      alignment: Alignment.center,
      child: Text(
        l10n.noImage,
        style: const TextStyle(color: darkPrimaryColor, fontSize: 12),
      ),
    );
  }
}
