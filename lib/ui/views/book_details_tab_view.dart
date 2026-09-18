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
import 'package:bookworm_friends/models/reading_date.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/providers/book_details_provider.dart';
import 'package:bookworm_friends/providers/book_search_provider.dart';
import 'package:bookworm_friends/providers/libby_library_provider.dart';
import 'package:bookworm_friends/services/apple_books_lookup.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/services/overdrive_lookup.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/empty_state_art.dart';
import 'package:bookworm_friends/ui/widgets/book/book_magnifier.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/reactions_sheet.dart';
import 'package:bookworm_friends/ui/widgets/reaction_capsule.dart';
import 'package:bookworm_friends/ui/widgets/headers/collapsing_book_title.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/reading_period_row.dart';
import 'package:bookworm_friends/ui/widgets/band_progress_edge.dart';
import 'package:bookworm_friends/ui/widgets/band_progress_row.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_percent_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/write_memo_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/compliment_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/libby_library_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/store_links_sheet.dart';
import 'package:bookworm_friends/services/store_links_service.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final routeBook = ModalRoute.of(context)?.settings.arguments as Book?;
    if (routeBook == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.bookDetailsTitle)),
        body: Center(child: Text(l10n.bookInfoUnavailable)),
      );
    }

    final currentUserId = ref.watch(currentUserIdProvider);
    final isSelf = routeBook.userId == currentUserId;
    // Shelf names live in the *owner's* library, so a friend's book has to be
    // resolved against their shelves rather than the signed-in user's.
    //
    // Watched before anything reads the book, because it is also where the **live**
    // book comes from — see below.
    final shelvesAsync = isSelf
        ? ref.watch(libraryProvider)
        : ref.watch(userLibraryProvider(routeBook.userId));
    final shelves = shelvesAsync.valueOrNull ?? const <Shelf>[];
    // **The book as it is now, not as it was when this route was pushed.**
    //
    // `ModalRoute.settings.arguments` is a snapshot taken at navigation time and it
    // never changes. Every write in this page invalidates `libraryProvider` and so
    // reloads the row, but nothing here was reading that — so a change landed in the
    // database and nowhere on screen until the page was popped and pushed again.
    // Storing a reader app was the visible case: the sheet went on naming the old
    // shop, which read as the write having failed.
    //
    // It was also a **correctness** bug, not only a stale-paint one. `setReaderApp`
    // short-circuits when the value is unchanged, and it compared against this
    // snapshot: switching Kindle -> Play wrote, and switching back to Kindle in the
    // same page session compared 'kindle' with the snapshot's 'kindle', decided there
    // was nothing to do, and left the row on 'play'. The reader could change their
    // shop once and then silently not at all.
    //
    // Falls back to the snapshot rather than showing nothing, which covers the honest
    // gaps: the first frame before the library resolves, and a book that is no longer
    // in it at all. Note the library is *unfiltered* — `withoutFinishedBooks` and
    // `withoutReadingBooks` are applied by `library_view`, not by the provider — so a
    // finished book is found here, which is the majority of this page's traffic.
    final book = _liveBook(shelves, routeBook.id) ?? routeBook;

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
    // The band carries a reading position while the book is open — as a read-out once
    // there is one, and as a **prompt** (`How far in? ›`) before that, which is the
    // only door to the wheel the band has.
    //
    // **Not gated on `progress != null`, and that is a correction.** It was, and the
    // consequence was that the first set — the one moment every book passes through —
    // had no door in the band at all, and that the feature was invisible on a fresh
    // install because the streak chip hides at 0 too. The rule the migration states is
    // that null draws no *bar*, because an empty track claims the reader started and
    // got nowhere; a prompt claims nothing, so the rule does not reach it. The bar
    // itself is still gated separately, below.
    //
    // On a **friend's** book the prompt is withheld: with no value there is nothing to
    // read, and the row is not a door for anyone but the owner, so it would be a bare
    // chevron on an empty line. A friend's book with a real position still shows it.
    final showsProgressRow =
        book.status == bookStatusReading && (book.progress != null || isSelf);
    // Shelf names live in the *owner's* library, so a friend's book has to be
    // resolved against their shelves rather than the signed-in user's.
    final shelf = _shelfFor(book, shelves);
    final shelfName = shelf?.name ?? '';
    // Whether the shelf under the cover — the plank and the name tab on it — flies
    // in from the library with the book, or is simply here on arrival.
    //
    // It flies for a book that is actually *on* a shelf over there, which now means a
    // book with no status at all. A finished book is kept off the shelves by
    // `withoutFinishedBooks` and shown in the read pile; an open one is kept off them by
    // `withoutReadingBooks` and stood on the Reading shelf. In both cases the book's own
    // shelf row is still on the library route under these tags but is not where the
    // reader tapped — flying to it would send a bare shelf across the screen from
    // somewhere the cover was never standing.
    //
    // The Reading shelf's own plank and tab carry no tags at all, for the mirror-image
    // reason: this page names the shelf a book *belongs* to, so there is nothing over
    // here for that plank to fly to either. See `ReadingShelfRow`.
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
    final flyShelfFromLibrary =
        book.status != bookStatusFinished && book.status != bookStatusReading;
    // One tag, two places: the cover flies in from the library on it and out to the
    // magnifier on it. Named once here rather than spelled twice, because the two
    // ends of a flight that disagree about the tag simply do not fly.
    final coverHeroTag = 'book_${book.isbn}';

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
        actions: [
          // **Not gated on `isSelf`, unlike the two below.** A friend's finished
          // book is the discovery moment — the app is built so you see what other
          // people read — so this is the one action both viewers get, and on a
          // friend's book it is the only thing in a bar that was previously
          // absent entirely.
          IconButton(
            onPressed: () => _onWhereToReadPressed(book),
            // The icon is the whole affordance, so its tooltip is real copy and
            // not an afterthought: it is also the VoiceOver label. "Where to
            // read" covers both wanting a copy and owning one, so a single
            // string serves every state — and it never says "buy".
            tooltip: l10n.whereToRead,
            icon: const Icon(Icons.north_east, size: 24),
          ),
          if (isSelf) ...[
            IconButton(
              onPressed: () => _onDeleteBookPressed(book),
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline, size: 24),
            ),
            // **The pencil is gone, and this comment is its headstone.**
            //
            // `edit_outlined` sat here and opened `showBookStatusBottomSheet` —
            // status, start date, finish date. The reading period card in the band
            // *displays* exactly those three facts, and it now opens that same
            // sheet, so the pencil's last job went with it.
            //
            // That is the point of making the card a door rather than a nicety: a
            // 48×48 target at x341–389, in the top-right corner no thumb reaches,
            // is replaced by a 333×44 row sitting on the fact it edits. Do not
            // "restore" it for symmetry with `delete_outline`; two ways in is how
            // the card stops being read as the way in.
          ],
        ],
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
                                    heroTag: coverHeroTag,
                                    // Up close, at about two and a half times
                                    // this size and centred over a dimmed page.
                                    // The 180pt hero is the largest cover in the
                                    // app and still smaller than the jacket art
                                    // it is showing, so there is genuinely more
                                    // to see; and the enlarged book is a book
                                    // rather than a picture of one, so it answers
                                    // a hold with the same turn this one does.
                                    onTap: () => showMagnifiedBook(
                                      context,
                                      book: book,
                                      heroTag: coverHeroTag,
                                    ),
                                    // A tap magnifies and a hold turns, so a hold
                                    // must not also magnify on release. See the
                                    // parameter's doc for why this is keyed on the
                                    // turn completing rather than on it starting.
                                    holdSuppressesTap: true,
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
                        // Shared with `BandProgressEdge`, which clips the bar to
                        // this exact arc. Two literal 30s in two files is how the
                        // bar and the band drift apart.
                        bottomLeft: Radius.circular(kBookBandCornerRadius),
                        bottomRight: Radius.circular(kBookBandCornerRadius),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            30,
                            8,
                            30,
                            // The progress row's 44pt tap target is 14pt taller
                            // than its ink, and those 14 come out of here rather
                            // than being added to the band. So the band is exactly
                            // as tall with the row as it was without it.
                            showsProgressRow
                                ? kBandProgressRowResidualPadding
                                : 16,
                          ),
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
                              // Holds the row's height while the fallback lookup is
                              // in flight, so the hero does not resize under the
                              // reader — which is also what the collapse threshold
                              // is measured against.
                              else if (authorsPending)
                                const SizedBox(height: 20),
                              // Always rendered now, because it carries the status
                              // badge as well as the dates. The old guard
                              // (`status >= 1 && startDate != null`) would have
                              // taken the badge off screen entirely on an
                              // Interested book, which is 133 of 472 books in
                              // production. `ReadingPeriodRow` drops to a bare badge
                              // when there are no dates rather than wrapping one
                              // chip in a full-width card.
                              const SizedBox(height: 12),
                              ReadingPeriodRow(
                                status: book.status,
                                startDate: book.startDate,
                                finishDate: book.finishDate,
                                // The first of the band's two doors, and the one
                                // that retired the app bar's pencil: it opens the
                                // sheet that edits the three facts it displays.
                                // Null on a friend's book — the card still reads,
                                // but it draws no handle.
                                onTap: isSelf
                                    ? () => _onEditStatusPressed(book)
                                    : null,
                              ),
                              if (showsProgressRow) ...[
                                const SizedBox(height: 10),
                                BandProgressRow(
                                  progress: book.progress,
                                  pageCount: book.pageCount,
                                  // The second door. Straight to the wheel rather
                                  // than through the status sheet: the row already
                                  // shows the value, so a sheet in between would
                                  // ask the reader to find it again.
                                  onTap: isSelf
                                      ? () => _onEditProgressPressed(book)
                                      : null,
                                ),
                              ],
                            ],
                          ),
                        ),
                        // The band's own bottom edge, inked in to the reader's
                        // position. Positioned over the whole band rather than a 4pt
                        // strip, because its ends are clipped by the corner arcs and
                        // those are only expressible against the band's real height.
                        if (book.progress != null &&
                            book.status == bookStatusReading)
                          Positioned.fill(
                            child: BandProgressEdge(progress: book.progress),
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

  /// The row for [bookId] as the library currently holds it, or null if it is not
  /// there.
  ///
  /// Searched by **id across every shelf** rather than by looking inside the shelf the
  /// snapshot names, because `shelfId` is one of the things a write can change: moving
  /// a book and then reading it back out of its old shelf would find nothing and fall
  /// silently back to the stale copy. Id is the only field of a book that never moves.
  ///
  /// Linear, and deliberately not indexed. The largest library in production is 473
  /// books across a handful of shelves, this runs once per build of one page, and a
  /// cached map would be a second thing to keep in step with the library.
  Book? _liveBook(List<Shelf> shelves, String bookId) {
    for (final shelf in shelves) {
      for (final book in shelf.books) {
        if (book.id == bookId) return book;
      }
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

  /// Opens the "where to read this" sheet, and acts on what the reader picks.
  ///
  /// The shop set is resolved from what the app already holds — the row's ISBN,
  /// title and authors — plus two on-demand lookups: the catalogue's Google volume
  /// id, which makes Play Books exact at both intents, and an Apple Books URL,
  /// which is the only way Apple can be exact at all.
  ///
  /// **Only the owner's tap is recorded.** `reader_app` is the owner's fact, so a
  /// friend's book always shows the acquire list — never "Open Kindle" because
  /// its owner uses Kindle — and writes nothing. `setReaderApp` re-checks that,
  /// so the rule holds even if this call site ever forgets it.
  Future<void> _onWhereToReadPressed(Book book) async {
    final l10n = AppLocalizations.of(context);
    final isSelf = book.userId == ref.read(currentUserIdProvider);
    // The owner's stored shop, if it is one this build recognises. An unknown key
    // reads as null, which puts the book back on the acquire list rather than
    // showing an action nothing can perform.
    final current = isSelf ? storeIdFromKey(book.readerApp) : null;

    // Awaited before the sheet rather than inside it: the sheet is presentation
    // only, and an identifier is the difference between an exact link and a bare
    // search. `_bookInfoProvider` is very often already resolved, because the Book
    // info tab asked for it on arrival.
    //
    // **All four run concurrently.** Kakao supplies no volume id ever, so on that
    // path — the `ko` default, and this app's primary market — waiting for the
    // catalogue before deciding to ask Google would serialise two requests for an
    // answer already known. Where the source *is* Google Books the id arrives with
    // the catalogue result and no second request is made at all. Apple's and
    // OverDrive's are independent of the catalogue, because nothing it returns
    // could ever contain either id.
    //
    // Destructured from a record rather than indexed out of a `List<Object?>`:
    // the previous shape read `results.first as BookSearchResult?` and
    // `results.last as String?`, which are casts that go on compiling — and start
    // lying — the moment a third future is added. Which is what happened here.
    final localeCode = Localizations.localeOf(context).languageCode;
    final needsVolumeLookup = !ref.read(sourceSuppliesVolumeIdProvider);
    // **Which intent the sheet leads with, in order of how much the app actually
    // knows.** Three signals, most specific first:
    //
    //  1. `reader_app` is set -- the reader told us, by tapping. That shop's *open*
    //     row leads and the rest stay available as acquire rows.
    //  2. The book is at [bookStatusReading] or [bookStatusFinished] -- they have it
    //     somewhere, we just do not know where. Every shop becomes an *open* row.
    //  3. Otherwise (status 0, "interested") -- they do not have it. Acquire.
    //
    // **Case 2 is the majority.** Offering "get this" on a book someone has finished
    // reads as absurd, and the numbers are stark: of 473 books in production, 342 are
    // reading or finished and **3** carry a `reader_app`. The old rule sent all 342 to
    // the shops to buy a book it knew they had read.
    //
    // It is self-correcting rather than a guess that sticks, because tapping an open
    // row records the shop -- see the `onOpen` handler. That is this feature's existing
    // principle ("ownership is inferred from a tap, and remembered"), not a new one;
    // case 2 simply gives it somewhere to happen. Before this, acquire taps were the
    // only writer, so the 339 books with no shop had no route to ever getting one.
    //
    // **Gated on `isSelf`, and that is not incidental.** A friend's finished book is
    // the case this whole feature was built for, and there the reader wants "where can
    // I get this" -- offering to open *their own* library for someone else's book is
    // nonsense. `reader_app` is already the owner's fact for the same reason (see
    // `current` above); status is too. A widget test pins it.
    //
    // Accepted cost: a reader who finished a **paper** book sees four "Open X" rows and
    // no one-tap store search. Nothing lies to them -- every row reads "Opens your X
    // library" -- and one tap brings the acquire list back via case 1. Paper is
    // invisible to this app (no format field anywhere, and catalogue metadata describes
    // the edition, never what the reader owns), so it cannot be detected; this is the
    // trade, taken knowingly.
    // **A book the reader is reading or has finished is one they already have**, so no
    // row on it should be offering to sell it. `reader_app` narrows that to *where*,
    // and the two facts are independent:
    //
    //  * `reader_app` decides which shop **leads** and carries the check.
    //  * Status decides whether the **other** shops are `open` rows or `acquire` rows.
    //
    // Getting that second part wrong is what this replaces. Inference used to require
    // no stored shop at all, so storing one sent every *other* shop back to the
    // storefront -- a book at Reading with Apple stored still offered "Opens this
    // book's store page in your browser" for Play Books. Storing Apple says nothing
    // about Play, and certainly not that the reader wants to go buy the book they are
    // halfway through.
    //
    // **The majority case.** Of 473 books in production, 342 are reading or finished
    // and 3 carry a `reader_app` -- so before this the acquire list was being shown for
    // almost the whole library, for books the app knew had been read.
    //
    // It is self-correcting rather than a guess that sticks, because tapping any row
    // records that shop. That is this feature's existing principle ("ownership is
    // inferred from a tap, and remembered"), not a new one; this simply gives it
    // somewhere to happen, and a reader who stored the wrong shop fixes it by tapping
    // the right one instead of hunting for `Forget where I read this` first.
    //
    // **Gated on `isSelf`, and that is not incidental.** A friend's finished book is the
    // case this whole feature was built for, and there the reader wants "where can I get
    // this" -- offering to open *their own* library for someone else's book is nonsense.
    // `reader_app` is already the owner's fact for the same reason; status is too.
    //
    // Accepted cost: a reader who finished a **paper** book is offered four ways to open
    // a copy they do not have digitally, and no one-tap store search. Paper is invisible
    // here -- no format field anywhere, and catalogue metadata describes the *edition*,
    // never what the reader owns -- so it cannot be detected. Traded knowingly against
    // the 342-book problem above.
    final ownsItSomewhere =
        isSelf &&
        (book.status == bookStatusReading || book.status == bookStatusFinished);
    // The intent for every shop the reader has *not* singled out. The stored one, if
    // there is one, always gets its open row below.
    final othersIntent = ownsItSomewhere
        ? StoreIntent.open
        : StoreIntent.acquire;
    // Skipped where no Libby row will be shown, so the `ko` path does not pay for
    // two requests whose answer nothing reads. Only the **acquire** list uses the
    // id, so a reader whose stored shop is Libby gains nothing from the lookup —
    // but the acquire list is built alongside their stored row, so it still runs.
    //
    final wantsLibby = storesForLocale(localeCode).contains(StoreId.libby);
    // Read once, before the awaits, so the sheet and every link it contains agree
    // about which library was known at the moment it was built.
    final libbyLibraryKey = ref.read(libbyLibraryProvider).key;
    // **The reader's real Apple storefront, not a guess from their language.** Awaited
    // before the Apple lookup rather than alongside it, because it decides *which
    // storefront that lookup asks* — running them concurrently would mean asking the
    // wrong store. It is one cheap platform call, resolved once per session and cached
    // by the provider, so the serialisation costs nothing after the first sheet.
    //
    // Null on Android, in tests, and briefly during launch; `storeCountryFor` then
    // falls back to the locale, which is what this did before it could ask.
    final storefrontCountry = await ref
        .read(appStoreStorefrontProvider.future)
        .catchError((_) => null);
    if (!mounted) return;
    final appleCountry = storeCountryFor(
      localeCode,
      storefront: storefrontCountry,
    );
    final (info, lookedUpVolumeId, apple, overDrive) = await (
      ref.read(_bookInfoProvider(book.isbn).future).catchError((_) => null),
      needsVolumeLookup
          ? ref.read(volumeIdForIsbnProvider(book.isbn).future)
          : Future<String?>.value(),
      // Keyed on the storefront as well as the book: an Apple book URL is
      // scoped to the storefront that sold it, so the country the lookup ran
      // against has to be the country the link is for.
      //
      // **The author comes off the row, not off `info`.** Using the
      // catalogue's author would mean awaiting it first and serialising two
      // requests, and the title+author fallback is a bonus path — an empty
      // author simply means Apple is asked by ISBN alone, which is the
      // stricter question anyway.
      ref.read(
        appleBooksProvider((
          isbn: book.isbn,
          title: book.title,
          author: book.authors.isEmpty ? '' : book.authors.first,
          country: appleCountry,
        )).future,
      ),
      // No ISBN and no country, both deliberately — OverDrive does not index
      // ISBNs, and its title ids are global. Title and author are the whole key.
      // The author comes off the row for the same reason as Apple's; unlike
      // Apple's it is *required*, since a match cannot be confirmed without one.
      wantsLibby
          ? ref.read(
              overDriveProvider((
                title: book.title,
                author: book.authors.isEmpty ? '' : book.authors.first,
              )).future,
            )
          : Future<OverDriveResult>.value(const OverDriveResult.none()),
    ).wait;
    if (!mounted) return;

    // The catalogue's own id wins; the lookup is the fallback for sources that
    // cannot supply one. Null from both leaves every row a search, which the
    // supporting lines already state truthfully.
    final volumeId = info?.volumeId ?? lookedUpVolumeId;
    // Only a *confirmed* absence drops the row. `unknown` deliberately does not:
    // hiding a shop because a request timed out would be worse than offering the
    // weak fallback.
    final appleHasNoEdition =
        apple.availability == AppleBooksAvailability.notSold;
    // Null covers both "could not ask" and "no library lends it", which need no
    // distinguishing: either way the Libby row falls back to an OverDrive search,
    // and unlike Apple's fallback that one is a real results page. Paired with the
    // reader's library key it reaches the book inside Libby; alone it reaches an
    // exact OverDrive page in a browser.
    final libbyTitleId = overDrive.titleId;

    final authors = book.authors.isNotEmpty
        ? book.authors
        : (info?.authors ?? const <String>[]);

    final links = current != null
        ? [
            // The stored shop leads, as the one thing the reader came for, and
            // the rest stay available because a stored value is a hint and not a
            // fact — see `LibraryActions.setReaderApp`.
            if (openLinkFor(
                  stored: current,
                  isbn: book.isbn,
                  title: book.title,
                  authors: authors,
                  volumeId: volumeId,
                  libbyTitleId: libbyTitleId,
                  libbyLibraryKey: libbyLibraryKey,
                  storefrontCountry: storefrontCountry,
                  localeCode: localeCode,
                )
                case final StoreLink open)
              open,
            ...storeLinksFor(
              intent: othersIntent,
              isbn: book.isbn,
              title: book.title,
              authors: authors,
              volumeId: volumeId,
              appleBookUrl: apple.url,
              appleHasNoEdition: appleHasNoEdition,
              libbyTitleId: libbyTitleId,
              libbyLibraryKey: libbyLibraryKey,
              storefrontCountry: storefrontCountry,
              localeCode: localeCode,
            ).where((l) => l.id != current),
          ]
        : storeLinksFor(
            intent: othersIntent,
            isbn: book.isbn,
            title: book.title,
            authors: authors,
            // **The per-book ids are passed on the open path too, and an earlier draft
            // withheld them.** The reasoning for withholding was that "Read in Play
            // Books / Opens at this book" asserts ownership *in Play*, which status
            // does not establish -- status says "somewhere".
            //
            // It was wrong, and checking the alternative is what showed it:
            // `play.google.com/books/reader` with no id **is the Play Books
            // storefront** -- deals, top charts, new releases. So the supposedly
            // humbler row promised "Opens your Play Books library" and landed on a
            // shop, which is a worse lie than the one being avoided. With the id it
            // reaches the book's own reader.
            //
            // It is also the promise the stored-shop row above has always made without
            // verifying entitlement, so withholding here bought consistency nowhere.
            volumeId: volumeId,
            appleBookUrl: apple.url,
            appleHasNoEdition: appleHasNoEdition,
            libbyTitleId: libbyTitleId,
            libbyLibraryKey: libbyLibraryKey,
            storefrontCountry: storefrontCountry,
            localeCode: localeCode,
          );

    if (!mounted) return;
    await showStoreLinksSheet(
      context,
      links: links,
      isLoading: false,
      current: current,
      onOpen: (link) async {
        Navigator.pop(context);
        // **The just-in-time ask.** Only for Libby, only when the reader has never
        // been offered the picker, and only when a title id is in hand -- with no id
        // there is nothing a library key could point at, so asking would collect an
        // answer that changes nothing about this tap.
        //
        // Asked *after* the store sheet closes and *before* the launch, which is the
        // only moment that reads as one action: the reader tapped Libby, so the
        // question is plainly about getting there.
        var resolved = link;
        if (link.id == StoreId.libby &&
            libbyTitleId != null &&
            ref.read(libbyLibraryProvider).shouldAsk) {
          final chosen = await showLibbyLibrarySheet(context);
          if (!mounted) return;
          if (chosen == null) {
            // Dismissed. Recorded so it is never asked again, and the original
            // link -- which works -- is launched unchanged.
            await ref.read(libbyLibraryProvider.notifier).decline();
          } else {
            await ref
                .read(libbyLibraryProvider.notifier)
                .choose(chosen.key, chosen.name);
            // Rebuilt rather than patched: the key changes the row's *reach* as
            // well as its URL, and `storeLinksFor` is the only thing entitled to
            // decide that. Mutating the URL here would leave a `storePage` link
            // pointing at an in-app destination.
            resolved = storeLinksFor(
              intent: link.intent,
              isbn: book.isbn,
              title: book.title,
              authors: authors,
              volumeId: volumeId,
              appleBookUrl: apple.url,
              appleHasNoEdition: appleHasNoEdition,
              libbyTitleId: libbyTitleId,
              libbyLibraryKey: chosen.key,
              storefrontCountry: storefrontCountry,
              localeCode: localeCode,
            ).firstWhere((l) => l.id == StoreId.libby, orElse: () => link);
          }
          if (!mounted) return;
        }
        final opened = await _launchStore(resolved.uri);
        if (!opened) {
          EasyLoading.showError(l10n.errorOccurred);
          return;
        }
        // Recorded for the owner on **either** intent, which is the change that makes
        // the status-inferred open list self-correcting instead of a guess that
        // sticks. It used to be `acquire`-only, and the stated reason for that —
        // "re-tapping the shop they already stored should not rewrite it" — was
        // already handled by `setReaderApp` short-circuiting an unchanged value, so
        // the gate was doing no work the writer did not already do.
        //
        // Tapping "Open Kindle" on a finished book *is* the ownership assertion, and
        // it is the only assertion the 339 books with no `reader_app` will ever get.
        // A mistaken tap is undone by "Forget where I read this", exactly as a
        // mistaken acquire tap always was.
        if (isSelf) {
          await ref
              .read(libraryActionsProvider)
              .setReaderApp(book, resolved.id.key);
        }
      },
      onForget: () async {
        Navigator.pop(context);
        await ref.read(libraryActionsProvider).setReaderApp(book, null);
      },
    );
  }

  /// Hands a store URL to the platform.
  ///
  /// `externalApplication` rather than the in-app browser `settings_page` uses:
  /// the point of every one of these links is to reach an app the reader already
  /// has, and an in-app web view would defeat the universal link that gets them
  /// there — `books.apple.com` opens Apple Books only when the OS resolves it.
  ///
  /// Returns false rather than throwing when nothing can handle the URL, which for
  /// a custom scheme means the reader app is not installed.
  Future<bool> _launchStore(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
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
      progress: book.progress,
      progressPage: book.progressPage,
      // Enables the wheel's Page mode, its derived-page rider and the row's ability
      // to print a page. Null for about two reading books in three, which is why the
      // sheet stores a fraction and opens on percent.
      pageCount: book.pageCount,
      readToday: ref.read(readTodayProvider),
      onSave: (edit) async {
        await ref
            .read(libraryActionsProvider)
            .updateBookStatus(
              book.id,
              edit.status,
              startDate: edit.startDate,
              finishDate: edit.finishDate,
              progress: edit.progress,
              progressPage: edit.progressPage,
            );
        // **A second, independent write, deliberately not folded into the first.**
        // One Save, two facts: a day is not a column on `books` and a bookmark is
        // not a row in `reading_days`. Keeping the calls apart is what makes it
        // impossible for a change of status to stamp a day by accident — and this
        // one no-ops when the tick did not move, so an ordinary date edit issues no
        // request at all.
        await ref
            .read(readingDaysProvider.notifier)
            .setRead(
              readingDate(DateTime.now()),
              read: edit.readToday,
              bookId: book.id,
            );
      },
    );
  }

  /// The band's second door: straight to the percent wheel.
  ///
  /// **Not through `showBookStatusBottomSheet`**, unlike the period card above it.
  /// The row already shows the position, so routing the tap through a form would ask
  /// the reader to locate the value they just tapped on. The status sheet keeps its
  /// own copy of the row for the case where the position is being set for the first
  /// time and there is nothing in the band yet to tap.
  void _onEditProgressPressed(Book book) {
    showSelectPercentBottomSheet(
      context,
      initialProgress: book.progress,
      initialPage: book.progressPage,
      pageCount: book.pageCount,
      onProgressSelected: (answer) async {
        // The status and both dates are passed back unchanged. This call is the
        // only writer of the column, and it must not become a way to edit anything
        // else by accident.
        await ref
            .read(libraryActionsProvider)
            .updateBookStatus(
              book.id,
              book.status,
              startDate: book.startDate,
              finishDate: book.finishDate,
              progress: answer.progress,
              progressPage: answer.page,
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
                  const EmptyStateArt(EmptyStateArtwork.noNote, size: 48),
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
