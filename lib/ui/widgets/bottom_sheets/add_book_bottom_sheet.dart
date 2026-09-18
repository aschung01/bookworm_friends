import 'dart:async';
import 'dart:math';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/services/cover_image.dart';
import 'package:bookworm_friends/services/library_match.dart';
import 'package:bookworm_friends/ui/pages/scan_book_page.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/add_to_library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/empty_state_art.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens Add Book as a modal starting just below the status bar.
///
/// A modal rather than a pushed page because adding a book is an errand you come
/// back from: the library stays visible behind it and dismissing lands you
/// exactly where you were.
///
/// The floating tab bar stays in front of this sheet rather than disappearing
/// behind it: `ShellChrome` hosts it above the `Navigator` and `ShellTabBar`
/// passes `autoHideOnModal: false`, because Add Book *is* the search tab and a
/// bar that vanished the moment you tapped it would be lying about where you are.
/// The sheet leaves room for it at the bottom via `ShellTabBarGeometry.reserve`.
///
/// A sheet opened *from* this one is the other way round — see
/// `shellBarVisibleProvider`, which drops the bar once a second modal is stacked
/// over the shell.

/// Smallest band of library left visible above the sheet.
///
/// Only reached on surfaces that report no top inset at all — landscape, and
/// `flutter test` — where deferring to the safe area alone would let the sheet go
/// full-screen and lose the barrier that makes it read as *covering* the library
/// rather than replacing it.
const double _minAddBookTopInset = 24;

Future<void> showAddBookBottomSheet(BuildContext context) {
  // The sheet starts at the safe-area inset so the status bar reads against the
  // library behind it rather than against sheet content. This was `95%` of the
  // screen height, which on a 402x874 phone put the sheet's top edge at 43.7pt --
  // *above* the 62pt status bar -- so "Add book" sat level with the clock. A
  // fraction is the wrong unit for it: 5% is 33pt on a 667pt phone, which covers
  // the status bar there too.
  //
  // Read from the **calling** context, not the builder's.
  // `showModalBottomSheet` wraps its content in
  // `MediaQuery.removePadding(removeTop: true)`, and that zeroes `viewPadding.top`
  // as well as `padding.top` (`media_query.dart`), so inside the builder this
  // silently measures 0 and the sheet would go full-screen.
  final topInset = max(
    MediaQuery.viewPaddingOf(context).top,
    _minAddBookTopInset,
  );
  return CNBottomSheet.show<void>(
    context: context,
    // `showDragHandle` is deliberately not used: Material adds that handle
    // *outside* the builder's child, so its height lands on top of whatever exact
    // height is asked for -- measured at ~98% of the screen with no barrier left.
    // The handle is drawn inside instead.
    isScrollControlled: true,
    backgroundColor: context.colors.sheetBackground,
    builder: (ctx) => SizedBox(
      // Height from the builder so a rotation still resizes it; only the inset
      // has to come from outside.
      height: MediaQuery.sizeOf(ctx).height - topInset,
      child: const _AddBookSheet(),
    ),
  );
}

final _searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// One page of catalogue results.
const int _pageSize = 20;

/// How many raw pages one fetch may pull through when suppression empties them.
///
/// Bounded so a query whose every result the reader already owns cannot spin
/// through the catalogue. Three is enough to cover the ordinary case — a reader
/// searching an author they collect — without turning one keystroke into a
/// dozen requests.
const int _maxSuppressionHops = 3;

final _searchResultsProvider =
    AutoDisposeAsyncNotifierProvider<
      _SearchResultsNotifier,
      List<BookSearchResult>
    >(_SearchResultsNotifier.new);

/// The catalogue half of the search, with books the reader provably already owns
/// removed.
///
/// **Suppression lives here rather than in the widget, and only just.** Tagging a
/// *probable* match is the widget's job, because it needs whatever the library
/// says right now. Dropping an *identical* one has to happen here, because it is
/// entangled with paging in two ways that are easy to get wrong:
///
///  1. **[_hasMore] is decided by the raw page size, before anything is
///     dropped.** Filter first and a full page of 20 with 4 owned looks like a
///     short page, so paging stops early and the reader silently loses the rest
///     of the catalogue.
///  2. **A page can come back empty after filtering**, and an empty section has
///     nothing to scroll, so `_onScroll` would never ask for the next page. The
///     fetch loop keeps going itself until it has something to show — see
///     [_maxSuppressionHops].
///
/// Reads the library with `ref.read` and deliberately does **not** watch it:
/// watching would re-run a network search every time a book was added. A search
/// run before the library has loaded therefore suppresses nothing, and those
/// duplicates come out *tagged* by the widget instead of hidden — which is the
/// right way to degrade, since a tag is visible and a suppression is not.
class _SearchResultsNotifier
    extends AutoDisposeAsyncNotifier<List<BookSearchResult>> {
  /// Raw pages requested so far. Counts pages *asked for*, not pages kept.
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  List<Book> get _owned => [
    for (final shelf
        in ref.read(libraryProvider).valueOrNull ?? const <Shelf>[])
      ...shelf.books,
  ];

  @override
  Future<List<BookSearchResult>> build() async {
    final query = ref.watch(_searchQueryProvider);
    // Re-run the search when the active source changes (e.g. user toggles it).
    final searchProvider = ref.watch(bookSearchProvider);
    _page = 0;
    _hasMore = true;
    if (query.isEmpty) return [];
    return _fetch(searchProvider, query, const []);
  }

  /// Pulls pages until at least one survives suppression, or the catalogue runs
  /// out, or [_maxSuppressionHops] is reached.
  ///
  /// Returns [soFar] plus whatever was kept, so [loadMore] can append.
  Future<List<BookSearchResult>> _fetch(
    BookSearchProvider provider,
    String query,
    List<BookSearchResult> soFar,
  ) async {
    final owned = _owned;
    var kept = soFar;
    for (var hop = 0; hop < _maxSuppressionHops && _hasMore; hop++) {
      _page++;
      final raw = await provider.search(query, page: _page, size: _pageSize);
      // **Before the filter.** See the class comment: the raw count is the only
      // honest answer to "was that the last page".
      if (raw.length < _pageSize) _hasMore = false;
      kept = [
        ...kept,
        ...raw.where(
          (r) => ownedVerdictFor(r, owned) != OwnedVerdict.identical,
        ),
      ];
      if (kept.length > soFar.length) break;
    }
    return kept;
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    final query = ref.read(_searchQueryProvider);
    if (query.isEmpty) return;

    _isLoadingMore = true;
    final pageBefore = _page;
    try {
      final searchProvider = ref.read(bookSearchProvider);
      state = AsyncData(
        await _fetch(searchProvider, query, state.valueOrNull ?? const []),
      );
    } catch (_) {
      // Put the cursor back so the failed page is retried rather than skipped.
      _page = pageBefore;
    } finally {
      _isLoadingMore = false;
    }
  }
}

class _AddBookSheet extends ConsumerStatefulWidget {
  const _AddBookSheet();

  @override
  ConsumerState<_AddBookSheet> createState() => _AddBookSheetState();
}

class _AddBookSheetState extends ConsumerState<_AddBookSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocus = FocusNode();

  /// True while the field holds a query the *app* wrote, not the user.
  ///
  /// Drives the provenance chip. Without it a query read off a cover is
  /// indistinguishable from one the user typed, so a misread title looks like
  /// their own typo — and an LLM reading stylised cover type will sometimes
  /// misread. Cleared the moment they edit, because from then on it is theirs.
  bool _queryFromCover = false;

  /// The text [_onQueryEdited] last saw, so it can tell an edit from a cursor move.
  ///
  /// `_controller` notifies for *any* [TextEditingValue] change, selection
  /// included — and [_runCoverQuery] leaves the selection invalid, because
  /// `TextEditingController.text` collapses it to -1. The field repairs that as
  /// soon as it has focus, which now that it autofocuses is always, and the repair
  /// arrives as a notification carrying identical text. Read as an edit it wiped
  /// the "from cover" chip a frame after it was set.
  String _lastQuery = '';

  /// What the reader's own library is filtered by: **the live text, not the
  /// submitted query.**
  ///
  /// The two halves of this field are searched on different triggers, and that is
  /// the design rather than an accident. The library is already in memory, so it
  /// can answer on the keystroke with no spinner and no error state; the catalogue
  /// is a network call that has to be asked for. Holding them in two pieces of
  /// state is what lets the sheet draw the reader's own books before the catalogue
  /// has been consulted at all — which is also, for free, what makes the two
  /// sections legible as two different kinds of answer.
  String _liveQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _controller.addListener(_onQueryEdited);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryEdited() {
    if (_controller.text == _lastQuery) return;
    _lastQuery = _controller.text;
    setState(() {
      // Filters the reader's own books on the keystroke. Cheap: `libraryProvider`
      // is already in memory and a library is bounded by how much one person has
      // read.
      _liveQuery = _controller.text;
      if (_queryFromCover) _queryFromCover = false;
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(_searchResultsProvider.notifier).loadMore();
    }
  }

  void _onSearchSubmitted(String val) {
    ref.read(_searchQueryProvider.notifier).state = val.trim();
  }

  /// Runs a query the app produced rather than one the user typed.
  ///
  /// Sets the text *and* the provider, because the field's own `onFieldSubmitted`
  /// is the only thing that normally triggers a search and nobody pressed return
  /// here. Order matters: the controller is written first so [_onQueryEdited]'s
  /// clear happens before the flag is set, rather than wiping it immediately.
  void _runCoverQuery(String query) {
    _controller.text = query;
    setState(() => _queryFromCover = true);
    ref.read(_searchQueryProvider.notifier).state = query;
  }

  void _onBookTap(BookSearchResult book, List<Shelf> shelves) {
    showAddToLibrarySheet(context, ref, book: book, shelves: shelves);
  }

  /// Opens a book the reader already owns.
  ///
  /// `AppRoutes.details` with the [Book] as its argument, which is how both
  /// `read_pile.dart` and `shelf_row.dart` already open one — so this is the
  /// existing destination rather than a new surface, and the details page needs no
  /// changes to serve it.
  ///
  /// **Left as a push deliberately, and it is the open question on this feature.**
  /// A push leaves the search and discards the query, while the commonest thing to
  /// want after finding a book you forgot you bought is to set it to Reading — one
  /// control, on a page that costs a navigation each way. A stacked
  /// `showBookInfoBottomSheet` would keep the query alive underneath. Not changed
  /// here because it is a decision about the details page's role, not about
  /// search; see `docs/mockups/library-search/`.
  ///
  /// **Do not wrap the row's cover in a `Hero` to fly it to the details page. It
  /// cannot work from here, and it fails silently.**
  /// `HeroController._maybeStartHeroTransition` starts a flight only when *both*
  /// routes are `PageRoute`s. This sheet is a `ModalBottomSheetRoute`, i.e. a
  /// `PopupRoute`, so the controller never begins one — measured, not assumed: a
  /// destination `flightShuttleBuilder` runs on a page-to-page push and does not
  /// run on a sheet-to-page push. A `Hero` added here would compile, look right in
  /// review, satisfy a test that only asserts the widget exists, and animate
  /// nothing. That is why `read_pile.dart` and `read_month_grid.dart` can carry
  /// `book_<isbn>` tags and no sheet in the app does: they live inside the shell's
  /// *page* route.
  ///
  /// Popping this sheet first would make the flight legal — library to details,
  /// sourced from wherever the book physically sits — but it would fire only
  /// sometimes: a shelved cover scrolled out of its row has no source hero, and the
  /// read pile tags **only the book currently turned out** (see `read_pile.dart`,
  /// "which is what makes the Hero legal here at all"). An animation that runs for
  /// Interested books and not for Read ones is the defect `read_month_grid`'s
  /// `_flyableIsbns` refuses on purpose: a cover arriving from somewhere the finger
  /// never touched is worse than one that does not move.
  void _onOwnedTap(Book book) {
    Navigator.pushNamed(context, AppRoutes.details, arguments: book);
  }

  /// Opens the barcode scanner.
  ///
  /// Awaits an outcome but usually gets none: a scan that finds a book opens the
  /// save sheet on top of the scanner and the save unwinds past this sheet, so
  /// control never comes back here. The one outcome worth acting on is the user
  /// saying they would rather type — answered by putting the cursor where they
  /// asked for it, instead of returning them to an untouched field and making them
  /// tap it themselves.
  ///
  /// The scanner **rises from the bottom** as a full-screen cover rather than
  /// sliding in from the trailing edge: it is an errand you come back from, and it
  /// carries an ✕ rather than a back chevron. `AppRoutes.onGenerateRoute` owns that
  /// and explains it.
  ///
  /// **Deliberately `pushNamed` with no type argument,** even though the route is
  /// generated as a `Route<ScanOutcome>`. `pushNamed<T>` casts the route it gets to
  /// `Route<T?>`, so a typed push would hard-depend on this name always being
  /// served by `onGenerateRoute` — anything serving it from a
  /// `Map<String, WidgetBuilder>` builds a `Route<dynamic>` and the cast throws on
  /// the first tap. The widget tests stub the scanner exactly that way, since a
  /// camera platform view is not something `flutter test` can open. The `is` checks
  /// below recover the safety the type argument would have given, at runtime, which
  /// is where the value actually arrives from.
  Future<void> _openScanner() async {
    // Focus is dropped *before* the push rather than after the pop, because
    // `unfocus` clears the enclosing scope's memory of which child held focus and
    // that memory is exactly what a pop hands the keyboard back to. The field
    // autofocuses on open, so that child is always this field — without this, both
    // outcomes below that deliberately leave the keyboard down would get one
    // anyway, restored underneath them as the scanner unwinds.
    _searchFocus.unfocus();
    final outcome = await Navigator.pushNamed(context, AppRoutes.scanBook);
    if (!mounted) return;
    switch (outcome) {
      case ScanTypeInstead():
        _searchFocus.requestFocus();
      case ScanFoundQuery(:final query):
        // Lands in the field and runs, but does *not* focus it: the answer is the
        // results grid, and raising the keyboard would cover the thing the user
        // came back to look at.
        _runCoverQuery(query);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resultsAsync = ref.watch(_searchResultsProvider);
    final shelvesAsync = ref.watch(libraryProvider);
    final shelves = shelvesAsync.valueOrNull ?? [];

    // What the catalogue was last asked, and what it has not been asked yet.
    // `pending` is the whole reason the invitation below exists: the field's two
    // scopes run on different triggers, so between a keystroke and a submit the
    // typed text is a question nothing has answered. Non-empty also when a search
    // *has* run and the text has since been edited — the results underneath are
    // then answering a query that is no longer the one on screen, and the reader
    // needs the same way forward as before they searched at all.
    final submitted = ref.watch(_searchQueryProvider);
    final live = _liveQuery.trim();
    final pending = (live.isEmpty || live == submitted) ? '' : live;

    // Computed once here rather than inside `_localSection`, because the
    // catalogue section needs the same answer: the illustration for a search
    // that found nothing belongs to the *combined* miss, and neither section
    // alone knows whether it is the only one that came up empty.
    final localMatches = searchOwnLibrary(shelves, _liveQuery);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetGrabHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.searchTitle, style: AppTextStyles.subtitle),
              ),
              // Same close affordance every content sheet in the app uses: a
              // 44pt target with an accessible name, glass on iOS 26. The drag
              // handle above is the other way out; neither is enough alone.
              AdaptiveIconButton(
                symbol: 'xmark',
                icon: Icons.close,
                diameter: kIconButtonDiameter,
                symbolSize: kIconButtonSymbolSize,
                iconSize: kIconButtonIconSize,
                semanticLabel: l10n.close,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 4, 25, 12),
          // One scan button, not two. A barcode icon and a camera icon side by
          // side would take the pill from 300pt to 248 and ask the user to know,
          // before pointing the phone at anything, which kind of reading will
          // work — a question they cannot answer and the app can. So there is one
          // door: detection runs on its own, and when it finds nothing the
          // scanner escalates in place rather than sending anyone back here to
          // press a different button. See docs/mockups/scan-to-add.
          child: Row(
            children: [
              Expanded(
                child: SearchFieldPill(
                  child: SearchTextField(
                    controller: _controller,
                    focusNode: _searchFocus,
                    // Selecting the search tab *is* the request to search, so the
                    // cursor is already where the user was going to put it. The
                    // keyboard it raises covers the empty state, which is why that
                    // state scrolls and pads for the view insets below.
                    autofocus: true,
                    // Advertises both scopes, which is the placeholder's whole job
                    // now that one field reaches both. `searchBookPlaceholder`
                    // ('Title, author, publisher…') is catalogue-flavoured and
                    // would undersell half of it — it stays in use by the friends
                    // header, which really does search one thing.
                    hintText: l10n.searchPlaceholder,
                    onFieldSubmitted: _onSearchSubmitted,
                    // Inside the pill, after the text: a query the app wrote has
                    // to be distinguishable from one the user typed, or a
                    // misread cover reads as their own typo. Disappears the
                    // moment they edit, because then it *is* theirs. Passed to
                    // the field rather than placed beside it so the field's
                    // clear button stays the rightmost thing in the pill.
                    trailing: _queryFromCover
                        ? Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: context.colors.surface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                child: Text(
                                  l10n.searchFromCover,
                                  style: AppTextStyles.label.copyWith(
                                    color: context.colors.brandText,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const AdaptiveIconButtonGap(),
              AdaptiveIconButton(
                symbol: 'barcode.viewfinder',
                icon: Icons.qr_code_scanner,
                diameter: 44,
                symbolSize: 20,
                iconSize: 22,
                semanticLabel: l10n.scanBookLabel,
                onPressed: () => unawaited(_openScanner()),
              ),
            ],
          ),
        ),
        Expanded(
          // Nothing typed: the empty state, which is also where the scan action
          // is advertised. Note this keys off the *live* text, not the submitted
          // query, so it clears the instant the field does — `_ClearSearchButton`
          // empties both together.
          child: _liveQuery.trim().isEmpty
              ? _emptyState(context, l10n)
              : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _localSection(
                        context,
                        l10n,
                        shelves,
                        localMatches,
                      ),
                    ),
                    // The section exists as soon as anything is typed, but it
                    // holds an *invitation* until the catalogue has been asked.
                    //
                    // It used to appear only on submit, and that was wrong in the
                    // one state that matters most: a query the library cannot
                    // answer drew "Nothing in your library matches." over an empty
                    // half-screen, with the only way on being a return key that is
                    // off-screen the moment the keyboard is dismissed. The reader
                    // is told the search failed and offered nothing — when in fact
                    // nothing had been searched. A header over an invitation is not
                    // the empty section that rule was avoiding; it is the section
                    // doing its job one step earlier.
                    if (submitted.isNotEmpty || pending.isNotEmpty) ...[
                      SliverToBoxAdapter(child: _sectionDivider(context)),
                      SliverToBoxAdapter(
                        child: _SectionHeader(label: l10n.searchSectionAdd),
                      ),
                      if (pending.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _CatalogueInvitation(
                            label: l10n.searchCatalogueFor(pending),
                            onTap: () => _onSearchSubmitted(pending),
                          ),
                        ),
                      if (submitted.isNotEmpty)
                        ...resultsAsync.when(
                          data: (results) => _catalogueSlivers(
                            context,
                            l10n,
                            results,
                            shelves,
                            localEmpty: localMatches.isEmpty,
                          ),
                          loading: () => [
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator.adaptive(),
                                ),
                              ),
                            ),
                          ],
                          error: (e, _) => [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  25,
                                  10,
                                  25,
                                  4,
                                ),
                                child: Text(
                                  l10n.searchErrorWithMessage(e.toString()),
                                  style: AppTextStyles.body.copyWith(
                                    color: context.colors.secondaryText,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                    // The keyboard overlays this sheet rather than resizing it, so
                    // the last rows would otherwise sit under it unreachable.
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 20 + MediaQuery.viewInsetsOf(context).bottom,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// The reader's own books, filtered live.
  ///
  /// Always drawn once anything is typed, **including when it matches nothing.**
  /// A section that vanished when empty would let the catalogue jump up into the
  /// slot the local results held a keystroke ago.
  ///
  /// The empty line states a fact and nothing more. What makes adding the obvious
  /// next move is `_CatalogueInvitation` below it — which is the correction to an
  /// earlier version of this comment that credited the empty line with that job.
  /// It never did it: "Nothing in your library matches." over blank space reads as
  /// a search that failed, not as a prompt to search somewhere else.
  Widget _localSection(
    BuildContext context,
    AppLocalizations l10n,
    List<Shelf> shelves,
    List<Book> matches,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: l10n.searchSectionYours, count: matches.length),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 2, 25, 4),
            child: Text(
              l10n.searchNoneInLibrary,
              style: AppTextStyles.body.copyWith(
                color: context.colors.secondaryText,
              ),
            ),
          )
        else
          for (final book in matches)
            _OwnedBookRow(
              book: book,
              shelfName: _shelfNameOf(book, shelves),
              onTap: () => _onOwnedTap(book),
            ),
      ],
    );
  }

  /// The shelf a book stands on, for the row's second line.
  ///
  /// A finished book keeps its `shelf_id` even though it is drawn in the read pile
  /// rather than on the plank (see `withoutFinishedBooks`), so this resolves for
  /// every status. Empty when it somehow does not, which the row then omits.
  String _shelfNameOf(Book book, List<Shelf> shelves) {
    for (final shelf in shelves) {
      if (shelf.id == book.shelfId) return shelf.name;
    }
    return '';
  }

  /// The catalogue's results, packed into shelf rows.
  ///
  /// The packing arithmetic is unchanged: books are 15% of screen height and
  /// `height / 1.6` wide — the sheet's own ratio, not `kDefaultCoverAspect`.
  List<Widget> _catalogueSlivers(
    BuildContext context,
    AppLocalizations l10n,
    List<BookSearchResult> results,
    List<Shelf> shelves, {
    required bool localEmpty,
  }) {
    if (results.isEmpty) {
      // Reached two different ways, and they deserve the same answer. Either the
      // catalogue had nothing, or everything it had was suppressed as a book
      // already on a shelf — and in both cases what the reader needs to know is
      // that there is nothing here to add. A header over nothing would read as a
      // request that failed.
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(25, 2, 25, 4),
            child: Text(
              l10n.searchNothingNewToAdd,
              style: AppTextStyles.body.copyWith(
                color: context.colors.secondaryText,
              ),
            ),
          ),
        ),
        // The spot belongs to the *combined* miss, not to this section. When the
        // library matched something, the screen already has content and two
        // sentences of explanation; adding a drawing under one of them would
        // point at the half that failed rather than describing the state. Only
        // when both scopes came up empty is "we looked and found nothing" the
        // whole screen, and then it deserves a picture instead of two grey lines
        // over blank space.
        if (localEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 14),
              child: Center(
                child: EmptyStateArt(EmptyStateArtwork.noMatch, size: 40),
              ),
            ),
          ),
      ];
    }

    final owned = [for (final shelf in shelves) ...shelf.books];
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final bookHeight = screenHeight * 0.15;
    final bookWidth = bookHeight / 1.6;
    final perLine = max(
      ((screenWidth - 50 + bookWidth * 0.2) / (bookWidth * 1.2)).floor(),
      1,
    );
    final lineCount = max((results.length / perLine).ceil(), 1);
    final notifier = ref.read(_searchResultsProvider.notifier);

    return [
      SliverPadding(
        padding: const EdgeInsets.only(top: 8),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(childCount: lineCount, (
            context,
            line,
          ) {
            final startIdx = perLine * line;
            final endIdx = min(startIdx + perLine, results.length);
            return Padding(
              padding: EdgeInsets.only(bottom: line == lineCount - 1 ? 0 : 26),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        (endIdx - startIdx) * 2 - 1,
                        (index) => index.isEven
                            ? _catalogueBook(
                                results[startIdx + index ~/ 2],
                                owned,
                                shelves,
                              )
                            : SizedBox(width: bookHeight / (5 * 1.6)),
                      ),
                    ),
                  ),
                  const ShelfWidget(),
                ],
              ),
            );
          }),
        ),
      ),
      if (notifier.hasMore)
        const SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator.adaptive(),
            ),
          ),
        ),
    ];
  }

  /// One catalogue result, tagged when it looks like a book the reader owns.
  ///
  /// **A tag and never a removal, unlike the identical-ISBN case the notifier
  /// drops.** What reaches here matched on title and author only, so it is either
  /// a genuinely different edition — a legitimate thing to add — or the same
  /// edition wearing an identifier one provider got wrong. The app cannot tell
  /// which, and under that uncertainty a mark is honest where hiding is not:
  /// hiding a book the reader wanted leaves them no recourse and no explanation.
  ///
  /// This also catches the identical duplicates the notifier could not, because it
  /// ran before `libraryProvider` had loaded — those arrive tagged rather than
  /// absent, which is the right way for suppression to degrade.
  Widget _catalogueBook(
    BookSearchResult book,
    List<Book> owned,
    List<Shelf> shelves,
  ) {
    final verdict = ownedVerdictFor(book, owned);
    final cover = BookWidget(
      imageUrl: book.thumbnail,
      isbn: book.isbn,
      title: book.title,
      onTap: () => _onBookTap(book, shelves),
    );
    if (verdict == OwnedVerdict.none) return cover;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        cover,
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _OwnedTag(label: AppLocalizations.of(context).searchOwnedTag),
        ),
      ],
    );
  }

  /// Nothing typed yet: the hint, and the scan action that pays for there being
  /// only one glyph in the search row.
  Widget _emptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: SingleChildScrollView(
        // The keyboard overlays the sheet rather than resizing it, so without this
        // the scan action sits entirely behind ~336pt of keyboard — which, with
        // the field autofocusing on open, is the *first* thing anyone sees.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: const EmptyStateArt(
                EmptyStateArtwork.searchIdle,
                size: 100,
              ),
            ),
            Text(
              l10n.searchHint,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: context.colors.secondaryText,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedActionButton(
              height: 44,
              buttonText: l10n.scanBook,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              backgroundColor: context.colors.surface,
              textStyle: AppTextStyles.label.copyWith(
                color: context.colors.brandText,
              ),
              leading: Icon(
                Icons.qr_code_scanner,
                size: 18,
                color: context.colors.brandText,
              ),
              onPressed: () => unawaited(_openScanner()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionDivider(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
    child: Divider(height: 1, thickness: 1, color: context.colors.divider),
  );
}

/// A section heading in the results list.
///
/// [AppTextStyles.caption] — the same token `ReadMonthGrid` gives a month heading,
/// deliberately: a section of results should read as the same class of object as a
/// month of read books rather than as new chrome.
///
/// **Only the local section passes a [count].** It is finite and known. The
/// catalogue's is paginated, and now also filtered, so any number beside it would
/// be a guess.
class _SectionHeader extends StatelessWidget {
  final String label;
  final int? count;

  const _SectionHeader({required this.label, this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 14, 25, 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ),
          if (count != null)
            Text(
              '$count',
              style: AppTextStyles.caption.copyWith(color: colors.brandText),
            ),
        ],
      ),
    );
  }
}

/// The way from a typed query to the catalogue.
///
/// **A filled, tappable pill rather than a line of hint text, because the state it
/// serves has no keyboard in it.** The field autofocuses, so most readers do meet
/// a return key labelled "Search" — but the keyboard goes the moment anyone
/// scrolls the results, taps the sheet, or comes back from the scanner, and a
/// nudge that only exists on the keyboard is gone with it. Being a control means
/// the instruction and the way to obey it are the same object.
///
/// Styled as the empty state's scan button is styled — [AppColors.surface] behind
/// `brandText` — so the two actions this sheet offers a reader who has not found
/// their book yet read as one class of thing.
class _CatalogueInvitation extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CatalogueInvitation({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 2, 25, 6),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: colors.brandText),
                const SizedBox(width: 10),
                // Names the query rather than saying "search the catalogue",
                // because the two sections differ by *scope* and the reader has
                // just been told this text found nothing. Repeating it here is
                // what makes clear the same words are about to be asked
                // elsewhere. Wraps twice, then clips: a long query is still a
                // legible button, and the row must not grow without bound.
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(
                      color: colors.brandText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One book the reader already owns.
///
/// **A 56pt row rather than a face-out cover, and the difference is load-bearing
/// twice over.** A status badge and a shelf name need horizontal room an 82pt
/// cover has nowhere to put; and the two answer types being visibly unlike each
/// other is what stops one field reading as one undifferentiated list.
class _OwnedBookRow extends StatelessWidget {
  final Book book;
  final String shelfName;
  final VoidCallback onTap;

  /// Tall enough to read as artwork in a list row, and — at 2:3 — narrower than
  /// [kGeneratedCoverMinWidth], which is why the fallback below is the colour
  /// block alone rather than a [GeneratedCover]. Drawing that title at 37pt wide
  /// would set it at 5pt, which reads as a rendering fault rather than as a small
  /// title. `CardCoverRow` makes the same trade for the same reason.
  static const double _coverHeight = 56;
  static const double _coverWidth = _coverHeight * 2 / 3;

  const _OwnedBookRow({
    required this.book,
    required this.shelfName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(25, 7, 25, 7),
        child: Row(
          children: [
            SizedBox(width: _coverWidth, height: _coverHeight, child: _cover()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The same title/author pair `book_info_bottom_sheet` uses for
                  // the same job, so a book reads identically wherever it is
                  // listed. `.copyWith` sets colour only — never size or weight;
                  // see `text_style_test.dart`, which pins that.
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.subtitle,
                  ),
                  if (book.authors.isNotEmpty)
                    Text(
                      book.authors.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                BookStatusBadge(status: book.status),
                if (shelfName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      shelfName,
                      style: AppTextStyles.caption.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The stored cover when there is one, the book's own tone when there is not.
  ///
  /// Prefers `Book.coverColor` over a hash of the ISBN because it is the colour
  /// something already decoded off this book's real cover, so a coverless row
  /// still belongs to the book rather than to its identifier.
  Widget _cover() {
    final block = ColoredBox(
      color: book.coverColor ?? generatedCoverColor(book.isbn),
    );
    if (book.thumbnail.isEmpty) return block;
    return Image(
      image: coverImageProvider(book.thumbnail),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => block,
    );
  }
}

/// Marks a catalogue cover as a book the reader appears to own.
///
/// Drawn on a near-opaque `surface` pill rather than as a tint over the artwork,
/// because it sits on a photograph whose colours cannot be predicted and the
/// label has to stay legible against all of them.
class _OwnedTag extends StatelessWidget {
  final String label;

  const _OwnedTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(color: colors.brandText),
        ),
      ),
    );
  }
}
