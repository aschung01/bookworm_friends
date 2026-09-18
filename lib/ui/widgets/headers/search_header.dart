import 'package:bookworm_friends/ui/widgets/buttons/adaptive_back_button.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
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

  /// Optional, so a caller can move focus in or out of the field from outside it.
  ///
  /// Add Book needs both directions. *In*, for coming back from the scanner having
  /// chosen "type it instead". *Out*, for the two ways back from the scanner that
  /// are not a request to type: popping a route restores focus to whatever held it
  /// underneath, and with [autofocus] on that is always this field.
  final FocusNode? focusNode;

  /// Whether the field takes focus, and so raises the keyboard, as soon as it is
  /// mounted.
  ///
  /// Off by default, because it is only right where search *is* the destination.
  /// Add Book passes it — arriving on the search tab having typed nothing, the
  /// only thing there is to do is type, and the empty state it covers is padded
  /// for the keyboard (see `add_book_bottom_sheet.dart`).
  final bool autofocus;

  /// Anything the caller wants sitting after the text but still inside the field.
  ///
  /// Add Book's provenance chip goes here rather than beside the field in the
  /// pill, so that the clear button stays the *rightmost* thing in the input in
  /// every state — a control at the edge with a badge to its right would read as
  /// a layout accident.
  final Widget? trailing;

  /// Called on every keystroke, for callers that search as you type.
  ///
  /// Optional because the original callers search on *submit*: Add Book runs a
  /// paged catalogue query that is too expensive to fire per letter. The Libby
  /// library picker passes it and debounces on the other side.
  ///
  /// The clear button calls [onFieldSubmitted], not this, in every case — clearing
  /// is a submit of the empty query, which is how both callers already read it.
  final ValueChanged<String>? onChanged;

  const SearchTextField({
    super.key,
    required this.controller,
    required this.onFieldSubmitted,
    this.hintText,
    this.dense = true,
    this.focusNode,
    this.autofocus = false,
    this.trailing,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onSubmitted: onFieldSubmitted,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: hintText ?? l10n.searchBookPlaceholder,
        hintStyle: AppTextStyles.body.copyWith(color: colors.secondaryText),
        border: InputBorder.none,
        // Let the pill supply the padding.
        isDense: dense,
        contentPadding: dense ? const EdgeInsets.symmetric(vertical: 9) : null,
        // Read off the controller rather than held in state, so the field stays
        // stateless and the button cannot fall out of step with the text however
        // it got there — typed, written by a cover read (`_runCoverQuery`), or
        // emptied by the clear itself.
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final dirty = value.text.isNotEmpty;
            if (!dirty && trailing == null) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailing != null) trailing!,
                if (dirty)
                  _ClearSearchButton(
                    label: l10n.clearSearch,
                    onPressed: () {
                      controller.clear();
                      // Clearing the field has to clear the *results* too, or
                      // the grid goes on answering a query that is no longer on
                      // screen. Both callers read this as "search for nothing",
                      // which is the empty state — for Add Book, the one holding
                      // the scan action.
                      onFieldSubmitted('');
                    },
                  ),
              ],
            );
          },
        ),
        // Material's default is a 48x48 minimum for a suffix. The height is
        // clamped by this dense field anyway, but the *width* is not: it pads the
        // 36pt button out to 48 and so parks it 12pt short of the field's
        // trailing edge, floating in the middle of nothing. Let it size itself.
        suffixIconConstraints: const BoxConstraints(),
      ),
    );
  }
}

/// The clear affordance inside [SearchTextField], shown only once there is
/// something to clear.
///
/// Deliberately does **not** touch focus. Tapping it mid-typing leaves the
/// keyboard up because there is more to type, and tapping it after a cover read —
/// where the field was filled without ever being focused — does not raise one,
/// the same restraint `_openScanner` shows in not focusing on the way back.
class _ClearSearchButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// Matches the dense field's own content height, so the button appearing and
  /// disappearing cannot change the pill's height. Short of 44 on purpose: the
  /// target here is bounded by the field it sits *inside*, and the 44pt rule is
  /// carried by the pill's neighbours (scan, close), which are free-standing.
  static const double _target = 36;

  const _ClearSearchButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onPressed,
          // Opaque so the whole square is tappable rather than just the glyph,
          // and so a near miss does not fall through to the field and raise a
          // keyboard on the way out.
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: _target,
            height: _target,
            child: Center(
              child: Icon(
                // The filled circle, not a bare mark: at this size a plain
                // cross reads as punctuation in the text it is there to delete.
                Icons.cancel,
                size: 18,
                color: context.colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The corner radius Apple platforms give a search field.
///
/// Shared, because [SearchFieldPill] is not the only thing that has to be this
/// shape: the emoji picker's search field comes from a package and cannot be
/// wrapped in the pill, so it reproduces it through an `InputDecorationTheme`
/// instead (see `compliment_bottom_sheet.dart`). One constant so the two cannot
/// drift.
const double kSearchPillRadius = 10;

/// The filled rounded container Apple platforms present search in.
class SearchFieldPill extends StatelessWidget {
  final Widget child;

  const SearchFieldPill({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(kSearchPillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      ),
    );
  }
}
