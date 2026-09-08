import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/shelf_density_provider.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_book_tile.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_lean_metrics.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_spine_tile.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

/// What a book in flight carries to whichever shelf it is dropped on.
///
/// **The shelf it came from travels with it**, because a drop is one of two
/// different edits depending on the answer — a reorder inside one row, or a move
/// between two — and the receiving shelf has no other way to tell which it is
/// being asked for.
///
/// **So does the width of the slot it vacated**, because that is the width of the
/// gap the receiving shelf has to open for it. A cover's width follows its decoded
/// aspect ratio and its jittered height, so no shelf can work out the size of a
/// book it does not hold; the shelf that does hold it measures it at the lift and
/// sends the number along.
@immutable
class ShelfBookDrag {
  const ShelfBookDrag({
    required this.bookId,
    required this.shelfId,
    required this.slotExtent,
    required this.reading,
  });

  final String bookId;
  final String shelfId;

  /// How much room the book took along its own row, its margins included.
  final double slotExtent;

  /// Whether the book in flight is one the reader is part-way through.
  ///
  /// Travels for the same reason [slotExtent] does: a receiving shelf cannot know
  /// it. Every shelf draws its in-progress books at the head of the row, so a book
  /// arriving from elsewhere has to say which side of that boundary it belongs on —
  /// otherwise the gap could open in a place the book cannot land, and the preview
  /// would be a promise the drop then breaks.
  final bool reading;
}

/// How long a cover has to be held in edit mode before it lifts.
///
/// **Every drag starts this way now.** It used to be split in two: a *vertical*
/// drag lifted a book instantly and could only ever be dropped on some other
/// shelf, while a long press started a reorder confined to the row it began in.
/// Two gestures with two different vocabularies, and the instant one was the
/// easier of them to trigger by accident — a shelf cannot be flicked vertically,
/// but the library it stands in scrolls that way, so a fumbled scroll that started
/// on a cover threw a book off its shelf. One hold now opens one drag that can do
/// both jobs.
const Duration kShelfLiftDelay = Duration(milliseconds: 250);

/// How long the covers take to part for an incoming book, and to close again.
/// Slow enough to read as books being nudged aside rather than snapping, which
/// matters most on a crowded shelf where several of them move at once.
const Duration _kPartDuration = Duration(milliseconds: 280);

/// Half the space between two covers, which each of them carries as its margin.
const double _kSlotMargin = 7.5;

/// How much a cover grows while it is being carried.
///
/// Small on purpose. The book is picked up where it stood rather than thrown up
/// under the finger, so this is the only thing saying it has left the shelf, and a
/// cover that jumped in size would undo that.
const double _kLiftScale = 0.06;

/// How long the lift's growing takes. Quicker than the turn, so the book reads as
/// coming loose first and turning second.
const Duration _kLiftScaleDuration = Duration(milliseconds: 160);

/// How near either end of a row the finger has to get before the row scrolls
/// itself, and how near the top or bottom of the pane before the *library* does.
///
/// Two bands rather than one, because the two scrollers are different sizes and a
/// band has to be something a finger can rest in. 44 is a comfortable reach at the
/// end of a row; the same 44 at the bottom of the pane would be a third of a shelf,
/// easy to overshoot straight past and hard to hold still inside.
const double _kRowScrollMargin = 44;
const double _kPaneScrollMargin = 88;

/// How far either scroller travels per frame while the finger is in its band.
const double _kAutoScrollStep = 8;

/// One shelf: its label, its books face-out on a plank, and in edit mode a row of
/// long-press draggables with delete badges.
///
/// A `Consumer` only so that a decoded cover can report its colour back to
/// `books.cover_color`; the shelf itself is still driven entirely by what the
/// parent passes in.
class ShelfRow extends ConsumerStatefulWidget {
  final Shelf shelf;
  final LibraryMode mode;

  /// How this row draws the books that are not in progress.
  ///
  /// Passed in rather than watched, because `LibraryPane` above this reads no shell
  /// state at all — the shell keeps it persistent across tab switches — and one
  /// widget in the chain reaching for a provider would quietly undo that.
  final ShelfDensity density;

  final VoidCallback onEditName;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  /// A book from *another* shelf was dropped on this one.
  ///
  /// Called with the row as the reader was shown it — this shelf's books in order
  /// with the arriving one inserted where the gap was — rather than with a bare
  /// index, because landing a book between two others renumbers the whole row and
  /// the receiving shelf is the only party that knows what was on screen.
  final void Function(String bookId, List<String> orderedBookIds)?
  onBookDropped;
  final void Function(List<String> bookIds)? onReorderBooks;
  final void Function(String bookId)? onDeleteBook;

  const ShelfRow({
    super.key,
    required this.shelf,
    required this.mode,
    required this.onEditName,
    required this.onDelete,
    required this.onLongPress,
    this.density = ShelfDensity.covers,
    this.onBookDropped,
    this.onReorderBooks,
    this.onDeleteBook,
  });

  @override
  ConsumerState<ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends ConsumerState<ShelfRow>
    with TickerProviderStateMixin {
  /// The row's own scroller, so a drag held near either end can move it.
  final ScrollController _rowScroll = ScrollController();

  /// The row's viewport, which is what "near either end" is measured against.
  final GlobalKey _rowKey = GlobalKey();

  /// One key per book, so the row can find out where its covers actually are.
  ///
  /// **Measured, because the covers cannot be computed.** A cover's width follows
  /// its decoded aspect ratio and its jittered height, so nothing above layout
  /// knows how wide a book is or where the next one starts — which is also why
  /// [ShelfBookDrag] has to carry a width over from the shelf a book was lifted
  /// from.
  ///
  /// **Keyed above the transform that parts the row, never below it.** The gap is
  /// painted, not laid out, so these boxes stay exactly where the row's layout put
  /// them for the whole drag. A pointer compared against them therefore cannot
  /// chase its own effect, which is the failure that makes a hand-rolled drop
  /// preview flicker between two indices.
  final Map<String, GlobalKey> _slotKeys = {};

  /// The book of *this* shelf that is in the air, if any.
  ///
  /// Set by this row's own draggable, which is why the shelves need no shared drag
  /// session between them: a shelf is either the one a book left or one the book
  /// is passing over, and it can always tell which from what it was handed.
  String? _liftedBookId;

  /// Where the book in flight would land in this row, indexed into the row with
  /// [_liftedBookId] taken out.
  ///
  /// Null means no drag is over this shelf — which is also how a shelf the finger
  /// has just left knows to close its gap again.
  int? _dropIndex;

  /// The width of the hole the book in flight left on its own shelf, from its
  /// payload. Both the gap this row opens and how far its covers slide.
  double _slotExtent = 0;

  /// Whether the book in flight is one being read, from its payload.
  ///
  /// Held rather than read from the drag each time, because [_stepAutoScroll]
  /// recomputes where the book would land while the row scrolls under a finger that
  /// is holding still — and it has no `DragTargetDetails` to consult.
  bool _draggedReading = false;

  /// Parts the row without animating, for the one frame a committed drop lands on.
  ///
  /// A drop changes the row's *layout* — the book really is in its new place now —
  /// while its covers are still carrying the paint-time slide that previewed it.
  /// Animating out of that would play every slide a second time, from positions
  /// that are already correct. A zero duration resolves the tween inside
  /// `didUpdateWidget`, so the very frame that shows the new order shows it at
  /// rest.
  bool _snapping = false;

  Timer? _autoScroll;
  int _rowScrollSign = 0;
  int _paneScrollSign = 0;

  /// The library's own vertical scroller, resolved from the tree while a drag is
  /// over this shelf so a book can be carried to a shelf below the fold.
  ///
  /// Looked up on a pointer move rather than on every tick of [_autoScroll],
  /// because reaching it is an inherited-widget lookup and the ticker runs at 60Hz.
  ScrollPosition? _paneScroll;

  /// Where the finger was last seen, so the row can keep working out where a book
  /// would land while it scrolls itself under a finger that is holding still.
  Offset _pointer = Offset.zero;

  /// The turn a lifted cover carries while it is in the air.
  ///
  /// Driven into [BookWidget.turnDrive], so a dragged book turns out by
  /// [kBookTurnAngle] exactly as it does under an ordinary hold — the same angle on
  /// the same timings, rather than a second rotation invented for the drag. The
  /// difference is when it unwinds: a hold lets go of it at stage two, because there
  /// the turn means *something is about to happen*, while a drag holds it out for as
  /// long as the book is off the shelf, where it means *this is the one you are
  /// carrying*.
  late final AnimationController _liftTurn;

  /// The book this row is setting back down, if any.
  ///
  /// The unwind cannot run on the flying cover, because there is no flying cover
  /// left by then: Flutter tears the feedback out of the overlay the instant the
  /// finger lifts. It runs on the cover that comes to rest in the row instead —
  /// which is close enough to where the feedback was to read as one motion, the gap
  /// having already opened under the finger.
  ///
  /// Which row does it depends on the drop: the shelf a book was dropped on for a
  /// drop that was taken, the shelf it came from for one that was refused.
  String? _landingBookId;

  /// One key per book, kept for the life of the row, used to carry a book's
  /// draggable *across* the change into edit mode.
  ///
  /// A drag belongs to the `Draggable`'s state: its recognizer is built once, in
  /// `initState`, and the pointer is routed to that object rather than to whatever
  /// is under the finger. So a drag survives the row being rebuilt if and only if
  /// the element does — and a global key is the one thing that makes the framework
  /// *move* an element instead of tearing it down and building a new one. Without
  /// this, entering edit mode mid-hold would destroy the very drag that entered it,
  /// and the reader would have to press the book a second time.
  final Map<String, GlobalKey> _handoverKeys = {};

  /// The book whose draggable is being carried into edit mode, if any.
  ///
  /// Only this one keeps its [_handoverKeys] entry once edit mode arrives. Every
  /// other cover is built keyless so that its recognizer is rebuilt with edit
  /// mode's much shorter [kShelfLiftDelay] — the delay is fixed when a recognizer
  /// is constructed, so an element that survives keeps the 700ms one it was born
  /// with, and that is only wanted for the gesture actually in flight.
  String? _handoverBookId;

  /// The lift's growing, kept apart from [_liftTurn] deliberately.
  ///
  /// The turn is *skipped* when the book was already turned by the hold that
  /// started the drag, and a scale sharing that controller would jump with it. This
  /// one always animates, so a cover comes loose the same way whichever gesture
  /// picked it up.
  late final AnimationController _liftScale;

  /// Where the cover's centre sat relative to the finger when the drag began.
  ///
  /// The book is picked up *in place*: it stays exactly where it stood and keeps
  /// that spacing from the finger for the whole drag, rather than leaping up to sit
  /// under the fingertip. Measured in [_anchorToPointer], which is the one callback
  /// handed both the pointer and the cover's box.
  Offset _pickUp = Offset.zero;

  @override
  void initState() {
    super.initState();
    _liftTurn = AnimationController(vsync: this, duration: kBookTurnDuration);
    _liftScale = AnimationController(
      vsync: this,
      duration: _kLiftScaleDuration,
    );
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  /// The density this row actually draws at, which is not always the active one.
  ///
  /// **`leaning` falls back to `covers` in edit mode, and the other two do not.**
  /// The rule lives here alone, because it is easy to get wrong in a way that shows
  /// up as a lying drop preview rather than as a wrong drawing.
  ///
  /// [ShelfBookDrag.slotExtent] is *measured* from the rendered slot and is the width
  /// of the gap a receiving shelf opens. So any density whose drawing changes on
  /// entering edit mode reports a gap sized for a book it is no longer drawing:
  ///
  /// - `covers` measures a cover and draws a cover. Nothing to reconcile.
  /// - `spines` measures a spine and draws a spine — **spines are edited as
  ///   spines**, which is what keeps this self-consistent, and is also the better
  ///   experience: rearranging a shelf while seeing nine of its books beats seeing
  ///   three and a sliver. A spine is 29–47pt wide, so it is a real drag target.
  /// - `leaning` cannot: shingled covers overlap, so a tap is genuinely ambiguous
  ///   about which book it hit, and the step is not the book's width. It therefore
  ///   draws face-out in edit mode and is the one density needing a `slotExtent`
  ///   override.
  ShelfDensity get _effectiveDensity =>
      widget.mode == LibraryMode.editLibrary &&
          widget.density == ShelfDensity.leaning
      ? ShelfDensity.covers
      : widget.density;

  /// Anchors the drag to the finger, and measures the cover on the way past.
  ///
  /// **Returning zero is not incidental.** [DragAvatar] derives both the feedback's
  /// position *and* `DragTargetDetails.offset` from one number, so the two cannot be
  /// chosen independently: an anchor that placed the cover nicely would hand every
  /// drop target the cover's corner instead of the finger, and the whole drop
  /// arithmetic here is finger-relative. So the anchor stays at the pointer and the
  /// cover is put back where it belongs by translating the *feedback* — which needs
  /// to know where the cover was relative to the finger, and this is the only
  /// callback the framework hands both of those.
  Offset _anchorToPointer(
    Draggable<Object> draggable,
    BuildContext context,
    Offset position,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    _pickUp = box == null || !box.hasSize
        ? Offset.zero
        : box.size.center(Offset.zero) - box.globalToLocal(position);
    return Offset.zero;
  }

  /// Wraps [child] in the small growing that says a cover has been picked up.
  Widget _liftScaled(Widget child) => AnimatedBuilder(
    animation: _liftScale,
    child: child,
    builder: (context, child) => Transform.scale(
      scale: 1 + _kLiftScale * _liftScale.value,
      child: child,
    ),
  );

  @override
  void didUpdateWidget(ShelfRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Leaving edit mode destroys the draggables mid-gesture, so nothing would ever
    // report the drag over.
    if (widget.mode != LibraryMode.editLibrary) {
      _stopAutoScroll();
      _liftedBookId = null;
      _dropIndex = null;
      // Nothing is in the air any more, so nothing is on its way down either.
      _landingBookId = null;
      _handoverBookId = null;
      _liftTurn.value = 0;
      _liftScale.value = 0;
    }
    final live = {for (final book in widget.shelf.books) book.id};
    _slotKeys.removeWhere((id, _) => !live.contains(id));
    _handoverKeys.removeWhere((id, _) => !live.contains(id));
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _liftTurn.dispose();
    _liftScale.dispose();
    _rowScroll.dispose();
    super.dispose();
  }

  /// What goes inside a book's slot, for the density this row is drawing at.
  ///
  /// One `switch`, so "how is a book drawn here" has a single answer. The slot, the
  /// draggable and every gesture around it are the row's and do not vary.
  Widget _buildBookContent(
    Book book,
    double bookHeight,
    bool isEditMode, {
    bool withHero = true,
  }) {
    // The book being set down carries the tail of the lift: the turn unwinds through
    // [BookWidget.turnDrive] below, and the growing has to come off out here, since
    // scaling a cover is not something the book itself does.
    final landing = book.id == _landingBookId;
    final content = switch (_effectiveDensity) {
      // Face-out in `covers`, and face-out in the other two for any book that is in
      // progress — keyed off the status rather than off the index, so it cannot
      // disagree with the promotion that put those books at the head.
      ShelfDensity.covers => _coverTile(book, bookHeight, isEditMode, withHero),
      ShelfDensity.leaning => _coverTile(
        book,
        bookHeight,
        isEditMode,
        withHero,
      ),
      ShelfDensity.spines =>
        book.status == bookStatusReading
            ? _coverTile(book, bookHeight, isEditMode, withHero)
            : ShelfSpineTile(
                book: book,
                baseHeight: bookHeight,
                onTap: isEditMode
                    ? () {}
                    : () => Navigator.pushNamed(
                        context,
                        AppRoutes.details,
                        arguments: book,
                      ),
              ),
    };
    return landing ? _liftScaled(content) : content;
  }

  /// A book drawn face-out, which is what every density does for some of its books.
  Widget _coverTile(
    Book book,
    double bookHeight,
    bool isEditMode,
    bool withHero,
  ) {
    final l10n = AppLocalizations.of(context);
    return ShelfBookTile(
      book: book,
      height: bookHeight,
      isEditMode: isEditMode,
      withHero: withHero,
      // Only for the one book on its way down: every other cover keeps its own
      // hold, which this would otherwise replace. See [_landingBookId].
      turnDrive: book.id == _landingBookId ? _liftTurn : null,
      onCoverSampled: (color) =>
          ref.read(libraryActionsProvider).recordCoverColor(book, color),
      // In edit mode the badge is the sole delete target. The no-op tap handler
      // keeps cover taps from bubbling to the page-level handler and
      // unintentionally leaving edit mode.
      onTap: isEditMode
          ? () {}
          : () => Navigator.pushNamed(
              context,
              AppRoutes.details,
              arguments: book,
            ),
      deleteBadge: _DeleteBookButton(
        key: ValueKey('delete_book_${book.id}'),
        label: l10n.deleteBookNamed(book.title),
        onPressed: () => widget.onDeleteBook?.call(book.id),
      ),
    );
  }

  int get _liftedIndex {
    final id = _liftedBookId;
    if (id == null) return -1;
    return widget.shelf.books.indexWhere((book) => book.id == id);
  }

  GlobalKey _slotKeyFor(String bookId) =>
      _slotKeys.putIfAbsent(bookId, GlobalKey.new);

  GlobalKey _handoverKeyFor(String bookId) =>
      _handoverKeys.putIfAbsent(bookId, GlobalKey.new);

  /// The laid-out box of [bookId]'s slot, or null if there isn't one to trust.
  ///
  /// **Not `findRenderObject`, and the difference is not stylistic.** A global key
  /// goes on naming its element while that element is *deactivated*, which is the
  /// state a `ListView` leaves the old arrangement in for part of the frame it
  /// reorders on — and [_slotExtentOf] is called from `build`, so it sees exactly
  /// that. `findRenderObject` asserts on a non-active element, and an exception
  /// thrown mid-build takes the whole shelf's subtree down with it: the row that
  /// failed to build is replaced for a frame, which on device looks like the plank
  /// losing its width just as a book lands.
  ///
  /// [Element.renderObject] makes no such assertion and answers null once an element
  /// is defunct, and [RenderObject.attached] rules out the merely deactivated — whose
  /// box has been detached from the pipeline and whose geometry is therefore no
  /// longer anybody's answer.
  RenderBox? _slotBoxOf(String bookId) {
    final context = _slotKeys[bookId]?.currentContext;
    if (context == null || !context.mounted) return null;
    final box = (context as Element).renderObject;
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// How much room [bookId] takes along the row, its margins included.
  ///
  /// **Measured, and the fallback only covers the frame before there is anything to
  /// measure.** The number travels to whichever shelf a book is dropped on as the
  /// width of the gap that shelf has to open, so a wrong answer here is a drop
  /// preview that lies rather than a drawing that looks off.
  double _slotExtentOf(String bookId, double bookHeight) {
    final book = widget.shelf.books.firstWhere(
      (b) => b.id == bookId,
      orElse: () => widget.shelf.books.first,
    );
    final coverEstimate = bookHeight * kDefaultCoverAspect + 2 * _kSlotMargin;

    // **`leaning` does not use the measured box, and this is the one density that
    // has to override it.** A shingled slot is one [kShelfLeanStep] wide — about a
    // quarter of a cover — but a lift from this row lands in edit mode, which draws
    // face-out. Reporting the strip would ask the receiving shelf to open a gap a
    // quarter of the size of the book about to fill it, and the drop preview would be
    // a promise the drop then breaks.
    //
    // `covers` measures a cover and draws a cover. `spines` measures a spine and
    // draws a spine — spines are edited as spines precisely so that stays true. Only
    // `leaning` changes its drawing on the way into edit mode, and only `leaning`
    // pays for it here.
    if (_effectiveDensity == ShelfDensity.leaning &&
        book.status != bookStatusReading) {
      return coverEstimate;
    }

    final measured = _slotBoxOf(bookId)?.size.width;
    if (measured != null) return measured;
    // Nothing laid out yet. A cover's default ratio is what `BookWidget` itself
    // draws until one decodes, and no book can be lifted inside the first
    // [kShelfLiftDelay] anyway — but a spine is a third of that width, so guessing a
    // cover for one would open a gap three times too wide.
    if (_effectiveDensity == ShelfDensity.spines &&
        book.status != bookStatusReading) {
      return shelfSpineWidth(book, bookHeight);
    }
    return coverEstimate;
  }

  double? _slotCentreOf(String bookId) {
    final box = _slotBoxOf(bookId);
    if (box == null) return null;
    return box.localToGlobal(Offset.zero).dx + box.size.width / 2;
  }

  /// Where a book held at [pointerX] would be inserted, as an index into this row
  /// with the lifted book taken out.
  ///
  /// The finger is compared against the *centre* of each cover, so a book is only
  /// stepped over once the finger is more than halfway past it. That is the rule
  /// `ReorderableListView` used to apply within a shelf, and it is what keeps the
  /// gap still while a finger rests on a boundary.
  ///
  /// **Then clamped to the zone the book belongs to.** Every shelf draws its
  /// in-progress books first, so a row is two regions and neither can be entered
  /// from the other: a book being read cannot be filed behind one that is not, and a
  /// book that is not cannot jump the queue. [reading] says which region the book in
  /// flight came from — for a book arriving from another shelf, this row has no other
  /// way to know.
  ///
  /// Clamped here rather than at each call site, so a third caller cannot forget.
  /// The point of clamping at all is that **the gap never opens where the book
  /// cannot land**: a preview that has to be corrected on release is a preview that
  /// lied.
  int _dropIndexFor(double pointerX, {required bool reading}) {
    var index = 0;
    var measuredOne = false;
    for (final book in widget.shelf.books) {
      if (book.id == _liftedBookId) continue;
      final centre = _slotCentreOf(book.id);
      // A row builds lazily, so the covers scrolled off either end have no box to
      // measure. Which end they are off is enough to place them: everything before
      // the first built cover is behind the finger, everything after the last one
      // is ahead of it.
      if (centre == null) {
        if (measuredOne) break;
        index++;
        continue;
      }
      measuredOne = true;
      if (centre >= pointerX) break;
      index++;
    }

    // Measured on the row *without* the lifted book, which is the row these indices
    // are into.
    final rest = [
      for (final book in widget.shelf.books)
        if (book.id != _liftedBookId) book,
    ];
    return clampDropIndex(
      index,
      headCount: rest
          .takeWhile((book) => book.status == bookStatusReading)
          .length,
      rowLength: rest.length,
      reading: reading,
    );
  }

  /// How far the cover at [index] slides to preview the drop, in logical pixels.
  ///
  /// Two independent effects, and one cover can be under both at once: the hole the
  /// lifted book left pulls everything after it back by a slot, and the gap opening
  /// at [_dropIndex] pushes everything from there on forward by one. On a
  /// same-shelf drag that has not yet crossed a cover they cancel exactly, which is
  /// what leaves the row looking untouched until it should not.
  ///
  /// **Paint, not layout.** Sliding the covers rather than re-laying the row out is
  /// what keeps the scroll extent fixed, keeps the keyed boxes in [_slotKeys] where
  /// the pointer arithmetic expects them, and lets a plain implicit animation carry
  /// the parting for free.
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

  Duration get _partDuration => _snapping ? Duration.zero : _kPartDuration;

  /// A book has just left the shelf.
  ///
  /// In view mode this is *also* the moment edit mode is entered: the hold that
  /// lifted the book is the same hold that used to be answered by
  /// [BookWidget.onLongPress], and letting the drag announce it is what stops the
  /// two racing — a timer firing beside a recognizer would sometimes cancel the tap
  /// that the recognizer needed, and edit mode would be missed altogether.
  void _onLift(int index, String bookId, double slotExtent, bool isEditMode) {
    if (!_reduceMotion) {
      if (isEditMode) {
        // `from: 0` rather than `forward()`: an unwind interrupted by a second
        // lift would otherwise start this one part-turned.
        _liftTurn.forward(from: 0);
      } else {
        // The hold has already turned this cover all the way out — that is what the
        // turn is *for* while a finger rests on a book. Animating it again would
        // unturn a turned book and start over.
        _liftTurn.value = 1;
      }
      // Always animated, either way: this is the only cue that the book has come
      // loose, since it is picked up where it stood.
      _liftScale.forward(from: 0);
    }
    setState(() {
      _liftedBookId = bookId;
      _landingBookId = null;
      _slotExtent = slotExtent;
      if (!isEditMode) {
        _handoverBookId = bookId;
        // **Seeded, or the row closes up under the finger.**
        //
        // A lift *inside* edit mode gets this for free: the shelf is already a
        // `DragTarget`, so building the drag avatar reports a move at once and the
        // gap opens exactly where the book left — the hole and the gap cancel out
        // in [_shiftFor] and the row looks untouched, which is the point. Here
        // there is no target to report to yet, the shelf only becoming one on the
        // frame edit mode arrives. And `onMove` answers pointer *movement*, not a
        // target appearing under a finger holding still, so nothing would reopen
        // it: the books to the right would slide over the held book's slot and stay
        // there until the finger moved.
        _dropIndex = index;
      }
    });
    if (!isEditMode) widget.onLongPress();
  }

  /// The row of covers, in either mode. Every cover is a long-press draggable, and
  /// in edit mode the shelf around them is the drop target that decides where one
  /// lands.
  ///
  /// **Draggable in view mode too, which is not decoration.** It is the only way a
  /// hold can both enter edit mode *and* leave the reader already carrying the book
  /// — a drag cannot be started programmatically, and a `Draggable` that appears
  /// after the finger is down can never adopt that pointer, because a recognizer
  /// claims its pointer route at pointer-down. So the draggable that will carry the
  /// book has to be there before the hold completes. See [_handoverKeys].
  ///
  /// **Deliberately not a `ReorderableListView`.** That widget owns the drag it
  /// starts and cannot hand it to a second list, which is what forced the old split
  /// in the first place — a long press reordered within one shelf, and a separate
  /// instant vertical `Draggable` was the only way to reach another one. A single
  /// drag that can do both has to be a drag the shelves *share*, so the lift, the
  /// preview and the drop are all wired by hand here instead.
  Widget _buildBookRow(double bookHeight, {required bool isEditMode}) {
    final books = widget.shelf.books;
    if (_effectiveDensity == ShelfDensity.leaning) {
      return _buildLeaningRow(bookHeight, isEditMode: isEditMode);
    }
    return SizedBox(
      key: _rowKey,
      child: ListView.builder(
        controller: _rowScroll,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        // Edit mode's covers carry a delete badge that hangs off the top-left
        // corner, so the row must not clip; the view-mode row is behind
        // [_EdgeFades], whose fade only means anything against a clipped edge.
        clipBehavior: isEditMode ? Clip.none : Clip.hardEdge,
        padding: const EdgeInsets.symmetric(horizontal: _kSlotMargin),
        // One past the last book, for [_buildTailRoom].
        itemCount: books.length + 1,
        itemBuilder: (context, index) => index == books.length
            ? _buildTailRoom()
            : _buildBook(
                index,
                books[index],
                bookHeight,
                isEditMode: isEditMode,
              ),
      ),
    );
  }

  /// The row at `ShelfDensity.leaning`: books in progress face-out, then everything
  /// else shingled and leaning right.
  ///
  /// **A `Stack`, because a `ListView` cannot paint in this order.** A list paints in
  /// child order, which would put the *rightmost* book in front — the opposite of a
  /// leaning cascade, and the opposite of the emphasis this density exists to give.
  /// So the shingled books are emitted **highest index first** and positioned by
  /// hand, which leaves book 0 painted last and therefore on top.
  ///
  /// **The head is a `Row`, not part of the `Stack`.** A face-out cover's width is
  /// whatever its decoded aspect makes it, so positioning the head by hand would mean
  /// guessing every one of those widths; laying it out lets Flutter answer. Only the
  /// group's own total width is approximated — see [shelfLeanGroupWidth].
  ///
  /// **This costs one built tile per book, where the list built about four.** A
  /// `Stack` has no laziness. It is the one place in this feature that spends more
  /// than it saves, and it is spent knowingly: the point of the density is shelves
  /// that *fit*, and a shelf that fits is a shelf whose tiles were all going to be
  /// built anyway.
  Widget _buildLeaningRow(double bookHeight, {required bool isEditMode}) {
    final books = widget.shelf.books;
    final head = readingHeadCount(widget.shelf);
    final shingled = books.sublist(head);

    final group = SizedBox(
      width: shelfLeanGroupWidth(shingled.length, bookHeight),
      // **Explicitly tall, and it has to be.** A `Positioned` given only `left` and a
      // `width` leaves its child's height unbounded, and the `OverflowBox` below
      // resolves to infinity and asserts. Reserving the row's own extent bounds it,
      // and `bookRowExtent` is the same reservation the rest of the row makes for a
      // book that hashes tall.
      height: bookRowExtent(bookHeight),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Reversed: the last book is emitted first and painted first, so the
          // leading book ends up on top and is hit-tested before the books it
          // covers. Do not "tidy" this into forward order — it is the whole
          // drawing. `test/shelf_leaning_layout_test.dart` pins it.
          for (var i = shingled.length - 1; i >= 0; i--)
            Positioned(
              left: shelfLeanOffset(i, bookHeight),
              top: 0,
              bottom: 0,
              // The exposed strip, so a tap lands on the book a reader can see
              // rather than on whichever one is frontmost. See
              // [shelfLeanSlotWidth].
              width: shelfLeanSlotWidth(i, shingled.length, bookHeight),
              child: OverflowBox(
                alignment: Alignment.bottomLeft,
                maxWidth: double.infinity,
                child: _buildBook(
                  head + i,
                  shingled[i],
                  bookHeight,
                  isEditMode: isEditMode,
                ),
              ),
            ),
        ],
      ),
    );

    return SizedBox(
      key: _rowKey,
      child: SingleChildScrollView(
        controller: _rowScroll,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: _kSlotMargin),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < head; i++)
              _buildBook(i, books[i], bookHeight, isEditMode: isEditMode),
            // A full gap between the books standing face-out and the cascade, so the
            // two groups do not read as one run.
            if (head > 0 && shingled.isNotEmpty)
              const SizedBox(width: _kSlotMargin),
            if (shingled.isNotEmpty) group,
          ],
        ),
      ),
    );
  }

  /// The air either side of [book]'s slot.
  ///
  /// [_kSlotMargin] each side ordinarily, which is what puts 15pt between two
  /// covers.
  ///
  /// **Spines touch**, the way books on a plank actually do, so a spine takes no
  /// margin at all — except on the leading edge of the *first* one, which keeps its
  /// half so that there is a full 15pt between the reading books standing face-out
  /// and the spines beginning. Without that the first spine leans against the last
  /// cover and the two groups read as one run.
  ///
  /// **A shingled book takes none either**, for a different reason: it is placed by
  /// [shelfLeanOffset] rather than laid out in sequence, so a margin here would shift
  /// it off the offset it was given. The gap before the cascade is a `SizedBox` in
  /// [_buildLeaningRow] instead.
  EdgeInsets _slotMarginFor(int index, Book book) {
    if (book.status == bookStatusReading) {
      return const EdgeInsets.symmetric(horizontal: _kSlotMargin);
    }
    switch (_effectiveDensity) {
      case ShelfDensity.covers:
        return const EdgeInsets.symmetric(horizontal: _kSlotMargin);
      case ShelfDensity.leaning:
        return EdgeInsets.zero;
      case ShelfDensity.spines:
        final firstSpine = index == readingHeadCount(widget.shelf);
        return EdgeInsets.only(left: firstSpine ? _kSlotMargin : 0);
    }
  }

  Widget _buildBook(
    int index,
    Book book,
    double bookHeight, {
    required bool isEditMode,
  }) {
    final slotExtent = _slotExtentOf(book.id, bookHeight);
    return SizedBox(
      key: _slotKeyFor(book.id),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _shiftFor(index)),
        duration: _partDuration,
        // Not `easeOutCubic`: that leaves at full speed, so a cover appears to
        // jump the instant the gap moves. This eases both ends, which reads as
        // the shelf being pushed rather than cut.
        curve: Curves.fastOutSlowIn,
        builder: (context, dx, child) =>
            Transform.translate(offset: Offset(dx, 0), child: child),
        // Bottom-aligned so a book that hashes short sits on the shelf line
        // instead of floating, and so the row's tight height constraint is
        // loosened — without this the book would be stretched to the row extent
        // and the height jitter would vanish.
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: _slotMarginFor(index, book),
            child: LongPressDraggable<ShelfBookDrag>(
              // Keyed in view mode so the element — and with it the drag — survives
              // the rebuild into edit mode; keyed in edit mode only for the book
              // actually being carried across. See [_handoverKeys].
              key: isEditMode
                  ? (book.id == _handoverBookId
                        ? _handoverKeyFor(book.id)
                        : null)
                  : _handoverKeyFor(book.id),
              // In view mode the hold *is* the gesture that enters edit mode, so it
              // waits as long as that always has. Once there, a lift is quicker.
              delay: isEditMode ? kShelfLiftDelay : kBookStageTwoDelay,
              // See [_anchorToPointer]: the anchor is the finger, and the cover is
              // put back where it stood by the translation on the feedback.
              dragAnchorStrategy: _anchorToPointer,
              data: ShelfBookDrag(
                bookId: book.id,
                shelfId: widget.shelf.id,
                slotExtent: slotExtent,
                reading: book.status == bookStatusReading,
              ),
              onDragStarted: () =>
                  _onLift(index, book.id, slotExtent, isEditMode),
              onDragEnd: (details) {
                _stopAutoScroll();
                // A drop that was taken has already moved the book in state, so the
                // preview slide has to be dropped rather than unwound. A drop that
                // was refused changed nothing, so the row closes the way it opened.
                if (details.wasAccepted) {
                  _snapNextFrame();
                } else {
                  // No shelf took it, so no shelf will set it down. This row has
                  // to: it is the one the cover is about to reappear in.
                  _setDown(book.id, alreadyLifted: true);
                }
                setState(() {
                  _liftedBookId = null;
                  _dropIndex = null;
                  // Released, so the element no longer has a drag to protect. Losing
                  // its key rebuilds it with edit mode's shorter lift delay.
                  _handoverBookId = null;
                });
              },
              feedback: Builder(
                // A `Builder`, because the value it reads is not known yet when this
                // widget is *constructed*. The row builds `feedback` a frame ahead of
                // the gesture; [_anchorToPointer] runs when the drag actually starts,
                // and the overlay mounts this only after that — so reading [_pickUp]
                // at build time reads this drag's measurement rather than the last
                // one's.
                builder: (context) => Transform.translate(
                  offset: _pickUp,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -0.5),
                    child: _liftScaled(
                      Material(
                        color: Colors.transparent,
                        child: BookWidget(
                          imageUrl: book.thumbnail,
                          isbn: book.isbn,
                          title: book.title,
                          // The cover's own height, not a larger one. The book is
                          // lifted from where it stood, so starting at any other
                          // size would be the jump this is here to avoid; the
                          // growing is [_liftScaled]'s job and it animates.
                          height: bookHeight,
                          // Jitter is hashed from the ISBN *and* the page count, so
                          // a feedback given only the ISBN is a subtly different
                          // book from the one that was lifted.
                          pageCount: book.pageCount,
                          // The turn that marks this as the book in hand. Driven
                          // from the row, because the drag has taken the pointer
                          // that the book's own hold would have answered to.
                          turnDrive: _liftTurn,
                          pressEffect: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Invisible rather than faint, and still holding its slot. The hole
              // it leaves is closed by [_shiftFor], and the gap that stands for the
              // book has moved to wherever the finger is — a ghost left behind in
              // the original slot would claim it had not.
              childWhenDragging: Opacity(
                opacity: 0,
                child: _buildBookContent(
                  book,
                  bookHeight,
                  isEditMode,
                  withHero: false,
                ),
              ),
              child: _buildBookContent(book, bookHeight, isEditMode),
            ),
          ),
        ),
      ),
    );
  }

  /// Room at the end of the row for a cover arriving from another shelf.
  ///
  /// A book being reordered within its own row left a slot behind and needs none.
  /// One arriving from elsewhere does: the row's content is exactly as wide as the
  /// covers already standing on it, so without this the last book would be pushed
  /// past the scrollable extent and clipped out of the frame instead of making
  /// room.
  Widget _buildTailRoom() {
    final wanted = _dropIndex != null && _liftedBookId == null
        ? _slotExtent
        : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: wanted),
      duration: _partDuration,
      curve: Curves.fastOutSlowIn,
      builder: (context, width, _) => SizedBox(width: width),
    );
  }

  // ---- the drag itself ------------------------------------------------------

  void _onDragOver(DragTargetDetails<ShelfBookDrag> details) {
    _pointer = details.offset;
    _draggedReading = details.data.reading;
    final index = _dropIndexFor(_pointer.dx, reading: details.data.reading);
    if (index != _dropIndex || details.data.slotExtent != _slotExtent) {
      setState(() {
        _dropIndex = index;
        _slotExtent = details.data.slotExtent;
      });
    }
    _driveAutoScroll();
  }

  void _onDrop(DragTargetDetails<ShelfBookDrag> details) {
    final drag = details.data;
    final ids = [
      for (final book in widget.shelf.books)
        if (book.id != drag.bookId) book.id,
    ];
    ids.insert((_dropIndex ?? ids.length).clamp(0, ids.length), drag.bookId);

    _stopAutoScroll();
    if (drag.shelfId == widget.shelf.id) {
      // A hold and a release with nothing in between is not an edit, and writing
      // one would renumber every book on the shelf for nothing.
      final before = [for (final book in widget.shelf.books) book.id];
      if (!listEquals(before, ids)) widget.onReorderBooks?.call(ids);
    } else {
      widget.onBookDropped?.call(drag.bookId, ids);
    }
    _snapNextFrame();
    _setDown(drag.bookId, alreadyLifted: drag.shelfId == widget.shelf.id);
    setState(() => _dropIndex = null);
  }

  /// Unwinds the lift on [bookId] as it comes to rest in this row — both the turn
  /// and the growing.
  ///
  /// [alreadyLifted] says whether *this row's* controllers are the ones holding the
  /// cover out. They are for a book put back where it came from and for a reorder
  /// within one shelf, and they are not for a book arriving from another shelf: that
  /// cover was lifted by the row it left, and these have never moved off zero.
  /// Unwinding from zero is no animation at all, so they are wound on first.
  ///
  /// Keeping the current values where there are some matters as much: a drag
  /// released before the lift finished should settle from where it got to, not snap
  /// out to a full lift it never reached and then come back.
  void _setDown(String bookId, {required bool alreadyLifted}) {
    if (_reduceMotion) return;
    if (!alreadyLifted) {
      _liftTurn.value = 1;
      _liftScale.value = 1;
    }
    setState(() => _landingBookId = bookId);
    _liftScale.animateBack(
      0,
      duration: kBookReleaseDuration,
      curve: Curves.easeOut,
    );
    _liftTurn
        .animateBack(0, duration: kBookReleaseDuration, curve: Curves.easeOut)
        .whenComplete(() {
          // Resolves on cancellation too, which is what a second lift starting
          // mid-unwind does — and that lift owns the controllers now, so only a
          // landing that is still the current one may clear itself.
          if (!mounted || _landingBookId != bookId) return;
          setState(() => _landingBookId = null);
        });
  }

  void _snapNextFrame() {
    if (_snapping) return;
    _snapping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _snapping = false);
    });
  }

  // ---- carrying a book past the edge of what is on screen -------------------

  /// This shelf's whole drop target, which is also its own render box: the edit-mode
  /// build returns the `SizedBox` the `DragTarget` sits in.
  RenderBox? get _shelfBox {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  /// Which way [viewport] is being asked to move, or 0 for "the finger is not at
  /// either edge of it": -1 towards the start, 1 towards the end.
  int _edgeSign(RenderBox? viewport, Axis axis, double margin) {
    if (viewport == null || !viewport.hasSize) return 0;
    final origin = viewport.localToGlobal(Offset.zero);
    final start = axis == Axis.horizontal ? origin.dx : origin.dy;
    final extent = axis == Axis.horizontal
        ? viewport.size.width
        : viewport.size.height;
    final at = axis == Axis.horizontal ? _pointer.dx : _pointer.dy;
    if (at < start + margin) return -1;
    if (at > start + extent - margin) return 1;
    return 0;
  }

  /// Starts, redirects or stops the scrolling a drag at [_pointer] is asking for.
  ///
  /// Two scrollers, one ticker. The row moves so a book can be put down beyond the
  /// covers the frame can hold; the library moves so it can be put down on a shelf
  /// the frame cannot hold at all — which, until this existed, meant a book could
  /// only ever be moved between two shelves that happened to be on screen together.
  void _driveAutoScroll() {
    final pane = Scrollable.maybeOf(context, axis: Axis.vertical);
    _paneScroll = pane?.position;
    final row = _edgeSign(
      _rowKey.currentContext?.findRenderObject() as RenderBox?,
      Axis.horizontal,
      _kRowScrollMargin,
    );
    final paneSign = _edgeSign(
      pane?.context.findRenderObject() as RenderBox?,
      Axis.vertical,
      _kPaneScrollMargin,
    );
    if (row == _rowScrollSign && paneSign == _paneScrollSign) return;
    _rowScrollSign = row;
    _paneScrollSign = paneSign;
    _autoScroll?.cancel();
    _autoScroll = null;
    if (row == 0 && paneSign == 0) return;
    _autoScroll = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _stepAutoScroll(),
    );
  }

  void _stepAutoScroll() {
    if (!mounted) return;
    final rowMoved = _nudge(
      _rowScroll.hasClients ? _rowScroll.position : null,
      _rowScrollSign,
    );
    final paneMoved = _nudge(_paneScroll, _paneScrollSign);
    if (!rowMoved && !paneMoved) return;

    // **The library moving takes this shelf out from under the finger, and Flutter
    // will not notice.** A `DragTarget` is only re-hit-tested when a pointer event
    // arrives, so a finger parked in the bottom band would keep this shelf as the
    // active target while the shelves slid past it — and the book would land here
    // rather than on whatever is now under the finger. Stopping when the finger is
    // no longer over us keeps the gap and the drop honest: the reader sees where it
    // will go, and the smallest movement hands the drag to the shelf that has
    // arrived.
    final box = _shelfBox;
    if (paneMoved &&
        box != null &&
        !(box.localToGlobal(Offset.zero) & box.size).contains(_pointer)) {
      _stopAutoScroll();
      return;
    }

    // The row moved under a finger that did not, so where the book would land moved
    // with it. Worked out again here rather than waiting for a pointer event that,
    // for a finger parked at the end of a row, may never come.
    if (_dropIndex == null) return;
    final index = _dropIndexFor(_pointer.dx, reading: _draggedReading);
    if (index != _dropIndex) setState(() => _dropIndex = index);
  }

  /// Moves [position] one step along, and reports whether it had anywhere to go.
  bool _nudge(ScrollPosition? position, int sign) {
    if (position == null || sign == 0) return false;
    final to = (position.pixels + sign * _kAutoScrollStep).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (to == position.pixels) return false;
    position.jumpTo(to);
    return true;
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _rowScrollSign = 0;
    _paneScrollSign = 0;
    _paneScroll = null;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final bookHeight = screenHeight * 0.15;
    // Books can hash up to 6% taller than the base, so the row has to reserve
    // that or every tall book gets clipped along the top.
    final rowExtent = bookRowExtent(bookHeight);
    final isEditMode = widget.mode == LibraryMode.editLibrary;

    // **Full width, with the shelf centred inside it — the row is 95% wide, not
    // 95% wide and flush left.**
    //
    // Without this the shelf hangs off the leading edge of the screen and stops
    // 19.65pt short of the trailing one, which is visible as soon as you look for
    // it and was reported as exactly that. The cause is two widgets away and is
    // not obvious from here: `RefreshIndicator` wraps its child in a *loose*
    // `Stack`, so the library's vertical scroll view shrink-wraps to its widest
    // child rather than filling the pane — and a `Stack` aligns to `topStart`, so
    // the whole column of shelves is then pinned to the left edge. The
    // `crossAxisAlignment: center` on the column above cannot help: it centres
    // children within a box that has already collapsed onto them.
    //
    // `library_view.dart` already documents that loose Stack, but only for its
    // effect on *height* (which is why the background lives outside the
    // indicator). This is the same widget's effect on width.
    //
    // Claiming the full width here rather than patching the parent keeps the row
    // correct wherever it is placed, and it is what makes the plank's Hero honest:
    // `ShelfWidget` reasons that its flight needs no `createRectTween` because both
    // rects are "centred on the screen's midline". The details-page plank is; this
    // one was 9.83pt to the left of it, so the premise was quietly false and the
    // plank drifted sideways across the flight.
    final Widget innerContent = Column(
      children: [
        SizedBox(
          height: rowExtent,
          width: screenWidth * 0.95,
          child: Stack(
            alignment: Alignment.bottomLeft,
            children: [
              Positioned(
                top: 0,
                child: SizedBox(
                  height: rowExtent,
                  width: screenWidth * 0.95,
                  child: isEditMode
                      // Built even for an empty shelf, unlike the read-only row:
                      // an empty plank is a legitimate destination, and
                      // [_buildTailRoom] is what shows the book arriving on it.
                      ? _buildBookRow(bookHeight, isEditMode: true)
                      : widget.shelf.books.isEmpty
                      ? const SizedBox.shrink()
                      : _EdgeFades(
                          child: _buildBookRow(bookHeight, isEditMode: false),
                        ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: isEditMode ? widget.onEditName : null,
                  onLongPress: isEditMode ? widget.onDelete : null,
                  // Travels with the plank below, so the shelf reaches the
                  // details page as one object.
                  child: ShelfLabel(
                    label: widget.shelf.name,
                    // The count is what gives the clipped row's edge a meaning.
                    // `shelvedBookCount` rather than `books.length` so it counts
                    // the covers actually on this plank; the details page uses
                    // the same function, which is what keeps the hero the same
                    // width at both ends of its flight.
                    count: shelvedBookCount(widget.shelf),
                    heroTag: shelfLabelHeroTag(widget.shelf.id),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Flies to the details page with whichever book on this shelf was
        // tapped, and with the name tab above it. Tagged in edit mode too,
        // harmlessly: a cover tap there is a no-op, so there is no push for
        // either of them to fly on.
        ShelfWidget(heroTag: shelfHeroTag(widget.shelf.id)),
      ],
    );

    if (isEditMode) {
      // **The target is outside the bottom padding on purpose**, so consecutive
      // shelves tile the column with nothing between them. A finger crossing from
      // one shelf to the next is over a target the whole way, and the gap it is
      // carrying never blinks shut in transit through a 26pt dead band.
      //
      // **Full width, and nothing drawn on it.** The shelf used to tint and frame
      // itself while a book from elsewhere hovered, back when a cross-shelf drop
      // was a blind append and the frame was the only thing that said *which*
      // shelf would take it. The gap opening between two covers says that now, and
      // says it more precisely — the frame had become a second, vaguer answer to a
      // question already answered, and it fired for exactly half of the drags.
      return SizedBox(
        width: double.infinity,
        child: DragTarget<ShelfBookDrag>(
          // **Everything is accepted, this shelf's own books included.** A drop here
          // is a reorder when the book came from this row and a move when it did
          // not, and neither can be previewed without being told where the finger
          // is — which only a target that accepted the drag is told.
          onWillAcceptWithDetails: (details) {
            _onDragOver(details);
            return true;
          },
          onMove: _onDragOver,
          onLeave: (_) {
            _stopAutoScroll();
            // Animated rather than snapped: the drag is still going on somewhere
            // else, so this row's gap should close the way it opened.
            setState(() => _dropIndex = null);
          },
          onAcceptWithDetails: _onDrop,
          builder: (context, candidateData, rejectedData) => Padding(
            padding: const EdgeInsets.only(bottom: 26),
            child: innerContent,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: SizedBox(width: double.infinity, child: innerContent),
    );
  }
}

/// Softens whichever ends of a shelf's row have books beyond them.
///
/// A shelf holds far more books than its row can show — at `screenHeight * 0.15`
/// the covers are ~84pt wide in ~340pt of usable row, so about three and a half fit
/// — and the sole signal that the rest exist is the row's hard clip at the frame
/// edge. A cover guillotined mid-spine reads as a rendering fault, not as an
/// invitation to swipe. The gradient turns the same clip into an edge that is
/// obviously *unfinished*.
///
/// **Both ends, not just the trailing one, and the leading edge is the one that was
/// actually reported.** A row that has been scrolled has books cut off behind it as
/// well as ahead, and the leading clip is the more misleading of the two: a shelf
/// resting mid-scroll shows a half cover hard against the screen's left margin,
/// where there is no padding to excuse it, so it reads less like "more this way"
/// than like a book drawn in the wrong place. Fading only the trailing edge would
/// also assert something false — that the row runs one way — and would make the
/// first book look deliberately different from the last.
///
/// **Each end is conditional on there being something past it, which is the whole
/// subtlety.** An unconditional mask would fade the first and last books of a
/// three-book shelf that scrolls nowhere, inventing an affordance for travel that
/// cannot happen; it would also dim the leading book of a row sitting at rest at
/// its start, which is the ordinary state of most shelves. So the two ends are
/// driven independently off `pixels` against `minScrollExtent` and
/// `maxScrollExtent`: at rest at the start only the trailing edge is soft, mid-row
/// both are, and at the end only the leading one is. Arriving at either end is
/// therefore a visible arrival rather than a row that looks endless in both
/// directions.
///
/// **Not used in edit mode.** The delete badges sit 22pt outside their covers'
/// top-left, and a `ShaderMask` composites its child into a saved layer, which
/// would clip them; edit mode also has no clipping problem to solve, since the
/// reader is manipulating the row rather than reading it.
class _EdgeFades extends StatefulWidget {
  const _EdgeFades({required this.child});

  final Widget child;

  /// Fraction of the row's width one gradient occupies. ~44pt on a 390pt phone,
  /// or about half a cover — wide enough to read as a fade rather than as a
  /// blurred edge, narrow enough that it never softens a whole book.
  @visibleForTesting
  static const double extent = 0.12;

  @override
  State<_EdgeFades> createState() => _EdgeFadesState();
}

class _EdgeFadesState extends State<_EdgeFades> {
  /// How much of each fade to draw, 0 (none) to 1 (full).
  ///
  /// Ramped over the last [_EdgeFades.extent] of travel at each end rather than
  /// switched on and off, or a gradient would pop out of existence in the final
  /// pixels of the scroll — which draws more attention than the fade itself.
  double _lead = 0;
  double _trail = 0;

  bool _onScroll(ScrollNotification n) {
    // Depth 0 is this row's own `ListView`. The library's vertical scroll view is
    // an ancestor, so its notifications never reach here — but a future nested
    // scrollable inside a book tile would, and it must not drive this mask.
    if (n.depth == 0) _apply(n.metrics);
    return false;
  }

  void _apply(ScrollMetrics m) {
    // Guards the first frame, where a ScrollMetrics may carry no extents yet and
    // reading `maxScrollExtent` would throw.
    if (!m.hasContentDimensions || !m.hasPixels) return;
    final ramp = m.viewportDimension * _EdgeFades.extent;
    if (ramp <= 0) return;
    final lead = ((m.pixels - m.minScrollExtent) / ramp).clamp(0.0, 1.0);
    final trail = ((m.maxScrollExtent - m.pixels) / ramp).clamp(0.0, 1.0);
    if ((lead - _lead).abs() > 0.001 || (trail - _trail).abs() > 0.001) {
      setState(() {
        _lead = lead;
        _trail = trail;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      // A row that overflows but has never been touched must already be faded —
      // that is the state a reader opening the library sees, and the one the whole
      // affordance exists for. `ScrollMetricsNotification` is dispatched when a
      // scrollable's extents are first established, so the initial measurement
      // arrives without waiting for a scroll that may never happen. It also fires
      // when a book is added or removed, which changes whether the row overflows
      // with no scroll involved.
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) {
          _apply(n.metrics);
          return false;
        },
        child: ShaderMask(
          // `dstIn` multiplies the child's alpha by the shader's, so the gradient
          // erases the row rather than painting a colour over it. That keeps the
          // fade correct against `surfaceVariant` in light and dark alike without
          // either colour being named here.
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            // Directional rather than left/right: a horizontal `ListView` under
            // RTL puts item 0 on the right, so `minScrollExtent` is the visual
            // right edge and a hardcoded left-to-right gradient would fade the
            // wrong ends. Start/end follow the list.
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: const [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            // When a factor is 0 its pair of stops coincides, which is a hard
            // transition of zero width — so a shelf whose books all fit is left
            // exactly as it was, with no mask visible at either end.
            stops: [
              0,
              _EdgeFades.extent * _lead,
              1 - _EdgeFades.extent * _trail,
              1,
            ],
          ).createShader(bounds, textDirection: direction),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The badge that takes a book off a shelf while the covers are wiggling.
///
/// **A white disc with a minus — iOS's own remove badge — rather than a red ✕.**
/// Three things were wrong with the red one, and the first is the one you saw before
/// reading any of them: a saturated red disc is the loudest thing that can be put on
/// a screen, and there was one per cover, so a shelf in edit mode read as a shelf
/// full of errors rather than a shelf waiting to be rearranged.
///
/// ✕ also means *close* everywhere else in this app — ending a visit, dismissing a
/// sheet — so this was the single place the glyph meant something destructive. And a
/// red fill under a white glyph is what a *committed* destructive action looks like,
/// which this is not: the tap opens a confirm sheet and nothing has happened yet. A
/// minus says "take this one out", which is exactly what the badge does, in the
/// vocabulary every reader already has from rearranging a home screen.
///
/// **Fixed colours, deliberately not the theme's.** The badge sits on a book cover,
/// not on the app's surface, and covers are arbitrary artwork under either theme — a
/// disc that flipped with the theme would be dark-on-dark half the time. What keeps
/// it off a *pale* cover, of which the shelves hold plenty, is the shadow rather than
/// the fill.
class _DeleteBookButton extends StatelessWidget {
  const _DeleteBookButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  /// The disc itself, centred on the cover's top-left corner.
  static const double _diameter = 22;

  /// The square the tap is taken over, bigger than the disc on purpose: 44pt is the
  /// minimum target both platforms ask for, and a 22pt one hanging mostly off the
  /// edge of its cover is the hardest kind there is to hit.
  static const double _target = 44;

  /// The minus, as a proportion of the disc rather than a glyph. Drawn rather than
  /// set as `Icons.remove`, because at this size the icon font's own padding and
  /// stroke weight decide the picture and neither of them is ours to choose.
  static const double _barWidth = 10;
  static const double _barThickness = 2;

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onPressed,
          child: const SizedBox(
            width: _target,
            height: _target,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xBFFFFFFF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    // The only thing separating the badge from a white jacket.
                    BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: SizedBox.square(
                  dimension: _diameter,
                  child: Center(
                    child: SizedBox(
                      width: _barWidth,
                      height: _barThickness,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          // Near-black rather than black, and rather than the
                          // theme's ink: see the note on this class.
                          color: Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.all(
                            Radius.circular(_barThickness / 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
