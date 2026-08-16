import 'package:bookworm_friends/ui/widgets/buttons/adaptive_back_button.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
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
    final colors = context.colors;
    final platform = Theme.of(context).platform;
    // Apple platforms present search as a filled rounded pill. Android keeps the
    // classic bare field in the app bar, which is idiomatic Material there.
    final isApplePlatform =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

    final field = SearchTextField(
      controller: controller,
      onFieldSubmitted: onFieldSubmitted,
      hintText: hintText,
      dense: isApplePlatform,
    );

    return AppBar(
      backgroundColor: colors.surface,
      elevation: elevate ? 2 : 0,
      leading: AdaptiveBackButton(onPressed: onBackPressed),
      // Sit the pill closer to the back button than Material's default 16.
      titleSpacing: isApplePlatform ? 6 : null,
      title: isApplePlatform
          ? Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SearchFieldPill(child: field),
            )
          : field,
    );
  }
}

/// The bare search field, shared by the app-bar header and the Add Book sheet so
/// the two cannot drift in placeholder, keyboard action or type size.
class SearchTextField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onFieldSubmitted;
  final String? hintText;

  /// Compact enough to sit in a toolbar without a fixed height (which risks
  /// overflow). The sheet wants the same, so it defaults on.
  final bool dense;

  const SearchTextField({
    super.key,
    required this.controller,
    required this.onFieldSubmitted,
    this.hintText,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return TextField(
      controller: controller,
      onSubmitted: onFieldSubmitted,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hintText ?? l10n.searchBookPlaceholder,
        hintStyle: TextStyle(color: colors.secondaryText, fontSize: 16),
        border: InputBorder.none,
        // Let the pill supply the padding.
        isDense: dense,
        contentPadding: dense ? const EdgeInsets.symmetric(vertical: 9) : null,
      ),
    );
  }
}

/// The filled rounded container Apple platforms present search in.
class SearchFieldPill extends StatelessWidget {
  final Widget child;

  const SearchFieldPill({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      ),
    );
  }
}
