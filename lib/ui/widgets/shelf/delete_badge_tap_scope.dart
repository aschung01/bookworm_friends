import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Takes the tap for a [DeleteBookBadge] anywhere the badge is **drawn**, rather than
/// only where its ancestors' boxes happen to overlap it.
///
/// **The defect this exists for: three quarters of every remove badge did nothing, and
/// the tap it swallowed ended the edit.** A badge is pinned `-halfTarget` outside its
/// book so the disc straddles the cover's corner, iOS-style. Flutter's
/// `RenderBox.hitTest` bounds-checks its own box *before* descending to children, so a
/// child painted outside its ancestors is unreachable: `Clip.none` buys paint, never hit
/// testing. The live area was the intersection with the cover — a 22pt square — with the
/// disc's own centre sitting exactly on its boundary, so aiming at the middle of what is
/// drawn was a coin flip. Misses fell through to the page-level `GestureDetector` in
/// `home_page.dart`, whose job is to end an edit, so the dead three quarters behaved as a
/// *Done* button.
///
/// **Why this is a gesture-level fix and not a layout one.** Every box between the disc
/// and the page rejects the overhang, and the two that matter cannot be opted out of:
/// `LongPressDraggable`'s own `RenderPointerListener` and the tile's `RenderStack`, both
/// exactly the book's size. Reparenting the badge above the draggable reaches the slot,
/// which buys `kShelfSlotMargin` (7.5pt) sideways and `bookRowExtent`'s jitter reserve
/// (~8pt, and zero for a book that hashed tall) upward — short of 22 in both axes. And
/// nothing *inside* the row can recover the rest, because the row is a horizontal
/// `ListView`: `RenderSliver.hitTest` rejects any cross-axis position outside the row's
/// extent, so the top of a corner-centred badge is unreachable from any level below the
/// page. The alternatives were to grow every row by 22pt in edit mode — the library
/// visibly changing shape on entering an edit — or to move the disc onto the cover, which
/// is a redrawing rather than a fix. (`RenderTransform` skips its own bounds check by
/// design, so neither `Wiggle` nor the slot's parting translate was ever at fault.)
///
/// **So the scope sits at the page, where the whole badge is inside the box, and asks the
/// badges themselves.** A tap is matched by transforming the pointer into each registered
/// badge's own coordinate space, which follows the wiggle exactly rather than approximating
/// it with a rect. A pointer that lands on no badge is never even added to the arena, so
/// every other gesture on the page — the background tap that ends the edit, the hold that
/// lifts a book, the pane's scroll — behaves exactly as it did.
///
/// Three things to know before changing it:
///
/// - **The badge keeps its own `GestureDetector` as well.** Depth decides the arena, so
///   inside the cover the badge's own detector wins, and it has to exist: a cover in edit
///   mode carries an empty `onTap` whose whole job is to swallow taps so they do not reach
///   the page, and that detector is deeper than this scope. Two hit paths, one callback.
/// - **It must not accept the arena eagerly.** Claiming at pointer-down would beat the
///   long-press draggable underneath and make the badge's corner of the cover the one
///   place a book cannot be picked up from. It wins by being deeper than the page's
///   detector at sweep, which is enough.
/// - **One residual dead sliver, by the same rule.** Where a badge's 44pt box overhangs
///   the *neighbouring* cover — up to 7pt of it, since covers stand 15pt apart — that
///   cover's swallowing tap is deeper and wins. The disc reaches only 11pt out, so what a
///   reader aims at is clear of it by 4pt.
class DeleteBadgeTapScope extends StatefulWidget {
  const DeleteBadgeTapScope({super.key, required this.child});

  final Widget child;

  /// The registry to register a badge with, or null outside a scope.
  ///
  /// Null is a working configuration rather than an error: the badge keeps the hit area
  /// its own box gives it, which is what every widget test that pumps a bare row sees.
  static DeleteBadgeTapRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DeleteBadgeTapScopeMarker>()
      ?.registry;

  @override
  State<DeleteBadgeTapScope> createState() => _DeleteBadgeTapScopeState();
}

/// What the scope needs from a badge: where it is, and what to run.
abstract class DeleteBadgeTapTarget {
  /// The badge's own render box, or null while it is not laid out.
  RenderBox? get badgeBox;

  /// The badge's action, or null for a badge that is drawn but not live.
  VoidCallback? get onBadgeTap;
}

/// The badges currently on screen, in registration order.
class DeleteBadgeTapRegistry {
  final List<DeleteBadgeTapTarget> _targets = <DeleteBadgeTapTarget>[];

  void add(DeleteBadgeTapTarget target) {
    if (!_targets.contains(target)) _targets.add(target);
  }

  void remove(DeleteBadgeTapTarget target) => _targets.remove(target);

  /// The badge drawn under [globalPosition], or null.
  ///
  /// Matched by transforming the point into each badge's own space rather than by
  /// comparing rects, so a wiggling badge is hit where it is *drawn* at that instant.
  /// Newest first, which only matters if two badges ever overlap; none do — covers stand
  /// 15pt apart and a spine's badge is no wider than its spine.
  DeleteBadgeTapTarget? hitTest(Offset globalPosition) {
    for (final target in _targets.reversed) {
      if (target.onBadgeTap == null) continue;
      final box = target.badgeBox;
      if (box == null) continue;
      if (box.size.contains(box.globalToLocal(globalPosition))) return target;
    }
    return null;
  }
}

class _DeleteBadgeTapScopeState extends State<DeleteBadgeTapScope> {
  final DeleteBadgeTapRegistry _registry = DeleteBadgeTapRegistry();

  @override
  Widget build(BuildContext context) {
    return _DeleteBadgeTapScopeMarker(
      registry: _registry,
      child: RawGestureDetector(
        // Translucent, so the recogniser is offered every pointer that lands in the scope
        // — the whole page — instead of only those a child claims. It filters to badges
        // itself; see [_BadgeTapRecognizer.isPointerAllowed].
        behavior: HitTestBehavior.translucent,
        // The badge carries its own `Semantics` with its own label and action. Without
        // this, the scope would add a screen-sized tappable node over the page.
        excludeFromSemantics: true,
        gestures: <Type, GestureRecognizerFactory>{
          _BadgeTapRecognizer:
              GestureRecognizerFactoryWithHandlers<_BadgeTapRecognizer>(
                () => _BadgeTapRecognizer(_registry, debugOwner: this),
                (_) {},
              ),
        },
        child: widget.child,
      ),
    );
  }
}

class _DeleteBadgeTapScopeMarker extends InheritedWidget {
  const _DeleteBadgeTapScopeMarker({
    required this.registry,
    required super.child,
  });

  final DeleteBadgeTapRegistry registry;

  @override
  bool updateShouldNotify(_DeleteBadgeTapScopeMarker oldWidget) =>
      registry != oldWidget.registry;
}

/// A tap recogniser that only enters the arena for a pointer that went down on a badge.
///
/// [isPointerAllowed] is the whole mechanism: a recogniser that declined the pointer is
/// never added, so on every other tap the page behaves as though this scope were not
/// there. The badge is resolved again on release rather than remembered from the press,
/// so a finger that slides off a badge before lifting removes nothing.
class _BadgeTapRecognizer extends TapGestureRecognizer {
  _BadgeTapRecognizer(this._registry, {super.debugOwner}) {
    onTapUp = _handleTapUp;
  }

  final DeleteBadgeTapRegistry _registry;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (_registry.hitTest(event.position) == null) return false;
    return super.isPointerAllowed(event);
  }

  void _handleTapUp(TapUpDetails details) {
    _registry.hitTest(details.globalPosition)?.onBadgeTap?.call();
  }
}
