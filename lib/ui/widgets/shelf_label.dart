import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:bookworm_friends/ui/widgets/shelf_picker_popover.dart';

/// Hero tag for the tab naming the shelf with [shelfId].
///
/// Separate from `shelfHeroTag`: the tab and the plank are two objects that happen
/// to travel together, and one tag shared between them would be two heroes under
/// one name on the same route, which throws.
String shelfLabelHeroTag(String shelfId) => 'shelf_label_$shelfId';

/// The small "tab" that names the shelf a book sits on.
///
/// Renders nothing for an empty [label] so callers don't have to special-case
/// a book whose shelf can't be resolved. Long shelf names are capped and
/// ellipsized instead of running past the edge of the screen.
///
/// Pass [heroTag] — built with [shelfLabelHeroTag] — to fly the tab between routes
/// alongside the plank it sits on, so the shelf travels to the details page as one
/// thing rather than the plank sliding up and the name blinking into place.
///
/// A tab that renders nothing is never a hero, which is the whole handling of an
/// unresolvable shelf: no tab at one end means no partner, and the other end's tab
/// simply stays put instead of flying to or from a zero-sized box.
///
/// No `createRectTween`, unlike `BookWidget`. The tab shrink-wraps the same name at
/// both ends, so its two rects are the *same size* and differ only by the 20pt of
/// side padding the details header adds — and the default [MaterialRectArcTween]
/// carries two congruent rects along congruent arcs, so the size is preserved to
/// floating-point noise. Holding it fixed matters, hence the check rather than the
/// assumption: this box is squeezed onto its text, so a fraction of a point off and
/// the name ellipsizes mid-flight.
///
/// **[count] is part of that same contract, which is why it is not optional in
/// practice even though it is nullable.** A tab showing `IT 12` is wider than one
/// showing `IT`, so passing the count at one end of a flight and not the other
/// resizes the hero in the air — precisely the failure the paragraph above exists to
/// prevent. Both ends derive it from [shelvedBookCount] so they cannot disagree.
///
/// ## The tab is a door on the details page, and [showChevron] is how it says so
///
/// Tapping it opens the shelf picker, because `moveBookToShelf` otherwise has exactly
/// one caller — a long-press-then-drag across `ShelfRow` — which is workable on a
/// twelve-book library and not on a 473-book one. The tab is the right place for it
/// under the same rule that retired the app bar's pencil: the thing you tap to change
/// a fact is the fact itself.
///
/// **The count gives way to the chevron rather than sitting beside it.** Three things
/// in a box that is squeezed onto its text means a long shelf name ellipsizes sooner
/// against [maxWidth], and the count is not actually lost — the picker lists every
/// shelf with its own, where `금융 3` beside `소설 21` is finally a comparison rather
/// than a lone number.
///
/// **But the swap cannot be visible while the tab is flying, which is the whole of
/// [ShelfLabelDoor].** Measured in a browser at the app's own 13/w600: replacing the
/// count with a 16pt icon box moves the tab **+4.5pt in English and −6.7pt in
/// Korean** — not even in the same direction, because `bookCountLabel` is a bare
/// `{count}` in one and `{count}권` in the other. Either way the two ends of the
/// flight stop agreeing, and the flight in question is the one every *Interested*
/// book takes. So the details page renders the **count** until its route animation
/// has finished and crossfades to the chevron after. See [ShelfLabelDoor].
class ShelfLabel extends StatefulWidget {
  final String label;

  /// How many books stand on this shelf, drawn after the name.
  ///
  /// Null draws no count at all, which is what the details page wants for a shelf
  /// it could not resolve. Use [shelvedBookCount] to compute it; a count that
  /// counted finished books would disagree with the shelf the reader is looking
  /// at, since those are drawn in the read pile rather than on the plank.
  ///
  /// This is the whole reason the clip at the end of a long row means anything:
  /// without it a shelf showing three covers and a sliver is indistinguishable
  /// from a shelf of three and a rendering fault.
  final int? count;

  /// Widest the tab may grow before its text ellipsizes.
  final double maxWidth;

  final Object? heroTag;

  /// The name's own colour, for a tab that is not one the reader named.
  ///
  /// The Reading shelf sets it to `brandText`, because that shelf belongs to the app:
  /// its books were put there by their *status* rather than by a reader filing them, and
  /// the colour is what says so without a second word on the tab. Null takes the
  /// ambient text colour, which is what every reader-named shelf wants.
  ///
  /// Safe for the hero contract above in a way that a font change would not be: colour
  /// does not affect the box's measured width, so a tab that flies keeps its size even
  /// if the two ends were ever to disagree about this. (They cannot today — the Reading
  /// shelf flies nothing. See `ReadingShelfRow`.)
  final Color? labelColor;

  /// Draws `›` in the trailing slot instead of [count], marking the tab as a door.
  ///
  /// **Never true at both ends of a hero flight, and never true at only one end
  /// *during* one** — see the class doc and [ShelfLabelDoor]. A caller that is not a
  /// hero (the details page for a book that is reading or finished) may set it on the
  /// first frame.
  final bool showChevron;

  /// Opens the shelf picker **in Flutter**. Null everywhere except the owner's own
  /// details page — the library's tab is a rename target in edit mode and nothing in
  /// view mode, and a friend's shelves are not ours to move a book between — and null
  /// there too whenever [overlay] is carrying the gesture instead.
  ///
  /// **Never non-null at the same time as [overlay].** Both would put a tap recognizer
  /// in the arena for the same pointer, and only one of them can win: a tap that the
  /// Flutter detector took would swallow the menu the platform view was about to open.
  /// [ShelfLabelDoor] picks exactly one of the two.
  final VoidCallback? onTap;

  /// Stacked over the tab at its full size, to supply *behaviour* the tab does not
  /// draw. On iOS 26 this is a chrome-free [CNPopupMenuButton] whose only job is to
  /// hang a native `UIMenu` off a box Flutter painted.
  ///
  /// **Last child of the stack, so it is hit-tested first.** Underneath — the division
  /// of labour `read_filter.dart`'s `_Capsule` uses, where the platform view supplies a
  /// *material* — the tab's own `Text` would win the hit test wherever the glyphs are,
  /// and `RenderStack` stops at the first child that reports one. Tapping the shelf's
  /// name, i.e. the middle of the target, would then do nothing at all.
  ///
  /// The cheap direction for composition, too: Flutter content *under* a platform view
  /// composites normally, and only content drawn over one has to be lifted into overlay
  /// quads.
  final Widget? overlay;

  const ShelfLabel({
    super.key,
    required this.label,
    this.count,
    this.maxWidth = 140,
    this.heroTag,
    this.labelColor,
    this.showChevron = false,
    this.onTap,
    this.overlay,
  }) : assert(
         onTap == null || overlay == null,
         'One gesture, one owner: see ShelfLabel.onTap.',
       );

  /// Whether this tab is a door at all, in either of the two ways it can be one.
  ///
  /// Drives the press response and the `button` semantics, which belong to the tab
  /// rather than to whichever of the two opened the menu — the native path draws no
  /// chrome of its own and an empty `UIButton` has no accessible name to offer.
  bool get _isDoor => onTap != null || overlay != null;

  @override
  State<ShelfLabel> createState() => _ShelfLabelState();
}

class _ShelfLabelState extends State<ShelfLabel> {
  /// Held from raw pointer events rather than from a tap recognizer, for the same
  /// reason `_Capsule` does: on the native path the platform view's own recognizer
  /// takes the gesture, so `onTapDown` would never fire and the tab would answer a
  /// thumb with nothing. Raw pointers arrive either way.
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed || !widget._isDoor) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) return const SizedBox.shrink();

    final Widget tab = Container(
      // No `alignment` here: a Container with an alignment expands to fill the
      // space it is offered, which stretched the tab across the cover. Without
      // it the tab shrink-wraps its label, as it does in the library.
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      decoration: BoxDecoration(
        // Toward the band without reaching it, the same blend and the same 0.63 the
        // period card presses to, so the two doors on this header answer a thumb the
        // same way. The tab sits on `surfaceVariant`, so it must not darken to it.
        color: _pressed
            ? Color.lerp(
                context.colors.surface,
                context.colors.surfaceVariant,
                0.63,
              )
            : context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          topRight: Radius.circular(3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      // A Row rather than one `Text.rich`, so that the *name* is what gives way
      // when the tab hits [maxWidth]. In a single text run the count trails the
      // name and is therefore the first thing an ellipsis eats — which would drop
      // the only new information on the tab exactly on the long-named shelves
      // where it is most useful.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.label,
              // A `const` token rather than a literal, and the constness is
              // load-bearing here rather than tidiness: the hero contract above
              // depends on this tab measuring the *same* width at both ends of
              // the flight. Two call sites spelling out 14/bold could drift
              // apart; one token cannot.
              style: widget.labelColor == null
                  ? AppTextStyles.label
                  : AppTextStyles.label.copyWith(color: widget.labelColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // One slot, two possible occupants, swapped with a fade. The fade is not
          // decoration: it is what makes the count-to-chevron handoff survivable
          // once the tab has landed, and it is deliberately *not* wrapped in an
          // `AnimatedSize` — the switcher's own layout builder already stacks the
          // outgoing and incoming children, so the box holds the wider of the two
          // for the duration instead of stepping twice.
          if (_trailing(context) case final trailing?) ...[
            const SizedBox(width: 5),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: trailing,
            ),
          ],
        ],
      ),
    );

    Widget gated = widget.overlay == null
        ? tab
        : Stack(
            // Passthrough so the tab still sizes the box — it is squeezed onto its
            // text and the hero contract above depends on that staying true — and
            // `Positioned.fill` stretches the overlay to whatever that came to,
            // with no intrinsic-size round trip to wait for.
            fit: StackFit.passthrough,
            children: [
              tab,
              Positioned.fill(child: widget.overlay!),
            ],
          );

    if (widget._isDoor) {
      gated = Semantics(
        button: true,
        // The tab's own text is the name of the shelf, which is the value
        // rather than the action, so the action is stated here. Without it
        // VoiceOver announces a shelf name and nothing about what happens.
        label: AppLocalizations.of(context).moveToShelf,
        value: widget.label,
        child: gated,
      );

      if (widget.onTap case final onTap?) {
        gated = GestureDetector(
          // Opaque, or the tab's 9pt of horizontal padding is a dead zone: a
          // `Container` with a decoration hit-tests through itself, so a bare
          // `deferToChild` target is only as wide as the glyphs inside it.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: gated,
        );
      }

      gated = Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: gated,
      );
    }

    final tag = widget.heroTag;
    if (tag == null) return gated;
    return Hero(tag: tag, child: gated);
  }

  /// The trailing slot: a chevron, a count, or nothing.
  ///
  /// Keyed, because an `AnimatedSwitcher` compares children by `Widget.canUpdate`
  /// and two `Text`s would otherwise be considered the same child — which is what
  /// makes a count *change* animate too, and is why the key carries the value.
  Widget? _trailing(BuildContext context) {
    if (widget.showChevron) {
      return Icon(
        Icons.chevron_right,
        // 16 rather than the 20 the band's rows carry. The tab is 23pt tall, and a
        // 20pt glyph in it reads as a button rather than as a disclosure.
        size: 16,
        color: context.colors.secondaryText,
        key: const ValueKey('chevron'),
      );
    }
    final count = widget.count;
    if (count == null) return null;
    return Text(
      // Localised rather than `'$count'`: Korean counts books with a
      // counter word, so this renders `12` in English and `12권` in
      // Korean. A bare number would read as a fragment there.
      AppLocalizations.of(context).bookCountLabel(count),
      key: ValueKey('count_$count'),
      style: AppTextStyles.label.copyWith(color: context.colors.secondaryText),
      maxLines: 1,
    );
  }
}

/// A [ShelfLabel] that becomes a door **after** it has finished flying, and opens the
/// platform's own menu when the platform has one.
///
/// ## Why the swap waits
///
/// The tab travels from the library to the book-details page as a [Hero], and
/// Flutter's default flight shuttle is the *destination* hero's child. So a details
/// tab that renders its chevron on the first frame hands the flight a box of the
/// wrong width: the shuttle is laid out against the source rect at the start of the
/// journey and the destination rect at the end, and this box is squeezed onto its
/// text, so the shelf name ellipsizes in mid-air. The delta is small and the
/// direction is not even stable across locales — the figures are in [ShelfLabel]'s
/// doc — which is exactly why it is handled rather than eyeballed.
///
/// So: [count] while the route is still arriving, chevron once it has arrived, faded
/// between by the switcher in [ShelfLabel]. The tab hangs off a
/// `Positioned(bottom: 0, right: 0)`, so whichever way the width moves it moves
/// leftward over the cover and nothing reflows.
///
/// **Not gated on whether this particular tab is a hero.** A book that is reading or
/// finished does not fly its shelf (`flyShelfFromLibrary`), so it could show the
/// chevron immediately — but reading the route's animation costs nothing, gives the
/// same answer within one transition either way, and keeps one rule instead of two.
///
/// ## The menu is the platform's, drawn off furniture that is ours
///
/// On iOS 26 this is the same control the settings page's *Edit profile* button is —
/// a [CNPopupMenuButton] presenting a real `UIMenu`, with the platform's glass, its
/// entrance, its checkmarks and its dismissal. The difference is that the tab must go
/// on being a top-rounded paper tab and a [Hero], and a `CNPopupMenuButton` draws its
/// own button. So the button is asked for **no chrome at all** —
/// `buttonStyle: CNButtonStyle.plain` with an empty label — and stacked over the tab
/// through [ShelfLabel.overlay]: Flutter paints every pixel, the platform supplies
/// only the behaviour. That is the inverse of `read_filter.dart`'s `_Capsule`, where
/// the platform view under the label supplies only the material.
///
/// Three conditions gate it, and each one is a real failure if dropped:
///
///  * **[useNativeGlass]**, because off iOS 26 `CNPopupMenuButton` falls back to a
///    `CupertinoActionSheet` — a full-width sheet from the bottom of the screen, which
///    is not what a tab in a header should open, and which would arrive with no
///    chrome to have been tapped.
///  * **Landed**, the same gate as the chevron: a `UiKitView` inside a flying [Hero]
///    is a platform view being moved and rescaled by Flutter's overlay compositor,
///    which is exactly the case hybrid composition handles worst. It is withdrawn
///    again the moment the route starts to leave — hence the status listener, which
///    catches a pop a frame sooner than a value listener would.
///  * **Uncovered**, via [ModalCoverBuilder]: this page presents the status sheet and
///    the store sheet over itself, and a live platform view under a Flutter sheet
///    leaks its own rectangle through the scrim and stays tappable behind it.
///
/// When any of the three says no, [showShelfPickerPopover] answers the tap instead —
/// an app-drawn card anchored to the tab, with a `BackdropFilter` where the glass
/// would be. It is also the only path a widget test ever takes, because `flutter test`
/// reports Android.
class ShelfLabelDoor extends StatefulWidget {
  const ShelfLabelDoor({
    super.key,
    required this.label,
    required this.count,
    required this.shelves,
    required this.currentShelfId,
    required this.onPicked,
    this.heroTag,
  });

  final String label;

  /// What the tab shows until the route has landed, and what the library's tab shows
  /// always. Null only for a shelf that could not be resolved, where the label is
  /// empty too and nothing is drawn.
  final int? count;

  /// Every shelf the book could be moved to, in the library's own order, *including*
  /// the one it is on — which is drawn checked. A menu that refuses the row it has
  /// ticked reads as broken.
  final List<Shelf> shelves;

  final String currentShelfId;

  /// The chosen shelf, and only ever a different one: picking the current shelf is a
  /// legal answer that means nothing, and is swallowed here rather than at the call
  /// site so both presentations agree about it.
  final ValueChanged<Shelf> onPicked;

  final Object? heroTag;

  @override
  State<ShelfLabelDoor> createState() => _ShelfLabelDoorState();
}

class _ShelfLabelDoorState extends State<ShelfLabelDoor> {
  /// The route's own arrival animation, or null when there is no route — a widget
  /// test pumping this bare, for instance.
  Animation<double>? _arrival;

  /// **Starts false, and that is the correction.** Reading the status during the
  /// route's first build says `completed` even for a route that has not begun to
  /// arrive: `ModalRoute.animation` is a `ProxyAnimation` whose parent is still
  /// `kAlwaysCompleteAnimation` at that point, and it is handed the real controller
  /// afterwards. Trusting it drew the chevron for exactly one frame — the frame the
  /// hero flight takes the destination child's measurements from.
  ///
  /// So the answer is deferred to the first post-frame callback instead, by which time
  /// the proxy is telling the truth. The cost is that a tab which really is landed
  /// shows its count for one frame before swapping; that is invisible in the page
  /// transition it always happens inside, and the `State` outlives the rebuilds a
  /// shelf change causes — same widget type in the same slot — so the swap does not
  /// re-run and does not flicker.
  bool _landed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolved here rather than in `initState`, where `ModalRoute.of` is not yet
    // available, and re-resolved on every dependency change because the route can
    // change under a widget that is moved between navigators.
    final next = ModalRoute.of(context)?.animation;
    if (next == _arrival) return;
    _detach();
    _arrival = next;
    if (next == null) {
      // Nothing to wait for and nothing to be wrong about.
      _landed = true;
      return;
    }
    next.addListener(_onArrival);
    // **And a status listener as well, for the journey back.** The value listener is
    // what notices the arrival finishing; a pop changes the status to `reverse` and
    // only *then* starts ticking values, so on the value listener alone the platform
    // view would still be mounted for the first frame of a hero flying home.
    next.addStatusListener(_onArrivalStatus);
    _landed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onArrival();
    });
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    _arrival?.removeListener(_onArrival);
    _arrival?.removeStatusListener(_onArrivalStatus);
  }

  void _onArrivalStatus(AnimationStatus _) => _onArrival();

  void _onArrival() {
    final landed = _arrival?.status == AnimationStatus.completed;
    if (landed == _landed || !mounted) return;
    setState(() => _landed = landed);
  }

  /// Reports a chosen shelf, unless it is the one the book is already on.
  ///
  /// `moveBookToShelf` no-ops on that case anyway; stopping here keeps the page from
  /// claiming a move happened when the reader only confirmed where the book was.
  void _pick(Shelf shelf) {
    if (shelf.id == widget.currentShelfId) return;
    widget.onPicked(shelf);
  }

  /// The app-drawn card, for every path that has no `UIMenu` to offer.
  Future<void> _openPopover() async {
    final anchor = context.findRenderObject() as RenderBox?;
    if (anchor == null) return;
    final target = await showShelfPickerPopover(
      context,
      anchor: anchor,
      shelves: widget.shelves,
      currentShelfId: widget.currentShelfId,
    );
    if (target != null) _pick(target);
  }

  /// The native menu: a `UIMenu` on a button with nothing drawn in it.
  Widget _menu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CNPopupMenuButton(
      // Nothing to draw. The tab under this is the whole of what the reader sees, and
      // an empty `.plain()` configuration paints neither background nor title.
      buttonLabel: '',
      buttonStyle: CNButtonStyle.plain,
      // Read in the library's order, top to bottom, whichever way the menu opens. The
      // platform's default keeps the first item nearest the button, which for a list
      // that mirrors a vertical order elsewhere in the app would reverse it whenever
      // the header has been scrolled down the screen.
      preserveTopToBottomOrder: true,
      items: [
        for (final shelf in widget.shelves)
          CNPopupMenuItem(
            // The count rides inside the label because a `UIMenu` item has no
            // subtitle and no trailing slot — `CNPopupMenuItem` carries a label, an
            // icon and a checkmark, and that is all. It has to be here somewhere:
            // giving it up is what bought the tab its chevron, and `금융 (3)` beside
            // `소설 (21)` is the comparison a lone number on the tab never was.
            label: l10n.shelfWithCount(
              shelf.name,
              l10n.bookCountLabel(shelvedBookCount(shelf)),
            ),
            checked: shelf.id == widget.currentShelfId,
          ),
      ],
      // Indexes into the same list the items came from, so the two can never
      // disagree about what a position means — including under
      // `preserveTopToBottomOrder`, which reverses the *display* order and leaves
      // each action's index with it.
      onSelected: (index) => _pick(widget.shelves[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModalCoverBuilder(
      builder: (context, covered) {
        final native = _landed && useNativeGlass && !covered;
        return ShelfLabel(
          label: widget.label,
          // The load-bearing line: the count is what the flight measures against, so
          // it stays until the flight is over.
          count: _landed ? null : widget.count,
          showChevron: _landed,
          // Exactly one of these two, never both — see [ShelfLabel.onTap]. A tab that
          // has not landed is inert: it does not show a chevron yet either.
          onTap: _landed && !native ? _openPopover : null,
          overlay: native ? _menu(context) : null,
          heroTag: widget.heroTag,
        );
      },
    );
  }
}
