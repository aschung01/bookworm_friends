import 'package:flutter/material.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/read_filter.dart';
import 'package:bookworm_friends/ui/widgets/read_month_grid.dart';
import 'package:bookworm_friends/ui/widgets/read_pile.dart';
import 'package:bookworm_friends/ui/widgets/read_set_filter_popover.dart';

/// The Library tab's sheet: read books, in two states.
///
/// Collapsed is the spine pile standing on its shelf. Expanded is the same books
/// as covers grouped by the month they were finished in. **The sheet's position is
/// the view switch** — that is why there is no Shelves/Read toggle anywhere.
///
/// Contents only. The handle, the snap positions and the spring belong to
/// [LibrarySheet], which every tab's sheet shares.
///
/// ## It shows two sets, and its title says which
///
/// [books] and [setAsideBooks] are two queries — status 2 and status 3 — merged
/// **here and nowhere else**. That is the whole argument for `bookStatusSetAside`
/// having a value of its own: every surface that counts *finished* books goes on asking
/// the same question and getting the same answer, and the one surface that wants both
/// pays for it. Widening a shared query to serve this sheet would undo that in one line.
///
/// Which set is showing is [ReadSetFilter], and **the title is its read-out** rather
/// than there being a filter label anywhere — see that enum for why, and
/// [_openFilter] for what opens it.
class FinishedBooksSheet extends StatefulWidget {
  /// Every finished book, unfiltered. The year filter is applied here rather than
  /// in the query, because the year capsules are derived from this same list.
  final List<Book> books;

  /// Every book closed short of the end, unfiltered, from `setAsideBooksProvider` —
  /// or, on a friend's library, `userSetAsideBooksProvider`.
  ///
  /// Shown only under [ReadSetFilter.allRead], so the default view of this sheet is
  /// byte-for-byte the view it had before set aside existed, and the count matches the
  /// Library Card's a tab away.
  ///
  /// **A friend's library gets the same filter**, which means a visitor can see which
  /// books you gave up on. That is a deliberate visibility decision: the default is
  /// finished-only, so it is per-view rather than published, and hiding it there would
  /// leave a visitor's count disagreeing with the owner's with nothing on screen to
  /// explain the gap.
  ///
  /// Required rather than defaulted, with only two call sites, because a silent empty
  /// list here is a filter that quietly does nothing.
  final List<Book> setAsideBooks;

  /// Springs the sheet shut and goes inert while the library is being edited.
  final bool isEditMode;

  /// Year to show, or `0` for all time.
  final int filterYear;
  final ValueChanged<int> onFilterChanged;

  /// Height available to the whole sheet — the band it shares with the library.
  /// The expanded cap is taken from this. See [sheetExpandedExtent].
  final double maxExtent;

  /// See [LibrarySheet.bottomReserve].
  final double bottomReserve;

  /// See [LibrarySheet.onRestingExtent].
  final ValueChanged<double>? onRestingExtent;

  /// Handed to the [LibrarySheet] inside, not to this widget.
  ///
  /// The shell passes the *same* `GlobalKey` to all three tabs' sheets, which is what
  /// makes a tab switch re-parent one sheet element rather than build a new one — and
  /// therefore what makes the height spring instead of jump. It cannot be this
  /// widget's own `key`: this widget is the part that changes on a switch, and the
  /// sheet underneath is the part that stays. See [LibrarySheet].
  final Key? sheetKey;

  const FinishedBooksSheet({
    super.key,
    required this.books,
    required this.setAsideBooks,
    required this.isEditMode,
    required this.filterYear,
    required this.onFilterChanged,
    required this.maxExtent,
    this.bottomReserve = 0,
    this.onRestingExtent,
    this.sheetKey,
  });

  /// The expanded sheet fills the band it is given.
  ///
  /// Forwards to [sheetExpandedExtent] in `library_sheet.dart`, which is where the
  /// expanded position is defined for both capped sheets. Kept as an alias because
  /// the clearance and sheet tests name it, and because this is where a reader of
  /// the read view looks for it.
  static double expandedExtentFor(double available) =>
      sheetExpandedExtent(available);

  @override
  State<FinishedBooksSheet> createState() => _FinishedBooksSheetState();
}

class _FinishedBooksSheetState extends State<FinishedBooksSheet> {
  /// Which set the sheet is showing.
  ///
  /// **Held here rather than in a provider, unlike the year.** `readsFilterYearProvider`
  /// is shared state because the Library Card filters by the same year, so the two tabs
  /// have to agree; nothing outside this sheet has an opinion about which *set* it is
  /// showing. The cost, stated rather than discovered: this resets to the default
  /// whenever the element is rebuilt from scratch, which is a trip through the Friends
  /// list (`FriendsSheet` replaces this widget at the same position) or the library's
  /// first load. It survives an edit, a tab switch to Card and back, a collapse, and a
  /// visit — `_hiddenWhileEditing` and `_sheetForTab` keep one element across all four.
  /// If it ever needs to outlive a Friends detour, the promotion is a provider beside
  /// `readsFilterYearProvider` and this field becomes a `ref.watch`.
  ReadSetFilter _filter = ReadSetFilter.finishedOnly;

  /// The expanded header's title row, which the popover is hung from.
  ///
  /// It has to be the rect of the thing the reader actually touched, and only the
  /// expanded header carries a tappable title — so only that one takes the key. Sharing
  /// one key with the collapsed title would be a duplicate-key crash on any frame that
  /// held both.
  final GlobalKey _titleKey = GlobalKey();

  /// Every book the current mode shows, before the year filter.
  ///
  /// Finished-only returns the incoming list untouched — same object, same order, so
  /// the default view costs no work and cannot drift from the provider's ordering.
  List<Book> get _inMode => _filter.isFinishedOnly
      ? widget.books
      : _byCloseDate([...widget.books, ...widget.setAsideBooks]);

  List<Book> get _filtered => widget.filterYear == 0
      ? _inMode
      : _inMode
            .where(
              (b) =>
                  b.finishDate != null &&
                  b.finishDate!.year == widget.filterYear,
            )
            .toList();

  /// Two date-ordered lists interleaved back into one.
  ///
  /// Both providers order by `finish_date` descending, so concatenating them would draw
  /// every finished book and then start the dates again for the set-aside ones — and
  /// `ReadMonthGrid.group` is only order-preserving *within* a month, so the defect
  /// would show as set-aside books collected at the end of each month's row rather than
  /// in date order with the rest.
  ///
  /// On a set-aside row `finish_date` is the day the book was **closed**, not the day it
  /// was finished, which is exactly what lets it sort and group beside the others
  /// untouched.
  ///
  /// Undated books sort last, with the incoming order as the tiebreak — applied
  /// explicitly rather than leaning on the sort, because `List.sort` is not guaranteed
  /// stable, so "finished before set aside on the same day" has to be a rule or it is
  /// luck.
  static List<Book> _byCloseDate(List<Book> books) {
    final ranked = [
      for (var i = 0; i < books.length; i++) (book: books[i], order: i),
    ];
    ranked.sort((a, b) {
      final ad = a.book.finishDate;
      final bd = b.book.finishDate;
      if (ad == null || bd == null) {
        if (ad != bd) return ad == null ? 1 : -1;
      } else {
        final byDate = bd.compareTo(ad);
        if (byDate != 0) return byDate;
      }
      return a.order.compareTo(b.order);
    });
    return [for (final entry in ranked) entry.book];
  }

  /// Opens the completion filter under the title that reads it out.
  ///
  /// The menu is app-drawn — see [showReadSetFilterPopover], which records why the
  /// native `CNPopupMenuButton` that looks like an exact fit cannot be used for a
  /// label this size.
  ///
  /// Returning the mode it was already on is a legal answer and is compared here rather
  /// than refused there: a menu that ignores the row it has checked reads as broken.
  Future<void> _openFilter() async {
    final anchor = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchor == null) return;
    final chosen = await showReadSetFilterPopover(
      context,
      anchor: anchor,
      current: _filter,
    );
    if (chosen == null || chosen == _filter || !mounted) return;
    setState(() => _filter = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = _filtered;
    // Derived from the set the *mode* shows, not from the finished books alone, so
    // every capsule the rail offers leads to something. Switching to finished-only can
    // therefore drop the selected year off the rail — which is already a state this
    // sheet handles, since a friend's library is visited with a year chosen in
    // someone else's: `pageIndex` clamps and the grid says the year is empty.
    final years = readFilterYears(_inMode);

    // **The title is the filter's read-out.** Finished-only says `Books finished` and
    // counts what the Library Card counts a tab away; the inclusive mode says
    // `Books read`, and it is the only state whose count reads higher. The count tracks
    // the *visible* list either way, which is what makes the month headers below sum to
    // it.
    final titleText = _filter.isFinishedOnly
        ? l10n.finishedOnlyTitle
        : l10n.finishedBooksTitle;

    // Where a sideways swipe on the sheet lands: the year rail's own list, in the
    // rail's own order, so swiping and tapping cannot disagree about which way is
    // next. Clamped exactly as `ReadFilter` clamps it — `filterYear` need not be one
    // of the offered years, since the provider defaults to the current one and the
    // friend pair is shared by every friend, so a year picked in one library may sit
    // outside the range of the next.
    final pageIndex = years
        .indexOf(widget.filterYear)
        .clamp(0, years.length - 1);

    // What the *content* may occupy: the sheet keeps the tab bar's band and the home
    // indicator below the collapsible area, so both come off the top.
    final available =
        widget.maxExtent -
        widget.bottomReserve -
        MediaQuery.viewPaddingOf(context).bottom;

    return LibrarySheet(
      key: widget.sheetKey,
      // What this sheet is showing, so a tab switch springs the height rather than
      // jumping it. See [LibrarySheet.contentId].
      contentId: FinishedBooksSheet,
      isEditMode: widget.isEditMode,
      bottomReserve: widget.bottomReserve,
      onRestingExtent: widget.onRestingExtent,
      // Rests on the pile: the drawings call the collapsed state the default on
      // launch, and opening into a full grid would bury the library.
      initialDetent: LibrarySheetDetent.collapsed,
      fullExtent: widget.maxExtent,
      expandedExtent: FinishedBooksSheet.expandedExtentFor(available),
      // The grid is worth the whole band, but a whole band of grid is also the
      // library gone. See [sheetMidExtent].
      midExtent: sheetMidExtent(available),
      collapsedBodyExtent: ReadPile.extent,
      minHeightFraction: sheetMinHeightFraction,
      // A swipe across the card moves along the same year list the capsules offer, and
      // the grid slides a page's width to answer. See [LibrarySheet.pageIndex].
      //
      // Collapsed, the spine pile is a horizontal scroller and takes the swipe for
      // itself whenever it is long enough to move — which is the right split, since
      // running along the pile is what a sideways drag means there. A pile that fits
      // the card declines the drag and the year turns instead.
      pageIndex: pageIndex,
      pageCount: years.length,
      onPageChanged: (index) => widget.onFilterChanged(years[index]),
      // Collapsed, the filter is a popover in the header: there is only the pile
      // to show and capsules would cost all of it.
      //
      // Both halves are flexible and pinned apart rather than the filter being
      // laid out at its natural width first. At accessibility text sizes the
      // popover's label is wide enough to starve the title of the room its own
      // count needs, and the title row then overflows instead of ellipsizing —
      // `library_clearance_test.dart` catches it at 2x with a two-digit count.
      // `spaceBetween` is what keeps the filter flush right once it is flexible.
      //
      // **No chevron on this title, and that is the one thing about the completion
      // filter that is state-dependent.** The set on show is not: a filter honoured
      // expanded and ignored collapsed would make the count jump as the sheet was put
      // away. What the collapsed row has no room for is a *second* control — the year
      // popover is already competing with the title for it, which is what the
      // clearance test measures.
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: LibrarySheetTitle(title: titleText, count: visible.length),
          ),
          Flexible(
            child: ReadFilter(
              years: years,
              selected: widget.filterYear,
              onChanged: widget.onFilterChanged,
              expanded: false,
              enabled: !widget.isEditMode,
            ),
          ),
        ],
      ),
      // Expanded, the filter moves out of the header and becomes the capsule row
      // above the grid. Unconditional: [readFilterYears] always offers all time plus
      // at least the current year, and whether the rail is worth drawing at all is
      // `ReadFilter`'s own decision, made once.
      //
      // **The rail stays directly under the title row.** The completion filter's card
      // is hung *over* it rather than taking a row of its own — drawn to scale it
      // covers the first few capsules while it is up, which is accepted: it is what a
      // menu under a title does, and it is the second reason that control could not
      // have gone on the rail's row.
      expandedHeader: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LibrarySheetTitle(
            key: _titleKey,
            title: titleText,
            count: visible.length,
            // Inert while the library is being edited, the same gate the rail below
            // takes. The chevron goes with it, which is invisible: the sheet has been
            // slid off the bottom of the screen by then.
            onTap: widget.isEditMode ? null : _openFilter,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ReadFilter(
              years: years,
              selected: widget.filterYear,
              onChanged: widget.onFilterChanged,
              expanded: true,
              enabled: !widget.isEditMode,
            ),
          ),
        ],
      ),
      collapsedBody: ReadPile(
        books: visible,
        filterYear: widget.filterYear,
        isEditMode: widget.isEditMode,
        finishedOnly: _filter.isFinishedOnly,
      ),
      body: ReadMonthGrid(
        // **A different filter is a different list, and it is read from the top.**
        // The key is what does that: it changes with the year, the grid is
        // remounted, and a fresh `ListView` starts at offset 0.
        //
        // Without it the viewport keeps the offset it had. Scrolled 880pt into all
        // time, choosing a year left you *inside* some arbitrary month with the
        // newest one above the fold — and only sometimes, because a year short
        // enough to fit the viewport clamps back to the top by itself. Landing at
        // the top sometimes and mid-list otherwise is the part that reads as broken.
        //
        // **The completion mode is part of the same key for the same reason**: turning
        // set-aside books on inserts rows throughout the list, so the offset the
        // reader had no longer points at what they were looking at.
        //
        // Keyed on the **filter**, not on the books, so a book that appears while
        // someone is scrolling — a finish logged on another device, a refresh —
        // leaves the viewport where they left it. Only a tap moves it.
        //
        // Instant on purpose. An animated scroll here would read as the list moving
        // of its own accord rather than as the answer to the tap, and the tap has
        // already been answered: the capsule shrinks under the finger and the
        // selection haptic fires before the content changes. See `ReadFilter`.
        key: ValueKey((widget.filterYear, _filter)),
        months: ReadMonthGrid.group(visible),
        // Drives the month headers and the empty state; see [ReadMonthGrid].
        filterYear: widget.filterYear,
        // So an empty sheet does not say "No books read yet" under a title reading
        // `Books finished`.
        finishedOnly: _filter.isFinishedOnly,
        // The grid's viewport reaches the card's bottom edge and its rows pass under
        // the floating tab bar, so what keeps the *last* row clear of it is this
        // padding — the same band the sheet is told to reserve, plus the 16 the grid
        // wanted anyway. Short of it, the bottom row would be unreachable behind the
        // bar; over it, there would be a gap where the reference shows a cover.
        bottomPadding:
            16 +
            widget.bottomReserve +
            MediaQuery.viewPaddingOf(context).bottom,
      ),
    );
  }
}
