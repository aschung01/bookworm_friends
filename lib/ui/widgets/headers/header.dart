import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';

class Header extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onPressed;
  final List<Widget>? actions;
  const Header({super.key, required this.onPressed, this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back_ios, color: darkPrimaryColor, size: 22),
      ),
      actions: actions,
    );
  }
}
