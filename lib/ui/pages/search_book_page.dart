import 'dart:math';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_info_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/headers/search_header.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class SearchBookPage extends ConsumerStatefulWidget {
  const SearchBookPage({super.key});

  @override
  ConsumerState<SearchBookPage> createState() => _SearchBookPageState();
}

class _SearchBookPageState extends ConsumerState<SearchBookPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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

  void _onBookTap(BookSearchResult book, List<Shelf> shelves) {
    showBookInfoBottomSheet(
      context,
      book: book,
      shelfNames: shelves.map((s) => s.name).toList(),
      onSavePressed:
          (
            shelfName,
            status, {
            DateTime? startDate,
            DateTime? finishDate,
          }) async {
            final shelf = shelves.firstWhere((s) => s.name == shelfName);
            await ref
                .read(libraryActionsProvider)
                .addBook(
                  shelfId: shelf.id,
                  isbn: book.isbn,
                  title: book.title,
                  thumbnail: book.thumbnail,
                  status: status,
                  startDate: startDate,
                  finishDate: finishDate,
                );
            if (mounted) {
              Navigator.popUntil(
                context,
                (route) => route.isFirst || route.settings.name == '/home',
              );
            }
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resultsAsync = ref.watch(_searchResultsProvider);
    final shelvesAsync = ref.watch(libraryProvider);
    final shelves = shelvesAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: resultsAsync.valueOrNull?.isEmpty ?? true
          ? context.colors.surface
          : context.colors.surfaceVariant,
      appBar: SearchHeader(
        controller: _controller,
        elevate: resultsAsync.valueOrNull?.isNotEmpty ?? false,
        onFieldSubmitted: _onSearchSubmitted,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: SafeArea(
        child: resultsAsync.when(
          data: (results) {
            if (results.isEmpty) {
              return Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).size.height * 0.25,
                ),
                child: Center(
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
                        style: TextStyle(
                          color: context.colors.secondaryText,
                          fontSize: 16,
                        ),
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
            final lineCount = max((results.length / numBooksPerLine).ceil(), 1);
            final notifier = ref.read(_searchResultsProvider.notifier);

            return ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 20, bottom: 20),
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
                final endIdx = min(startIdx + numBooksPerLine, results.length);
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
                                  imageUrl:
                                      results[startIdx + index ~/ 2].thumbnail,
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
    );
  }
}
