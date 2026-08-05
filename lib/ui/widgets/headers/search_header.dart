import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class SearchHeader extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController controller;
  final bool elevate;
  final String? hintText;
  final void Function(String) onFieldSubmitted;
  final VoidCallback onBackPressed;

  const SearchHeader({
    super.key,
    required this.controller,
    this.elevate = false,
    this.hintText,
    required this.onFieldSubmitted,
    required this.onBackPressed,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBar(
      backgroundColor: Colors.white,
      elevation: elevate ? 2 : 0,
      leading: IconButton(
        onPressed: onBackPressed,
        icon: const Icon(Icons.arrow_back_ios, color: darkPrimaryColor, size: 22),
      ),
      title: TextField(
        controller: controller,
        onSubmitted: onFieldSubmitted,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText ?? l10n.searchBookPlaceholder,
          hintStyle: const TextStyle(color: grayColor, fontSize: 16),
          border: InputBorder.none,
        ),
        style: const TextStyle(color: darkPrimaryColor, fontSize: 16),
      ),
    );
  }
}
