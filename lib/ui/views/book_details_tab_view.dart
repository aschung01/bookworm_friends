import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/book_memo.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/write_memo_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';

final _bookInfoProvider =
    FutureProvider.autoDispose.family<BookSearchResult?, String>(
  (ref, isbn) => ref.read(bookSearchProvider).getByIsbn(isbn),
);

class BookDetailsTabView extends ConsumerStatefulWidget {
  const BookDetailsTabView({super.key});

  @override
  ConsumerState<BookDetailsTabView> createState() => _BookDetailsTabViewState();
}

class _BookDetailsTabViewState extends ConsumerState<BookDetailsTabView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _memoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = ModalRoute.of(context)?.settings.arguments as Book?;
    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.bookDetailsTitle)),
        body: Center(child: Text(l10n.bookInfoUnavailable)),
      );
    }

    final currentUserId = ref.watch(currentUserIdProvider);
    final isSelf = book.userId == currentUserId;
    final memosAsync = ref.watch(bookMemosProvider(book.id));
    final complimentsAsync = ref.watch(bookComplimentsProvider(book.id));
    final bookInfoAsync = ref.watch(_bookInfoProvider(book.isbn));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: lightGrayColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, color: darkPrimaryColor, size: 22),
        ),
        actions: isSelf
            ? [
                IconButton(
                  onPressed: () => _onDeleteBookPressed(book),
                  icon: const Icon(Icons.delete_outline, color: darkPrimaryColor, size: 24),
                ),
                IconButton(
                  onPressed: () => _onEditStatusPressed(book),
                  icon: const Icon(Icons.edit_outlined, color: darkPrimaryColor, size: 24),
                ),
              ]
            : null,
      ),
      body: NestedScrollView(
        physics: const ClampingScrollPhysics(),
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Hero section with gray background
                Container(
                  width: double.infinity,
                  color: lightGrayColor,
                  padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BookWidget(height: 180, imageUrl: book.thumbnail, heroTag: 'book_${book.isbn}'),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (!isSelf) _ComplimentButton(book: book),
                                      if (!isSelf)
                                        complimentsAsync.when(
                                          data: (compliments) {
                                            if (compliments.isEmpty) return const SizedBox.shrink();
                                            return Padding(
                                              padding: const EdgeInsets.only(top: 8),
                                              child: Wrap(
                                                spacing: 4,
                                                children: compliments.map((c) => Container(
                                                  width: 28, height: 28,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: backgroundColor,
                                                    border: Border.all(color: greenThemeColor.withOpacity(0.3)),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(c.compliment, style: const TextStyle(fontSize: 14)),
                                                )).toList(),
                                              ),
                                            );
                                          },
                                          loading: () => const SizedBox.shrink(),
                                          error: (_, __) => const SizedBox.shrink(),
                                        ),
                                      BookStatusBadge(status: book.status),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Shelf label positioned at bottom-right, just above the shelf
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: ShelfLabel(label: _getShelfName(book)),
                          ),
                        ],
                      ),
                      const ShelfWidget(),
                    ],
                  ),
                ),
                // Title + authors + reading period section with bottom radius
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: lightGrayColor,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(30, 8, 30, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 24,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          child: Text(
                            book.title,
                            style: const TextStyle(color: darkPrimaryColor, fontSize: 20, fontWeight: FontWeight.bold, height: 1),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      bookInfoAsync.when(
                        data: (info) => info != null && info.authors.isNotEmpty
                            ? SizedBox(
                                height: 20,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(info.authors.join(', '), style: const TextStyle(fontSize: 13, color: darkPrimaryColor)),
                                ),
                              )
                            : const SizedBox.shrink(),
                        loading: () => const SizedBox(height: 20),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      if (book.status >= 1 && book.startDate != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(l10n.readingPeriod, style: const TextStyle(color: darkPrimaryColor, fontSize: 14, fontWeight: FontWeight.bold)),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: Text(
                                      '${_formatDate(book.startDate!)} ~ ${book.finishDate != null ? _formatDate(book.finishDate!) : ''}',
                                      style: const TextStyle(color: darkPrimaryColor, fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                l10n.daysCount((book.finishDate ?? DateTime.now()).difference(book.startDate!).inDays),
                                style: const TextStyle(color: greenThemeColor, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tab bar - pinned
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabController,
                indicatorWeight: 2,
                indicatorColor: darkPrimaryColor,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: darkPrimaryColor,
                unselectedLabelColor: darkPrimaryColor,
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontSize: 14),
                dividerColor: Colors.transparent,
                tabs: [Tab(text: l10n.bookInfoTab), Tab(text: l10n.memoTab)],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _BookInfoTab(book: book, bookInfoAsync: bookInfoAsync),
            _BookMemoTab(
              memosAsync: memosAsync,
              isSelf: isSelf,
              onWriteMemo: () => _onWriteMemoPressed(book.id),
              onDeleteMemo: (memoId) => _onDeleteMemo(memoId),
              onEditMemo: (memoId, content) => _onEditMemoPressed(book.id, memoId, content),
            ),
          ],
        ),
      ),
      floatingActionButton: isSelf
          ? AnimatedBuilder(
              animation: _tabController.animation!,
              builder: (context, _) {
                final val = _tabController.animation!.value;
                if (val < 0.5) return const SizedBox.shrink();
                return FloatingActionButton(
                  backgroundColor: backgroundColor,
                  onPressed: () => _onWriteMemoPressed(book.id),
                  child: Icon(Icons.edit, color: greenThemeColor, size: 24),
                );
              },
            )
          : null,
    );
  }

  String _getShelfName(Book book) {
    final shelves = ref.read(libraryProvider).valueOrNull ?? [];
    for (final shelf in shelves) {
      if (shelf.id == book.shelfId) return shelf.name;
    }
    return '';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  void _onDeleteBookPressed(Book book) {
    showDeleteBookBottomSheet(context, onDeletePressed: () async {
      Navigator.pop(context);
      await ref.read(libraryActionsProvider).deleteBook(book.id);
      if (mounted) Navigator.pop(context);
    });
  }

  void _onEditStatusPressed(Book book) {
    showBookStatusBottomSheet(
      context,
      currentStatus: book.status,
      startDate: book.startDate,
      finishDate: book.finishDate,
      onSave: (status, start, finish) async {
        await ref.read(libraryActionsProvider).updateBookStatus(book.id, status, startDate: start, finishDate: finish);
      },
    );
  }

  void _onWriteMemoPressed(String bookId) {
    _memoController.clear();
    showWriteMemoBottomSheet(context, controller: _memoController, onSavePressed: () async {
      Navigator.pop(context);
      final content = _memoController.text.trim();
      if (content.isNotEmpty) {
        await ref.read(libraryActionsProvider).addMemo(bookId, content);
        ref.invalidate(bookMemosProvider(bookId));
      }
    });
  }

  void _onDeleteMemo(String memoId) async {
    await ref.read(libraryActionsProvider).deleteMemo(memoId);
  }

  void _onEditMemoPressed(String bookId, String memoId, String currentContent) {
    _memoController.text = currentContent;
    showWriteMemoBottomSheet(context, controller: _memoController, onSavePressed: () async {
      Navigator.pop(context);
      final content = _memoController.text.trim();
      if (content.isNotEmpty) {
        await ref.read(libraryActionsProvider).updateMemo(memoId, content);
        ref.invalidate(bookMemosProvider(bookId));
      }
    });
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(color: Colors.white, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}

class _ComplimentButton extends ConsumerWidget {
  final Book book;
  const _ComplimentButton({required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (book.status != 2) return const SizedBox.shrink();
    return ElevatedButton.icon(
      onPressed: () {
        showEmojiBottomSheet(context, onEmojiPressed: (emoji) async {
          Navigator.pop(context);
          await ref.read(bookDetailsActionsProvider).addCompliment(book.id, emoji);
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: greenThemeColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      icon: const Icon(Icons.celebration, size: 18),
      label: Text(l10n.praise, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }
}

class _BookInfoTab extends StatelessWidget {
  final Book book;
  final AsyncValue<BookSearchResult?> bookInfoAsync;
  const _BookInfoTab({required this.book, required this.bookInfoAsync});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      color: Colors.white,
      child: bookInfoAsync.when(
        data: (info) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info?.contents != null && info!.contents!.isNotEmpty) ...[
                Text(l10n.bookDescription, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkPrimaryColor)),
                const SizedBox(height: 8),
                Text(info.contents!, style: const TextStyle(fontSize: 14, color: darkPrimaryColor, height: 1.6)),
                const SizedBox(height: 24),
              ],
              if (info?.publisher != null) ...[
                Text(l10n.publisher, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkPrimaryColor)),
                const SizedBox(height: 8),
                Text(info!.publisher!, style: const TextStyle(fontSize: 14, color: darkPrimaryColor)),
                const SizedBox(height: 24),
              ],
              const Text('ISBN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkPrimaryColor)),
              const SizedBox(height: 8),
              Text(book.isbn, style: const TextStyle(fontSize: 14, color: darkPrimaryColor)),
            ],
          ),
        ),
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
        error: (_, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ISBN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkPrimaryColor)),
              const SizedBox(height: 8),
              Text(book.isbn, style: const TextStyle(fontSize: 14, color: darkPrimaryColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookMemoTab extends StatelessWidget {
  final AsyncValue<List<BookMemo>> memosAsync;
  final bool isSelf;
  final VoidCallback onWriteMemo;
  final void Function(String) onDeleteMemo;
  final void Function(String memoId, String content) onEditMemo;
  const _BookMemoTab({required this.memosAsync, required this.isSelf, required this.onWriteMemo, required this.onDeleteMemo, required this.onEditMemo});

  void _showMemoMenu(BuildContext context, BookMemo memo) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.edit),
                onTap: () {
                  Navigator.pop(context);
                  onEditMemo(memo.id, memo.content);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: cancelRedColor),
                title: Text(l10n.delete, style: const TextStyle(color: cancelRedColor)),
                onTap: () {
                  Navigator.pop(context);
                  onDeleteMemo(memo.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      color: Colors.white,
      child: memosAsync.when(
        data: (memos) {
          if (memos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.note_outlined, size: 48, color: grayColor),
                  const SizedBox(height: 12),
                  Text(
                    isSelf ? l10n.writeAMemo : l10n.noMemos,
                    style: const TextStyle(color: grayColor, fontSize: 14),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: memos.length,
            separatorBuilder: (_, __) => const Divider(height: 24),
            itemBuilder: (context, index) {
              final memo = memos[index];
              return GestureDetector(
                onTap: isSelf ? () => _showMemoMenu(context, memo) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(memo.content, style: const TextStyle(fontSize: 14, color: darkPrimaryColor)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${memo.createdAt.year}.${memo.createdAt.month.toString().padLeft(2, '0')}.${memo.createdAt.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11, color: grayColor),
                        ),
                        if (isSelf)
                          const Icon(Icons.more_horiz, size: 18, color: grayColor),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.errorWithMessage(e.toString()))),
      ),
    );
  }
}
