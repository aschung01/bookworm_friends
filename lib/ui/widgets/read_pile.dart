import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

/// Air either side of the book that has been turned out, at full turn.
///
/// Zero at rest, so the resting pile's density is exactly what it was. Flush was
/// the first answer and it took seeing it to reject: the turned cover sat hard
/// against the spines on both sides, which reads as a book wedged in place rather
/// than one taken off the shelf, and it clipped the stacked shadows that are the
/// only thing separating a cover from the plank behind it.
const double kTurnMargin = 8;

/// The pose a book in the pile rests at: spine-on, cover edge-on.
///
/// Negative because positive turn exposes the fore-edge. See [bookParentMatrix].
const double kReadSpinePose = -math.pi / 2;

/// The size of one book in the read pile.
///
/// [spineMetricsFor] with the pile's own base height bound. The body moved to
/// `book_geometry.dart` when a shelf became the third thing that draws a spine —
/// see there for why one function has to serve all of them, and why the aspect is
/// resolved at [kDefaultCoverAspect].
({BookJitter jitter, BookMetrics metrics}) readSpineMetrics(Book book) =>
    spineMetricsFor(book, baseHeight: ReadPile.spineBase);

/// The fill and the title colour for [book]'s spine.
///
/// **Top-level, so a spine on a shelf and a spine in the pile cannot come out
/// different colours for the same book.** It was private to `_ReadPileState` while
/// the pile was the only thing that drew a spine.
///
/// No theme is involved, deliberately — a spine's fill is opaque, so the same book
/// gets the same spine in light and dark mode. See [kSpineInkDark].
({Color fill, Color title}) spineToneOf(Book book) =>
    spineToneFor(book.coverColor ?? generatedCoverColor(book.isbn));

/// The read pile: spines standing on a shelf, scrolling sideways.
///
/// This is the read view's **collapsed** state, and the one place in the app that
/// shows every book at once. Tapping a spine turns that book out to its cover in
/// place, hinged on the spine, after which it behaves like a book on a shelf: hold
/// it and it turns a further [kBookTurnAngle], tap it and its cover flies to the
/// details page.
///
/// [extent] is its height *at the collapsed position*, and that number is
/// load-bearing: [LibrarySheet] needs the collapsed snap position while the *grid*
/// is the body on screen, so it cannot measure this. It is honest because nothing
/// here scales — the spine row is a fixed-height horizontal scroller — and because
/// the collapsed position is defined as the header plus exactly this.
///
/// **Above that position it grows, and the shelf stays at the bottom edge.** A drag
/// up from the pile does not reach the grid until halfway to the next detent (see
/// `LibrarySheet._swapPoint`), and for the whole of that stretch the sheet is taller
/// than the pile. Pinned at [extent] the shelf stopped where the collapsed card used
/// to end, with a growing band of blank card below it and books standing in mid-air —
/// which reads as the sheet coming apart rather than opening. So the pile takes the
/// height the card is showing ([SheetBodyViewport]) when that is more than its own,
/// and the room opens up *above* the books: the shelf, and the books standing on it,
/// stay where the reader is dragging the bottom of the card to.
class ReadPile extends ConsumerStatefulWidget {
  final List<Book> books;

  /// Which year is being shown, or `0` for all time.
  ///
  /// The empty state reads it, to avoid telling someone who has filtered to a past
  /// year that they have never finished a book. An open book also closes when it
  /// changes, since the list under it is no longer the list that was tapped.
  final int filterYear;

  /// True while the library is being edited.
  ///
  /// The pile has no edit mode of its own; this closes any open book, because the
  /// sheet is springing shut and a book left turned out would reopen turned out.
  final bool isEditMode;

  const ReadPile({
    super.key,
    required this.books,
    this.filterYear = 0,
    this.isEditMode = false,
  });

  /// The pile's height at the collapsed position: top gap, then the spine row, then
  /// the shelf it stands on, then the gap below it. Kept as the sum of the parts so a
  /// change to any of them is visibly a change to this number.
  static const double extent = _topGap + rowExtent + _shelfHeight + _bottomPad;

  /// The gap above the spines when the pile is at [extent]. Not a padding any more —
  /// the row is pinned to the shelf and this is simply what is left over — but it is
  /// still what the resting pile looks like, so it stays a named part of the sum.
  static const double _topGap = 14;

  /// What a praised spine grows by, above the book itself.
  static const double _praiseGrowth = 13;

  /// The tallest spine plus [_praiseGrowth], so a book that gains praise does not
  /// change the pile's height.
  ///
  /// Public because it is the pile's real contract with a spine: this much room,
  /// and no more. A test asserts no book exceeds it.
  static const double rowExtent = 124 + _praiseGrowth;
  static const double _shelfHeight = 8;
  static const double _bottomPad = 10;

  /// Base height the pile's jitter is applied to.
  ///
  /// Derived, never typed. Books span [BookJitter.minHeightFactor] to
  /// [BookJitter.maxHeightFactor] of this, so the base has to be the row's own
  /// space for a spine *divided* by the tallest factor — otherwise the tallest book
  /// is the one that gets clipped, and it is clipped by 6% of its height at the
  /// head, which is exactly where the eye is.
  ///
  /// It works out at ~117, and the point of writing it this way is that [extent]
  /// stays 169 by construction rather than by coincidence: the tallest book is
  /// still 124pt, which is the flat height every spine used to have.
  static const double spineBase =
      (rowExtent - _praiseGrowth) / BookJitter.maxHeightFactor;

  @override
  ConsumerState<ReadPile> createState() => _ReadPileState();
}

class _ReadPileState extends ConsumerState<ReadPile>
    with TickerProviderStateMixin {
  /// Id of the book that is turned out, or turning out. At most one.
  String? _openId;

  /// Id of the book turning *back*, if a second book was tapped while one was
  /// open. Held separately so both animate, on the shelves' own two durations,
  /// rather than the outgoing book snapping flat under the incoming one.
  String? _closingId;

  /// 0 is spine-on, 1 is cover-on. The pose is interpolated from it, so the two
  /// books in flight during a switch share one scale.
  late final AnimationController _open;
  late final AnimationController _close;

  @override
  void initState() {
    super.initState();
    // The shelves' timings, not new ones. Two motions at visibly different rates
    // read as two mechanisms.
    _open = AnimationController(
      vsync: this,
      duration: kBookTurnDuration,
      reverseDuration: kBookReleaseDuration,
    );
    _close = AnimationController(
      vsync: this,
      duration: kBookTurnDuration,
      reverseDuration: kBookReleaseDuration,
    );
    _close.addStatusListener((status) {
      // The outgoing book becomes a flat spine again only once it is fully back,
      // or it would vanish mid-turn.
      if (status == AnimationStatus.dismissed && _closingId != null) {
        setState(() => _closingId = null);
      }
    });
  }

  @override
  void dispose() {
    _open.dispose();
    _close.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReadPile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different filter is a different list, and edit mode springs the sheet
    // shut. Either way the book that was tapped is no longer the book in front of
    // the reader, so it closes rather than being left open behind the change.
    final listChanged = widget.filterYear != oldWidget.filterYear;
    final editing = widget.isEditMode && !oldWidget.isEditMode;
    // A book removed from the list while open would otherwise leave `_openId`
    // pointing at nothing, which is harmless but keeps a controller running.
    final gone = _openId != null && !widget.books.any((b) => b.id == _openId);
    if (listChanged || editing || gone) _closeAll();
  }

  void _closeAll() {
    if (_openId == null && _closingId == null) return;
    setState(() {
      _openId = null;
      _closingId = null;
    });
    _open.value = 0;
    _close.value = 0;
  }

  /// Turns [book] out, and turns back whatever was out before it.
  void _turnOut(Book book) {
    if (_openId == book.id) return;
    setState(() {
      if (_openId != null) {
        _closingId = _openId;
        _close.value = _open.value;
        _close.reverse();
      }
      _openId = book.id;
    });
    _open.value = 0;
    _open.forward();
  }

  /// Projected width of a book at [pose], which is what the row lays out against.
  ///
  /// `cover×|cos| + thickness×|sin|`, the silhouette of two perpendicular faces.
  /// Non-monotonic by ~3pt near cover-on, because a book at 80° is very slightly
  /// wider than one at 90° — which is what a real book does, and is accepted: the
  /// alternative is to lay out against the maximum and have the row open a gap
  /// before the book grows into it.
  double _slotWidth(BookMetrics m, double pose) =>
      m.width * math.cos(pose).abs() + m.thickness * math.sin(pose).abs();

  Widget _flatSpine(Book book) {
    final size = readSpineMetrics(book);
    final tone = _spineTone(book);
    return BookVertical(
      title: book.title,
      width: size.metrics.thickness,
      height: size.metrics.height,
      fill: tone.fill,
      titleColor: tone.title,
      // The pile is a sheet's `collapsedBody`, so `sheetBackground` is what a pale
      // spine is actually seen against — not `surface`, which is what `BookVertical`
      // would otherwise assume.
      background: context.colors.sheetBackground,
      separator: true,
      onTap: () => _turnOut(book),
    );
  }

  /// The fill and title ink for [book]'s spine.
  ///
  /// [spineToneOf], which is top-level so a shelf spine and a pile spine of the same
  /// book cannot disagree. Kept as a one-line alias because this class names it a
  /// dozen times and the reasoning below belongs with the pile.
  ///
  /// Both come out of one call, so a spine cannot end up with a fill chosen for one
  /// ink and a title drawn in the other.
  ///
  /// The cover tone comes from the book's own record and **never from a live
  /// decode**: a stored colour if the backfill has reached it, otherwise the swatch
  /// its ISBN already picks for a generated cover. Correct on the first frame either
  /// way, which is what a pile of dozens of spines needs.
  ///
  /// No theme is involved, deliberately — a spine's fill is opaque, so the same book
  /// gets the same spine in light and dark mode. See [kSpineInkDark].
  ({Color fill, Color title}) _spineTone(Book book) => spineToneOf(book);

  /// The one book that is a real [BookWidget]: turned out, or on its way.
  Widget _turnedBook(Book book, Animation<double> progress) {
    final size = readSpineMetrics(book);
    final m = size.metrics;
    final tone = _spineTone(book);

    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value;
        final pose = kReadSpinePose * (1 - t);
        final slot = _slotWidth(m, pose);
        // The hinge is the chassis box's left edge at every angle, and at a
        // negative pose the spine hangs a thickness to the *left* of it. Offset
        // the box by that much so the drawing's leftmost point is the slot's, and
        // the resting pile is laid out exactly as flat spines are.
        final hinge = m.thickness * math.sin(pose).abs();
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: kTurnMargin * t),
          child: SizedBox(
            width: slot,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: hinge,
                  bottom: 0,
                  width: m.width,
                  height: m.height,
                  child: child!,
                ),
              ],
            ),
          ),
        );
      },
      // Built once, outside the builder: it owns an ImageStream, and rebuilding it
      // every frame of the turn would re-resolve the cover 16 times.
      child: BookWidget(
        imageUrl: book.thumbnail,
        isbn: book.isbn,
        title: book.title,
        height: ReadPile.spineBase,
        pageCount: book.pageCount,
        // The same jitter the flat spine was drawn at, handed over rather than
        // recomputed, so the cover is exactly as thick as the spine that was
        // tapped.
        jitterOverride: size.jitter,
        turnRadians: progress.drive(
          Tween<double>(begin: kReadSpinePose, end: 0),
        ),
        pivot: Alignment.centerLeft,
        spine: BookVertical(
          title: book.title,
          width: m.thickness,
          height: m.height,
          fill: tone.fill,
          titleColor: tone.title,
          background: context.colors.sheetBackground,
          separator: true,
          // A face of a solid object cannot have a notch in its head that the
          // faces beside it do not. See [BookVertical.arch].
          arch: false,
        ),
        // Only the open book carries the tag, which is what makes the Hero legal
        // here at all — see the note in `book_details_tab_view.dart`.
        heroTag: 'book_${book.isbn}',
        // **The pile is the screen where a missing colour is visible as a
        // disagreement**, and this is the one book on it with a decoded cover to
        // offer. Turn out a book whose spine is still an ISBN swatch and the swatch
        // sits directly beside the jacket it does not match; reporting the sample
        // here means that cannot happen twice for the same book.
        //
        // It also closes a gap the other three call sites could not: a finished book
        // is kept off the shelves by `withoutFinishedBooks`, so of the paths that
        // decode a cover, only the read grid and the details page ever saw these
        // books at all.
        onCoverSampled: (color) =>
            ref.read(libraryActionsProvider).recordCoverColor(book, color),
        onTap: () =>
            Navigator.pushNamed(context, AppRoutes.details, arguments: book),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = SheetBodyViewport.maybeOf(context);
    return SizedBox(
      height: visible == null || visible < ReadPile.extent
          ? ReadPile.extent
          : visible,
      child: Column(
        children: [
          Expanded(
            child: widget.books.isEmpty
                // Centred in the room above the shelf, which is the room that grows,
                // so the message tracks the card the way the grid's does rather than
                // sitting at the height the collapsed card happened to end at. See
                // [SheetBodyCenter], which is the same rule for the expanded state.
                ? Center(
                    child: Text(
                      widget.filterYear == 0
                          ? l10n.noFinishedBooks
                          : l10n.noFinishedBooksInYear(widget.filterYear),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        color: context.colors.secondaryText,
                      ),
                    ),
                  )
                // Bottom-aligned at its own height rather than filling the room: the
                // books stand *on* the shelf, so what a taller pile adds is headroom
                // above them. Left to fill, the horizontal list would stretch its
                // children to the full height — the spines are drawn at the bottom of
                // whatever box they get, so it would look the same and be tappable
                // half a card above the book.
                : Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      height: ReadPile.rowExtent,
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 25),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          // As on the shelves. A turned-out book carries the
                          // stacked shadows that separate a cover from the plank,
                          // and they fall outside the row's box.
                          clipBehavior: Clip.none,
                          itemCount: widget.books.length,
                          itemBuilder: (context, index) {
                            final book = widget.books[index];
                            if (book.id == _openId) {
                              return _turnedBook(book, _open);
                            }
                            if (book.id == _closingId) {
                              return _turnedBook(book, _close);
                            }
                            return Align(
                              alignment: Alignment.bottomCenter,
                              child: _flatSpine(book),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 25),
            child: ShelfWidget(),
          ),
          const SizedBox(height: ReadPile._bottomPad),
        ],
      ),
    );
  }
}
