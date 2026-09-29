import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// Which set the read sheet is showing.
///
/// **The sheet's own title is this value's read-out** — `Books finished` against
/// `Books read` — which is why there is no separate filter label anywhere. The drawn
/// alternative was a `Finished` / `All` segment top-right of the title row, and its
/// flaw was that `All` would sit two rows above the year rail's `All time`: one word
/// doing duty for two scopes. A title that names the set it is showing needs no second
/// label at all.
///
/// The pair is also this feature's vocabulary split rather than a coincidence.
/// *Finished* is the state a book is in; *read* is the act. A set-aside book was not
/// finished, but it was partly read, so the inclusive title is accurate rather than
/// generous.
enum ReadSetFilter {
  /// Finished books only — status 2. The default, and the set the Library Card counts
  /// a tab away, so the two agree on arrival.
  finishedOnly,

  /// Finished **and** set-aside books, merged. The only state whose count reads higher
  /// than the Card's, and its title says why.
  allRead;

  bool get isFinishedOnly => this == ReadSetFilter.finishedOnly;
}

/// The chevron beside the read sheet's title, and the menu it opens.
///
/// ## This replaced ~250 lines of app-drawn popover, on instruction
///
/// The filter used to be a hand-built card: its own [PopupRoute], a 216pt panel hung
/// from the title's [RenderBox], two `InkWell` rows with a check slot, a scale-and-fade
/// entrance, and a glass material with a [BackdropFilter] fallback. All of it is gone.
///
/// **The file it was built from recorded a reason not to use the platform's menu, and
/// that reason was half right.** It said `CNPopupMenuButton` is "the wrong mechanism
/// here for one reason: that button's `buttonLabel` is rendered **by the platform**",
/// and pointed at `read_filter.dart`'s record of a label arriving at "the system's 17pt
/// in the theme's tint, wrapped onto two lines inside a platform view Flutter had sized
/// for 13pt". True — and it only rules out the **labelled** constructor.
/// [CNPopupMenuButton.icon] renders one SF Symbol and no text, so the title beside it
/// stays Flutter's, at Flutter's 22pt, with its count in `brandText`. `home_page.dart`'s
/// `_VisitMenuButton` has been shipping exactly that next to a Flutter-drawn title —
/// the friend's-library chevron with `Remove friend` under it — and a reader pointed at
/// it as the thing to copy.
///
/// **Three rounds of trying to build the material by hand is the other half of why.** A
/// [LiquidGlassContainer] came out flat, because it is a bare `glassEffect` with no
/// material of its own over an opaque sheet. A stretched contentless glass [CNButton]
/// fixed the flatness and drew a **capsule**, because
/// `CupertinoButtonPlatformView.swift`'s UIKit branch sets
/// `cornerStyle = round ? .capsule : .dynamic` and never reads `borderRadius`. Adding a
/// `glassEffectId` to reach the SwiftUI branch that *does* honour the radius then sized
/// the glass to the button's **content** — an empty label — so it collapsed to a small
/// pill floating in the middle of the card. Each fix was correct about the thing it
/// fixed and uncovered the next one, and none of it was verifiable from here, because
/// `useNativeGlass` needs an Apple target *and* iOS 26 while `flutter test` reports
/// Android. `AGENTS.md` keeps the whole chain; the lesson it ends on is this widget.
///
/// A `UIMenu` brings the material, the corner radius, the entrance, the dismissal, the
/// checkmarks, the destructive tinting and the keyboard and VoiceOver behaviour, all
/// from the platform, and none of them can drift from iOS because none of them is ours.
///
/// ## What it costs, and the cost is real
///
/// **The title is no longer part of the tap target.** That was a documented decision —
/// _"title, count and chevron are one tap target; three separately tappable things in a
/// row this size would be three ways to miss"_ — with a case of its own asserting that
/// tapping the count opens the menu. It cannot be kept: UIKit presents the menu from
/// `button.showsMenuAsPrimaryAction`, so the thing tapped has to **be** the native
/// button, and the plugin exposes no way to present a menu programmatically. A Flutter
/// gesture on the row has nothing to call.
///
/// The one way to keep it would be to stretch a label-less `.plain`
/// [CNPopupMenuButton] across the whole row behind the Flutter title, which is what
/// `read_filter._Capsule` does with a plain [CNButton]. It is not taken here: after
/// three unverifiable attempts at hand-built glass, copying a control that is known to
/// work on a device beats inventing a fourth. The friend's library has the same
/// chevron-only target, so this is at least the app agreeing with itself.
///
/// ## The fallback is Material's menu, not a card
///
/// Off iOS 26 this is a [PopupMenuButton], as `_VisitMenuButton`'s fallback is. It is
/// also the only path a widget test can see, so every case about this filter is really
/// a case about Material's menu — which is fine for the ones that matter (the labels,
/// the check moving with the choice, the order of the two rows, dismissal returning
/// nothing) and cannot say anything about the native one.
class ReadSetFilterMenuButton extends StatelessWidget {
  const ReadSetFilterMenuButton({
    super.key,
    required this.current,
    required this.onSelected,
  });

  /// Which row draws the check.
  final ReadSetFilter current;

  /// Called with the chosen mode, including the one already current.
  ///
  /// **Choosing the checked row is a legal answer and is not filtered here.** A menu
  /// that ignores the row it has checked reads as broken, so the caller compares.
  final ValueChanged<ReadSetFilter> onSelected;

  /// The glyph, at the size [LibrarySheetTitle] drew it before this existed.
  static const double _iconSize = 18;

  /// The SF Symbol runs smaller than the Material icon for the usual reason: Apple's
  /// marks are inset in their box and Material's fill it. Same ratio and same figure as
  /// `_VisitMenuButton`.
  static const double _symbolSize = 13;

  /// The button's box, and the one number here that is a compromise.
  ///
  /// `_VisitMenuButton` is 34×44 because it punctuates a 56pt row. This punctuates the
  /// sheet's title row, which is sized by a 22pt line, so 44 would make the row 44 tall
  /// and push everything under it down — `library_clearance_test.dart` measures that row
  /// at 2× text with a two-digit count. 30 keeps the row's height under the title's own
  /// and is still a target a thumb can find, where the 18pt glyph it replaced was not
  /// one at all. **It is below the platform's 44pt floor, which is accepted** for the
  /// reason the read-out's numerals accept it: this is the coarse control's neighbour,
  /// not the only way to the state.
  static const double _box = 30;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The colour of the suffix beside it rather than of the title: the chevron is the
    // app talking about the reader's content.
    final tint = context.colors.secondaryText;

    // Native only while nothing is over this control, as every other native control in
    // this sheet is: a platform view under a sheet leaks its own rectangle through the
    // scrim and stays tappable behind it. See [ModalCoverBuilder].
    return ModalCoverBuilder(
      builder: (context, covered) => SizedBox(
        width: _box,
        height: _box,
        child: useNativeGlass && !covered
            ? _native(l10n, tint)
            : _fallback(context, l10n, tint),
      ),
    );
  }

  /// The two rows, in the order the enum declares them, with the current one checked.
  ///
  /// Order is `finishedOnly` then `allRead`, which is narrow-to-wide. It matches the
  /// titles' own progression and is asserted, because a menu that reorders itself with
  /// the selection is a menu the reader has to re-read.
  List<ReadSetFilter> get _order => ReadSetFilter.values;

  String _label(AppLocalizations l10n, ReadSetFilter v) =>
      v.isFinishedOnly ? l10n.showFinishedOnly : l10n.showAllRead;

  Widget _native(AppLocalizations l10n, Color tint) => Semantics(
    label: l10n.readSetFilterMenu,
    button: true,
    container: true,
    child: CNPopupMenuButton.icon(
      buttonIcon: CNSymbol('chevron.down', size: _symbolSize, color: tint),
      // Square by construction, so it takes the narrower of the two dimensions.
      size: _box,
      // **No material.** The chevron sits inside a title row on the sheet's own
      // ground; a glass or tinted button here would be a fourth object in a row that
      // already holds a title, a count and a glyph.
      buttonStyle: CNButtonStyle.plain,
      items: [
        for (final v in _order)
          CNPopupMenuItem(label: _label(l10n, v), checked: v == current),
      ],
      onSelected: (i) => onSelected(_order[i]),
    ),
  );

  /// Material's menu, which is what every widget test sees.
  Widget _fallback(BuildContext context, AppLocalizations l10n, Color tint) {
    final colors = context.colors;
    return PopupMenuButton<ReadSetFilter>(
      // Doubles as the accessible name, as it does on `AdaptiveIconButton`'s fallback
      // and `_VisitMenuButton`'s. Without it this announces Material's generic "Show
      // menu", which says nothing about what the menu is about.
      tooltip: l10n.readSetFilterMenu,
      padding: EdgeInsets.zero,
      // Under the chevron rather than over it, which is where the app-drawn card hung
      // and where a menu belongs relative to the thing it is a read-out of.
      position: PopupMenuPosition.under,
      // **Both of these are the difference between a menu and a rendering fault**, and
      // leaving them out is what the first render of this showed: Material's default
      // shape drew a 3pt black outline with square-ish corners over the sheet. Copied
      // from `_VisitMenuButton._fallback`, which is the app's other `PopupMenuButton`, so
      // the two menus are one object in different words.
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final v in _order)
          PopupMenuItem<ReadSetFilter>(
            value: v,
            child: Row(
              children: [
                // **Reserved in both rows**, so the two labels start at the same x and
                // the menu does not shuffle sideways as the reader changes their mind.
                // The native menu does its own version of this; here it is ours.
                SizedBox(
                  width: 16,
                  child: v == current
                      ? Icon(Icons.check, size: 15, color: colors.brandText)
                      : null,
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(_label(l10n, v))),
              ],
            ),
          ),
      ],
      // `child` rather than `icon`, as `_VisitMenuButton` does it: `icon` hands the glyph
      // to Material's own `IconButton` padding, which does not fit a 30pt box.
      child: Center(
        child: Icon(Icons.keyboard_arrow_down, size: _iconSize, color: tint),
      ),
    );
  }
}
