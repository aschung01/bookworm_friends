import 'dart:math' as math;
import 'dart:ui';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// Width of the popover. Wide enough for a 140pt shelf name — the cap [ShelfLabel]
/// ellipsizes at — plus its count and a check, and narrow enough that it never spans
/// the header it is dropped over.
const double _kWidth = 232;

/// Height of one shelf row. The platform's touch floor, and the figure every list
/// row in the app is built to.
const double _kRowHeight = 44;

/// Height of the `Move to shelf` heading, counted into the card's own height so the
/// fits-below test is measured rather than estimated.
const double _kHeadingHeight = 32;

/// Gap between the tab's bottom edge and the top of the popover.
const double _kAnchorGap = 6;

/// Keep-out from the screen's edges, so a tab near the right margin does not push the
/// card off it.
const double _kScreenInset = 8;

/// Corner radius of the card, shared by the clip, the native glass shape and the
/// fallback's border. Three places, one figure, because a glass shape that disagrees
/// with its clip shows as a bright seam along the corner arcs.
const double _kRadius = 13;

/// The shelves a book can be moved to, dropped under the name tab that opens it —
/// **the fallback presentation, for everywhere the platform has no menu of its own.**
///
/// On iOS 26 the tab opens a real `UIMenu` instead; [ShelfLabelDoor] owns that choice
/// and this is what it falls back to off iOS 26, while something is presented over the
/// page, and under `flutter test`. See [ShelfLabelDoor] for the three gates.
///
/// Returns the chosen shelf, or null if the reader dismissed without choosing. The
/// current shelf is a legal choice and returns itself — `moveBookToShelf` no-ops on
/// it — because a menu that refuses the row it has checked reads as broken.
///
/// ## Two wrong turns on the way here, both recorded because both are easy to repeat
///
/// **This file first claimed the menu's *behaviour* could not be native, and that was
/// wrong.** The claim was that [CNPopupMenuButton] draws its own button — it is a
/// platform view configured with a `buttonLabel` — so using it would mean the shelf tab
/// stops being a tab, loses its top-rounded shape and cannot be a [Hero]. What that
/// missed is that `CNButtonStyle.plain` with an empty label draws **nothing at all**:
/// the button can be stacked over a tab Flutter paints and contribute only
/// `showsMenuAsPrimaryAction`. That is what ships. (The package's attach-to-any-child
/// alternative, `CNPopupGesture`, genuinely is unusable: long-press only, fixed at
/// 220pt, drawn in hardcoded `CupertinoColors` that ignore this app's themes, no
/// checkmark support, and every icon rendered as `CupertinoIcons.circle` behind a
/// `// TODO`.)
///
/// **From that it concluded the material could not be native either, and that was wrong
/// twice over.** [LiquidGlassContainer] applies iOS 26's glass to an arbitrary child: it
/// stacks an `IgnorePointer(UiKitView)` under the child with `Positioned.fill` and lets
/// the child size the stack. That is the same division of labour `read_filter.dart`'s
/// `_Capsule` uses for the selected year pill — **Flutter draws every pixel of content,
/// the platform supplies the material behind it** — and it is what this card still does
/// on the rare iOS 26 path that reaches it. The [BackdropFilter] path is the fallback's
/// fallback, and it is a blur rather than glass: no rim highlight, no specular edge.
///
/// Two consequences worth stating, because both are easy to undo by accident:
///
///  * **Nothing opaque may be painted over the native material.** The fill belongs to
///    the fallback only. A `DecoratedBox` with a colour on the native path would hide
///    the very thing it is standing on.
///  * **The shadow lives outside the clip.** It used to be a `boxShadow` on a
///    `DecoratedBox` *inside* the `ClipRRect`, which clips it away completely — the
///    card had no shadow at all and read as pasted onto the page rather than floating
///    over it. On the native path there is still none of ours: the glass carries its
///    own, and two would read as a smear.
///
/// ## Why it is a [PopupRoute]
///
/// Two reasons, and neither is about the transition. `ShellRouteObserver._isAnyModal`
/// answers true for any `PopupRoute` before it starts sniffing type names, so native
/// glass controls on the route below deactivate for as long as this is up — without
/// that, a `UiKitView`'s Liquid Glass halo leaks outside its own bounds and paints
/// over whatever covers it. And a route gets barrier dismissal, back-button handling
/// and focus trapping for free, all of which an `OverlayEntry` would have to
/// re-implement.
///
/// The card's own glass is *not* caught by that: `ModalHideMixin` gates on the modal
/// depth captured at mount, so a platform view living inside the newest modal does not
/// count itself as covered by it.
Future<Shelf?> showShelfPickerPopover(
  BuildContext context, {

  /// The tab. Its rect on screen is where the card is hung from, so this must be the
  /// render object of the thing the reader actually touched.
  required RenderBox anchor,
  required List<Shelf> shelves,
  required String currentShelfId,
}) {
  if (!anchor.attached || !anchor.hasSize) return Future<Shelf?>.value();

  final anchorRect = Rect.fromPoints(
    anchor.localToGlobal(Offset.zero),
    anchor.localToGlobal(anchor.size.bottomRight(Offset.zero)),
  );

  return Navigator.of(context, rootNavigator: true).push(
    ShelfPickerPopupRoute(
      anchorRect: anchorRect,
      shelves: shelves,
      currentShelfId: currentShelfId,
      // Captured once here rather than read inside the route, which is built outside
      // the page's own tree and therefore outside its theme and locale.
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
    ),
  );
}

/// **The class name is load-bearing.** `ShellRouteObserver._isAnyModal` and the
/// package's own predicate both match a route whose runtime type name contains
/// `Popup`, and this being a `PopupRoute` already satisfies the stricter of the two
/// checks. Renaming it to something without that substring would silently stop native
/// glass controls underneath from standing down.
class ShelfPickerPopupRoute extends PopupRoute<Shelf> {
  ShelfPickerPopupRoute({
    required this.anchorRect,
    required this.shelves,
    required this.currentShelfId,
    required this.capturedThemes,
  });

  final Rect anchorRect;
  final List<Shelf> shelves;
  final String currentShelfId;
  final CapturedThemes capturedThemes;

  /// Short, and shorter than a sheet's, because the card is anchored: it has a much
  /// smaller distance to explain than something arriving from the bottom of the
  /// screen. It is also as long as a platform view can be asked to fade for — see
  /// [_ShelfPickerCard].
  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 110);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  /// Barely there. A menu anchored to the thing that opened it does not need a scrim
  /// to explain where it came from, and a dark one over this header would read as a
  /// sheet — which is the interaction model this deliberately is not.
  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.06);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return capturedThemes.wrap(
      _ShelfPickerCard(
        anchorRect: anchorRect,
        shelves: shelves,
        currentShelfId: currentShelfId,
        animation: animation,
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class _ShelfPickerCard extends StatelessWidget {
  const _ShelfPickerCard({
    required this.anchorRect,
    required this.shelves,
    required this.currentShelfId,
    required this.animation,
  });

  final Rect anchorRect;
  final List<Shelf> shelves;
  final String currentShelfId;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;

    // Right-aligned with the tab, because the tab is itself pinned to the right edge
    // of the cover: a left-aligned card would hang off toward the middle of the
    // screen from an object sitting at its margin.
    final rightEdge = math.max(
      _kScreenInset,
      screen.width - _kWidth - _kScreenInset,
    );
    final left = (anchorRect.right - _kWidth).clamp(_kScreenInset, rightEdge);

    // **The card is capped and the list scrolls, which is not hypothetical.** The
    // library that prompted this feature has ten shelves; at 44pt a row that is 472pt
    // of card, and a reader with twenty would ask for 912 on an 874pt screen. Without
    // a cap the rows past the fold are simply unreachable.
    final natural = _kHeadingHeight + _kRowHeight * shelves.length;
    final roomBelow =
        screen.height -
        media.padding.bottom -
        _kScreenInset -
        (anchorRect.bottom + _kAnchorGap);
    final roomAbove =
        anchorRect.top - _kAnchorGap - media.padding.top - _kScreenInset;
    // Under the tab when it fits, and otherwise on whichever side has more room. A
    // disclosure should drop away from the thing that disclosed it —
    // `PopupMenuPosition.under`, the rule `home_page.dart`'s own fallback menu
    // already states — but that is a preference, not a guarantee.
    final below = natural <= roomBelow || roomBelow >= roomAbove;
    final room = math.max(
      below ? roomBelow : roomAbove,
      // One heading and one row, so a pathologically short viewport still shows
      // something scrollable rather than a sliver.
      _kHeadingHeight + _kRowHeight,
    );
    final height = math.min(natural, room);
    final top = below
        ? anchorRect.bottom + _kAnchorGap
        : anchorRect.top - _kAnchorGap - height;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: _kWidth,
          height: height,
          child: _entrance(
            // Grown from the corner nearest the tab, so the card reads as coming out
            // of it rather than appearing beside it.
            alignment: below ? Alignment.topRight : Alignment.bottomRight,
            child: _card(context, scrolls: natural > height),
          ),
        ),
      ],
    );
  }

  /// The arrival.
  ///
  /// **Deliberately modest on the native path**, and the reason is a platform-view
  /// limitation rather than taste: Flutter cannot apply opacity to a `UiKitView`, so a
  /// `FadeTransition` over the card would fade the list while the glass behind it
  /// appeared at full strength — worse than not fading at all. A transform is
  /// composited, so the scale survives; at 140ms the difference is a flicker either
  /// way, and the fallback keeps both.
  Widget _entrance({required Alignment alignment, required Widget child}) {
    final scaled = ScaleTransition(
      scale: Tween<double>(
        begin: 0.94,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      alignment: alignment,
      child: child,
    );
    if (useNativeGlass) return scaled;
    return FadeTransition(opacity: animation, child: scaled);
  }

  Widget _card(BuildContext context, {required bool scrolls}) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final content = Material(
      // Transparent, purely so the rows' ink has a surface to splash on. A colour
      // here would paint over the material the whole card is standing on.
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A heading rather than a bare list, because the card's rows are shelf
          // *names* — nouns with no verb among them — so without it the reader has to
          // infer the act from the fact that they tapped a shelf tab.
          SizedBox(
            height: _kHeadingHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 9, 13, 5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.moveToShelf,
                  style: AppTextStyles.label.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              // Only scrollable when there is something to scroll. A bouncing list of
              // three shelves would say the card had more in it than it does.
              physics: scrolls
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemExtent: _kRowHeight,
              itemCount: shelves.length,
              itemBuilder: (context, i) => _ShelfRow(
                shelf: shelves[i],
                checked: shelves[i].id == currentShelfId,
                last: i == shelves.length - 1,
              ),
            ),
          ),
        ],
      ),
    );

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(_kRadius),
      child: useNativeGlass
          ? LiquidGlassContainer(
              config: LiquidGlassConfig(
                effect: CNGlassEffect.regular,
                shape: CNGlassEffectShape.rect,
                cornerRadius: _kRadius,
                // Not interactive: the glass is material, not a control. The rows
                // underneath it own every touch.
                interactive: false,
              ),
              // **Off.** The default destroys the platform view whenever a modal is
              // above this widget's host route, and this card *is* that modal — the
              // mount-depth gate in `ModalHideMixin` covers the case correctly today,
              // but nothing above this route can ever need our glass gone, so the
              // question is better not asked.
              autoHideOnModal: false,
              child: content,
            )
          : BackdropFilter(
              // The fallback, and it is a blur rather than glass: no rim highlight and
              // no specular edge, which is most of what the real material is.
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Low enough to let the page through, which is the whole point of
                  // blurring it. At 0.82 over this page — a near-uniform light band
                  // above near-uniform white tab content — the card came out looking
                  // flatly opaque, because a blur of something uniform is that thing.
                  color: colors.surface.withValues(alpha: isDark ? 0.7 : 0.72),
                  border: Border.all(
                    color: colors.primaryText.withValues(
                      alpha: isDark ? 0.14 : 0.1,
                    ),
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(_kRadius),
                ),
                child: content,
              ),
            ),
    );

    // Outside the clip, or it is clipped away — which is exactly what happened when
    // this was a `boxShadow` on the decoration above. None on the native path: the
    // glass brings its own.
    if (useNativeGlass) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: clipped,
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.shelf,
    required this.checked,
    required this.last,
  });

  final Shelf shelf;
  final bool checked;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: () => Navigator.pop(context, shelf),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(
                  bottom: BorderSide(
                    color: colors.primaryText.withValues(alpha: 0.07),
                    width: 0.5,
                  ),
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shelf.name,
                  style: AppTextStyles.body.copyWith(color: colors.primaryText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // The count the tab gave up to make room for its chevron, put where it
              // is worth more: several shelves side by side is a comparison, where one
              // number on a tab was only ever a fact about the shelf you were already
              // on.
              //
              // `shelvedBookCount` rather than `books.length`, or this list would
              // advertise covers that are provably not on those planks — and would
              // disagree with the tab that opened it.
              Text(
                AppLocalizations.of(
                  context,
                ).bookCountLabel(shelvedBookCount(shelf)),
                style: AppTextStyles.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
              if (checked) ...[
                const SizedBox(width: 10),
                Icon(Icons.check, size: 18, color: colors.brandText),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
