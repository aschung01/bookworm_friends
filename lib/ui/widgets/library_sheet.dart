import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'package:bookworm_friends/constants/app_theme.dart';

/// The bottom sheet that sits above the library, pinned to the bottom of the
/// screen (e.g. as the last child of a [Column] whose other child is an
/// [Expanded] library).
///
/// This widget owns only the *chrome and the motion*; what it shows is passed
/// in. That split exists because the shell gives every tab its own sheet over
/// one shared library background: the drag handle, the corner radius, the
/// shadow, the home-indicator inset, the two snap positions and the spring must
/// be identical on all of them, and duplicating a spring is how tabs drift apart.
///
/// [header] is the row that survives a collapse — it defines the collapsed snap
/// position, so it should stay a fixed-height row. [body] is everything the
/// collapse hides.
///
/// The sheet snaps between two positions:
/// * expanded — the content's natural height, i.e. exactly tall enough to show
///   [header] and [body].
/// * collapsed — only the drag handle and [header] stay visible.
///
/// Motion is a genuine under-damped spring, so it overshoots the target and
/// settles back, and it can be overdragged past either position with
/// rubber-band resistance.
///
/// Because the sheet reports its (possibly collapsed) height to its parent, the
/// library above is laid out in whatever space is left over: the sheet is always
/// fully visible without scrolling to the bottom of the page, and the library
/// grows as the sheet is dragged down.
class LibrarySheet extends StatefulWidget {
  /// The row kept visible when collapsed, drawn below the drag handle and inset
  /// to the sheet's horizontal gutter. Its height *is* the collapsed snap
  /// position.
  final Widget header;

  /// Shown when expanded, hidden by a collapse. Laid out at its natural height;
  /// it is clipped rather than squeezed, so it must not be scrollable in the
  /// vertical axis.
  final Widget body;

  /// While the library is being edited the sheet springs shut to get out of the
  /// way and goes inert (no dragging, no tapping the handle), then springs back
  /// to wherever it was when editing ends.
  ///
  /// Interactive controls *inside* [header] and [body] are the caller's to gate:
  /// children win hit tests, so this widget cannot disable them from outside.
  final bool isEditMode;

  /// Extra room left empty at the bottom, for chrome that floats over the sheet
  /// — in the shell, the tab bar (`ShellTabBar.reserve`).
  ///
  /// Reserved *inside* the sheet rather than by insetting the floating widget,
  /// because the sheet is what would otherwise be covered: at the collapsed snap
  /// position the header is all that is left, and a bar floating over the bottom
  /// edge would land straight on it.
  ///
  /// Additive with the home-indicator inset, which is always reserved.
  final double bottomReserve;

  const LibrarySheet({
    super.key,
    required this.header,
    required this.body,
    this.isEditMode = false,
    this.bottomReserve = 0,
  });

  @override
  State<LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends State<LibrarySheet>
    with SingleTickerProviderStateMixin {
  /// Velocity (px/s) above which a drag is treated as a fling instead of
  /// snapping to the nearest position.
  static const double _flingVelocity = 220;

  static const double _cornerRadius = 20;

  /// Horizontal gutter shared by the header and, by convention, by bodies — so
  /// a tab switch does not shift the title sideways.
  static const double _gutter = 25;

  /// Fraction of a drag that still moves the sheet once it is past a snap
  /// position, i.e. how rubbery it feels when overdragged.
  static const double _overdragResistance = 0.35;

  /// Under-damped on purpose: a ratio of ~0.55 overshoots by ~12%, which is the
  /// visible bounce. Anything above ~0.75 overshoots by single-digit pixels and
  /// just reads as a fast ease.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.55,
  );

  final _contentKey = GlobalKey();
  final _headerKey = GlobalKey();

  /// Unbounded because the simulation animates the sheet's height in pixels and
  /// is allowed to overshoot past both snap positions.
  late final AnimationController _snapController;

  /// Height of the visible slice of content, or `null` while fully expanded —
  /// letting the content size itself keeps the sheet correct when the body, the
  /// header labels or the text scale changes.
  double? _clipHeight;

  /// How far the whole sheet is pushed below its resting position. Used instead
  /// of shrinking below [_minHeight] so an undershoot slides the sheet off the
  /// bottom of the screen rather than cutting the header in half.
  double _slideDown = 0;

  /// Drag position before overdrag resistance is applied.
  double _rawTravel = 0;

  bool _isExpanded = true;

  /// Remembered across an edit-mode round trip so leaving edit mode doesn't
  /// override a sheet the user had deliberately collapsed.
  bool _expandedBeforeEdit = true;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController.unbounded(vsync: this)
      ..addListener(_onSnapTick)
      ..addStatusListener(_onSnapStatus);
  }

  @override
  void didUpdateWidget(LibrarySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditMode != oldWidget.isEditMode) {
      if (widget.isEditMode) _expandedBeforeEdit = _isExpanded;
      final expand = widget.isEditMode ? false : _expandedBeforeEdit;
      // Deferred so the snap positions are measured against the layout that
      // this build produces, and so no setState happens mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _snapTo(expand: expand);
      });
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  double _measure(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    return box.size.height;
  }

  /// Natural content height — the sheet's expanded snap position.
  double get _maxHeight => _measure(_contentKey);

  /// Handle + header height — the sheet's collapsed snap position.
  double get _minHeight {
    final max = _maxHeight;
    final min = _measure(_headerKey);
    if (max <= 0 || min <= 0) return max;
    return min > max ? max : min;
  }

  /// Current position of the sheet's top edge, expressed as a height. May sit
  /// outside `[_minHeight, _maxHeight]` while bouncing or being overdragged.
  double get _travel => (_clipHeight ?? _maxHeight) - _slideDown;

  /// Splits [travel] into a clip height and, when it undershoots, a downwards
  /// slide. Overshoot above the natural height simply stretches the box: the
  /// content is top-anchored, so it rises and the extra white is invisible
  /// against the sheet.
  void _setTravel(double travel) {
    final min = _minHeight;
    setState(() {
      if (travel < min) {
        _clipHeight = min;
        _slideDown = min - travel;
      } else {
        _clipHeight = travel;
        _slideDown = 0;
      }
    });
  }

  void _onSnapTick() {
    if (_maxHeight <= 0) return;
    _setTravel(_snapController.value);
  }

  void _onSnapStatus(AnimationStatus status) {
    // Hand height control back to the content once fully settled open.
    if (status == AnimationStatus.completed && _isExpanded) {
      setState(() {
        _clipHeight = null;
        _slideDown = 0;
      });
    }
  }

  /// Springs the sheet to one of its two snap positions, carrying [velocity]
  /// (px/s, positive = downwards) over from the gesture that triggered it.
  void _snapTo({required bool expand, double velocity = 0}) {
    final max = _maxHeight;
    final min = _minHeight;
    if (max <= 0 || min >= max) return;

    _isExpanded = expand;
    final from = _travel;
    final to = expand ? max : min;
    if ((from - to).abs() < 0.5 && velocity.abs() < 1) {
      _snapController.stop();
      setState(() {
        _clipHeight = expand ? null : to;
        _slideDown = 0;
      });
      return;
    }
    // Drag velocity is in screen space (down = positive) while the simulation
    // animates height (down = shrinking), hence the sign flip.
    _snapController.animateWith(SpringSimulation(_spring, from, to, -velocity));
  }

  void _onDragStart(DragStartDetails details) {
    _snapController.stop();
    _rawTravel = _travel;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final max = _maxHeight;
    if (max <= 0) return;
    final min = _minHeight;
    _rawTravel -= details.delta.dy;
    // Rubber-band past either snap position instead of hitting a hard stop.
    final travel = _rawTravel > max
        ? max + (_rawTravel - max) * _overdragResistance
        : _rawTravel < min
        ? min - (min - _rawTravel) * _overdragResistance
        : _rawTravel;
    _setTravel(travel);
  }

  void _onDragEnd(DragEndDetails details) {
    final max = _maxHeight;
    if (max <= 0) return;
    final min = _minHeight;
    final velocity = details.primaryVelocity ?? 0;
    final expand = velocity.abs() > _flingVelocity
        ? velocity < 0
        : _travel >= (min + max) / 2;
    _snapTo(expand: expand, velocity: velocity);
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    final clipHeight = _clipHeight;
    // Pinned shut while the library is being edited.
    final interactive = !widget.isEditMode;
    const radius = BorderRadius.vertical(top: Radius.circular(_cornerRadius));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: interactive ? _onDragStart : null,
      onVerticalDragUpdate: interactive ? _onDragUpdate : null,
      onVerticalDragEnd: interactive ? _onDragEnd : null,
      // Undershoot slides the sheet off the bottom of the screen, revealing the
      // library behind it, rather than shrinking it below the collapsed height.
      child: Transform.translate(
        offset: Offset(0, _slideDown),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                blurRadius: 6,
                offset: const Offset(0, -3),
                color: Colors.black.withValues(alpha: 0.15),
              ),
            ],
          ),
          child: Padding(
            // Reserved outside the collapsible area so the handle and header
            // never sit under the home indicator.
            padding: EdgeInsets.only(
              bottom:
                  MediaQuery.viewPaddingOf(context).bottom +
                  widget.bottomReserve,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: clipHeight == null
                  ? content
                  : SizedBox(
                      height: clipHeight,
                      // Keeps the content at its natural height while the box
                      // shrinks, so the overflow is simply clipped away.
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: content,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final interactive = !widget.isEditMode;
    return KeyedSubtree(
      key: _contentKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            key: _headerKey,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: interactive ? () => _snapTo(expand: !_isExpanded) : null,
                child: const SheetGrabHandle(),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: _gutter,
                  right: _gutter,
                  bottom: 6,
                ),
                child: widget.header,
              ),
            ],
          ),
          widget.body,
        ],
      ),
    );
  }
}

/// The grab handle at the top of a sheet.
///
/// Shared with the Add Book modal, which draws its own rather than using
/// Material's `showDragHandle`: that one is added outside the builder's child, so
/// it silently adds its height to a sheet asked for an exact fraction of the
/// screen — a 95% sheet came out at ~98% with no barrier left to see.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: context.colors.secondaryText,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// The title-and-count pair every sheet header opens with, so the three tabs
/// share one type size and one spacing rather than three approximations of it.
class LibrarySheetTitle extends StatelessWidget {
  final String title;

  /// Drawn in the brand colour beside [title]. Omitted when there is nothing to
  /// count (the Card tab).
  final int? count;

  const LibrarySheetTitle({super.key, required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 18);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible, not fixed: at accessibility text sizes an 18pt bold title
        // plus whatever sits beside it in the header overflowed the row outright.
        Flexible(
          child: Text(
            title,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 12),
          Text(
            '$count',
            style: style.copyWith(color: context.colors.brandText),
          ),
        ],
      ],
    );
  }
}
