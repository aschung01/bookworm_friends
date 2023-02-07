import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class Header extends StatelessWidget implements PreferredSizeWidget {
  final Function()? onPressed;
  final Color? color;
  final String? title;
  final List<Widget>? actions;
  final Widget? icon;

  const Header({
    Key? key,
    this.onPressed,
    this.color = Colors.transparent,
    this.title,
    this.actions,
    this.icon,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return title == null
        ? AppBar(
            leading: onPressed != null
                ? IconButton(
                    splashRadius: 20,
                    icon: const Icon(
                      PhosphorIcons.caretLeftLight,
                      color: darkPrimaryColor,
                      size: 26,
                    ),
                    onPressed: onPressed,
                  )
                : null,
            elevation: 0,
            backgroundColor: color,
            actions: actions,
          )
        : AppBar(
            leading: onPressed != null
                ? IconButton(
                    splashRadius: 20,
                    icon: const Icon(
                      PhosphorIcons.caretLeftLight,
                      color: darkPrimaryColor,
                      size: 26,
                    ),
                    onPressed: onPressed,
                  )
                : null,
            title: Text(
              title!,
              style: const TextStyle(
                color: darkPrimaryColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
            elevation: 0,
            backgroundColor: color,
            actions: actions,
          );
  }
}
