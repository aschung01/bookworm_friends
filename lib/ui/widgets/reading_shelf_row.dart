import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_bookmark.dart';
import 'package:bookworm_friends/ui/widgets/book/reading_day_stamp.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/reading_shelf_lamp.dart';
import 'package:bookworm_friends/ui/widgets/shelf/delete_book_badge.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_book_tile.dart';
import 'package:bookworm_friends/ui/widgets/shelf_drop_index.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart'
    show
        ShelfEdgeFades,
        kShelfAutoScrollStep,
        kShelfLiftDelay,
        kShelfPartDuration,
        kShelfRowScrollMargin,
        kShelfSlotMargin;
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

/// A book lifted off the Reading shelf.
///
/// **A type of its own, and that is the entire mechanism keeping this drag inside this
/// row.** A queue shelf's `DragTarget<ShelfBookDrag>` cannot accept a `ReadingBookDrag`,
/// and this row's `DragTarget<ReadingBookDrag>` cannot accept a book off a plank — so
/// neither direction needs an `if` on a shelf id that a later caller could forget to write.
///
/// **Why the permissive version is wrong rather than merely generous.** If these covers
/// carried `ShelfBookDrag`, every shelf below would already accept the drop, and
/// `moveBookToShelf` rewrites `shelf_id` and positions but *not* `status`: the book would
/// stay at [bookStatusReading], reappear on this shelf immediately, and the only thing that
/// changed would be the invisible field naming the shelf it will return to. Dropping a book
/// onto a plank cannot mean "stop reading it" either — that is a claim about the book, and
/// `book_info_bottom_sheet` owns it behind an explicit tap, where a slightly overshot drag
/// cannot reach it.
@immutable
class ReadingBookDrag {
  const ReadingBookDrag({required this.bookId, required this.slotExtent});

  final String bookId;

  /// How much room the book took along the row, its margins included — the width of the
  /// hole it left, and so of the gap the row opens to preview where it will land.
  final double slotExtent;
}

/// **The books on this shelf stand upright, and the lean that used to be here is worth
/// recording because the design record chose it and the drawing overturned it.**
///
/// The shipped design was `s-lit` with `lean: "even"` — every cover tipped −6.5° about the
/// bottom-left corner, the one still touching the board. It was built, drawn at one, three
/// and seven books, and then removed. Three things the frames showed and the arithmetic
/// had not:
///
///  * **The rows stopped lining up.** A cover tipped by θ overhangs its slot to the left by
///    `h·sin θ` — 15.2pt at the row's tallest — so the row's leading padding had to absorb
///    that or the first book leaned off the front of the plank. Which put the leading
///    cover's *base* 15pt right of where every queue shelf below starts its own first
///    cover. The Reading shelf read as indented from the whole library.
///  * **It made the hero flight dishonest.** A `Hero` takes its rect from the
///    axis-aligned bounding box of its subtree, and a rotated subtree's box is ~15pt wider
///    and ~9pt taller than the cover in it. Tapping a leaning book flew an upright cover
///    from a rect that was not the book, and the tilt vanished on the first frame instead
///    of unwinding. Standing the books up removes the problem rather than documenting it.
///  * **It was the one channel saying something already said.** The ribbon says the book
///    is open; the stamp says how long it has been open. The tilt said "in progress",
///    which is the ribbon's job — and the record had already conceded the tilt could not
///    claim anything stronger, since there is no `last_opened` and no page position, so
///    "the one I am actually reading" could only ever have meant "first by shelf order".
///
/// What is left carrying "this shelf is different" is the lamp and the tab's colour, which
/// is what `s-lit`'s own note argued was doing the work anyway. The row is also ~9pt
/// shorter, since it no longer reserves headroom for a tilt — [bookRowExtent] is now
/// exactly what a Reading row reserves, the same as every other row in the library.
///
/// Restoring the lean means re-adding a rotation about `Alignment.bottomLeft` in
/// [_OpenBook], `kShelfSlotMargin + h·sin θ` of leading padding, and
/// `h·cos θ + w·sin θ` of row height. Do not pivot anywhere right of the bottom-left
/// corner: the cover's lower-left swings *below* the plank and the book pierces the shelf
/// it is standing on. That was measured on the drawings before it was believed.
///
/// **The lamp is not here, and that is the second thing this shelf got wrong.** The bloom
/// belongs to `LibraryPane`, drawn as a fixed layer at the top of the library *outside*
/// the scroll view — see [readingLampHeight]. Two drafts lived in this widget first and
/// both were wrong in the same way: light that is part of the scrolling content travels
/// with the books. A lamp is a fixture. When the reader scrolls, the shelves move and the
/// light does not, which is what a light over a bookcase actually does — and it is what
/// was asked for twice.
///
/// What stays here is what the light *lands on*: [ReadingLampWash] on each cover (the
/// `brightness`/`saturate` multiply, so a cover keeps its own hue) and
/// [kReadingLampPlankGlow] on the plank. Both travel with the row, which is right — they
/// are marks on a book and on a board, not the light itself. The light's own answer to this
/// row leaving is to dim rather than to follow: see [readingLampIntensity].
///
/// The shelf at the top of the library holding every book the reader has open.
///
/// **A separate widget from [ShelfRow] rather than a mode of it, deliberately.** That file
/// is 1,600 lines and most of it is machinery this shelf must not have: cross-shelf
/// handover, the density turn, the pane auto-scroll that carries a book to a shelf below the
/// fold. What it *does* now share is a reorder and a delete badge — see below — plus exactly
/// two pieces of code, [dropIndexForPointer] and [DeleteBookBadge], because "where would
/// this land" and "what does remove look like" are each one question and two implementations
/// of either would drift.
///
/// **In edit mode a cover here behaves exactly like a cover on a plank, bar one thing: it
/// cannot leave the row.** It wiggles, it carries the remove badge at its top-left, it can
/// be dragged to a new place among the other open books. What it cannot do is land on
/// another shelf — see [ReadingBookDrag] for the type that enforces that, and note that
/// "cannot leave" is about the *drag*, not about removal: the badge deletes the book
/// outright, from the library, which is a different act and the same one it is on every
/// other row.
///
/// **This reversed twice, so the reasoning is worth keeping.** The shelf shipped fully
/// inert, on the grounds that a book gets here by having its status set in
/// `book_info_bottom_sheet` and there is no other way in or out. That took the
/// *arrangement* away from the reader, and the arrangement is theirs — so the reorder was
/// added, and the badges were still withheld on the grounds that this shelf "is not a place
/// the reader arranges". Which had just stopped being true. A row whose covers wiggle under
/// a hold and then answer half the gestures a wiggling cover answers everywhere else is not
/// a restraint a reader can learn; it reads as the badge having failed to draw. So the
/// badges are here too.
///
/// The shelf itself still cannot be renamed or deleted, and that is not an inconsistency:
/// the reader did not make this shelf. See the [ShelfLabel] below, which has no
/// `GestureDetector`.
///
/// **Order is the reader's, stored in `books.reading_shelf_index`.** It used to be shelf
/// order — a consequence of where the books came from, and the one thing about this shelf a
/// reader could not change. [readingBooksOf] now sorts by that column, falling back to shelf
/// order for a book that has never been arranged, which is what makes the migration's
/// backfill invisible. A reorder writes that column and never `position`, so clearing a
/// book's status still puts its cover back on its own plank where the reader filed it.
///
/// **Nothing here flies to the details page except the cover.** No `heroTag` on the
/// plank or the tab, because the details page names the book's *real* shelf — the one it
/// will return to when it is finished — and there is no partner over there for this
/// plank to fly to. Flying it anyway would send a bare shelf across the screen from
/// somewhere the cover was never standing, which is exactly the case
/// `book_details_tab_view.dart` already suppresses for a finished book. The cover itself
/// does fly, from its own true rect: [withoutReadingBooks] takes it off its own shelf, so
/// there is precisely one `book_<isbn>` hero for it on the library route, and the covers
/// here are not transformed, so the `Hero` measures the book rather than a box around it.
class ReadingShelfRow extends ConsumerStatefulWidget {
  const ReadingShelfRow({
    super.key,
    required this.books,
    required this.mode,
    required this.onLongPress,
    this.onReorder,
    this.onDeleteBook,
  });

  /// Every book at [bookStatusReading], from [readingBooksOf], in the reader's order.
  ///
  /// Never empty — the caller draws nothing at all when there is nothing in progress,
  /// which is the settled answer to the zero state. An empty plank with a `Reading` tab
  /// would be furniture standing in the library making a promise about a state the
  /// reader is not in, and it would push every real shelf down ~170pt to do it. The
  /// shelf appearing when a book is opened is itself the feedback.
  final List<Book> books;

  final LibraryMode mode;

  /// Answered when a hold on a cover should put the library into edit mode.
  ///
  /// The *drag* announces this rather than a `BookWidget.onLongPress` timer, which is what
  /// stops the two racing — see [_onLift].
  final VoidCallback onLongPress;

  /// The row's new order, once a drop has landed. Null in a friend's library.
  final void Function(List<String> bookIds)? onReorder;

  /// Answered by the remove badge on a cover. Null in a friend's library, and null
  /// outside edit mode — the caller gates it, the same way it gates [ShelfRow]'s.
  final void Function(String bookId)? onDeleteBook;

  @override
  ConsumerState<ReadingShelfRow> createState() => _ReadingShelfRowState();
}

class _ReadingShelfRowState extends ConsumerState<ReadingShelfRow>
    with TickerProviderStateMixin {
  /// The row's own scroller, so a drag held near either end can move it.
  ///
  /// Not optional here: the row clips at about three covers behind [ShelfEdgeFades] and a
  /// reader can have seven or more open, so without this the books past the fade could be
  /// seen but never dragged to.
  final ScrollController _rowScroll = ScrollController();

  /// The row's viewport, which is what "near either end" is measured against.
  final GlobalKey _rowKey = GlobalKey();

  /// One key per book's slot, for measuring where the covers actually are.
  final Map<String, GlobalKey> _slotKeys = {};

  /// One key per cover's draggable, so the element carrying an in-flight gesture survives
  /// the rebuild into edit mode. See [_buildBook].
  final Map<String, GlobalKey> _handoverKeys = {};

  String? _liftedBookId;

  /// The book whose draggable is being carried *into* edit mode, if any.
  ///
  /// Only this one keeps its [_handoverKeys] entry once edit mode arrives; every other
  /// cover is rebuilt keyless so its recognizer picks up edit mode's shorter
  /// [kShelfLiftDelay]. A recognizer's delay is fixed when it is constructed, so an element
  /// that survives keeps the 700ms one it was born with — wanted only for the gesture
  /// actually in flight.
  String? _handoverBookId;

  /// Where the lifted book would land, or null when nothing is over the row.
  int? _dropIndex;

  /// The width of the hole the book in flight left behind.
  double _slotExtent = 0;

  /// True for the frame after an accepted drop, when the preview must be dropped rather
  /// than unwound: the books have already moved in state.
  bool _snapping = false;

  /// The small growing that says a cover has come loose.
  ///
  /// Built in [initState] rather than as a lazy `late final`, which is not a style
  /// preference: with the feedback behind a `Builder`, nothing touches this during an
  /// ordinary build, so the *first* access would be [dispose] calling `dispose` on it —
  /// which forces the lazy initialiser to run `createTicker` against an element that has
  /// already been deactivated, and that trips "looking up a deactivated widget's ancestor".
  late final AnimationController _liftScale;

  Timer? _autoScroll;
  int _rowScrollSign = 0;
  Offset _pointer = Offset.zero;

  /// Where the finger sat inside the cover when it was picked up, measured from the cover's
  /// centre — so the feedback can be drawn where the book was actually standing rather than
  /// snapping its middle to the fingertip.
  Offset _pickUp = Offset.zero;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  bool get _isEditMode => widget.mode == LibraryMode.editLibrary;

  @override
  void initState() {
    super.initState();
    _liftScale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _liftScale.dispose();
    _rowScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReadingShelfRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Leaving edit mode destroys the draggables mid-gesture, so nothing would ever
    // report the drag ending. Mirrors `ShelfRow`.
    //
    // **[_liftScale] is deliberately not reset here.** This runs *during* build, and
    // touching a controller notifies its listeners — one of which is the feedback's
    // `AnimatedBuilder`, possibly already defunct, which then marks itself dirty mid-build.
    // No reset is needed: every lift starts with `forward(from: 0)`.
    if (!_isEditMode) {
      _stopAutoScroll();
      _liftedBookId = null;
      _dropIndex = null;
      _handoverBookId = null;
    }

    final live = {for (final book in widget.books) book.id};
    _slotKeys.removeWhere((id, _) => !live.contains(id));
    _handoverKeys.removeWhere((id, _) => !live.contains(id));

    // **The book being carried has left the shelf.** Finished on another device, or its
    // status cleared from a details page pushed over this one: either way the cover under
    // the finger is gone and there is nothing left to land. Cancel rather than hold a drag
    // against a book the row no longer draws.
    if (_liftedBookId case final id? when !live.contains(id)) {
      _stopAutoScroll();
      _liftedBookId = null;
      _dropIndex = null;
      _handoverBookId = null;
    }
  }

  GlobalKey _slotKeyFor(String bookId) =>
      _slotKeys.putIfAbsent(bookId, GlobalKey.new);

  /// The remove badge for [book], or null when nothing should be removable.
  ///
  /// **Built only in edit mode**, rather than built once and shown conditionally, for the
  /// same reason `ShelfRow` does it: [ShelfBookTile] already refuses to draw a badge with
  /// `isEditMode` false, so a badge built for the resting row would be a widget that exists
  /// only to be discarded — and the resting row is the one that has to stay cheap, since it
  /// is what a reader looks at.
  ///
  /// There is no `spines` case here, unlike the queue rows: this shelf has one density and
  /// its books are always face-out, so every cover can carry its own badge without the discs
  /// blanketing each other.
  Widget? _deleteBadgeFor(Book book, AppLocalizations l10n) {
    if (!_isEditMode) return null;
    return DeleteBookBadge(
      key: DeleteBookBadge.keyFor(book.id),
      label: l10n.deleteBookNamed(book.title),
      onPressed: () => widget.onDeleteBook?.call(book.id),
    );
  }

  GlobalKey _handoverKeyFor(String bookId) =>
      _handoverKeys.putIfAbsent(bookId, GlobalKey.new);

  /// The laid-out box of [bookId]'s slot, or null if there isn't one to trust.
  ///
  /// `Element.renderObject` rather than `findRenderObject`, for the reason `ShelfRow`
  /// documents at length: a global key goes on naming its element while that element is
  /// *deactivated*, which is the state a `ListView` leaves the old arrangement in for part
  /// of the frame it reorders on — and this is called from `build`. `findRenderObject`
  /// asserts on a non-active element, and an exception thrown mid-build takes the row's
  /// whole subtree down for a frame.
  RenderBox? _slotBoxOf(String bookId) {
    final context = _slotKeys[bookId]?.currentContext;
    if (context == null || !context.mounted) return null;
    final box = (context as Element).renderObject;
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  double? _slotCentreOf(String bookId) {
    final box = _slotBoxOf(bookId);
    if (box == null) return null;
    return box.localToGlobal(Offset.zero).dx + box.size.width / 2;
  }

  /// How much room [bookId] takes along the row, its margins included.
  ///
  /// Measured, with a fallback that only covers the frame before there is anything to
  /// measure. Simpler than the shelves' version because this row has one density: every
  /// book here is in progress, and an in-progress book is never compressed.
  double _slotExtentOf(String bookId, double bookHeight) {
    final measured = _slotBoxOf(bookId)?.size.width;
    if (measured != null) return measured;
    return bookHeight * kDefaultCoverAspect + 2 * kShelfSlotMargin;
  }

  int get _liftedIndex {
    final id = _liftedBookId;
    if (id == null) return -1;
    return widget.books.indexWhere((book) => book.id == id);
  }

  Duration get _partDuration => _snapping ? Duration.zero : kShelfPartDuration;

  /// How far the cover at [index] slides to preview the drop.
  ///
  /// Two effects, and one cover can be under both: the hole the lifted book left pulls
  /// everything after it back by a slot, and the gap opening at [_dropIndex] pushes
  /// everything from there on forward by one. Before the finger has crossed a cover the two
  /// cancel exactly, which is what leaves the row looking untouched until it should not.
  ///
  /// **Paint, not layout.** Sliding the covers rather than re-laying the row out keeps the
  /// scroll extent fixed and keeps the keyed boxes where the pointer arithmetic expects
  /// them.
  double _shiftFor(int index) {
    final lifted = _liftedIndex;
    if (index == lifted) return 0;
    final afterLifted = lifted != -1 && index > lifted;
    var dx = afterLifted ? -_slotExtent : 0.0;
    final drop = _dropIndex;
    if (drop != null && (afterLifted ? index - 1 : index) >= drop) {
      dx += _slotExtent;
    }
    return dx;
  }

  int _dropIndexFor(double pointerX) => dropIndexForPointer(
    pointerX: pointerX,
    slotCentres: [
      for (final book in widget.books)
        if (book.id != _liftedBookId) _slotCentreOf(book.id),
    ],
  );

  /// The drag's anchor, which is the finger itself.
  ///
  /// **Returning zero is not incidental**, and `ShelfRow` learned it first: [DragAvatar]
  /// derives both the feedback's position *and* `DragTargetDetails.offset` from this one
  /// number, so the two cannot be chosen independently. An anchor that placed the cover
  /// nicely would hand this row's drop target the cover's *corner* instead of the finger,
  /// and every drop index would be out by half a cover — which looks like a preview that
  /// inserts one slot early rather than like an arithmetic mistake.
  ///
  /// So the anchor is the pointer, and the cover is put back where it stood by the
  /// translation on the feedback instead.
  Offset _anchorToPointer(
    Draggable<Object> draggable,
    BuildContext context,
    Offset position,
  ) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _pickUp = box.size.center(Offset.zero) - box.globalToLocal(position);
    }
    return Offset.zero;
  }

  /// A cover has just left the row.
  ///
  /// **In view mode this is also the moment edit mode is entered**, and letting the drag
  /// announce it is what stops a timer and a recognizer racing: a `BookWidget.onLongPress`
  /// firing beside the draggable's own recognizer would sometimes cancel the gesture that
  /// was about to become the drag, and the hold would enter edit mode with nothing in hand.
  void _onLift(int index, String bookId, double slotExtent, bool isEditMode) {
    if (!_reduceMotion) _liftScale.forward(from: 0);
    setState(() {
      _liftedBookId = bookId;
      _slotExtent = slotExtent;
      if (!isEditMode) {
        _handoverBookId = bookId;
        // **Seeded, or the row closes up under the finger.** A lift *inside* edit mode
        // gets this free: the row is already a `DragTarget`, so building the drag avatar
        // reports a move at once and the gap opens exactly where the book left — hole and
        // gap cancel in [_shiftFor] and the row looks untouched. Here there is no target
        // yet, the row only becoming one on the frame edit mode arrives, and `onMove`
        // answers pointer *movement* rather than a target appearing under a finger holding
        // still. Without this the covers to the right would slide over the held book's slot
        // and stay there until the finger moved.
        _dropIndex = index;
      }
    });
    if (!isEditMode) widget.onLongPress();
  }

  /// Puts the row back the way it was, with nothing in the air.
  void _setDown() {
    if (!_reduceMotion) _liftScale.reverse();
    setState(() {
      _liftedBookId = null;
      _dropIndex = null;
      _handoverBookId = null;
    });
  }

  void _onDragOver(DragTargetDetails<ReadingBookDrag> details) {
    _pointer = details.offset;
    _driveAutoScroll();
    final index = _dropIndexFor(details.offset.dx);
    if (index != _dropIndex) setState(() => _dropIndex = index);
  }

  /// The reader let go over this row.
  ///
  /// Reports the whole set in its new order, which is what
  /// [LibraryNotifier.reorderReadingBooks] expects: unlike a shelf, this row hides nothing,
  /// so there is no absent book whose stored index has to be preserved.
  void _onDrop(DragTargetDetails<ReadingBookDrag> details) {
    _stopAutoScroll();
    final index = _dropIndex;
    if (index == null) return;

    final rest = [
      for (final book in widget.books)
        if (book.id != details.data.bookId) book.id,
    ];
    final ordered = [
      ...rest.take(index),
      details.data.bookId,
      ...rest.skip(index),
    ];

    // Unchanged orders are not written. A hold that lifts a cover and puts it straight back
    // is a common way to leave edit mode, and it should not cost an UPDATE per book.
    if (ordered.length == widget.books.length) {
      final before = [for (final book in widget.books) book.id];
      if (!_sameOrder(before, ordered)) widget.onReorder?.call(ordered);
    }
    _snapNextFrame();
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Drops the preview without animating it, for the frame after an accepted drop.
  ///
  /// The books have already moved in state, so unwinding the slides would animate every
  /// cover back from where it no longer is.
  void _snapNextFrame() {
    setState(() {
      _snapping = true;
      _liftedBookId = null;
      _dropIndex = null;
      _handoverBookId = null;
    });
    _liftScale.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _snapping = false);
    });
  }

  /// Which way the row is being asked to move, or 0 when the finger is not at either edge.
  int _edgeSign() {
    final box = _rowKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0;
    final start = box.localToGlobal(Offset.zero).dx;
    if (_pointer.dx < start + kShelfRowScrollMargin) return -1;
    if (_pointer.dx > start + box.size.width - kShelfRowScrollMargin) return 1;
    return 0;
  }

  /// Starts, redirects or stops the scrolling a drag at [_pointer] is asking for.
  ///
  /// One scroller, unlike the shelves' two: a book cannot leave this row, so there is no
  /// reason to move the library underneath it.
  void _driveAutoScroll() {
    final sign = _edgeSign();
    if (sign == _rowScrollSign) return;
    _rowScrollSign = sign;
    _autoScroll?.cancel();
    _autoScroll = null;
    if (sign == 0) return;
    _autoScroll = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _stepAutoScroll(),
    );
  }

  void _stepAutoScroll() {
    if (!mounted || !_rowScroll.hasClients) return;
    final position = _rowScroll.position;
    final to = (position.pixels + _rowScrollSign * kShelfAutoScrollStep).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (to == position.pixels) return;
    position.jumpTo(to);

    // The row moved under a finger that did not, so where the book would land moved with
    // it. Worked out here rather than waiting for a pointer event that, for a finger parked
    // at the end of a row, may never come.
    if (_dropIndex == null) return;
    final index = _dropIndexFor(_pointer.dx);
    if (index != _dropIndex) setState(() => _dropIndex = index);
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _rowScrollSign = 0;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.books.isNotEmpty,
      'The caller draws no shelf for no open books.',
    );
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;
    final bookHeight = size.height * 0.15;
    // Exactly what every other row in the library reserves. The lean this shelf used to
    // carry needed ~9pt more; see the note at the top of the file.
    final rowExtent = bookRowExtent(bookHeight);
    final rowWidth = size.width * 0.95;

    // Named separately from the wrapper below, and not reassigned into it. A
    // `builder: (_, _, _) => row` that closed over a mutable `row` would, by the time it
    // ran, be handing back the `DragTarget` itself — which nests inside itself until the
    // stack gives out. `ShelfRow` keeps the two names apart for the same reason.
    final Widget rowContent = SizedBox(
      height: rowExtent,
      width: rowWidth,
      // **The fade is view mode's only, and that reversed.** It was kept in edit mode as
      // well on the reasoning that the row still clips there — which was true and beside
      // the point, because the thing a fade needs is a *clipped* edge and edit mode has to
      // stop clipping: the remove badge is a 44pt disc hung 22pt outside its cover's
      // top-left, so it sits ~7pt above this box and 22pt left of the leading cover, and a
      // clipping row shears the top off every badge on the shelf. `ShelfRow` splits the two
      // modes the same way, for the same reason.
      child: _isEditMode
          ? _buildRow(bookHeight)
          : ShelfEdgeFades(child: _buildRow(bookHeight)),
    );

    final Widget row = _isEditMode
        ? DragTarget<ReadingBookDrag>(
            // Only this row's own books can be offered — nothing else constructs a
            // [ReadingBookDrag] — so there is nothing to refuse.
            onWillAcceptWithDetails: (details) {
              _onDragOver(details);
              return true;
            },
            onMove: _onDragOver,
            onLeave: (_) {
              _stopAutoScroll();
              // Guarded for the same reason [onDragEnd] is: this also fires while the
              // dragged book's element is being *unmounted*, when the book has left the
              // reading set mid-drag. [didUpdateWidget] has already cleared the preview by
              // then, and a `setState` from inside that unmount is a build-phase
              // `markNeedsBuild`.
              if (_dropIndex != null) setState(() => _dropIndex = null);
            },
            onAcceptWithDetails: _onDrop,
            builder: (context, candidate, rejected) => rowContent,
          )
        : rowContent;

    return Padding(
      // The same 26pt every shelf leaves below itself, so the Reading shelf sits in the
      // column at the pitch of the ones under it rather than announcing itself by
      // spacing. The lamp's bloom is what makes it different.
      padding: const EdgeInsets.only(bottom: 26),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            SizedBox(
              height: rowExtent,
              width: rowWidth,
              child: Stack(
                alignment: Alignment.bottomLeft,
                // A cover's drop shadow paints a little outside its own box, and the
                // covers at either end of the row sit on this box's edges.
                clipBehavior: Clip.none,
                children: [
                  Positioned(top: 0, child: row),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    // No `GestureDetector`: this shelf cannot be renamed or deleted,
                    // because the reader did not make it. Reordering its books is theirs;
                    // the shelf itself is the app's.
                    child: ShelfLabel(
                      label: l10n.readingShelfName,
                      // Every book handed to this widget is standing on this plank —
                      // there is no finished/reading exclusion to apply the way
                      // `shelvedBookCount` applies on a queue shelf — so the count is
                      // simply `books.length`. It is also the one honest answer to "how
                      // many open books do I have", which the row itself cannot give once
                      // it clips: `ShelfEdgeFades` starts fading at about the fourth cover.
                      count: widget.books.length,
                      // The app's shelf rather than the reader's, said in colour instead
                      // of in words. 5.62:1 on `surface`.
                      labelColor: context.colors.brandText,
                    ),
                  ),
                ],
              ),
            ),
            // Ordinary white carpentry, plus the pool the lamp throws on it. The board
            // is the same stock as every other plank in the library on purpose — the
            // timber variants were drawn and set aside, and `ShelfLabel` draws
            // `surface` too, so re-stocking one would have meant re-stocking both.
            const ShelfWidget(glow: kReadingLampPlankGlow),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(double bookHeight) {
    return SizedBox(
      key: _rowKey,
      child: ListView.builder(
        controller: _rowScroll,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        // Edit mode's covers carry a remove badge that hangs off the top-left corner and
        // out of this viewport, so the row must not clip; view mode's is behind
        // [ShelfEdgeFades], whose fade only means anything against a clipped edge.
        clipBehavior: _isEditMode ? Clip.none : Clip.hardEdge,
        padding: const EdgeInsets.symmetric(
          // **The same 15pt in from the row that every shelf below uses**, which is what
          // aligns this row's leading cover with theirs. It was `kShelfSlotMargin` plus the
          // lean's horizontal sweep while the books tipped — the sweep had to be absorbed
          // here or the first cover leaned off the front of the plank, and the cost was
          // that this row's covers began 15pt right of every other row's.
          horizontal: kShelfSlotMargin,
        ),
        itemCount: widget.books.length,
        itemBuilder: (context, index) =>
            _buildBook(index, widget.books[index], bookHeight),
      ),
    );
  }

  /// One slot: the cover, the gap it slides to open, and the drag that lifts it.
  ///
  /// **Draggable in view mode too, which is not decoration.** It is the only way a hold can
  /// both enter edit mode *and* leave the reader already carrying the book: a drag cannot be
  /// started programmatically, and a `Draggable` that appears after the finger is down can
  /// never adopt that pointer, because a recognizer claims its pointer route at
  /// pointer-down. So the draggable that will carry the book has to exist before the hold
  /// completes.
  Widget _buildBook(int index, Book book, double bookHeight) {
    final isEditMode = _isEditMode;
    final slotExtent = _slotExtentOf(book.id, bookHeight);

    return SizedBox(
      key: _slotKeyFor(book.id),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _shiftFor(index)),
        duration: _partDuration,
        // Not `easeOutCubic`: that leaves at full speed, so a cover appears to jump the
        // instant the gap moves. This eases both ends, which reads as the shelf being
        // pushed rather than cut.
        curve: Curves.fastOutSlowIn,
        builder: (context, dx, child) =>
            Transform.translate(offset: Offset(dx, 0), child: child),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kShelfSlotMargin),
          // Bottom-aligned so a book that hashes short stands on the plank instead of
          // floating, and so the row's tight height constraint is loosened — without this
          // the book would be stretched to the row's extent and the jitter would vanish.
          child: Align(
            alignment: Alignment.bottomCenter,
            child: LongPressDraggable<ReadingBookDrag>(
              // Keyed in view mode so the element — and with it the drag — survives the
              // rebuild into edit mode; keyed in edit mode only for the book actually
              // being carried across, so every other cover is rebuilt with edit mode's
              // shorter lift delay.
              key: isEditMode
                  ? (book.id == _handoverBookId
                        ? _handoverKeyFor(book.id)
                        : null)
                  : _handoverKeyFor(book.id),
              // In view mode the hold *is* the gesture that enters edit mode, so it waits
              // as long as that always has on the shelves below. Once there, a lift is
              // quicker.
              delay: isEditMode ? kShelfLiftDelay : kBookStageTwoDelay,
              dragAnchorStrategy: _anchorToPointer,
              data: ReadingBookDrag(bookId: book.id, slotExtent: slotExtent),
              onDragStarted: () =>
                  _onLift(index, book.id, slotExtent, isEditMode),
              onDragEnd: (details) {
                _stopAutoScroll();
                // An accepted drop has already moved the books in state, so the preview is
                // dropped rather than unwound; a refused one changed nothing, so the row
                // closes the way it opened.
                //
                // **Guarded on something still being lifted**, because this also fires when
                // the draggable is *disposed* mid-drag — which is what happens when the
                // book leaves the reading set while it is in the air. [didUpdateWidget] has
                // already cancelled by then, and calling `setState` from inside that
                // unmount is a `markNeedsBuild` during build.
                if (!details.wasAccepted && _liftedBookId != null) _setDown();
              },
              feedback: Builder(
                // A `Builder`, because [_pickUp] is not known when this widget is
                // *constructed*: the row builds `feedback` a frame ahead of the gesture,
                // [_anchorToPointer] runs when the drag actually starts, and the overlay
                // mounts this only after that. Reading it here reads *this* drag's
                // measurement rather than the previous one's.
                builder: (context) => Transform.translate(
                  offset: _pickUp,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -0.5),
                    child: _DraggedCover(
                      book: book,
                      height: bookHeight,
                      scale: _liftScale,
                    ),
                  ),
                ),
              ),
              // Invisible rather than faint, and still holding its slot: the hole it
              // leaves is closed by [_shiftFor], and the gap standing for the book has
              // moved to wherever the finger is — a ghost left in the original slot would
              // claim it had not. Drawn from the same widget as the resting cover so the
              // slot keeps exactly the width the measurement was taken from.
              //
              // **No badge on it**, even though it is in edit mode: an `Opacity(0)` subtree
              // still hit-tests, so a badge here would be an invisible remove target sitting
              // over the shelf, under a key already worn by the cover in flight.
              childWhenDragging: Opacity(
                opacity: 0,
                child: _OpenBook(
                  book: book,
                  height: bookHeight,
                  isEditMode: isEditMode,
                  onTap: () {},
                  onCoverSampled: (_) {},
                  withHero: false,
                ),
              ),
              child: _OpenBook(
                book: book,
                height: bookHeight,
                isEditMode: isEditMode,
                deleteBadge: _deleteBadgeFor(
                  book,
                  AppLocalizations.of(context),
                ),
                // A cover's tap is withheld in edit mode, so a finger that fails to hold
                // long enough does not open a book the reader was trying to move. The
                // empty callback rather than null keeps the tap from bubbling to the
                // page-level handler that leaves edit mode.
                onTap: isEditMode
                    ? () {}
                    : () => Navigator.pushNamed(
                        context,
                        AppRoutes.details,
                        arguments: book,
                      ),
                onCoverSampled: (color) => ref
                    .read(libraryActionsProvider)
                    .recordCoverColor(book, color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The cover as it travels under the finger.
///
/// Picked up where it stood, so the small growing is the only cue that it has come loose —
/// there is no turn to animate here the way the shelves have, because a Reading cover is
/// always face-out.
///
/// **It has to be the cover that was lifted, and it twice was not.** Both misses came from
/// building the drawing again here instead of reusing [_OpenBook], and both are the kind that
/// only a moving finger reveals:
///
///  * **The ribbon went missing.** Every book on this shelf is at [bookStatusReading] and
///    wears one, so lifting a cover un-marked it for as long as it was in the air — the one
///    moment the reader is looking straight at it.
///  * **[BookWidget.pageCount] was not passed**, and the jitter is hashed from the ISBN
///    *and* the page count. So the cover in flight was a hair's different height and
///    thickness from the one that left the row, and the row's gap — measured off the real
///    slot — was the wrong width for it. `ShelfRow`'s own feedback carries the same note.
///
/// Not simply [_OpenBook] with `withHero: false`, though, and the reason is the day stamp:
/// `D+n` is a label about a book sitting on a shelf being read, not about an object in
/// transit, and at 1.06x under a finger it is the one element small enough to read as debris.
/// The ribbon is part of the book; the stamp is an annotation on the row.
class _DraggedCover extends StatelessWidget {
  const _DraggedCover({
    required this.book,
    required this.height,
    required this.scale,
  });

  final Book book;
  final double height;
  final Animation<double> scale;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: scale,
        builder: (context, child) =>
            Transform.scale(scale: 1 + 0.06 * scale.value, child: child),
        // No hero tag on a cover in flight: it is not the one standing in the row, and two
        // heroes with one tag on a route is an error rather than a race.
        child: ReadingLampWash(
          // The wash goes outside the ribbon as well as the cover, exactly as [_OpenBook]
          // has it: the lamp lights the mark on the book too.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              BookWidget(
                imageUrl: book.thumbnail,
                title: book.title,
                isbn: book.isbn,
                height: height,
                // The jitter is hashed from the ISBN *and* the page count, so a feedback
                // given only the ISBN is a subtly different book from the one lifted — and
                // the gap the row opens was measured off the real slot.
                pageCount: book.pageCount,
                // Nothing can hold this: the drag already owns the pointer, and the
                // feedback lives in an `Overlay` the finger never addresses.
                pressEffect: false,
              ),
              // Every book on this shelf is open, so this is unconditional here — unlike
              // [ShelfBookTile], which draws it on a status check because a plank holds
              // books that are not.
              //
              // The inset is computed the same way the tile computes it, so the mark does
              // not jump along the cover's edge at the moment a drag starts.
              Positioned(
                top: 0,
                right: readingBookmarkInsetFor(
                  book.progress,
                  coverWidth: height * kDefaultCoverAspect,
                ),
                child: const ReadingBookmark(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One open book: its cover standing on the board, lit, ribboned, and stamped with how
/// long it has been open.
class _OpenBook extends StatelessWidget {
  const _OpenBook({
    required this.book,
    required this.height,
    required this.onTap,
    required this.onCoverSampled,
    this.isEditMode = false,
    this.deleteBadge,
    this.withHero = true,
  });

  final Book book;
  final double height;
  final VoidCallback onTap;
  final ValueChanged<Color> onCoverSampled;

  /// Whether the cover wiggles and shows [deleteBadge] — [ShelfBookTile] draws both, so
  /// there is nothing to do here beyond passing it along.
  final bool isEditMode;

  /// The remove badge, already built, or null for a cover that should not show one.
  final Widget? deleteBadge;

  /// False for the copy left behind while the book is in the air, which is invisible and
  /// must not be a second hero under the same tag.
  final bool withHero;

  @override
  Widget build(BuildContext context) {
    final days = readingDayCount(book);
    return ReadingLampWash(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Sizes the stack, so the stamp below can be placed against the cover's own
          // edges. Draws the ribbon itself for a book at [bookStatusReading], which is
          // every book on this shelf — and in edit mode the wiggle and the badge, both of
          // which are the tile's, so an open cover and a shelved one behave identically.
          ShelfBookTile(
            book: book,
            height: height,
            isEditMode: isEditMode,
            withHero: withHero,
            deleteBadge: deleteBadge,
            onTap: onTap,
            onCoverSampled: onCoverSampled,
          ),
          if (days != null)
            Positioned(
              bottom: ReadingDayStamp.inset,
              right: ReadingDayStamp.inset,
              child: ReadingDayStamp(days: days),
            ),
        ],
      ),
    );
  }
}
