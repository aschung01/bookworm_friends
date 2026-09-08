import 'dart:ui';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// Every number that decides where the bar sits, as a pure function of the only
/// two things it depends on: which path is drawing (a native `UITabBar` or our own
/// pill), and the home-indicator inset.
///
/// Pulled out of [ShellTabBar] so that **both** paths' numbers are reachable from
/// a test. `flutter test` reports Android, so the native geometry is otherwise
/// only ever checked by eye on a simulator — which is how the bar came to float
/// ~21pt above, and sit 14pt per side narrower than, every system tab bar, and
/// survive a round of device verification that was looking at something else.
@immutable
class ShellTabBarGeometry {
  /// Whether the native `CNTabBar` is drawing, i.e. [useNativeGlass].
  final bool native;

  /// `MediaQuery.viewPaddingOf(context).bottom` — the home-indicator strip.
  final double bottomViewPadding;

  const ShellTabBarGeometry({
    required this.native,
    required this.bottomViewPadding,
  });

  /// Clearance the visible glass keeps from what it must not touch: the sheet
  /// above it, and — on the fallback path only — the bottom of the screen. On the
  /// native path the bar's own frame provides the bottom clearance; see
  /// [glassTop].
  static const double gap = 8;

  /// Height of the box handed to the bar.
  ///
  /// Passed to `CNTabBar` explicitly rather than letting it measure itself: the
  /// package measures its intrinsic height asynchronously from native and keeps
  /// it private — no constant, no callback — so a caller that must reserve space
  /// beneath the bar cannot learn the number.
  ///
  /// 83 is not a guess. It is `UITabBar.sizeThatFits` for an iOS 26 bar with three
  /// labelled items and a search item, read off the rendered view on an iPhone 17
  /// Pro / iOS 26.4 simulator. At 50 the native bar drew its labels on top of its
  /// icons — a squashed `UITabBar` is what too small looks like. It is also
  /// exactly `49 + 34`: a tab bar plus a home-indicator inset, which is the clue
  /// [glassTop] turns on.
  double get boxHeight => native ? 83 : 50;

  /// Height of what you can actually see, which on the native path is *not*
  /// [boxHeight].
  ///
  /// iOS lays the visible glass out as a 62pt platter anchored to the **top** of
  /// the 83pt frame, keeping 21pt of padding at the bottom of its own box. Both
  /// the platter and the search orb measure 62.
  ///
  /// On the native path this is **descriptive only** — no position is derived from
  /// it. That is deliberate and it is the point of [glassTop]: the 21pt inset is a
  /// native subview's offset that Flutter cannot see, so a layout that depends on
  /// it can never be verified from Dart. Anchoring to the frame's top edge instead
  /// removes it from every formula here.
  double get visualHeight => native ? 62 : 50;

  /// Inset from the screen's side edges.
  ///
  /// **Zero on the native path, and that is not an omission.** The plugin pins the
  /// `UITabBar` to all four edges of the platform view it is handed
  /// (`CupertinoTabBarSearchView.setupUI`), so our box *is* the bar's frame — and
  /// iOS 26 draws its glass as a platter inset *within* that frame. Anything added
  /// here lands on top of the margin iOS already applies, and the bar comes out
  /// narrower than the system's. A system tab bar is handed the full width;
  /// matching one means handing it the full width.
  ///
  /// Measured on an iPhone 17 Pro / iOS 26.4 simulator (402pt wide) by building it
  /// both ways: the glass sits **14.0pt further in from each edge at `14` than at
  /// `0`**, so the inset was purely additive with iOS's own. That delta is the
  /// claim; it is read the same way in both builds, so it does not depend on where
  /// exactly a soft glass edge is judged to end.
  ///
  /// For the absolute, iOS's own layout is the authority: with this at `0` the
  /// `UITabBar`'s accessibility tree reports the search orb at x `319.2..381.1` —
  /// 62pt wide, **20.9pt in from the right edge**. That margin is the system's, and
  /// it is the whole of what a system tab bar shows.
  ///
  /// 14 is right for the fallback, which fills its box with a pill it draws
  /// itself.
  double get sideInset => native ? 0 : 14;

  /// Distance from the bottom of the screen to the **top edge of the visible
  /// glass** — the one number both the bar's position and the sheet's reservation
  /// are derived from, so the two cannot drift apart.
  ///
  /// The top edge is the honest anchor because on both paths the glass's top edge
  /// *is* the box's top edge: iOS anchors its platter to the top of the frame, and
  /// the fallback's pill fills its box. Every other edge involves an inset only
  /// native code can see.
  ///
  /// **Native: the frame sits flush with the bottom of the screen**, exactly where
  /// a `UITabBar` puts itself. Its 83pt is `49 + 34` — bar plus home-indicator
  /// inset — and the 21pt it keeps below the platter *is* that allowance, with the
  /// indicator sitting in the band beneath the glass. Adding `bottomViewPadding`
  /// on top counted the same clearance twice and floated the bar ~21pt above every
  /// system tab bar.
  ///
  /// **Fallback: nothing reserves the indicator strip for us**, so we do, plus
  /// [gap].
  ///
  /// Confirmed by iOS itself on an iPhone 17 Pro / iOS 26.4 simulator. The
  /// accessibility tree reports the bar's frame as `(0, 791)–(402, 874)` — full
  /// width, flush with the screen bottom — and the search orb inside it at
  /// **`bottom-up 21.0..83.0`**, i.e. the platter band is 21pt to 83pt above the
  /// screen bottom and 62pt tall, exactly as [visualHeight] says. Before this the
  /// same band sat at 42..104.
  double get glassTop =>
      native ? boxHeight : bottomViewPadding + gap + visualHeight;

  /// Where to pin the bar's box, measured from the bottom of the screen.
  ///
  /// The box's top edge is the glass's top edge, so this is [glassTop] less the
  /// box. Zero on the native path, by the reasoning at [glassTop].
  double get bottomOffset => glassTop - boxHeight;

  /// Vertical room a sheet must leave free at its bottom so the floating bar does
  /// not cover its contents: up to the top of the glass, plus a [gap].
  ///
  /// Measured from the top of the home-indicator inset rather than from the screen
  /// edge, because `LibrarySheet` always reserves that inset itself and adds this
  /// on top.
  double get reserve {
    final remaining = glassTop + gap - bottomViewPadding;
    return remaining < 0 ? 0 : remaining;
  }
}

/// The shell's floating tab bar: a pill of Library / Friends / Card, plus a
/// detached circular button that opens Add Book.
///
/// It floats *over* the sheet rather than sitting under it, which is why the
/// sheet has to leave [ShellTabBarGeometry.reserve] pixels of room at its bottom.
/// Nothing here measures that: both sides are derived from
/// [ShellTabBarGeometry.glassTop], so the clearance is fixed by construction.
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
  ///
  /// Awaited: the native bar keeps the search item lit while it is open, which is
  /// truthful, and is put back only once Add Book closes.
  final Future<void> Function() onAddBook;

  const ShellTabBar({
    super.key,
    required this.current,
    required this.onChanged,
    required this.onAddBook,
  });

  /// The bar's geometry for this screen. Callers use it to position the bar and to
  /// work out what a sheet underneath must leave free — both from the same object,
  /// which is what keeps them in step.
  static ShellTabBarGeometry geometryOf(BuildContext context) =>
      ShellTabBarGeometry(
        native: useNativeGlass,
        bottomViewPadding: MediaQuery.viewPaddingOf(context).bottom,
      );

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

  Future<void> _onAddBookTapped() async {
    await widget.onAddBook();
    // The native bar moves its own selection to the search item on tap and never
    // puts it back, so without this the bar keeps claiming you are on a fourth
    // tab that does not exist. Deferred until Add Book closes: called any earlier
    // it runs while the pushed page covers the bar, and the search item comes
    // back still tinted as the active tab.
    if (mounted) _searchController.deactivateSearch();
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
      height: ShellTabBar.geometryOf(context).boxHeight,
      // `ShellChrome` hosts this bar above the `Navigator`, so a modal route is
      // painted *before* it and it floats in front — which is the point. Left at
      // the default `true`, the bar would delete itself the moment any sheet
      // opened.
      //
      // The package's reason for hiding is worth knowing, because it does not
      // apply here: the search variant uses an unclipped native container so the
      // orb can overhang the bar's top edge, and that lets the bar's shadow bleed
      // through a sheet drawn over it (`tab_bar.dart:341-355`). Bleeding *through*
      // a sheet is only wrong when the bar is meant to be behind it. It is not.
      //
      // Turning this off does not give up halo containment for anything else:
      // `ShellRouteObserver` still drives `anyModalDepth`, so `CNButton` and the
      // native segmented controls on the page below still clip while a sheet is
      // up. Only the bar opts out of reacting.
      autoHideOnModal: false,
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
    // The fallback's box *is* its glass, so one height serves as both.
    final height = ShellTabBar.geometryOf(context).visualHeight;
    // **Clamped, because this bar's height is geometry and not type.**
    // [ShellTabBarGeometry] derives `visualHeight` from the home-indicator strip
    // and the design's own numbers, so the box does not grow with the text
    // inside it. Now that the labels are a real token with a real line-height
    // (13 × 1.2), the largest accessibility step drove them straight past the
    // pill's edge, and a three-tab row with nowhere to go ellipsizes every
    // label to one letter — which is worse for the reader who turned the setting
    // on than a slightly small label is.
    //
    // 1.3 rather than 1.0: refusing scaling outright is the thing to avoid, and
    // 13 → 16.9 still fits. The native `CNTabBar` path is untouched; UIKit sizes
    // its own bar.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Row(
        children: [
          Expanded(
            child: _Glass(
              borderRadius: BorderRadius.circular(height / 2),
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        Expanded(
                          child: _TabSegment(
                            label: labels[i],
                            height: height,
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
            borderRadius: BorderRadius.circular(height / 2),
            child: SizedBox.square(
              dimension: height,
              child: Semantics(
                button: true,
                label: AppLocalizations.of(context).addBook,
                // A `GestureDetector` rather than an `IconButton`, matching
                // [_TabSegment]. `ShellChrome` hosts this bar above the
                // `Navigator`, where there is no `Material` and no `Overlay` -- so
                // ink and tooltips have no ancestor to find and throw. The label
                // moves to `Semantics`, which needs neither.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onAddBookTapped,
                  child: Center(
                    child: Icon(
                      Icons.search,
                      color: context.colors.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
  final double height;
  final bool selected;
  final VoidCallback onTap;

  const _TabSegment({
    required this.label,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular((height - 8) / 2);
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
            // **One weight in both states, deliberately.** This used to go w500 →
            // bold on selection, and because the label is centred, a heavier face
            // is a wider string, so the text grew outward from its own middle
            // every time you switched tabs — the segment's two edges twitching in
            // opposite directions under a pill that had not moved. Selection is
            // already carried twice over, by [AppColors.brandText] and by the
            // filled capsule behind it; it did not also need to reflow the label.
            style: AppTextStyles.label.copyWith(
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
