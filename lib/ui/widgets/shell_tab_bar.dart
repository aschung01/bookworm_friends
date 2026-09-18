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

  /// Dead room the package's own platform view keeps above the `UITabBar` it
  /// hosts.
  ///
  /// `CupertinoTabBarPlatformView` pins its bar's top to `container.topAnchor`
  /// with `constant: 14` and reports its intrinsic height as `sizeThatFits + 14`
  /// — deliberately, so iOS 26's selection pill can overshoot the bar's top edge
  /// during its morph without being clipped (the package's 1.4.1 fix). It is a
  /// package constant rather than one of ours, and it is the reason the box handed
  /// to the bar is taller than the bar.
  ///
  /// The search variant used before iOS 27 had no such inset, which is why moving
  /// off it changed every number below.
  static const double pillTopRoom = 14;

  /// Height of the box handed to the bar.
  ///
  /// Passed to `CNTabBar` explicitly rather than letting it measure itself: the
  /// package measures its intrinsic height asynchronously from native and keeps
  /// it private — no constant, no callback — so a caller that must reserve space
  /// beneath the bar cannot learn the number.
  ///
  /// 83 is not a guess. It is `UITabBar.sizeThatFits` for an iOS 26 bar with three
  /// labelled items, read off the rendered view on an iPhone 17 Pro / iOS 26.4
  /// simulator. At 50 the native bar drew its labels on top of its icons — a
  /// squashed `UITabBar` is what too small looks like. It is also exactly
  /// `49 + 34`: a tab bar plus a home-indicator inset, which is the clue
  /// [glassTop] turns on.
  ///
  /// [pillTopRoom] is added on top because the box is the *platform view's*, not
  /// the bar's: the package insets the bar inside it by that much.
  static const double barHeight = 83;

  double get boxHeight => native ? barHeight + pillTopRoom : 50;

  /// Height of what you can actually see, which on the native path is *not*
  /// [boxHeight].
  ///
  /// iOS lays the visible glass out as a 62pt platter anchored to the **top** of
  /// the 83pt frame, keeping 21pt of padding at the bottom of its own box.
  ///
  /// On the native path this is **descriptive only** — no position is derived from
  /// it. That is deliberate and it is the point of [glassTop]: the 21pt inset is a
  /// native subview's offset that Flutter cannot see, so a layout that depends on
  /// it can never be verified from Dart.
  double get visualHeight => native ? 62 : 50;

  /// Inset from the screen's side edges.
  ///
  /// **Zero on the native path, and that is not an omission.** The plugin pins the
  /// `UITabBar` to the platform view's side edges (`CupertinoTabBarPlatformView`),
  /// so our box's width *is* the bar's — and iOS 26 draws its glass as a platter
  /// inset *within* that. Anything added here lands on top of the margin iOS already
  /// applies, and the bar comes out narrower than the system's. A system tab bar is
  /// handed the full width; matching one means handing it the full width.
  ///
  /// 14 is right for the fallback, which fills its box with a pill it draws
  /// itself.
  double get sideInset => native ? 0 : 14;

  /// Distance from the bottom of the screen to the **top edge of the visible
  /// glass** — the one number both the bar's position and the sheet's reservation
  /// are derived from, so the two cannot drift apart.
  ///
  /// The top edge is the honest anchor because on both paths the glass's top edge
  /// is a fixed offset from the box's top edge: iOS anchors its platter to the top
  /// of the bar's frame, and the fallback's pill fills its box. Every other edge
  /// involves an inset only native code can see.
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
  ///
  /// **[pillTopRoom] does not move it.** The package's 14pt of dead room sits above
  /// the bar's frame, inside the box; the frame is still flush with the bottom, so
  /// the platter is still [barHeight] up. Which is why dropping the search item
  /// changed [boxHeight] and this number not at all — and why sheets did not have
  /// to move.
  double get glassTop =>
      native ? barHeight : bottomViewPadding + gap + visualHeight;

  /// Where to pin the bar's box, measured from the bottom of the screen.
  ///
  /// **Zero on the native path**, because that is what a `UITabBar` frame is, and
  /// the box's bottom edge *is* the frame's bottom edge — the package's inset is
  /// all at the top. Note this is no longer [glassTop] less [boxHeight]: the box
  /// now overshoots the glass upward by [pillTopRoom].
  double get bottomOffset => native ? 0 : glassTop - boxHeight;

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

/// The shell's floating tab bar: one capsule of Library / Friends / Card /
/// Search.
///
/// Search is a tab like the others, and it is the only one that opens a sheet
/// instead of swapping what the shell shows. It was a detached glass orb until
/// iOS 27 stopped drawing one and Apple's own apps stopped asking for one; see
/// [_ShellTabBarState._buildNative].
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

  /// Fires when the fourth tab — Search — is tapped. The sheet it opens searches
  /// the reader's own library *and* the catalogue, which is why the tab is a
  /// magnifier rather than a plus.
  ///
  /// Awaited, because the bar keeps Search lit for as long as its sheet is up and
  /// has to know when to stop. See [_ShellTabBarState._searchActive].
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
  static const _tabs = LibraryTab.values;

  /// Index of the Search tab, which sits after the three [LibraryTab]s and is not
  /// one of them — it opens a sheet rather than swapping what the shell shows.
  static const _searchIndex = 3;

  /// Whether Search's sheet is up, and so whether Search is the lit tab.
  ///
  /// **The bar has to hold this itself**, because the shell's own notion of the
  /// current tab cannot represent it: [LibraryTab] has three values and Search is
  /// not one of them. Without it the bar would light Search on tap and then be
  /// pushed straight back to Library by the next `setSelectedIndex`, which reads as
  /// a flicker and, worse, as a claim that tapping Search did nothing.
  ///
  /// Lit for exactly as long as the sheet is up, which is what Apple Books does
  /// with the same tab.
  bool _searchActive = false;

  List<String> _labels(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [l10n.library, l10n.friends, l10n.tabCard, l10n.tabSearch];
  }

  int get _selectedIndex =>
      _searchActive ? _searchIndex : _tabs.indexOf(widget.current);

  void _onTap(int index) {
    if (index == _searchIndex) {
      _onSearchTapped();
      return;
    }
    // No `_searchActive = false` here: picking another tab pops the sheet, which
    // completes the future below, which turns the light off. Doing it twice would
    // just be two rebuilds.
    widget.onChanged(_tabs[index]);
  }

  Future<void> _onSearchTapped() async {
    setState(() => _searchActive = true);
    await widget.onAddBook();
    if (mounted) setState(() => _searchActive = false);
  }

  @override
  Widget build(BuildContext context) {
    return useNativeGlass ? _buildNative(context) : _buildFallback(context);
  }

  /// iOS 26+: one real `UITabBar` of four items, Search among them.
  ///
  /// **Search is an ordinary labelled tab, and that is the current platform
  /// pattern rather than a compromise.** It used to be a `CNTabBarSearchItem`,
  /// which asks the package for a `UITabBarItem(tabBarSystemItem: .search)`; on
  /// iOS 26 UIKit promoted that item out of the capsule and drew it as a detached
  /// Liquid Glass circle, and iOS 27 stopped doing so — verified side by side on
  /// iPhone 17 Pro / iOS 26.5 and iPhone 18 Pro / iOS 27.0 from
  /// `main_shell_preview.dart`, same build, and on a physical iPhone 16 Pro /
  /// iOS 27.0.
  ///
  /// That looked like a regression and was chased as one. It is not: Apple's own
  /// apps moved the same way. **Books** puts Home / Library / Book Store /
  /// Audiobooks / Search in a single capsule with Search as a plain labelled tab
  /// and no detached orb anywhere. So the bar follows Books, and the orb — whether
  /// UIKit's or, briefly, one of our own — is gone.
  ///
  /// What that buys, beyond being current: the layout is entirely UIKit's again.
  /// A detached orb of our own meant placing it against a pill that content-sizes
  /// and centres itself, which Flutter cannot measure — so the gap between the two
  /// came out as whatever slack the labels happened to leave, ~35pt in English and
  /// wider in Korean, where the labels are shorter. One capsule has no such gap to
  /// get wrong.
  ///
  /// The plain `CNTabBarItem` is also what keeps 26 and 27 identical: the search
  /// item is the only thing the two OS versions disagreed about, and nothing here
  /// asks for it any more.
  Widget _buildNative(BuildContext context) {
    final labels = _labels(context);
    return CNTabBar(
      height: ShellTabBar.geometryOf(context).boxHeight,
      // `ShellChrome` hosts this bar above the `Navigator`, so a modal route is
      // painted *before* it and it floats in front — which is the point. Left at
      // the default `true`, the bar would delete itself the moment any sheet
      // opened.
      //
      // Turning this off does not give up halo containment for anything else:
      // `ShellRouteObserver` still drives `anyModalDepth`, so `CNButton` and the
      // native segmented controls on the page below still clip while a sheet is
      // up. Only the bar opts out of reacting.
      autoHideOnModal: false,
      // **The size knobs.** `iconSize` is yours; `buildItems`' own default is 25 if
      // you ever want the platform's. A null font pair leaves the labels on the
      // system face, and passing null is identical to omitting them — the Dart side
      // only forwards each one `if (... != null)`.
      iconSize: 18,
      labelFontFamily: null,
      labelFontSize: null,
      currentIndex: _selectedIndex,
      onTap: _onTap,
      tint: context.colors.brandText,
      // SF Symbols only: the native view ignores rasterised `customIcon`s and
      // image assets on the iOS 26+ path.
      //
      // Icon and label size *are* adjustable here, unlike on the search variant
      // this replaced — add `iconSize:` and `labelFontFamily:` + `labelFontSize:`
      // above. Two things to know before you do, both measured on iOS 27:
      //
      //   - `labelFontSize` alone does nothing. `applyLabelFont` returns early
      //     unless `labelFontFamily` is also set, size included.
      //   - **iOS fixes the glass platter at 62pt**, so the icon and its label
      //     share a budget that [ShellTabBarGeometry.barHeight] cannot enlarge:
      //     raising the frame only moves the platter up, and drags every sheet
      //     with it via `reserve`. Above 25 UIKit also adds a
      //     `titlePositionAdjustment` of `iconSize - 25`, pushing the label down
      //     into the glyph. 30/15 collided; 27 with Pretendard at 12 fits.
      //
      // **`.fill` on three of the four, and the fourth is not an oversight.**
      // Filled glyphs are what the current platform bar uses — Books' Home /
      // Library / Book Store / Audiobooks are all filled — and `magnifyingglass`
      // simply has no `.fill` counterpart in SF Symbols. Books therefore sets a
      // plain magnifier beside its filled glyphs too, so the odd one out here
      // matches Apple's own bar rather than falling short of it.
      //
      // Filled in **both** states rather than `icon` outline / `activeIcon` filled.
      // Selection is already carried twice over, by [AppColors.brandText] and by
      // the capsule iOS draws behind the selected item; a third signal that swaps
      // the glyph's whole silhouette is what makes a bar look like it is animating
      // when you have only changed tabs. `_TabSegment` declines a weight change for
      // the same reason.
      items: [
        CNTabBarItem(
          label: labels[0],
          icon: const CNSymbol('books.vertical.fill'),
        ),
        CNTabBarItem(label: labels[1], icon: const CNSymbol('person.2.fill')),
        CNTabBarItem(label: labels[2], icon: const CNSymbol('creditcard.fill')),
        CNTabBarItem(label: labels[3], icon: const CNSymbol('magnifyingglass')),
      ],
    );
  }

  /// Everywhere else — and under `flutter test`, which reports Android — the same
  /// four-tab capsule is drawn in Flutter over a blur.
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
    // pill's edge, and a row with nowhere to go ellipsizes every label to one
    // letter — which is worse for the reader who turned the setting on than a
    // slightly small label is.
    //
    // 1.3 rather than 1.0: refusing scaling outright is the thing to avoid, and
    // 13 → 16.9 still fits. The native `CNTabBar` path is untouched; UIKit sizes
    // its own bar.
    //
    // There is one fewer pixel of slack than there was, because Search moved in
    // here from a circle of its own: four labels share the width three used to.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: _Glass(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: _TabSegment(
                      label: labels[i],
                      height: height,
                      selected: i == _selectedIndex,
                      onTap: () => _onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
