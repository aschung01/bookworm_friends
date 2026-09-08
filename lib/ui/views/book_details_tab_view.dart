import 'package:bookworm_friends/ui/widgets/buttons/adaptive_fab.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_back_button.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/menu_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
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
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/reactions_sheet.dart';
import 'package:bookworm_friends/ui/widgets/reaction_capsule.dart';
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
    // Authors come from the row when the row has them, and from the catalogue only
    // when it does not. Every book saved since `books.authors` landed carries its
    // own, so the name under the title paints on the first frame instead of
    // arriving a request later and resizing the hero under the reader. The lookup
    // stays as the fallback for rows written before the column existed and for any
    // the backfill could not resolve — 15 of the migrated books have no ISBN to
    // look one up with.
    //
    // Note what this does *not* do: it does not save the request. The Book info tab
    // below shows publisher, publication date and description, none of which the
    // row owns, so the catalogue is asked either way. What the column buys here is
    // that the header no longer depends on the answer.
    final bookInfoAsync = ref.watch(_bookInfoProvider(book.isbn));
    final authors = book.authors.isNotEmpty
        ? book.authors
        : (bookInfoAsync.valueOrNull?.authors ?? const <String>[]);
    final authorsPending = book.authors.isEmpty && bookInfoAsync.isLoading;
    // Shelf names live in the *owner's* library, so a friend's book has to be
    // resolved against their shelves rather than the signed-in user's.
    final shelvesAsync = isSelf
        ? ref.watch(libraryProvider)
        : ref.watch(userLibraryProvider(book.userId));
    final shelf = _shelfFor(book, shelvesAsync.valueOrNull ?? const []);
    final shelfName = shelf?.name ?? '';
    // Whether the shelf under the cover — the plank and the name tab on it — flies
    // in from the library with the book, or is simply here on arrival.
    //
    // It flies for a book that is actually *on* a shelf over there. A finished book
    // is kept off the shelves by `withoutFinishedBooks` and shown in the read pile
    // instead, so its shelf row is still on the library route under these tags but
    // is not where the reader tapped — flying to it would send a bare shelf across
    // the screen from somewhere the cover was never standing.
    //
    // **The book itself is a separate question, and the answer to it has changed.**
    // This used to read "the pile and the month grid fly no book either, for the
    // same reason", and the reason was sound while the pile drew thirteen identical
    // green spines: there was no cover there to fly, and thirteen candidates for one
    // tag if there had been. The pile now turns a book out to its cover, one at a
    // time, and **only that book carries the tag** — so there is exactly one source
    // for it on the route, and what flies is the very cover the reader tapped. The
    // month grid flies its covers too: it is never on screen at the same time as the
    // pile, and it withholds the tag from any ISBN it holds twice — or holds none of
    // — so the same "exactly one source" property holds there. See
    // `ReadMonthGrid._flyableIsbns`.
    //
    // The *plank* is still not flown from the pile, and that is not an oversight:
    // the pile's shelf is shared by every book standing on it rather than being any
    // particular shelf's, so there is nothing for a named shelf tab to fly from.
    // Hence this stays keyed on status and not on where the tap came from.
    final flyShelfFromLibrary = book.status != bookStatusFinished;

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
                                    pageCount: book.pageCount,
                                    heroTag: 'book_${book.isbn}',
                                    // The largest cover in the app, so it is the
                                    // one most likely to have decoded. Guarded
                                    // inside the action, which matters here more
                                    // than anywhere: this page renders a friend's
                                    // book as readily as your own.
                                    onCoverSampled: (color) => ref
                                        .read(libraryActionsProvider)
                                        .recordCoverColor(book, color),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        // Hidden the moment you hold a reaction:
                                        // you may only hold one, so a button
                                        // still offering to add would be
                                        // promising something it cannot do —
                                        // what it actually does is replace or
                                        // withdraw, and both of those belong to
                                        // the reaction you already have. The
                                        // capsule below owns them.
                                        if (!isSelf) _ReactButton(book: book),
                                        // Shown to the owner too: only the
                                        // button adding a reaction is theirs to
                                        // be denied. This is the recipient's
                                        // only sight of what they were given —
                                        // there is no notification and no
                                        // history anywhere in the app.
                                        complimentsAsync.when(
                                          data: (compliments) =>
                                              ReactionCapsule(
                                                compliments: compliments,
                                                currentUserId: ref.watch(
                                                  currentUserIdProvider,
                                                ),
                                                onTap: () =>
                                                    _onReactionsPressed(
                                                      book,
                                                      compliments,
                                                    ),
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
                            // The shelf label, alone. The status badge used to
                            // stack above it here and to be hoisted to the top
                            // of the right-hand column on your own book — two
                            // places for one thing, because this corner belonged
                            // to a button the owner is never shown. It lives in
                            // the reading-period card now, which has one rule
                            // for both viewers.
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: ShelfLabel(
                                label: shelfName,
                                // **The count is part of the hero contract, not
                                // decoration.** The tab shrink-wraps its
                                // contents, so a library tab reading `IT 12`
                                // flying to a details tab reading `IT` would
                                // change size in the air — which is the one
                                // thing `ShelfLabel`'s doc says must not happen,
                                // because the box is squeezed onto its text and
                                // a fraction of a point off ellipsizes the name
                                // mid-flight. Both ends therefore derive it from
                                // `shelvedBookCount` of the same shelf.
                                //
                                // Null when the shelf could not be resolved: the
                                // name is empty then too, so the tab paints
                                // nothing and there is no hero at either end.
                                count: shelf == null
                                    ? null
                                    : shelvedBookCount(shelf),
                                heroTag: flyShelfFromLibrary
                                    ? shelfLabelHeroTag(book.shelfId)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        // The other half of the book's flight: the shelf comes in
                        // from the library carrying the book that was standing on
                        // it, rather than vanishing at one end while a different
                        // one appears at this one.
                        ShelfWidget(
                          heroTag: flyShelfFromLibrary
                              ? shelfHeroTag(book.shelfId)
                              : null,
                        ),
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
                              style: AppTextStyles.subtitle,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (authors.isNotEmpty)
                          SizedBox(
                            height: 20,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                authors.join(', '),
                                style: AppTextStyles.label,
                              ),
                            ),
                          )
                        // Holds the row's height while the fallback lookup is in
                        // flight, so the hero does not resize under the reader —
                        // which is also what the collapse threshold is measured
                        // against.
                        else if (authorsPending)
                          const SizedBox(height: 20),
                        // Always rendered now, because it carries the status
                        // badge as well as the dates. The old guard
                        // (`status >= 1 && startDate != null`) would have taken
                        // the badge off screen entirely on an Interested book,
                        // which is 133 of 472 books in production.
                        // `ReadingPeriodRow` drops to a bare badge when there are
                        // no dates rather than wrapping one chip in a full-width
                        // card.
                        const SizedBox(height: 12),
                        ReadingPeriodRow(
                          status: book.status,
                          startDate: book.startDate,
                          finishDate: book.finishDate,
                        ),
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
                  // Selection used to be carried by weight as well as by the
                  // underline; both label styles are one token now, so colour has
                  // to do that half of the work. Without this the two tabs were
                  // typographically identical and the 2pt indicator was the only
                  // difference between them.
                  unselectedLabelColor: context.colors.secondaryText,
                  labelStyle: AppTextStyles.label,
                  unselectedLabelStyle: AppTextStyles.label,
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

  /// The shelf [book] sits on, or null if it cannot be resolved.
  ///
  /// Returns the shelf rather than just its name because the tab now needs its
  /// book count as well, and resolving it twice would be two chances to disagree
  /// with the library about what this shelf is.
  Shelf? _shelfFor(Book book, List<Shelf> shelves) {
    for (final shelf in shelves) {
      if (shelf.id == book.shelfId) return shelf;
    }
    return null;
  }

  /// Opens the who-reacted sheet from the capsule, and owns the round trip out to
  /// the picker and back.
  ///
  /// The capsule is the only route to your own reaction now that the button
  /// hides as soon as you have one — and, because the capsule belongs to the
  /// record rather than to the button, the only route that still works on a book
  /// which has gone back to *Reading* or *Interested*. That state used to strand
  /// a reaction on screen with no way to reach it.
  ///
  /// The sheet pops itself before handing over, so the picker replaces it rather
  /// than stacking on it. On its own that left backing out of the picker on the
  /// bare book — two steps from where you started, with nothing to show you had
  /// been anywhere. So the reactions sheet is a **hub** here rather than one leg
  /// of a chain: dismissing the picker without choosing loops round and puts it
  /// back.
  ///
  /// Choosing deliberately does not loop. A pick is the task completing, and
  /// completing closes the flow where cancelling returns you to where you were.
  /// That also sidesteps the one case a loop would get wrong: withdraw your only
  /// reaction and there is no record left for the sheet to show.
  ///
  /// [compliments] is not re-read between passes, because no path that loops can
  /// have changed it — the loop only runs again after a dismissal, which by
  /// definition changed nothing.
  Future<void> _onReactionsPressed(
    Book book,
    List<BookCompliment> compliments,
  ) async {
    final userId = ref.read(currentUserIdProvider);

    while (true) {
      // Re-checked per pass rather than in the `while` condition: the analyzer
      // only accepts a dedicated `mounted` guard as cover for the `context` uses
      // that follow an await.
      if (!mounted) return;

      var editMine = false;
      await showReactionsSheet(
        context,
        compliments: compliments,
        currentUserId: userId,
        onEditMine: () => editMine = true,
      );
      // Dismissed the hub itself rather than drilling in, so the flow is over.
      if (!editMine) return;
      if (!mounted) return;

      String? chosen;
      await showEmojiBottomSheet(
        context,
        // Marks your own cell in the grid, which is the whole of the toggle's
        // legibility once the sheet is open: tapping the marked emoji withdraws
        // it, tapping any other replaces it. `praiseTapFor` makes both the same
        // call.
        selected: praiseBy(compliments, userId),
        // Records the choice and closes. The write waits until below, where it
        // can be awaited without the picker still sitting on screen.
        onEmojiPressed: (emoji) {
          chosen = emoji;
          Navigator.pop(context);
        },
      );

      // Dismissed without choosing. `chosen` is captured by the callback above,
      // so it cannot be promoted here and the `!` below is load-bearing.
      if (chosen == null) continue;
      if (!mounted) return;

      await ref.read(bookDetailsActionsProvider).togglePraise(book.id, chosen!);
      return;
    }
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

/// The control for adding a reaction to a friend's finished book.
///
/// Shown only while there is something to add: hidden on your own book, hidden
/// below status 2, and **hidden once you already hold a reaction**. That last
/// one is the change worth explaining. You may hold only one reaction per book,
/// so a button still saying *React* would be offering an action it cannot
/// perform — what a tap actually does at that point is replace or withdraw, and
/// both of those belong to the reaction you already have rather than to a fresh
/// one. [ReactionCapsule] owns them, and says they are yours by taking the
/// picker's marked-cell tint.
///
/// Earlier drafts tried to make the button's *state* honest instead: carrying
/// your emoji on its face (which duplicated the record beside it), then going
/// outlined and saying "Reacted" (which restated what the record already said,
/// and needed a second string in every locale). Removing it outright is simpler
/// than either, needs no new string at all, and works in the states where the
/// button is absent anyway.
class _ReactButton extends ConsumerWidget {
  final Book book;
  const _ReactButton({required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (book.status != 2) return const SizedBox.shrink();

    final mine = praiseBy(
      ref.watch(bookComplimentsProvider(book.id)).valueOrNull ?? const [],
      ref.watch(currentUserIdProvider),
    );
    if (mine != null) return const SizedBox.shrink();

    return ElevatedButton.icon(
      onPressed: () => showEmojiBottomSheet(
        context,
        onEmojiPressed: (emoji) async {
          Navigator.pop(context);
          await ref
              .read(bookDetailsActionsProvider)
              .togglePraise(book.id, emoji);
        },
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: context.colors.brandFill,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      icon: const Icon(Icons.celebration, size: 18),
      label: Text(l10n.praise, style: AppTextStyles.label),
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
                Text(l10n.bookDescription, style: AppTextStyles.subtitle),
                const SizedBox(height: 8),
                Text(info.contents!, style: AppTextStyles.body),
                const SizedBox(height: 24),
              ],
              if (info?.publisher != null) ...[
                Text(l10n.publisher, style: AppTextStyles.subtitle),
                const SizedBox(height: 8),
                Text(info!.publisher!, style: AppTextStyles.body),
                const SizedBox(height: 24),
              ],
              const Text('ISBN', style: AppTextStyles.subtitle),
              const SizedBox(height: 8),
              Text(book.isbn, style: AppTextStyles.body),
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
              const Text('ISBN', style: AppTextStyles.subtitle),
              const SizedBox(height: 8),
              Text(book.isbn, style: AppTextStyles.body),
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
                    style: AppTextStyles.body.copyWith(
                      color: context.colors.secondaryText,
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
                    Text(memo.content, style: AppTextStyles.body),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${memo.createdAt.year}.${memo.createdAt.month.toString().padLeft(2, '0')}.${memo.createdAt.day.toString().padLeft(2, '0')}',
                          // `label` rather than `caption`: caption exists for the
                          // tracked uppercase stat labels, and its letterspacing
                          // would pull a run of digits apart.
                          style: AppTextStyles.label.copyWith(
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
