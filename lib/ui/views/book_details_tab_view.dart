import 'package:bookworm_friends/ui/widgets/buttons/adaptive_fab.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_back_button.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/menu_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/book_memo.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';
import 'package:bookworm_friends/ui/widgets/compliment_block.dart';
import 'package:bookworm_friends/ui/widgets/headers/collapsing_book_title.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/reading_period_row.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/write_memo_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';

final _bookInfoProvider = FutureProvider.autoDispose
    .family<BookSearchResult?, String>(
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

  /// The in-page title, whose position and height decide the handoff.
  final _titleKey = GlobalKey();

  /// How far the app bar's own title has faded in. 0 at rest, 1 collapsed.
  ///
  /// A notifier rather than `setState` because this changes every scroll frame,
  /// and [build] here watches five providers and lays out the whole hero.
  /// Rebuilding all of that to fade one row would be wasteful.
  final _collapse = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _collapse.dispose();
    _tabController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  /// Hands the title over to the app bar exactly as the in-page one goes under
  /// it: the fade runs across the title's own height, beginning when its top
  /// reaches the app bar's bottom edge and finishing when its bottom does.
  ///
  /// Both ends are measured rather than assumed. The header's height is not a
  /// constant — `BookJitter` scales the 180pt cover by up to ±6% off the ISBN,
  /// and the authors row only appears once the catalogue lookup resolves — so a
  /// hardcoded scroll threshold would be wrong for most books and would go stale
  /// for the rest.
  ///
  /// The measurement is deliberately in *scroll* space rather than screen space.
  /// A scroll notification is dispatched before the frame it belongs to is laid
  /// out, so comparing the title's on-screen position against the app bar here
  /// reads last frame's layout and lags a frame behind the finger.
  /// [RenderAbstractViewport.getOffsetToReveal] instead answers "at what scroll
  /// offset would this box sit at the top of the viewport", which is a property
  /// of the content and does not move as we scroll, so pairing it with the
  /// notification's own offset is exact.
  void _handleScroll(ScrollNotification notification) {
    // Depth 0 is the outer scroll view, the one the header collapses along. The
    // tab content's own scrollables sit deeper and must not drive this.
    if (notification.depth != 0) return;

    final title = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    if (title == null || !title.attached || !title.hasSize) return;

    final fadeStart = RenderAbstractViewport.of(
      title,
    ).getOffsetToReveal(title, 0.0).offset;
    final progress =
        ((notification.metrics.pixels - fadeStart) / title.size.height).clamp(
          0.0,
          1.0,
        );

    if (progress != _collapse.value) _collapse.value = progress;
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
    // Shelf names live in the *owner's* library, so a friend's book has to be
    // resolved against their shelves rather than the signed-in user's.
    final shelvesAsync = isSelf
        ? ref.watch(libraryProvider)
        : ref.watch(userLibraryProvider(book.userId));
    final shelfName = _shelfNameFor(book, shelvesAsync.valueOrNull ?? const []);

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surfaceVariant,
        elevation: 0,
        leading: const AdaptiveBackButton(),
        // The row needs the full width between the back button and the actions to
        // truncate at the right point, so it is start-aligned rather than
        // centred (which is the iOS default this would otherwise inherit).
        centerTitle: false,
        title: ValueListenableBuilder<double>(
          valueListenable: _collapse,
          builder: (context, collapse, _) => CollapsingBookTitle(
            title: book.title,
            isbn: book.isbn,
            imageUrl: book.thumbnail,
            progress: collapse,
          ),
        ),
        actions: isSelf
            ? [
                IconButton(
                  onPressed: () => _onDeleteBookPressed(book),
                  icon: const Icon(Icons.delete_outline, size: 24),
                ),
                IconButton(
                  onPressed: () => _onEditStatusPressed(book),
                  icon: const Icon(Icons.edit_outlined, size: 24),
                ),
              ]
            : null,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _handleScroll(notification);
          return false;
        },
        child: NestedScrollView(
          physics: const ClampingScrollPhysics(),
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // Hero section with gray background
                  Container(
                    width: double.infinity,
                    color: context.colors.surfaceVariant,
                    padding: const EdgeInsets.only(
                      top: 20,
                      left: 20,
                      right: 20,
                    ),
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BookWidget(
                                    height: 180,
                                    imageUrl: book.thumbnail,
                                    isbn: book.isbn,
                                    title: book.title,
                                    heroTag: 'book_${book.isbn}',
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (!isSelf)
                                          _ComplimentButton(book: book),
                                        // A friend's badge is drawn above the
                                        // shelf label instead (see below), since
                                        // the praise button already owns this
                                        // corner.
                                        if (isSelf)
                                          BookStatusBadge(status: book.status),
                                        // Praise is shown to the owner too: only
                                        // the button adding it is theirs to be
                                        // denied.
                                        complimentsAsync.when(
                                          data: (compliments) =>
                                              ComplimentBlock(
                                                compliments: compliments,
                                              ),
                                          loading: () =>
                                              const SizedBox.shrink(),
                                          error: (_, __) =>
                                              const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Shelf label positioned at bottom-right, just above
                            // the shelf. On a friend's book the status badge
                            // stacks on top of the label rather than sharing the
                            // spot, which used to hide it behind the label.
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!isSelf)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: shelfName.isEmpty ? 0 : 6,
                                      ),
                                      child: BookStatusBadge(
                                        status: book.status,
                                      ),
                                    ),
                                  ShelfLabel(label: shelfName),
                                ],
                              ),
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
                    decoration: BoxDecoration(
                      color: context.colors.surfaceVariant,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(30, 8, 30, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          key: _titleKey,
                          height: 24,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            child: Text(
                              book.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        bookInfoAsync.when(
                          data: (info) =>
                              info != null && info.authors.isNotEmpty
                              ? SizedBox(
                                  height: 20,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      info.authors.join(', '),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                          loading: () => const SizedBox(height: 20),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        if (book.status >= 1 && book.startDate != null) ...[
                          const SizedBox(height: 12),
                          ReadingPeriodRow(
                            startDate: book.startDate!,
                            finishDate: book.finishDate,
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
                  indicatorColor: context.colors.primaryText,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelColor: context.colors.primaryText,
                  unselectedLabelColor: context.colors.primaryText,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: const TextStyle(fontSize: 14),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: l10n.bookInfoTab),
                    Tab(text: l10n.memoTab),
                  ],
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
                onEditMemo: (memoId, content) =>
                    _onEditMemoPressed(book.id, memoId, content),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isSelf
          ? AnimatedBuilder(
              animation: _tabController.animation!,
              builder: (context, _) {
                final val = _tabController.animation!.value;
                if (val < 0.5) return const SizedBox.shrink();
                return AdaptiveFab(
                  symbol: 'square.and.pencil',
                  icon: Icons.edit,
                  onPressed: () => _onWriteMemoPressed(book.id),
                );
              },
            )
          : null,
    );
  }

  String _shelfNameFor(Book book, List<Shelf> shelves) {
    for (final shelf in shelves) {
      if (shelf.id == book.shelfId) return shelf.name;
    }
    return '';
  }

  void _onDeleteBookPressed(Book book) {
    showDeleteBookBottomSheet(
      context,
      onDeletePressed: () async {
        Navigator.pop(context);
        await ref.read(libraryActionsProvider).deleteBook(book.id);
        if (mounted) Navigator.pop(context);
      },
    );
  }

  void _onEditStatusPressed(Book book) {
    showBookStatusBottomSheet(
      context,
      currentStatus: book.status,
      startDate: book.startDate,
      finishDate: book.finishDate,
      onSave: (status, start, finish) async {
        await ref
            .read(libraryActionsProvider)
            .updateBookStatus(
              book.id,
              status,
              startDate: start,
              finishDate: finish,
            );
      },
    );
  }

  void _onWriteMemoPressed(String bookId) {
    _memoController.clear();
    showWriteMemoBottomSheet(
      context,
      controller: _memoController,
      onSavePressed: () async {
        Navigator.pop(context);
        final content = _memoController.text.trim();
        if (content.isNotEmpty) {
          await ref.read(libraryActionsProvider).addMemo(bookId, content);
          ref.invalidate(bookMemosProvider(bookId));
        }
      },
    );
  }

  void _onDeleteMemo(String memoId) async {
    await ref.read(libraryActionsProvider).deleteMemo(memoId);
  }

  void _onEditMemoPressed(String bookId, String memoId, String currentContent) {
    _memoController.text = currentContent;
    showWriteMemoBottomSheet(
      context,
      controller: _memoController,
      onSavePressed: () async {
        Navigator.pop(context);
        final content = _memoController.text.trim();
        if (content.isNotEmpty) {
          await ref.read(libraryActionsProvider).updateMemo(memoId, content);
          ref.invalidate(bookMemosProvider(bookId));
        }
      },
    );
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
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(color: context.colors.surface, child: tabBar);
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
        showEmojiBottomSheet(
          context,
          onEmojiPressed: (emoji) async {
            Navigator.pop(context);
            await ref
                .read(bookDetailsActionsProvider)
                .addCompliment(book.id, emoji);
          },
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: context.colors.brandFill,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      icon: const Icon(Icons.celebration, size: 18),
      label: Text(
        l10n.praise,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
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
      color: context.colors.surface,
      child: bookInfoAsync.when(
        data: (info) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info?.contents != null && info!.contents!.isNotEmpty) ...[
                Text(
                  l10n.bookDescription,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  info.contents!,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 24),
              ],
              if (info?.publisher != null) ...[
                Text(
                  l10n.publisher,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(info!.publisher!, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 24),
              ],
              const Text(
                'ISBN',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(book.isbn, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator.adaptive(),
          ),
        ),
        error: (_, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ISBN',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(book.isbn, style: const TextStyle(fontSize: 14)),
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
  const _BookMemoTab({
    required this.memosAsync,
    required this.isSelf,
    required this.onWriteMemo,
    required this.onDeleteMemo,
    required this.onEditMemo,
  });

  void _showMemoMenu(BuildContext context, BookMemo memo) {
    final l10n = AppLocalizations.of(context);
    showMenuBottomSheet(
      context: context,
      title: l10n.memoTab,
      actions: [
        MenuAction(
          label: l10n.edit,
          icon: Icons.edit_outlined,
          onPressed: () => onEditMemo(memo.id, memo.content),
        ),
        MenuAction(
          label: l10n.delete,
          icon: Icons.delete_outline,
          isDestructive: true,
          onPressed: () => onDeleteMemo(memo.id),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      color: context.colors.surface,
      child: memosAsync.when(
        data: (memos) {
          if (memos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.note_outlined,
                    size: 48,
                    color: context.colors.secondaryText,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isSelf ? l10n.writeAMemo : l10n.noMemos,
                    style: TextStyle(
                      color: context.colors.secondaryText,
                      fontSize: 14,
                    ),
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
                    Text(memo.content, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${memo.createdAt.year}.${memo.createdAt.month.toString().padLeft(2, '0')}.${memo.createdAt.day.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.secondaryText,
                          ),
                        ),
                        if (isSelf)
                          Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: context.colors.secondaryText,
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) =>
            Center(child: Text(l10n.errorWithMessage(e.toString()))),
      ),
    );
  }
}
