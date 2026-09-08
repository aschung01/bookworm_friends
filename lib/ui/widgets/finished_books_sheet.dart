import 'package:flutter/material.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/read_filter.dart';
import 'package:bookworm_friends/ui/widgets/read_month_grid.dart';
import 'package:bookworm_friends/ui/widgets/read_pile.dart';

/// The Library tab's sheet: read books, in two states.
///
/// Collapsed is the spine pile standing on its shelf. Expanded is the same books
/// as covers grouped by the month they were finished in. **The sheet's position is
/// the view switch** — that is why there is no Shelves/Read toggle anywhere.
///
/// Contents only. The handle, the snap positions and the spring belong to
/// [LibrarySheet], which every tab's sheet shares.
class FinishedBooksSheet extends StatelessWidget {
  /// Every finished book, unfiltered. The year filter is applied here rather than
  /// in the query, because the year capsules are derived from this same list.
  final List<Book> books;

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

  List<Book> get _filtered => filterYear == 0
      ? books
      : books
            .where(
              (b) => b.finishDate != null && b.finishDate!.year == filterYear,
            )
            .toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = _filtered;
    final years = readFilterYears(books);

    // Where a sideways swipe on the sheet lands: the year rail's own list, in the
    // rail's own order, so swiping and tapping cannot disagree about which way is
    // next. Clamped exactly as `ReadFilter` clamps it — `filterYear` need not be one
    // of the offered years, since the provider defaults to the current one and the
    // friend pair is shared by every friend, so a year picked in one library may sit
    // outside the range of the next.
    final pageIndex = years.indexOf(filterYear).clamp(0, years.length - 1);

    // What the *content* may occupy: the sheet keeps the tab bar's band and the home
    // indicator below the collapsible area, so both come off the top.
    final available =
        maxExtent - bottomReserve - MediaQuery.viewPaddingOf(context).bottom;

    final title = LibrarySheetTitle(
      title: l10n.finishedBooksTitle,
      count: visible.length,
    );

    return LibrarySheet(
      key: sheetKey,
      // What this sheet is showing, so a tab switch springs the height rather than
      // jumping it. See [LibrarySheet.contentId].
      contentId: FinishedBooksSheet,
      isEditMode: isEditMode,
      bottomReserve: bottomReserve,
      onRestingExtent: onRestingExtent,
      // Rests on the pile: the drawings call the collapsed state the default on
      // launch, and opening into a full grid would bury the library.
      initialDetent: LibrarySheetDetent.collapsed,
      fullExtent: maxExtent,
      expandedExtent: expandedExtentFor(available),
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
      onPageChanged: (index) => onFilterChanged(years[index]),
      // Collapsed, the filter is a popover in the header: there is only the pile
      // to show and capsules would cost all of it.
      //
      // Both halves are flexible and pinned apart rather than the filter being
      // laid out at its natural width first. At accessibility text sizes the
      // popover's label is wide enough to starve the title of the room its own
      // count needs, and the title row then overflows instead of ellipsizing —
      // `library_clearance_test.dart` catches it at 2x with a two-digit count.
      // `spaceBetween` is what keeps the filter flush right once it is flexible.
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: title),
          Flexible(
            child: ReadFilter(
              years: years,
              selected: filterYear,
              onChanged: onFilterChanged,
              expanded: false,
              enabled: !isEditMode,
            ),
          ),
        ],
      ),
      // Expanded, the filter moves out of the header and becomes the capsule row
      // above the grid. Unconditional: [readFilterYears] always offers all time plus
      // at least the current year, and whether the rail is worth drawing at all is
      // `ReadFilter`'s own decision, made once.
      expandedHeader: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ReadFilter(
              years: years,
              selected: filterYear,
              onChanged: onFilterChanged,
              expanded: true,
              enabled: !isEditMode,
            ),
          ),
        ],
      ),
      collapsedBody: ReadPile(
        books: visible,
        filterYear: filterYear,
        isEditMode: isEditMode,
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
        // Keyed on the **filter**, not on the books, so a book that appears while
        // someone is scrolling — a finish logged on another device, a refresh —
        // leaves the viewport where they left it. Only a tap moves it.
        //
        // Instant on purpose. An animated scroll here would read as the list moving
        // of its own accord rather than as the answer to the tap, and the tap has
        // already been answered: the capsule shrinks under the finger and the
        // selection haptic fires before the content changes. See `ReadFilter`.
        key: ValueKey(filterYear),
        months: ReadMonthGrid.group(visible),
        // Drives the month headers and the empty state; see [ReadMonthGrid].
        filterYear: filterYear,
        // The grid's viewport reaches the card's bottom edge and its rows pass under
        // the floating tab bar, so what keeps the *last* row clear of it is this
        // padding — the same band the sheet is told to reserve, plus the 16 the grid
        // wanted anyway. Short of it, the bottom row would be unreachable behind the
        // bar; over it, there would be a gap where the reference shows a cover.
        bottomPadding:
            16 + bottomReserve + MediaQuery.viewPaddingOf(context).bottom,
      ),
    );
  }
}
