import 'dart:math' as math;
import 'dart:ui';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
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

/// Width of the card. From the drawing (`sheet-popover`), which sets it at 216 against
/// a 388pt sheet: wide enough for `Show finished only` with its check slot, and narrow
/// enough that it reads as a menu hung under the title rather than as a row of the
/// sheet.
const double _kWidth = 216;

/// Least height of one row: the platform's touch floor, and the figure every list row
/// in the app is built to. A row grows past it with the text scale — see [_FilterRow].
const double _kRowMinHeight = 44;

/// Gap between the title row's bottom edge and the top of the card.
const double _kAnchorGap = 6;

/// Keep-out from the screen's edges.
const double _kScreenInset = 8;

/// Corner radius of the card, shared by the clip, the native glass shape and the
/// fallback's border. Three places, one figure, because a glass shape that disagrees
/// with its clip shows as a bright seam along the corner arcs.
const double _kRadius = 14;

/// The read sheet's completion filter: two checkable rows, hung under the sheet's own
/// title.
///
/// Returns the chosen mode, or null if the reader dismissed without choosing. The
/// current mode is a legal choice and returns itself — a menu that refuses the row it
/// has checked reads as broken — so the caller compares before acting.
///
/// ## Why this is app-drawn, when an apparently exact native fit exists
///
/// `read_filter.dart`'s collapsed year popover is a [CNPopupMenuButton] with
/// `CNButtonStyle.glass` and `CNPopupMenuItem(checked:)` — the platform's own menu,
/// with the platform's glass, entrance, checkmarks and dismissal, which is the same
/// shape as this control down to the check marks. It is the wrong mechanism here for
/// one reason: that button's `buttonLabel` is rendered **by the platform**, and that
/// file's own record documents the label arriving at "the system's 17pt in the theme's
/// tint, wrapped onto two lines inside a platform view Flutter had sized for 13pt".
/// The anchor here is [LibrarySheetTitle] — the largest text on the sheet, with its
/// count drawn in `brandText` — so it cannot become a platform-styled button label.
///
/// The precedent this follows is `shelf_picker_popover.dart`'s
/// `showShelfPickerPopover`: an app-drawn card hung from an anchor's [RenderBox] rect,
/// with [LiquidGlassContainer] on iOS 26 and a [BackdropFilter] fallback, where
/// **Flutter draws every pixel of content and the platform supplies the material
/// behind it**. Read that file for the two wrong turns on the way to that division of
/// labour; none of it is repeated here. The one consequence worth restating, because
/// it is easy to undo by accident: **nothing opaque may be painted over the native
/// material** — the fill belongs to the fallback only.
///
/// It is also what makes this testable at all. `flutter test` reports Android, so
/// [useNativeGlass] is false there and the app-drawn path is the only one a widget
/// test ever takes.
///
/// ## Mirrored rather than shared, deliberately
///
/// This is a second anchored glass card, not a generalisation of the first. The two
/// differ in every decision that is not the material: the shelf picker right-aligns to
/// a tab pinned at a cover's margin where this left-aligns to a title at the sheet's
/// gutter; the shelf picker carries a heading because its rows are shelf *names* with
/// no verb among them where these two rows are imperative sentences; the shelf picker
/// caps its height and scrolls because a library can hold twenty shelves where this
/// has exactly two rows and always will; and the shelf picker chooses a side because
/// its anchor can sit anywhere in a scrolling library where this one cannot (below).
/// What is left to share is the clip, the glass, the shadow and the entrance — about
/// thirty lines — and extracting those means editing a file this change does not
/// otherwise touch. If a third anchored card ever appears, that extraction is the
/// thing to do, and `_card` below is the seam to lift.
Future<ReadSetFilter?> showReadSetFilterPopover(
  BuildContext context, {

  /// The title row. Its rect on screen is where the card is hung from, so this must be
  /// the render object of the thing the reader actually touched.
  required RenderBox anchor,
  required ReadSetFilter current,
}) {
  if (!anchor.attached || !anchor.hasSize) {
    return Future<ReadSetFilter?>.value();
  }

  final anchorRect = Rect.fromPoints(
    anchor.localToGlobal(Offset.zero),
    anchor.localToGlobal(anchor.size.bottomRight(Offset.zero)),
  );

  return Navigator.of(context, rootNavigator: true).push(
    ReadSetFilterPopupRoute(
      anchorRect: anchorRect,
      current: current,
      // Captured once here rather than read inside the route, which is built outside
      // the sheet's own tree and therefore outside its theme and locale.
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
    ),
  );
}

/// **The class name is load-bearing.** `ShellRouteObserver._isAnyModal` and the
/// package's own predicate both match a route whose runtime type name contains
/// `Popup`, and being a [PopupRoute] already satisfies the stricter of the two.
/// Renaming it to something without that substring would silently stop native glass
/// controls underneath — the year rail's selected capsule is one, directly below the
/// anchor — from standing down while this is up.
class ReadSetFilterPopupRoute extends PopupRoute<ReadSetFilter> {
  ReadSetFilterPopupRoute({
    required this.anchorRect,
    required this.current,
    required this.capturedThemes,
  });

  final Rect anchorRect;
  final ReadSetFilter current;
  final CapturedThemes capturedThemes;

  /// Short, and shorter than a sheet's: an anchored card has a much smaller distance
  /// to explain than something arriving from the bottom of the screen. Matched to the
  /// shelf picker's, so the app's two anchored cards arrive at one speed.
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
      _ReadSetFilterCard(
        anchorRect: anchorRect,
        current: current,
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

class _ReadSetFilterCard extends StatelessWidget {
  const _ReadSetFilterCard({
    required this.anchorRect,
    required this.current,
    required this.animation,
  });

  final Rect anchorRect;
  final ReadSetFilter current;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);

    // **Left-aligned with the title, which inverts the shelf picker's rule rather than
    // forgetting it.** That card right-aligns because its anchor is a tab pinned to the
    // right edge of a cover, so a left-aligned card would hang off toward the middle of
    // the screen from an object at the margin. This anchor is the opposite: a title at
    // the sheet's left gutter, with the row running the full width. Hanging the card
    // from the left edge puts it under the first word of the thing it is a read-out
    // for.
    final left = anchorRect.left
        .clamp(
          _kScreenInset,
          math.max(_kScreenInset, screen.width - _kWidth - _kScreenInset),
        )
        .toDouble();

    // **Always below, and there is no flip-above branch.** The shelf picker needs one
    // because its anchor is a tab that can sit anywhere in a scrolling library and its
    // list is as long as the reader's shelves. This anchor is the title of a sheet that
    // is *expanded* whenever the chevron exists at all — the chevron is drawn in no
    // other state — so there are hundreds of points below it, against a card whose
    // natural height is bounded at two single-purpose rows: ~97pt at the default text
    // scale and ~152 at 2x. Choosing a side would mean predicting that height, which
    // with wrapping rows is an estimate rather than a measurement.
    //
    // **The card covers the first few year capsules while it is up**, which is measured
    // in the drawing and accepted rather than designed away: it is what a menu hung
    // under a title does, and the rail is one dismissal away. It is also the second
    // reason the filter could not have gone on the rail's own row — the two would have
    // collided in geometry as well as in wording.
    final top = math.max(
      MediaQuery.paddingOf(context).top + _kScreenInset,
      anchorRect.bottom + _kAnchorGap,
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: _kWidth,
          // Grown from the corner nearest the title, so the card reads as coming out of
          // it rather than appearing beside it.
          child: _entrance(alignment: Alignment.topLeft, child: _card(context)),
        ),
      ],
    );
  }

  /// The arrival.
  ///
  /// **Deliberately modest on the native path**, and the reason is a platform-view
  /// limitation rather than taste: Flutter cannot apply opacity to a `UiKitView`, so a
  /// [FadeTransition] over the card would fade the rows while the glass behind them
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

  Widget _card(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // **No heading, where the shelf picker has one.** That card's rows are shelf
    // *names* — nouns with no verb among them — so without a heading the reader has to
    // infer the act from having tapped a shelf tab. These two rows are imperative
    // sentences that name both the act and its object, and a `Show` heading over
    // `Show finished only` would be the card explaining its own rows.
    final content = Material(
      // Transparent, purely so the rows' ink has a surface to splash on. A colour here
      // would paint over the material the whole card is standing on.
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterRow(
            label: l10n.showFinishedOnly,
            value: ReadSetFilter.finishedOnly,
            checked: current == ReadSetFilter.finishedOnly,
            last: false,
          ),
          _FilterRow(
            label: l10n.showAllRead,
            value: ReadSetFilter.allRead,
            checked: current == ReadSetFilter.allRead,
            last: true,
          ),
        ],
      ),
    );

    // **The native card's material is a contentless glass `CNButton` stretched behind the
    // rows, and it was a [LiquidGlassContainer].** A reader's verdict on that version was
    // that the dropdown "isn't glassy", and this app had already written down why, twice —
    // in `read_filter.dart` and in `adaptive_icon_button.dart`, both of which call
    // `LiquidGlassContainer` *the thing that does not work*. It renders a bare
    // `glassEffect(.regular)` layer with **no material of its own**, and glass refracts what
    // is behind it; behind this card is an opaque sheet that the platform view is composited
    // over, so there is nothing to refract and it comes out flat — no rim, no specular edge,
    // no shadow. `CNGlassEffect.prominent` would not have helped, because the plugin's Swift
    // pins `Glass.regular` either way.
    //
    // A glass `UIButton`'s material comes from its *button configuration* instead, which
    // carries the rim and the shadow whatever is behind it. So the visible content stays
    // Flutter's and the material is the platform's — the arrangement `read_filter._Capsule`
    // and `AdaptiveContentButton` already use, for exactly this reason.
    //
    // **`onPressed` is a no-op rather than null, and that is not sloppiness.** `CNButton`
    // sends `'enabled': (widget.enabled && widget.onPressed != null)`, so a null callback
    // disables the platform button and UIKit draws a *dimmed* material — the failure this
    // change is fixing, arrived at from the other direction. The [IgnorePointer] is what
    // makes it inert: `CNButton` hangs a `Listener` off the platform view to push
    // `isHighlighted` on pointer down, and its own tap recognizer otherwise joins the arena
    // and usually beats the row's. Neither is wanted on a menu — the whole card would flash
    // under a finger aimed at one row, and the wrong row might answer. This is the opposite
    // choice from `_Capsule`, which leaves its button interactive on purpose so a selected
    // pill presses like the glass button it is.
    final glass = useNativeGlass
        ? Stack(
            // **Not clipped, which is the second half of the fix.** A glass button's shadow
            // and rim are drawn *outside* its own box — `_Capsule`'s row reserves 3pt for
            // exactly that — so the `ClipRRect` this card used to wrap its material in was
            // cutting off the two things that make it read as glass. The rows are still
            // clipped, because their ink would otherwise splash past the corner arcs.
            clipBehavior: Clip.none,
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CNButton(
                    // No content. The rows above are Flutter's; this is here for the
                    // material alone.
                    label: '',
                    onPressed: () {},
                    config: const CNButtonConfig(
                      style: CNButtonStyle.glass,
                      // Null would mean a capsule, which on a 216×97 card is a 48pt arc
                      // instead of the drawing's 14.
                      borderRadius: _kRadius,
                      padding: EdgeInsets.zero,
                    ),
                    // **Off.** The default destroys the platform view whenever a modal is
                    // above this widget's host route, and this card *is* that modal —
                    // nothing above this route can ever need our glass gone, so the
                    // question is better not asked.
                    autoHideOnModal: false,
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(_kRadius),
                child: content,
              ),
            ],
          )
        : null;

    final clipped =
        glass ??
        ClipRRect(
          borderRadius: BorderRadius.circular(_kRadius),
          child: BackdropFilter(
            // The fallback, and it is a blur rather than glass: no rim highlight and
            // no specular edge, which is most of what the real material is.
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Low enough to let the sheet through, which is the whole point of
                // blurring it. The drawing sets white at 0.74 over a light sheet;
                // this is the same figure taken from the theme so the dark card is
                // not a white one.
                color: colors.surface.withValues(alpha: isDark ? 0.7 : 0.74),
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

    // The fallback's shadow, outside the clip or it is clipped away. The native path has
    // already returned its own unclipped stack above: a glass button brings a shadow with
    // it, and two would read as a smear.
    if (useNativeGlass) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: clipped,
    );
  }
}

/// One checkable row. The model is `shelf_picker_popover.dart`'s `_ShelfRow`; what
/// differs is where the check sits and why.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.value,
    required this.checked,
    required this.last,
  });

  final String label;
  final ReadSetFilter value;
  final bool checked;
  final bool last;

  /// Width of the check's slot, reserved in **both** rows.
  ///
  /// Held whether or not the row is checked, so the two labels start at the same x.
  /// Laid out only under the check, the unchecked label would sit 25pt to the left of
  /// the checked one and the whole card would shuffle sideways as the reader changed
  /// their mind about it.
  static const double _checkSlot = 16;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: () => Navigator.pop(context, value),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(
                  bottom: BorderSide(
                    color: colors.primaryText.withValues(alpha: 0.09),
                    width: 0.5,
                  ),
                ),
        ),
        child: ConstrainedBox(
          // A floor rather than a fixed extent, so a row grows with the text scale
          // instead of clipping. The shelf picker can use a fixed `itemExtent` because
          // its rows hold a shelf name it ellipsizes; these hold a sentence, and a
          // reader at 2x text is exactly the reader who needs to read it.
          constraints: const BoxConstraints(minHeight: _kRowMinHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              children: [
                // **Leading, where the shelf picker's is trailing.** There the check
                // follows a shelf's count, so the row reads name–count–check; here
                // there is nothing to the right of the label, and a check floated out
                // at the far edge of a card this wide reads as belonging to neither
                // row. It is also where iOS puts a menu item's check.
                SizedBox(
                  width: _checkSlot,
                  child: checked
                      ? Icon(Icons.check, size: 15, color: colors.brandText)
                      : null,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      color: colors.primaryText,
                    ),
                    // Wraps rather than ellipsizing. `Show finished only` fits the
                    // card's 216 with ~30pt to spare at the default scale and needs a
                    // second line somewhere past 1.2x, and two rows reading
                    // `Show finished…` / `Show all read` would have lost the word the
                    // choice turns on.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
