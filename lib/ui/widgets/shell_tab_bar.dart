import 'dart:ui';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// The shell's floating tab bar: a pill of Library / Friends / Card, plus a
/// detached circular button that opens Add Book.
///
/// It floats *over* the sheet rather than sitting under it, which is why the
/// sheet has to leave [reserve] pixels of room at its bottom. Nothing here
/// measures that: both sides read the same constants, so the gap above and below
/// the bar is fixed by construction. See [reserve].
///
/// Hidden during a visit — a tab bar that is visible but cannot say where you
/// are is the thing four rejected design rounds kept working around. That is the
/// caller's job: this widget is simply not built while visiting.
class ShellTabBar extends StatefulWidget {
  final LibraryTab current;
  final ValueChanged<LibraryTab> onChanged;

  /// Fires when the detached circular button is tapped. Add Book is a search, so
  /// on iOS 26 this is the system's search tab; see the class comment in
  /// [_buildNative].
  final VoidCallback onAddBook;

  const ShellTabBar({
    super.key,
    required this.current,
    required this.onChanged,
    required this.onAddBook,
  });

  /// Passed to `CNTabBar` explicitly rather than letting it measure its own
  /// intrinsic height. The package measures that asynchronously from native and
  /// keeps it private — there is no constant and no callback — so a caller that
  /// has to reserve space beneath the bar cannot learn the number. Fixing it
  /// makes the reservation exact instead of a guess.
  static const double height = 50;

  /// Gap above and below the bar, and the inset from the screen's side edges.
  static const double gap = 8;
  static const double sideInset = 14;

  /// Vertical room a sheet must leave free at its bottom so the floating bar
  /// does not cover its contents: a gap, the bar, and a gap again.
  ///
  /// Excludes the home-indicator inset, which the sheet reserves separately —
  /// the bar is offset by the same inset, so the two stay in step.
  static const double reserve = gap + height + gap;

  @override
  State<ShellTabBar> createState() => _ShellTabBarState();
}

class _ShellTabBarState extends State<ShellTabBar> {
  /// Only used on the native path, to put the bar's selection back after the
  /// search tab has been tapped.
  final _searchController = CNTabBarSearchController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const _tabs = LibraryTab.values;

  List<String> _labels(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [l10n.library, l10n.friends, l10n.tabCard];
  }

  void _onAddBookTapped() {
    widget.onAddBook();
    // The native bar moves its own selection to the search item on tap and does
    // not put it back, so without this the pill would keep claiming you are on a
    // fourth tab that does not exist.
    _searchController.deactivateSearch();
  }

  @override
  Widget build(BuildContext context) {
    return useNativeGlass ? _buildNative(context) : _buildFallback(context);
  }

  /// iOS 26: a real `UITabBar` with a system search item, which the OS renders as
  /// the detached Liquid Glass circle the design draws.
  ///
  /// Using the search item as a plain button is deliberate, and it is worth
  /// writing down because the package's own docs say otherwise. On iOS 26 the
  /// search item is *only* a button: the Swift view behind it builds a plain
  /// `UITabBar` with a `.search` system item and contains no text field,
  /// `UISearchTab` or `UISearchController` at all. `onSearchChanged` and
  /// `onSearchSubmit` are published on a different method channel (the one
  /// `CNSearchScaffold` uses) and never fire here, so `onSearchActiveChanged` is
  /// the tap hook. That is exactly what we want — Add Book owns its own search
  /// UI in a modal — but it also means the inline-search behaviour the README
  /// describes is fallback-only, which is why the fallback below is hand-rolled
  /// instead of letting `CNTabBar` provide it.
  Widget _buildNative(BuildContext context) {
    final labels = _labels(context);
    return CNTabBar(
      height: ShellTabBar.height,
      currentIndex: _tabs.indexOf(widget.current),
      onTap: (index) => widget.onChanged(_tabs[index]),
      tint: context.colors.brandText,
      // SF Symbols only: with a search item set, the native view ignores
      // rasterised `customIcon`s, image assets and icon sizes entirely.
      items: [
        CNTabBarItem(label: labels[0], icon: const CNSymbol('books.vertical')),
        CNTabBarItem(label: labels[1], icon: const CNSymbol('person.2')),
        CNTabBarItem(label: labels[2], icon: const CNSymbol('creditcard')),
      ],
      searchController: _searchController,
      searchItem: CNTabBarSearchItem(
        label: AppLocalizations.of(context).addBook,
        onSearchActiveChanged: (isActive) {
          if (isActive) _onAddBookTapped();
        },
      ),
    );
  }

  /// Everywhere else — and under `flutter test`, which reports Android — the
  /// pill and the circle are drawn in Flutter over a blur.
  ///
  /// `CNTabBar`'s own fallback is not used: given a search item it grows an
  /// inline `CupertinoTextField` in the bar, which is a different interaction
  /// from the modal this design specifies, and it would only appear off iOS 26.
  Widget _buildFallback(BuildContext context) {
    final labels = _labels(context);
    return Row(
      children: [
        Expanded(
          child: _Glass(
            borderRadius: BorderRadius.circular(ShellTabBar.height / 2),
            child: SizedBox(
              height: ShellTabBar.height,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Expanded(
                        child: _TabSegment(
                          label: labels[i],
                          selected: _tabs[i] == widget.current,
                          onTap: () => widget.onChanged(_tabs[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _Glass(
          borderRadius: BorderRadius.circular(ShellTabBar.height / 2),
          child: SizedBox.square(
            dimension: ShellTabBar.height,
            child: IconButton(
              onPressed: _onAddBookTapped,
              tooltip: AppLocalizations.of(context).addBook,
              icon: Icon(Icons.search, color: context.colors.secondaryText),
            ),
          ),
        ),
      ],
    );
  }
}

/// A translucent, blurred, shadowed surface — the fallback's stand-in for Liquid
/// Glass. Floating over the library means whatever is behind it has to stay
/// legible through it, which a flat fill does not manage over book covers.
class _Glass extends StatelessWidget {
  final BorderRadius borderRadius;
  final Widget child;

  const _Glass({required this.borderRadius, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            offset: const Offset(0, 2),
            color: Colors.black.withValues(alpha: 0.18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: ColoredBox(
            color: context.colors.surface.withValues(alpha: 0.86),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _TabSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular((ShellTabBar.height - 8) / 2);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: selected ? context.colors.surfaceVariant : null,
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected
                  ? context.colors.brandText
                  : context.colors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}
