import 'dart:async';
import 'dart:math';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/pages/scan_book_page.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/add_to_library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
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

final _searchResultsProvider =
    AutoDisposeAsyncNotifierProvider<
      _SearchResultsNotifier,
      List<BookSearchResult>
    >(_SearchResultsNotifier.new);

class _SearchResultsNotifier
    extends AutoDisposeAsyncNotifier<List<BookSearchResult>> {
  int _page = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<BookSearchResult>> build() async {
    final query = ref.watch(_searchQueryProvider);
    // Re-run the search when the active source changes (e.g. user toggles it).
    final searchProvider = ref.watch(bookSearchProvider);
    if (query.isEmpty) {
      _page = 1;
      _hasMore = true;
      return [];
    }
    _page = 1;
    _hasMore = true;
    final results = await searchProvider.search(query, page: 1, size: 20);
    if (results.length < 20) _hasMore = false;
    return results;
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    final query = ref.read(_searchQueryProvider);
    if (query.isEmpty) return;

    _isLoadingMore = true;
    _page++;
    try {
      final searchProvider = ref.read(bookSearchProvider);
      final moreResults = await searchProvider.search(
        query,
        page: _page,
        size: 20,
      );
      if (moreResults.length < 20) _hasMore = false;
      final current = state.valueOrNull ?? [];
      state = AsyncData([...current, ...moreResults]);
    } catch (e) {
      _page--;
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
    if (_queryFromCover) setState(() => _queryFromCover = false);
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetGrabHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.addBook, style: AppTextStyles.subtitle),
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
          child: resultsAsync.when(
            data: (results) {
              if (results.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    // The keyboard overlays the sheet rather than resizing it, so
                    // without this the scan action sits *entirely* behind ~336pt
                    // of keyboard — which the field autofocusing on open means is
                    // the *first* thing anyone sees. The results list has always
                    // compensated; the empty state went without because nothing
                    // in it was tappable and nothing raised a keyboard over it.
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: Icon(
                            Icons.menu_book_outlined,
                            size: 100,
                            color: context.colors.secondaryText,
                          ),
                        ),
                        Text(
                          l10n.searchBookHint,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            color: context.colors.secondaryText,
                          ),
                        ),
                        // The discoverable half of the scan entry point, and what
                        // pays for there being only one glyph in the row above: a
                        // 44pt target is a poor place to advertise a capability,
                        // whereas a user staring at an empty state has nothing
                        // else to do and every reason to read it.
                        const SizedBox(height: 22),
                        ElevatedActionButton(
                          height: 44,
                          buttonText: l10n.scanBook,
                          // The one button in the app that sizes itself to its
                          // own label instead of being stretched or given a
                          // width, so it is the one that has to say this: the
                          // shared button pads by zero, and with a 50pt radius
                          // that left "Scan a book" running into the pill's
                          // rounded ends.
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          // `surface` on the sheet's faintly mint
                          // `sheetBackground`, which reads as a raised pill
                          // without competing with a primary CTA. Not
                          // `activated: false` + `disabledStyleOutline`, which
                          // looks outlined and is genuinely disabled —
                          // [ElevatedActionButton] gates `onPressed` on
                          // `activated`.
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

              final screenWidth = MediaQuery.of(context).size.width;
              final screenHeight = MediaQuery.of(context).size.height;
              final bookHeight = screenHeight * 0.15;
              final bookWidth = bookHeight / 1.6;
              final numBooksPerLine = max(
                ((screenWidth - 50 + bookWidth * 0.2) / (bookWidth * 1.2))
                    .floor(),
                1,
              );
              final lineCount = max(
                (results.length / numBooksPerLine).ceil(),
                1,
              );
              final notifier = ref.read(_searchResultsProvider.notifier);

              return ListView.separated(
                controller: _scrollController,
                // The keyboard overlays the sheet rather than resizing it, so the
                // last rows would otherwise sit under it unreachable.
                padding: EdgeInsets.only(
                  top: 20,
                  bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                itemCount: lineCount + (notifier.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 26),
                itemBuilder: (context, line) {
                  if (line == lineCount) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    );
                  }
                  final startIdx = numBooksPerLine * line;
                  final endIdx = min(
                    startIdx + numBooksPerLine,
                    results.length,
                  );
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 25),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            (endIdx - startIdx) * 2 - 1,
                            (index) => index % 2 == 0
                                ? BookWidget(
                                    imageUrl: results[startIdx + index ~/ 2]
                                        .thumbnail,
                                    isbn: results[startIdx + index ~/ 2].isbn,
                                    title: results[startIdx + index ~/ 2].title,
                                    onTap: () => _onBookTap(
                                      results[startIdx + index ~/ 2],
                                      shelves,
                                    ),
                                  )
                                : SizedBox(width: bookHeight / (5 * 1.6)),
                          ),
                        ),
                      ),
                      const ShelfWidget(),
                    ],
                  );
                },
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator.adaptive()),
            error: (e, _) =>
                Center(child: Text(l10n.searchErrorWithMessage(e.toString()))),
          ),
        ),
      ],
    );
  }
}
