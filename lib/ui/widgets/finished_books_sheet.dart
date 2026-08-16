import 'package:flutter/material.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
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
  /// The expanded cap is taken from this. See [expandedExtentFor].
  final double maxExtent;

  /// See [LibrarySheet.bottomReserve].
  final double bottomReserve;

  const FinishedBooksSheet({
    super.key,
    required this.books,
    required this.isEditMode,
    required this.filterYear,
    required this.onFilterChanged,
    required this.maxExtent,
    this.bottomReserve = 0,
  });

  /// The expanded sheet stops short of the top so **one shelf stays visible** —
  /// the library is the shell's persistent background, and a sheet that covered it
  /// entirely would be a page pretending to be a sheet.
  ///
  /// Derived from [bookRowExtent], the same function the library uses to size a
  /// shelf row, so the two cannot disagree about what one shelf is. The drawings'
  /// 79% is a consequence of this, not the rule.
  ///
  /// [available] is the height the sheet's **collapsible content** may occupy, not
  /// the whole band: the sheet's box is this plus the chrome it reserves below
  /// itself for the tab bar and the home indicator. Getting that wrong is not a
  /// rounding error — the first version of this subtracted only the shelf row, and
  /// `library_clearance_test.dart` measured the shelf it was supposed to leave
  /// coming out at 40pt instead of 106pt on a 375x667 phone, because the tab bar's
  /// 66pt reservation was taken out of the library rather than out of the grid.
  static double expandedExtentFor(double available, double shelfRowExtent) {
    final cap = available - shelfRowExtent;
    // Never smaller than a third of what is available: on a very short screen,
    // leaving a shelf visible matters less than the grid being usable at all.
    final floor = available / 3;
    return cap < floor ? floor : cap;
  }

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

    final title = LibrarySheetTitle(
      title: l10n.finishedBooksTitle,
      count: visible.length,
    );

    return LibrarySheet(
      isEditMode: isEditMode,
      bottomReserve: bottomReserve,
      // Rests on the pile: the drawings call the collapsed state the default on
      // launch, and opening into a full grid would bury the library.
      initiallyExpanded: false,
      expandedExtent: expandedExtentFor(
        // What the *content* may occupy: the sheet reserves the tab bar's band
        // and the home indicator outside the collapsible area, so both come off
        // the top before a shelf is set aside.
        maxExtent - bottomReserve - MediaQuery.viewPaddingOf(context).bottom,
        _shelfRowExtent(context),
      ),
      collapsedBodyExtent: ReadPile.extent,
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
      // above the grid.
      expandedHeader: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          if (years.length > 1)
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
      collapsedBody: ReadPile(books: visible),
      body: ReadMonthGrid(
        months: ReadMonthGrid.group(visible),
        bottomPadding: 16,
      ),
    );
  }

  /// One shelf row, at the height the library draws it.
  double _shelfRowExtent(BuildContext context) =>
      bookRowExtent(MediaQuery.sizeOf(context).height * 0.15);
}
