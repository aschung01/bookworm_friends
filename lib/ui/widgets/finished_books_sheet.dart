import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

/// Bottom-sheet style "Books read" panel, meant to be pinned to the bottom of
/// the library (e.g. as the last child of a [Column] whose other child is an
/// [Expanded] library).
///
/// The sheet snaps between two positions:
/// * expanded — the content's natural height, i.e. exactly tall enough to show
///   every child.
/// * collapsed — only the drag handle and the title row stay visible.
///
/// Motion is a genuine under-damped spring, so it overshoots the target and
/// settles back, and it can be overdragged past either position with
/// rubber-band resistance.
///
/// Because the sheet reports its (possibly collapsed) height to its parent, the
/// library above is laid out in whatever space is left over: the panel is always
/// fully visible without scrolling to the bottom of the page, and the library
/// grows as the sheet is dragged down.
class FinishedBooksSheet extends StatefulWidget {
  final List<Book> books;

  /// While the library is being edited the sheet springs shut to get out of the
  /// way and goes inert (no dragging, no tapping), then springs back to wherever
  /// it was when editing ends.
  final bool isEditMode;
  final int filterYear;
  final int filterMonth;
  final VoidCallback onFilterPressed;

  const FinishedBooksSheet({
    super.key,
    required this.books,
    required this.isEditMode,
    required this.filterYear,
    required this.filterMonth,
    required this.onFilterPressed,
  });

  @override
  State<FinishedBooksSheet> createState() => _FinishedBooksSheetState();
}

class _FinishedBooksSheetState extends State<FinishedBooksSheet>
    with SingleTickerProviderStateMixin {
  /// Velocity (px/s) above which a drag is treated as a fling instead of
  /// snapping to the nearest position.
  static const double _flingVelocity = 220;

  static const double _cornerRadius = 20;

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
  /// letting the content size itself keeps the sheet correct when the book list,
  /// the filter label or the text scale changes.
  double? _clipHeight;

  /// How far the whole sheet is pushed below its resting position. Used instead
  /// of shrinking below [_minHeight] so an undershoot slides the sheet off the
  /// bottom of the screen rather than cutting the title in half.
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
  void didUpdateWidget(FinishedBooksSheet oldWidget) {
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

  /// Handle + title row height — the sheet's collapsed snap position.
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

  String _filterText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.filterYear == 0) return l10n.all;
    if (widget.filterMonth == 0) return l10n.yearLabel(widget.filterYear);
    return l10n.yearMonthLabel(widget.filterYear, widget.filterMonth);
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
            // Reserved outside the collapsible area so the handle and title
            // never sit under the home indicator.
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom,
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
    final l10n = AppLocalizations.of(context);
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: context.colors.secondaryText,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 25, right: 25, bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.finishedBooksTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${widget.books.length}',
                          style: TextStyle(
                            color: context.colors.brandText,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: interactive ? widget.onFilterPressed : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _filterText(context),
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.keyboard_arrow_down, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.books.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14, left: 25, right: 25),
              child: SizedBox(
                height: 124 + 13,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.books.length,
                  itemBuilder: (context, index) {
                    final opacityList = bookOpacityList;
                    final opacity = opacityList[index % opacityList.length];
                    return BookVertical(
                      title: widget.books[index].title,
                      opacity: opacity,
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.details,
                        arguments: widget.books[index],
                      ),
                    );
                  },
                ),
              ),
            )
          else
            SizedBox(
              height: 124 + 14 + 13,
              child: Center(
                child: Text(
                  l10n.noFinishedBooks,
                  style: TextStyle(
                    color: context.colors.secondaryText,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 25),
            child: ShelfWidget(),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
