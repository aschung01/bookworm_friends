import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/ui/pages/share_card_page.dart';
import 'package:bookworm_friends/ui/widgets/library_card/library_card_body.dart';
import 'package:bookworm_friends/ui/widgets/library_card/share_library_card.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/read_filter.dart';

/// The Card tab's sheet: the Library Card (도서관 카드), this app's Passport.
///
/// Stats and a shareable artifact. Deliberately holds **no** read-books list — read
/// books belong entirely to the Library tab, which already groups them by month, so a
/// second sortable list of the same rows here would be a second home for one set of
/// data.
///
/// **Capped, and it took a measurement to get there.** The first version left the
/// sheet on Phase 1's uncapped path, on the reasoning that a card that has to scroll
/// is a card that says too much. `library_clearance_test.dart` disagreed: at 2x text
/// on a 375x667 phone the card's own labels and figures grew until the library view's
/// column overflowed by 95pt. The drawing had it right all along — `card-open` is
/// drawn at **h:74**, a tall sheet with the tiles at the top, not a short one hugging
/// its contents — so the cap is the same `sheetExpandedExtent` rule the read view
/// uses, and the body scrolls when accessibility sizes make it taller than the cap.
///
/// What stays Phase 1's is the *collapse*: no `collapsedBody`, so every snap position
/// shows the same thing and collapsing only shortens the viewport onto it — the card is
/// clipped at its own bottom edge rather than swapped for something smaller.
///
/// **And the header is the same at every position too, which `card-down` is drawn as
/// and the code did not do.** The drawing gives both `card-open` and `card-down`
/// `hdr: { title, share: true }`; the first version dropped share when collapsed, on the
/// reading that `card-down` is "a title and nothing else". Three things were wrong with
/// that. The rail is what names the card's scope, and the filter keeps applying whether
/// or not it is drawn — so collapsing on 2024 showed a 2024 card, clipped and
/// unlabelled, with no way back to all time. Share is the sheet's reason to exist, and a
/// partially visible card is still a card worth sending. And the swap did not even
/// happen at the collapsed position: [LibrarySheet]'s `_swapPoint` is halfway to the
/// *medium* detent, so both controls vanished a third of the way into a downward drag,
/// which reads as a glitch rather than as a state.
///
/// One header also means one *element*. The share button is a platform view on iOS 26
/// (see [LibraryCardShareButton.glass]), and a header that changed shape mid-drag
/// destroyed and recreated a `UiKitView` on every gesture.
///
/// The share affordance lives on the sheet rather than the tab bar, per the `card-open`
/// note: the card *is* the shareable artifact. It wears the platform's Liquid Glass
/// here — see [LibraryCardShareButton.glass].
///
/// **This is now the only share button.** The library bar carried a second copy in its
/// trailing slot, which exported straight to the platform sheet; it is gone, so sharing
/// starts from the artifact itself. This one pushes [AppRoutes.shareCard] — the
/// `View and share` screen, where the reader sees the image, is told which year is in
/// it, and chooses framing and lighting — which ends at [shareLibraryCard].
class LibraryCardSheet extends StatelessWidget {
  /// Every finished book, unfiltered. The year filter is applied here rather than in
  /// the query, because the year capsules are derived from this same list — the same
  /// reason `finishedBooksProvider` fetches the whole set for the read view.
  final List<Book> books;

  /// The books the reader has open right now.
  ///
  /// Not year-filtered and not counted — see [LibraryCardBody.reading]. Carried through to
  /// the share route so the exported card and this preview draw the same shelf.
  final List<Book> reading;

  /// Year to show, or `0` for all time.
  final int filterYear;
  final ValueChanged<int> onFilterChanged;

  /// The reader's display name, printed as the exported card's `Holder`. Null when
  /// unset.
  final String? username;

  /// The reader's `profiles.handle`: the Latin identity the exported card's strip prints.
  ///
  /// **Two identities, two jobs.** [username] is printed as `Holder`, in whatever script
  /// it is written in; this is what goes in the machine-readable strip, which is Latin-only
  /// by construction. Null on a database without the handle migration, and null is a
  /// working state — the strip omits the identity segment rather than printing a mangled
  /// display name.
  final String? handle;

  /// `profiles.created_at`, printed as the card's `Member since`. Null omits the row
  /// rather than guessing a date.
  final DateTime? memberSince;

  /// Height available to the whole sheet — the band it shares with the library.
  /// The expanded cap is taken from this. See [sheetExpandedExtent].
  final double maxExtent;

  /// Springs the sheet shut and goes inert while the library is being edited — an
  /// edit can be started from any tab, so every sheet has to get out of the way.
  final bool isEditMode;

  /// See [LibrarySheet.bottomReserve].
  final double bottomReserve;

  /// See [LibrarySheet.onRestingExtent].
  final ValueChanged<double>? onRestingExtent;

  /// The shell's shared sheet key, handed to the [LibrarySheet] inside rather than to
  /// this widget — which is what makes a tab switch spring the sheet's height instead
  /// of jumping it. See [LibrarySheet].
  final Key? sheetKey;

  const LibraryCardSheet({
    super.key,
    this.books = const [],
    this.reading = const [],
    this.filterYear = 0,
    this.onFilterChanged = _ignore,
    this.username,
    this.handle,
    this.memberSince,
    this.maxExtent = double.infinity,
    this.isEditMode = false,
    this.bottomReserve = 0,
    this.onRestingExtent,
    this.sheetKey,
  });

  static void _ignore(int _) {}

  /// Horizontal inset for the body, measured from the card's edge.
  ///
  /// **Nine, not the sheet's 25pt gutter, and the difference is a `StatTile`'s own
  /// padding.** The tiles used to run flush to the card's edges while the title above
  /// them sat at 25 — the one body in this sheet family that did not honour the gutter
  /// (`ReadMonthGrid` insets its month rows by it; `FriendsSheet` splits it 13 + 12).
  /// Friends' arithmetic is the one that applies here, because a tile is a *box*: it
  /// carries 16pt of padding, so insetting the box by 9 lands its label, figure and
  /// small print on the same gutter as the title. Sitting the box itself at 25 would
  /// push the text to 41 and wrap `per book, of 22 dated` on a half-width tile.
  static const double _bodyGutter = 9;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stats = libraryCardStats(books, year: filterYear);
    final years = readFilterYears(books);

    // Where a sideways swipe lands. Clamped as `ReadFilter` clamps it: `filterYear`
    // need not be one of the years offered.
    final pageIndex = years.indexOf(filterYear).clamp(0, years.length - 1);

    final title = LibrarySheetTitle(title: l10n.libraryCard);

    // **Not gated on the year list's length.** It used to be built only when there was
    // more than one year to choose between, on the grounds that 43 of the 55 readers in
    // the migrated data have finished books in a single year and a lone dead capsule
    // would be the common case. [readFilterYears] now always offers all time plus at
    // least the current year, and records why; the rail is the card's scope and the
    // scope is worth naming even when there is one of it.
    //
    // Built once and used by *both* headers, so the two cannot drift: the rail is what
    // names the card's scope, and the scope outlives the collapse.
    final Widget filter = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ReadFilter(
        years: years,
        selected: filterYear,
        onChanged: onFilterChanged,
        expanded: true,
        enabled: !isEditMode,
      ),
    );

    // Stacks the rail under the title row. One header serves every snap position — there
    // is no `expandedHeader`, which is what makes the collapse a shorter viewport onto
    // the same chrome rather than a different set of controls.
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Flexible and pinned apart rather than laid out at natural width:
            // the read view's collapsed header overflowed at accessibility text
            // sizes for exactly this shape, and the fix there was this.
            Expanded(child: title),
            // **Gated on the library, not on the selected year.** `readFilterYears`
            // offers every year between the first finish and today, gaps included, so
            // a reader whose last book was two years ago can select a year with
            // nothing in it — and gating on `stats.booksRead` made the button vanish
            // when they did, taking the header's shape with it. The button stays put
            // and goes inert instead: sharing a hero that says 0 is still not
            // something anyone wants to have tapped by accident, but that is a reason
            // to disable a control, not to move the furniture.
            if (books.isNotEmpty)
              LibraryCardShareButton(
                enabled: !isEditMode && stats.booksRead > 0,
                // Liquid Glass here, bare icon in the library bar, and the split is
                // deliberate — see [LibraryCardShareButton.glass]. Flighty's Passport
                // puts a glass share in exactly this corner, and the card is the
                // artifact the sheet exists to hand over.
                glass: true,
                color: context.colors.brandText,
                // Pushes the preview rather than exporting straight to the OS
                // sheet, which is what this button did until Phase 5 Task 3. The
                // export itself has not moved — `ShareCardPage` still calls
                // `shareLibraryCard`, the app's one capture path — but the reader
                // now sees the image, is told which year is in it, and gets the
                // framing and lighting controls, none of which a blind hand-off can
                // offer.
                //
                // `origin` is dropped here: the iPad popover has to be anchored to
                // whatever was tapped, and by the time the OS sheet opens that is a
                // destination on the pushed screen, not this button. The library bar
                // used to carry a second share that took the direct path and needed
                // the rect; that button is gone.
                onShare: (_) => Navigator.pushNamed(
                  context,
                  AppRoutes.shareCard,
                  arguments: ShareCardArgs(
                    books: books,
                    reading: reading,
                    year: filterYear,
                    displayName: username,
                    handle: handle,
                    memberSince: memberSince,
                  ),
                ),
              ),
          ],
        ),
        filter,
      ],
    );

    // What the *content* may occupy: the sheet keeps the tab bar's band and the home
    // indicator below the collapsible area, so both come off the top.
    final available = maxExtent.isFinite
        ? maxExtent - bottomReserve - MediaQuery.viewPaddingOf(context).bottom
        : null;

    return LibrarySheet(
      key: sheetKey,
      // See [LibrarySheet.contentId] — the sheet's own identity, so a tab switch is
      // told apart from a rebuild.
      contentId: LibraryCardSheet,
      isEditMode: isEditMode,
      bottomReserve: bottomReserve,
      onRestingExtent: onRestingExtent,
      // Opens at the medium detent — about 60% of the screen — rather than at either
      // end. Expanded means the whole band now, and launching there covered the
      // library entirely with a card whose content does not fill it: a screen of
      // mostly empty white with no cover left to long-press. Collapsed was the fix
      // for that and overshot in the other direction: the Card has no pile to rest
      // on, so `card-down` is a title and nothing else, and opening the tab showed
      // none of the card it exists to show. The middle position is the one that shows
      // the card and keeps a strip of library behind it. See [sheetMidExtent].
      initialDetent: LibrarySheetDetent.medium,
      fullExtent: maxExtent.isFinite ? maxExtent : null,
      expandedExtent: available == null ? null : sheetExpandedExtent(available),
      // See [sheetMidExtent]. Also where the sheet opens — the card's own content is
      // often shorter than the band, so this is usually the position that fits it
      // without the empty white.
      midExtent: available == null ? null : sheetMidExtent(available),
      minHeightFraction: sheetMinHeightFraction,
      // A swipe across the card turns the year, and the card itself slides a page's
      // width to answer — the same list the rail above it offers, in the same order.
      // See [LibrarySheet.pageIndex].
      //
      // The Card is the sheet this suits best of the two that have it: it has no
      // collapsed body and nothing inside it scrolls sideways, so the gesture is the
      // card's at every snap position, and a card *is* the sort of object you expect
      // to be able to flick through.
      pageIndex: pageIndex,
      pageCount: years.length,
      onPageChanged: (index) => onFilterChanged(years[index]),
      // One header, no `expandedHeader`: every snap position shows the same controls.
      // See the note on this class for the three things the swap got wrong.
      header: header,
      body: SingleChildScrollView(
        // Scrolls only when it has to. A capped sheet hands the body the room the
        // header leaves, and the card is normally far shorter than that — so at
        // ordinary text sizes this never moves, and at accessibility sizes it is
        // what stops the card overflowing.
        //
        // The bottom padding is the band the tab bar floats in: the body's viewport
        // reaches the card's bottom edge, so this is what keeps the last tile clear
        // of the bar once the card is tall enough to scroll.
        child: Padding(
          padding: EdgeInsets.only(
            left: _bodyGutter,
            right: _bodyGutter,
            top: 4,
            bottom:
                8 + bottomReserve + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: LibraryCardBody(
            stats: stats,
            books: books,
            reading: reading,
            year: filterYear,
          ),
        ),
      ),
    );
  }
}
