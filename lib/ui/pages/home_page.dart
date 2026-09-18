import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/friend_reading.dart';

import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/shelf_density_provider.dart';
import 'package:bookworm_friends/providers/shell_chrome_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/reading_days_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/views/library_view.dart';
import 'package:bookworm_friends/ui/widgets/avatar_circle.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/remove_friend_confirm.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/glass_avatar_button.dart';
import 'package:bookworm_friends/ui/widgets/friends_sheet.dart';
import 'package:bookworm_friends/ui/widgets/invite/invite_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_card_sheet.dart';
import 'package:bookworm_friends/ui/widgets/reading_streak_chip.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/update_shelf_name_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_shelf_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/manage_shelves_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/loading_blocks.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _shelfNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The floating tab bar is hosted above the `Navigator` by `ShellChrome`, which
    // therefore cannot see this page at all. Publishing our own route is how it
    // learns the shell is on screen — and, by comparing against the top page
    // route, that nothing has been pushed over it.
    //
    // Deferred to the end of the frame on purpose: writing to a provider from
    // `initState` happens while this subtree is building, and `ShellChrome` is an
    // ancestor that has already built — marking it dirty in the same frame is an
    // error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(shellHomeRouteProvider.notifier).state = ModalRoute.of(context);
    });
  }

  @override
  void dispose() {
    _shelfNameController.dispose();
    super.dispose();
  }

  /// The library on screen, held across a change of owner so the pane never blanks.
  ///
  /// **Why a field and not just `valueOrNull`.** Switching whose library you are
  /// looking at re-points two `autoDispose.family` reads at a different user id, and
  /// the first frame after the tap has no data for the new one. Drawn honestly that
  /// is an empty pane, which is what a visit used to look like: `_FriendLibraryPage`
  /// resolved its shelves with `.when(loading: CircularProgressIndicator.adaptive())`
  /// and wiped the screen. Holding the outgoing pair and fading it keeps the tap's
  /// answer continuous with what was on screen when it was made — see
  /// [LibraryPane.stale] and [_LoadingChip], which draw the in-flight state.
  ///
  /// **Swapped as a pair, never one at a time.** Shelves and read books are two
  /// queries that land in either order, so replacing them independently shows one
  /// reader's shelves under another's read count for a frame. The pair is the unit.
  ({List<Shelf> shelves, List<Book> reads})? _onScreen;

  /// Set when a long press opens edit mode, and cleared by the stray tap that
  /// same gesture produces on release.
  ///
  /// Entering edit mode replaces the shelf's whole list — the plain row becomes a
  /// row of long-press `Draggable`s — so the `BookWidget` element holding the
  /// in-flight tap is destroyed at the moment the mode flips. Its arena entry
  /// goes with it, and the page-level "tap anywhere to leave edit mode" handler
  /// below inherits the release. Without this latch, letting go of the book you
  /// just long-pressed closes the mode it opened, which made long-press-to-edit
  /// look like it did nothing at all.
  bool _editOpenedByThisGesture = false;

  /// How much of the screen the collapsed sheet covers, published by the sheet after
  /// each layout. The library insets its shelf list by it, because a floating sheet
  /// shrinks nothing to make room for itself.
  double _restingExtent = 0;

  /// Given to whichever tab's sheet is on screen, so all three hand the **same**
  /// `LibrarySheet` element between them.
  ///
  /// Without it a tab switch builds a new sheet, which arrives at its opening position
  /// with no way of knowing where the last one was — so a switch between tabs of
  /// different heights was a jump cut. With it the element is re-parented, keeps its
  /// height, and springs to the incoming tab's position; see `LibrarySheet`.
  ///
  /// One key, held by this `State` rather than being a constant, because two live
  /// elements cannot share a `GlobalKey` and a second shell could be pumped beside
  /// this one in a test. There is exactly one sheet on screen now that a visit is a
  /// state of this page rather than a page of a pager — which is also what lets the
  /// Friends tab's two levels spring into each other rather than jump-cut.
  final GlobalKey _sheetKey = GlobalKey();

  void _enterEditMode() {
    _editOpenedByThisGesture = true;
    ref.read(libraryModeProvider.notifier).state = LibraryMode.editLibrary;
  }

  /// Ends a visit: back to your own library.
  ///
  /// Two writes, and the second is the one that is easy to forget. Clearing the
  /// selection swaps the background and the bar back to yours; resetting the level
  /// puts the Friends sheet back to the list, so the tab you are standing on does not
  /// keep showing a second level belonging to nobody.
  ///
  /// Three controls end up here: the bar's ✕, the system back, and selecting the
  /// Library or Card tab — the last of those through `ShellChrome._selectTab`, which
  /// cannot call this and writes the same two providers itself.
  void _endVisit() {
    ref.read(selectedFriendProvider.notifier).state = null;
    ref.read(friendsSheetLevelProvider.notifier).state = FriendsSheetLevel.list;
  }

  /// Re-reads whichever library is on screen.
  ///
  /// One path for both callers — the pull-to-refresh on the shelves, and the Retry on
  /// the error state — because "how do I re-read this library" should have one answer.
  /// Reads the friend at call time rather than taking it as an argument: a refresh can
  /// be started at any point, and what should be re-read is whatever is on screen then.
  ///
  /// A friend's providers are `keepAlive`, so this is the only thing that ever re-reads
  /// them. That is what keeps the cache honest rather than permanent.
  Future<void> _refreshLibrary() async {
    final friend = ref.read(selectedFriendProvider);
    if (friend == null) {
      ref.invalidate(libraryProvider);
      ref.invalidate(finishedBooksProvider);
      return;
    }
    ref.invalidate(userLibraryProvider(friend.id));
    ref.invalidate(userFinishedBooksProvider(friend.id));
  }

  /// The sheet the selected tab puts above the library.
  ///
  /// Only the sheet changes here. The [LibraryPane] holding it is the same widget
  /// in the same place with the same shelves, which is what keeps the background
  /// persistent across a tab switch instead of merely looking persistent.
  ///
  /// And only the sheet's *contents*, strictly: all three pass [_sheetKey], so the
  /// `LibrarySheet` underneath them is one element handed from tab to tab — which is
  /// what lets the height spring between two tabs of different sizes.
  ///
  /// **[finishedBooks] belongs to whoever's library is behind the sheet**, not always
  /// to you, and that is safe because of the shell's one invariant: a friend can only
  /// be selected while the Friends tab is, so Library and Card never see anyone
  /// else's books. See [selectedFriendProvider].
  Widget _sheetForTab(
    LibraryTab tab, {
    required LibraryMode mode,
    required List<Book> finishedBooks,
    required int filterYear,
    required int friendFilterYear,
    required int cardFilterYear,
    required String? username,
    required String? handle,
    required DateTime? memberSince,
    required List<Profile> following,
    required Map<String, FriendReading> friendsReading,
    required Profile? selectedFriend,
    required FriendsSheetLevel friendsLevel,
    required double maxExtent,
    required ValueChanged<double> onRestingExtent,
  }) {
    final isEditMode = mode == LibraryMode.editLibrary;
    // No bar to leave room for while editing, and the library wants every pixel
    // it can get to be rearranged in.
    final reserve = isEditMode ? 0.0 : ShellTabBar.geometryOf(context).reserve;
    switch (tab) {
      case LibraryTab.library:
        return FinishedBooksSheet(
          sheetKey: _sheetKey,
          books: finishedBooks,
          isEditMode: isEditMode,
          filterYear: filterYear,
          maxExtent: maxExtent,
          bottomReserve: reserve,
          onRestingExtent: onRestingExtent,
          onFilterChanged: (year) =>
              ref.read(readsFilterYearProvider.notifier).state = year,
        );
      case LibraryTab.friends:
        // The Friends tab has two levels, and this is the whole of the difference
        // between them: the list of everyone you follow, or the reads of the one you
        // tapped. Her *library* is behind both — coming back up to the list does not
        // end the visit — which is why the level is its own bit of state rather than
        // something [selectedFriendProvider] could imply.
        //
        // **There is no back control in the sheet.** Tapping the Friends tab again is
        // what comes back up, which is the gesture iOS already trains: a tap on the
        // tab you are standing on means "take me to the top of this tab". It costs no
        // pixels in a header that has a title, a count and a year control in it, and
        // it leaves her read view identical to your own. See
        // `ShellChrome._selectTab`, which owns it.
        //
        // The `contentId` change between the two sheets is what makes the swap a
        // spring rather than a jump cut: `LibrarySheet` sees `FriendsSheet` become
        // `FinishedBooksSheet` under one shared key and travels from the list's medium
        // detent down to the pile. Nothing new is needed for that — see
        // [LibrarySheet.contentId].
        if (selectedFriend != null &&
            friendsLevel == FriendsSheetLevel.friend) {
          return FinishedBooksSheet(
            sheetKey: _sheetKey,
            books: finishedBooks,
            isEditMode: isEditMode,
            filterYear: friendFilterYear,
            maxExtent: maxExtent,
            bottomReserve: reserve,
            onRestingExtent: onRestingExtent,
            onFilterChanged: (year) =>
                ref.read(friendReadsFilterYearProvider.notifier).state = year,
          );
        }
        return FriendsSheet(
          sheetKey: _sheetKey,
          following: following,
          reading: friendsReading,
          selectedFriend: selectedFriend,
          isEditMode: isEditMode,
          bottomReserve: reserve,
          maxExtent: maxExtent,
          onRestingExtent: onRestingExtent,
          onSelectFriend: (profile) {
            ref.read(selectedFriendProvider.notifier).state = profile;
            ref.read(friendsSheetLevelProvider.notifier).state =
                FriendsSheetLevel.friend;
            ref.read(libraryModeProvider.notifier).state = LibraryMode.library;
          },
          onAddFriend: _showInviteSheet,
        );
      case LibraryTab.card:
        return LibraryCardSheet(
          sheetKey: _sheetKey,
          books: finishedBooks,
          reading: ref.watch(readingBooksProvider),
          filterYear: cardFilterYear,
          username: username,
          handle: handle,
          memberSince: memberSince,
          maxExtent: maxExtent,
          isEditMode: isEditMode,
          bottomReserve: reserve,
          onRestingExtent: onRestingExtent,
          onFilterChanged: (year) =>
              ref.read(cardFilterYearProvider.notifier).state = year,
          // Derived from `reading_days` on read, never stored. Watched here with
          // everything else the card is handed, so the sheet itself stays free of
          // providers — see `LibraryCardSheet.streak`.
          streak: ref.watch(currentStreakProvider),
          longestStreak: ref.watch(longestStreakProvider),
        );
    }
  }

  /// Slides [sheet] off the bottom of the screen while the library is being edited,
  /// and stops it taking hits there.
  ///
  /// **Hidden, not merely shut.** Every sheet already springs to its collapsed detent
  /// in edit mode and goes inert, and that was enough while an edit was a matter of
  /// deleting a cover or renaming a shelf. It is not enough now that a book can be
  /// *carried* between shelves: a collapsed sheet is a third of a screen of dead card
  /// sitting over the bottom shelves, and those are the shelves a drag needs to be
  /// able to reach and drop onto. What the reader is doing while editing has nothing
  /// to do with what they have read.
  ///
  /// **Slid rather than unbuilt.** `LibraryPaneFrame` exists to make the presence of a
  /// sheet structural, and the sheet's `State` is what remembers the detent to return
  /// to once the edit ends — see `LibrarySheet._detentBeforeEdit`. Taking it out of
  /// the tree would throw both away, so it stays mounted, measured, and one
  /// screen-height further down.
  ///
  /// The room the library reserves for it goes with it: see [_bottomInset].
  static Widget _hiddenWhileEditing(LibraryMode mode, Widget sheet) {
    final hidden = mode == LibraryMode.editLibrary;
    return IgnorePointer(
      ignoring: hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: AnimatedSlide(
          offset: Offset(0, hidden ? 1 : 0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: sheet,
        ),
      ),
    );
  }

  /// How much of the library the sheet is standing on, which is what the shelf list
  /// pads itself by so its last shelf can still be scrolled clear of it.
  ///
  /// Nothing but the home indicator while editing, because [_hiddenWhileEditing] has
  /// taken the sheet off the screen and the floating tab bar is gone too (see
  /// `shellBarVisibleProvider`). The sheet goes on reporting the extent it *would*
  /// rest at — it is still laid out — so this has to be the one place that decides
  /// whether to believe it.
  double _bottomInset(BuildContext context, LibraryMode mode) =>
      mode == LibraryMode.editLibrary
      ? MediaQuery.viewPaddingOf(context).bottom
      : _restingExtent;

  /// The height the shell's bar occupies at the top of the screen, which is what the
  /// library beneath it is inset by.
  ///
  /// Ours to compute now that the bar is a stack child rather than the `Scaffold`'s
  /// app bar — the price of a sheet that can rise over it. One row, the same on every
  /// screen: the `FriendRail`'s second row is gone, so a visit no longer shoves the
  /// shelves down 56pt and the bar's height cannot change under a running animation.
  static double _barExtent(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + _libraryBarRow;

  static const double _libraryBarRow = 56;

  /// The band a sheet may cover: everything but the status bar and the bottom half
  /// of the library bar, so a fully expanded sheet stops at the middle of "My
  /// Library" rather than swallowing it whole.
  static double _sheetBand(BuildContext context, BoxConstraints constraints) =>
      constraints.maxHeight -
      MediaQuery.viewPaddingOf(context).top -
      (_libraryBarRow / 2);

  /// The shell's bar: whose library you are looking at, and the actions for it.
  ///
  /// Painted *behind* the library pane, so the sheet can rise over it. The pane leaves
  /// this band unpainted, which is what keeps the bar's own buttons live.
  Widget _bar({
    required bool isSelf,
    required LibraryMode mode,
    required Profile? selectedFriend,
    required Profile? me,
  }) => SizedBox(
    // `AppBar` is a flex with a flexible child, so it cannot be handed the
    // unbounded height a `Positioned` without a `bottom` gives it. [_barExtent] is
    // exactly what a `Scaffold` would have reserved for it: the status bar it insets
    // itself by, plus its one row.
    height: _barExtent(context),
    child: AppBar(
      backgroundColor: context.colors.surface,
      automaticallyImplyLeading: false,
      centerTitle: false,
      elevation: 0,
      titleSpacing: 0,
      // Nothing in the toolbar row: the bar is one row now that the rail is gone, and
      // that row is the `bottom`. Collapsing the toolbar rather than moving the bar
      // into it keeps the status-bar inset `AppBar` applies for free.
      toolbarHeight: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(_libraryBarRow),
        child: _LibraryBar(
          isSelf: isSelf,
          mode: mode,
          username: selectedFriend?.username ?? '',
          me: me,
          density: ref.watch(shelfDensityProvider),
          onDensityPressed: () =>
              ref.read(shelfDensityProvider.notifier).cycle(),
          onDonePressed: () {
            ref.read(libraryModeProvider.notifier).state = LibraryMode.library;
          },
          onEndVisitPressed: _endVisit,
          onManageShelvesPressed: () => showManageShelvesBottomSheet(context),
          onProfilePressed: () =>
              Navigator.pushNamed(context, AppRoutes.settings),
          onPokePressed: !isSelf
              ? () => ref
                    .read(userActionsProvider)
                    .pokeUser(selectedFriend?.username ?? '')
              : null,
          onRemoveFriendPressed: !isSelf && selectedFriend != null
              ? () => confirmAndRemoveFriend(
                  context: context,
                  ref: ref,
                  friend: selectedFriend,
                )
              : null,
        ),
      ),
    ),
  );

  /// The Friends sheet's ✉, and its empty state's CTA.
  ///
  /// A method rather than an inline closure because two call sites reach it — the
  /// header icon and the no-friends button — and both have to open the same thing.
  void _showInviteSheet() => showInviteSheet(context);

  void _onAddShelfPressed() {
    _shelfNameController.clear();
    showUpdateShelfNameBottomSheet(
      context,
      controller: _shelfNameController,
      update: false,
      onSavePressed: () async {
        Navigator.pop(context);
        final name = _shelfNameController.text.trim();
        if (name.isNotEmpty) {
          await ref.read(libraryActionsProvider).addShelf(name);
        }
      },
    );
  }

  void _onEditShelfName(String shelfId, String currentName) {
    _shelfNameController.text = currentName;
    showUpdateShelfNameBottomSheet(
      context,
      controller: _shelfNameController,
      onSavePressed: () async {
        Navigator.pop(context);
        final name = _shelfNameController.text.trim();
        if (name.isNotEmpty) {
          await ref.read(libraryActionsProvider).updateShelfName(shelfId, name);
        }
      },
    );
  }

  void _onDeleteShelf(String shelfId) {
    showDeleteShelfBottomSheet(
      context,
      onDeletePressed: () async {
        Navigator.pop(context);
        await ref.read(libraryActionsProvider).deleteShelf(shelfId);
      },
    );
  }

  /// Confirms, then removes the book.
  ///
  /// Deleting a book is irreversible — the confirm sheet says exactly that — and
  /// in edit mode the whole cover is the delete target, so this cannot be a
  /// one-tap action. An undo SnackBar was tried here instead and was the wrong
  /// trade: undo only earns the right to replace confirmation when it is
  /// dependable, and a 5-second window that a second delete cuts short isn't.
  ///
  /// Confirming removes the book from local state immediately and commits
  /// without a loading overlay: the cover vanishing is the feedback. A failed
  /// delete puts it back.
  void _onDeleteBook(String bookId) {
    final notifier = ref.read(libraryProvider.notifier);
    // Read now, not in the callback: these outlive the sheet.
    final actions = ref.read(libraryActionsProvider);

    showDeleteBookBottomSheet(
      context,
      onDeletePressed: () async {
        Navigator.pop(context);

        final pending = notifier.removeBookLocally(bookId);
        if (pending == null) return;

        final deleted = await actions.deleteBookSilently(bookId);
        // No `mounted` guard: the book belongs in library state whether or not
        // this page is still around to show it.
        if (!deleted) notifier.restoreBookLocally(pending);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filterYear = ref.watch(readsFilterYearProvider);
    final friendFilterYear = ref.watch(friendReadsFilterYearProvider);
    final cardFilterYear = ref.watch(cardFilterYearProvider);
    final mode = ref.watch(libraryModeProvider);
    final density = ref.watch(shelfDensityProvider);
    final tab = ref.watch(libraryTabProvider);
    final selectedFriend = ref.watch(selectedFriendProvider);
    final friendsLevel = ref.watch(friendsSheetLevelProvider);
    final friendsAsync = ref.watch(friendsProvider);
    final following = friendsAsync.valueOrNull ?? const <Profile>[];
    // The reader's own profile: the bar's avatar, and the handle stamped on a
    // shared card.
    final me = ref.watch(profileProvider).valueOrNull;

    final isSelf = selectedFriend == null;

    // **Your own library is watched on every screen, visit or not.** It is what the
    // Card sheet draws from, and keeping it warm is what makes ending a visit
    // instant rather than another round trip.
    final ownLibraryAsync = ref.watch(libraryProvider);
    final ownReadsAsync = ref.watch(finishedBooksProvider);

    // Whoever's library is behind the sheet — the one persistent background, now
    // literally one pane rather than a pager's worth of them. A visit re-points these
    // two reads at her id; both are kept alive, so coming back to someone already
    // looked at is free. See [userLibraryProvider].
    final shelvesAsync = isSelf
        ? ownLibraryAsync
        : ref.watch(userLibraryProvider(selectedFriend.id));
    final readsAsync = isSelf
        ? ownReadsAsync
        : ref.watch(userFinishedBooksProvider(selectedFriend.id));

    final shelves = shelvesAsync.valueOrNull;
    // A failed read query is treated as an empty pile rather than allowed to hold the
    // pane on the outgoing library forever. The shelves are what gate the pane, as
    // they always have.
    final reads =
        readsAsync.valueOrNull ?? (readsAsync.hasError ? const <Book>[] : null);
    if (shelves != null && reads != null) {
      _onScreen = (shelves: shelves, reads: reads);
    }
    final onScreen = _onScreen;
    // The switch has landed but its queries have not. Drawn as the held library,
    // faded, plus a named chip — never as a blank pane.
    final inFlight = shelves == null || reads == null;

    // If the friend on screen is no longer a friend — after a removal from
    // `ManageFriendPage`, say — fall back to your own library. Nothing else can: the
    // list she was selected from no longer contains her.
    //
    // **Under a mutual model this has a second cause the old one could not produce:
    // *she* can end it.** An unfollow was always something you did to a list you
    // owned, so the eviction only ever fired from your own action. A friendship is
    // shared, so a refresh can now return a list she is simply absent from — and her
    // shelves are already unreadable by the time it does.
    if (selectedFriend != null &&
        friendsAsync.hasValue &&
        !following.any((Profile f) => f.id == selectedFriend.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _endVisit();
      });
    }

    return PopScope(
      // Three states, innermost first: an edit ends, then a visit ends, then the
      // page may pop. Each is a context the user opened and expects back out of
      // in the order they opened it.
      canPop: mode == LibraryMode.library && isSelf,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (mode != LibraryMode.library) {
          ref.read(libraryModeProvider.notifier).state = LibraryMode.library;
          return;
        }
        if (!isSelf) _endVisit();
      },
      child: Listener(
        // Any new pointer sequence means the gesture that opened edit mode is
        // over, so the latch must not outlive it: if that gesture ended in a drag
        // rather than a tap, nothing consumed it.
        onPointerDown: (_) => _editOpenedByThisGesture = false,
        child: GestureDetector(
          onTap: () {
            if (_editOpenedByThisGesture) {
              _editOpenedByThisGesture = false;
              return;
            }
            if (mode == LibraryMode.editLibrary) {
              ref.read(libraryModeProvider.notifier).state =
                  LibraryMode.library;
            }
          },
          child: Scaffold(
            backgroundColor: context.colors.pageBackground,
            // **No `appBar`.** The bar is the first child of the body's stack
            // instead, so the sheet — which is inside the pane, above it — can rise
            // over it. A `Scaffold`'s app bar is painted after its body and cannot be
            // covered by anything in it, and `extendBodyBehindAppBar` only moves the
            // body under the bar, not the bar under the body.
            //
            // The cost is that the library's top inset is ours to work out rather
            // than the `Scaffold`'s: [_barExtent].
            body: LayoutBuilder(
              // The whole screen now, since there is no app bar taking a slice first.
              builder: (context, constraints) {
                // The chrome, built once and handed to whichever state renders below.
                // The books it shows are the freshest thing available: the incoming
                // reads if they have landed, the held ones if a switch is in flight,
                // and an empty pile before either — so the sheet fills in as the
                // library does rather than waiting for it.
                final pileBooks =
                    readsAsync.valueOrNull ?? onScreen?.reads ?? const <Book>[];
                Widget sheetFor(List<Book> books) => _hiddenWhileEditing(
                  mode,
                  _sheetForTab(
                    tab,
                    mode: mode,
                    finishedBooks: books,
                    filterYear: filterYear,
                    friendFilterYear: friendFilterYear,
                    cardFilterYear: cardFilterYear,
                    username: me?.username,
                    handle: me?.handle,
                    memberSince: me?.createdAt,
                    following: following,
                    friendsReading:
                        ref.watch(friendsReadingProvider).valueOrNull ??
                        const {},
                    selectedFriend: selectedFriend,
                    friendsLevel: friendsLevel,
                    maxExtent: _sheetBand(context, constraints),
                    onRestingExtent: (extent) {
                      if ((extent - _restingExtent).abs() < 0.5) return;
                      setState(() => _restingExtent = extent);
                    },
                  ),
                );

                return Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _bar(
                        isSelf: isSelf,
                        mode: mode,
                        selectedFriend: selectedFriend,
                        me: me,
                      ),
                    ),
                    // **One `LibraryPane`, and there is no horizontal axis anywhere in
                    // the tree.** It used to be a `PageView` of them — your library at
                    // index 0 and a friend at every index after it — which made two
                    // things possible that nobody asked for: a sideways drag on your own
                    // shelves opened someone else's library (the pager's `physics` were
                    // gated on the edit mode alone, and any row that does not overflow
                    // hands its horizontal drag to whatever is behind it), and a tap on
                    // the fourth friend built and threw away every page in between,
                    // firing two Supabase queries each. Neither is a bug in the pager; a
                    // lateral axis between libraries is the thing that was wrong.
                    //
                    // **All three states carry the sheet**, which is why the two that are
                    // not the pane still go through [LibraryPaneFrame]. A state without a
                    // sheet is a tab bar that does nothing when tapped — the bar is on
                    // screen throughout now, and the sheet is the friend switcher — and
                    // the first two rounds of this design shipped exactly that bug twice.
                    // They also all pass [_sheetKey], so the sheet element is *re-parented*
                    // when the library lands rather than rebuilt: the chrome does not blink
                    // on the way from skeleton to shelves.
                    if (shelvesAsync.hasError)
                      LibraryPaneFrame(
                        topInset: _barExtent(context),
                        sheet: sheetFor(pileBooks),
                        library: _LibraryError(
                          message: l10n.errorWithMessage(
                            (shelvesAsync.error ?? '').toString(),
                          ),
                          onRetry: _refreshLibrary,
                          bottomInset: _restingExtent,
                        ),
                      )
                    else if (onScreen == null)
                      LibraryPaneFrame(
                        topInset: _barExtent(context),
                        sheet: sheetFor(pileBooks),
                        library: const LoadingLibrary(),
                      )
                    else
                      LibraryPane(
                        shelves: onScreen.shelves,
                        finishedBooks: onScreen.reads,
                        isSelf: isSelf,
                        // Held from the outgoing owner while the incoming one loads, so
                        // a switch fades rather than blanks.
                        stale: inFlight,
                        // A friend's library is never editable, and an edit cannot be
                        // open when one is entered: `onSelectFriend` puts the mode back.
                        // Passed explicitly all the same, because a long press on a cover
                        // is a live gesture on her shelves too.
                        mode: isSelf ? mode : LibraryMode.library,
                        // The reader's own preference, applied to whosever shelves
                        // are on screen: an unfamiliar library is where seeing all
                        // of a shelf helps most, not least.
                        density: density,
                        topInset: _barExtent(context),
                        bottomInset: _bottomInset(context, mode),
                        sheet: sheetFor(onScreen.reads),
                        onEditShelfName: isSelf ? _onEditShelfName : (_, __) {},
                        onDeleteShelf: isSelf ? _onDeleteShelf : (_) {},
                        onAddShelf: isSelf ? _onAddShelfPressed : null,
                        onEnterEditMode: isSelf ? _enterEditMode : () {},
                        onMoveBook: isSelf
                            ? (bookId, targetShelfId, orderedBookIds) {
                                ref
                                    .read(libraryProvider.notifier)
                                    .moveBookToShelf(
                                      bookId,
                                      targetShelfId,
                                      orderedBookIds,
                                    );
                              }
                            : null,
                        onReorderBooks: isSelf
                            ? (shelfId, bookIds) {
                                ref
                                    .read(libraryProvider.notifier)
                                    .reorderBooksInShelf(shelfId, bookIds);
                              }
                            : null,
                        onReorderReadingBooks: isSelf
                            ? (bookIds) {
                                ref
                                    .read(libraryProvider.notifier)
                                    .reorderReadingBooks(bookIds);
                              }
                            : null,
                        onDeleteBook: isSelf ? _onDeleteBook : null,
                        onRefresh: _refreshLibrary,
                      ),
                    if (inFlight && onScreen != null)
                      Positioned(
                        top: _barExtent(context) + 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _LoadingChip(
                            label: l10n.loadingUserLibrary(
                              selectedFriend?.username ?? l10n.myLibrary,
                            ),
                          ),
                        ),
                      ),
                    // The floating tab bar is NOT here. It is hosted above the
                    // `Navigator` by `ShellChrome`, which is the only place a native
                    // platform view can be painted in front of a modal route — so it
                    // floats over Add Book instead of being destroyed by it. The
                    // sheets below still reserve room for it via
                    // `ShellTabBarGeometry.reserve`, and it still disappears for an
                    // edit — but no longer for a visit, because under this design no
                    // tab ever changes what it means. `shellBarVisibleProvider` has
                    // the argument written out.
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A library that could not be read, and the way to try again.
///
/// **The retry is the point.** This state used to be bare error text with no sheet
/// over it, which left a reader with a live tab bar that did nothing, no
/// pull-to-refresh (that lives on the shelves, and there are none), and nothing to
/// press — so an offline launch or an unreadable friend was a dead end you left by
/// backgrounding the app. It goes through [LibraryPaneFrame] now, so the sheet and the
/// tabs keep working, and the button re-reads whatever library is on screen through
/// the same path the pull-to-refresh uses.
class _LibraryError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  /// How much of the bottom the collapsed sheet is covering, so this centres in the
  /// band the reader can actually see.
  ///
  /// Not cosmetic: centred in the *whole* pane the Retry button lands underneath the
  /// sheet and cannot be tapped at all, which is how the test found it — a hit test
  /// at the button's own centre came back with the sheet's header. Exactly the mistake
  /// `LibraryPane`'s empty state makes if it forgets [LibraryPane.bottomInset].
  final double bottomInset;

  const _LibraryError({
    required this.message,
    required this.onRetry,
    this.bottomInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.secondaryText),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 20),
                label: Text(l10n.retry),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.brandText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// “loading hana…” — the whole of the in-flight state for a change of library.
///
/// A named chip rather than a spinner, and over the held library rather than
/// instead of it. A centred `CircularProgressIndicator` on a blank pane was the
/// old behaviour and it answered the wrong question: the reader knows something is
/// loading, what they cannot tell is *whose* library is arriving — which is the one
/// thing worth saying when the tap that started this was a name in a list.
class _LoadingChip extends StatelessWidget {
  final String label;

  const _LoadingChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.divider, width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.label.copyWith(color: colors.secondaryText),
        ),
      ),
    );
  }
}

/// The shell's bar: whose library you are looking at, and the actions for it.
///
/// Three states, and the title never moves between two of them — it keeps you
/// oriented, and it keeps actions out of the slot where users expect Cancel:
///
///  * your library — "My Library" and your avatar
///  * a visit      — ✕, "jisoo's Library", Poke and an overflow menu
///  * an edit      — manage shelves and Done
///
/// **The visit state is the exception, and it is the slot's own reasoning that makes
/// it one.** Keeping the leading slot free was never about symmetry; it was about
/// reserving the place a reader looks for Cancel. A visit is the one context on this
/// bar that *has* a dismissal, so it is the one context entitled to that slot. The
/// ✕ moved here from `FriendRail`'s head unchanged — same widget, same glyph, same
/// label — when the rail was deleted, so the mark a reader already knows did not
/// change along with the row it sits in.
///
/// Edit and `+` are gone. Long-pressing a book is how an edit starts (`ShelfRow`
/// already does it), and the tab bar's search button is how a book is added, so
/// both were duplicate entry points sitting in the most valuable row on screen.
///
/// The one control added back is [_ShelfDensityButton], which earns its width by
/// changing what every shelf on screen is: nothing else can reach it, and the
/// alternative was a three-glyph segmented pill costing 110–130pt of this row.
class _LibraryBar extends StatelessWidget {
  final bool isSelf;
  final LibraryMode mode;

  /// The friend's name during a visit; ignored when [isSelf].
  final String username;

  /// The reader's own profile, for the avatar that opens Settings. Null while it
  /// loads, which [AvatarCircle] draws as its default glyph rather than as a gap.
  final Profile? me;

  final VoidCallback onDonePressed;

  /// Ends the visit, from the ✕ in the leading slot. Ignored when [isSelf].
  final VoidCallback onEndVisitPressed;

  final VoidCallback onManageShelvesPressed;
  final VoidCallback onProfilePressed;

  /// The density the shelves behind this bar are drawn at, and the tap that moves to
  /// the next one.
  ///
  /// The button shows **the state you are in**, not the one you would get. It is a
  /// mode indicator, and with three states a full cycle is two taps, so "what am I
  /// looking at" is the more useful thing for it to answer. The effect is unmissable
  /// — the whole library redraws — so the feedback does the work a "next state" glyph
  /// would have to do.
  final ShelfDensity density;
  final VoidCallback onDensityPressed;

  final VoidCallback? onPokePressed;

  /// Confirms and performs a removal, from the overflow menu. Null when [isSelf],
  /// for the same reason [onPokePressed] is: neither action has a subject outside a
  /// visit.
  ///
  /// A callback rather than the [Profile] and a `ref`, so this bar stays
  /// presentational — every other action on it is passed in the same way.
  final VoidCallback? onRemoveFriendPressed;

  const _LibraryBar({
    required this.isSelf,
    required this.mode,
    required this.username,
    this.me,
    required this.onDonePressed,
    required this.onEndVisitPressed,
    required this.onManageShelvesPressed,
    required this.onProfilePressed,
    required this.density,
    required this.onDensityPressed,
    this.onPokePressed,
    this.onRemoveFriendPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditing = mode == LibraryMode.editLibrary;

    return Material(
      color: context.colors.surface,
      // No elevation. This bar is painted *before* the pager so that a sheet can rise
      // over it, and a shadow from back here lands under the page, hidden by the
      // library's own background. `LibraryPane` re-casts it from the page's top edge
      // instead — see `_BarShadow` in `library_view.dart`, which mirrors the 56pt row
      // height and the elevation of 4 this used to carry.
      elevation: 0,
      child: SizedBox(
        height: 56,
        child: Padding(
          // 11 rather than 15 when the ✕ is present: a round button reads as inset by
          // its own edge, so the same 15 would push it visibly further in than the
          // title it replaces.
          //
          // The trailing edge is 15 in every state, including the edit. It was 4
          // while Done was text — a `TextButton` carries its own inset — and
          // keeping it there would have slid the check disc almost onto the screen
          // edge and, worse, put it 11pt off the avatar it replaces, so switching
          // modes would visibly shift the trailing control.
          padding: EdgeInsets.only(left: isSelf ? 15 : 11, right: 15),
          child: Row(
            children: [
              if (!isSelf) ...[
                AdaptiveIconButton(
                  symbol: 'xmark',
                  icon: Icons.close,
                  diameter: 36,
                  symbolSize: 14,
                  iconSize: 18,
                  semanticLabel: l10n.endVisit,
                  onPressed: onEndVisitPressed,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: isSelf
                    ? Text(
                        // The app's own two words, in the app's own voice, in the
                        // most permanent row on screen — which is the whole test
                        // for [AppTextStyles.title].
                        l10n.myLibrary,
                        style: AppTextStyles.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    // **The title is the menu.** A visit's title carries a chevron
                    // and that chevron discloses what can be done about this
                    // friendship — which is the honest place for it, because every
                    // item in that menu is about the person the title names. The two
                    // earlier shapes are worth recording: a gear inboard of Poke that
                    // pushed a whole page for one destructive action, then a glass
                    // ellipsis outboard of Poke. Both spent a 44pt slot in the most
                    // contested row in the app on a control that says nothing about
                    // its subject; a chevron on the subject itself says it for free.
                    //
                    // A [Row] rather than a `WidgetSpan` inside the title. A span
                    // would ride the text's own layout — and this text ellipsizes, so
                    // the chevron would be the first thing truncated away, on exactly
                    // the long names that already truncate. Outside the paragraph it
                    // is [Flexible] that gives way instead.
                    : Row(
                        children: [
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                text: username.isEmpty
                                    ? l10n.library
                                    : username,
                                // The serif too, not [AppTextStyles.titleUser], and
                                // one size down from your own title. Both states of
                                // this row are the same row, and setting one of them
                                // in the UI face made switching into a visit read as
                                // a change of surface — the phrase around the name is
                                // the app's voice either way. The step down to 20
                                // says the other half of it: this state is temporary
                                // and yours is not. See [AppTextStyles.titleVisit],
                                // which also records what the step does *not* fix.
                                //
                                // What makes the serif safe is the coverage it
                                // already has for `spine`: Latin-1 plus KS X 1001's
                                // 2,350 syllables, verified at 0 misses against real
                                // Korean. A name outside that still falls through to
                                // Pretendard per glyph, which is the risk this branch
                                // used to avoid wholesale — the trade is deliberate
                                // now, and it is the same one a book title on a shelf
                                // already takes.
                                style: AppTextStyles.titleVisit,
                                children: [
                                  TextSpan(
                                    // The suffix used to be separated by weight —
                                    // 18/bold name, 16/normal `의 서재`. It is
                                    // separated by colour now, at one size, for two
                                    // reasons. A weight step needs a second cut of
                                    // the face loaded to be honest about it, and the
                                    // size step made the pair read as two fragments
                                    // rather than one phrase. Colour says the same
                                    // thing more quietly: the name is the reader's
                                    // content, the suffix is the app's framing of it.
                                    text: l10n.librarySuffixOther,
                                    style: TextStyle(
                                      color: context.colors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (onRemoveFriendPressed != null)
                            _VisitMenuButton(
                              semanticLabel: l10n.manageFriend,
                              removeLabel: l10n.removeFriend,
                              onRemove: onRemoveFriendPressed!,
                            ),
                        ],
                      ),
              ),
              // **Between the title and the actions, and only at rest on your own
              // library.** It withdraws in edit mode, where the row's two controls are
              // the whole point and a third object competing with them would be noise;
              // and on a visit, where a streak belongs to the reader looking rather
              // than the reader being looked at — friends' streaks are deliberately
              // out of scope, and `reading_days`' RLS is owner-only, so there would be
              // no rows to read anyway.
              //
              // **It draws at zero too, which is a reversal.** It used to draw nothing
              // without a run — "which is every account in this database today", as the
              // note here said. That was the argument against it, not for it: exactly one
              // of 137 profiles has a reading day, so omitting at zero hid the chip from
              // everyone who had yet to start. See `ReadingStreakChip`.
              if (isSelf && !isEditing) const ReadingStreakChip(),
              if (isEditing)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // **This row went to glass when Done stopped being text.** The
                    // note here used to say the opposite, and it was right for the
                    // row it described: a glass capsule beside a *text* Done made
                    // the secondary action heavier than the primary one, so the
                    // secondary stayed a bare glyph. Done is a tinted disc now, and
                    // a disc outranks clear glass by fill alone — the contest the
                    // bare glyph was protecting is over, and the two controls read
                    // as a pair on the same material instead of one control and one
                    // word.
                    //
                    // Glass over an opaque bar buys the rim, the shadow and the
                    // press response rather than any refraction; see the note on
                    // the avatar below, which is the same compromise.

                    // Lucide's two horizontal rows read as shelves without the
                    // sorting meaning carried by the old up/down arrows. Flutter
                    // uses the SVG; UIKit gets its raster counterpart because the
                    // package's SVGKit path rendered this glyph blank on-device.
                    AdaptiveIconButton.svg(
                      assetPath: kStretchHorizontalIconAsset,
                      nativeAssetPath: kStretchHorizontalIconNativeAsset,
                      diameter: 44,
                      symbolSize: 20,
                      iconSize: 22,
                      semanticLabel: l10n.manageShelves,
                      onPressed: onManageShelvesPressed,
                    ),
                    const AdaptiveIconButtonGap(),
                    // **A check on a brand disc, not the word "Done".** The word
                    // was the widest control in the bar and the only text in it
                    // that was not the library's own name, which made a 44pt
                    // target read as a fourth title. A filled disc is the iOS
                    // affirmative shape, and it is the only fill in this row, so it
                    // is unmistakably the way out without spending a word on it.
                    //
                    // `brandFill` over `brandText`: this is a *surface* now, and
                    // the glyph on it is white — `brandText` is the pair tuned for
                    // ink on a light surface, which is the opposite direction.
                    AdaptiveIconButton(
                      symbol: 'checkmark',
                      icon: Icons.check,
                      diameter: 44,
                      prominent: true,
                      tint: context.colors.brandFill,
                      iconColor: Colors.white,
                      semanticLabel: l10n.done,
                      onPressed: onDonePressed,
                    ),
                  ],
                )
              else if (isSelf)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ShelfDensityButton(
                      density: density,
                      onPressed: onDensityPressed,
                    ),
                    const AdaptiveIconButtonGap(),
                    // **The avatar is a glass disc.** This band was bare icons for
                    // as long as its two states were judged together, on a finding
                    // recorded against *edit mode*: a glass capsule there "made the
                    // secondary action heavier than Done". That still holds, and edit
                    // mode above is untouched — but it never described this row. At
                    // rest there is no Done, and the only trailing control is an
                    // [AvatarCircle], which is a filled disc whatever the material
                    // around it.
                    //
                    // Glass is earned here in the narrow sense too: `_LibraryBar`
                    // paints an opaque surface and `LibraryPane` starts below it, so
                    // there is nothing behind the disc to refract. What it gets
                    // from the platform is the rim, the shadow and the press
                    // response — the material, not the refraction. See
                    // `library_view.LibraryPaneFrame` for why the ground is opaque,
                    // and `AdaptiveGlassCircle` for the shape of the compromise.

                    // The reader's own avatar, which is what the drawing has here
                    // and what the rail's "me" lead has always been: their photo or
                    // emoji, not a generic person glyph.
                    //
                    // **The avatar *is* the disc on glass, rather than sitting inside
                    // it.** The two paths want different sizes, and giving them one
                    // was the bug: at 32 inside a 44 target the photo had a 6pt ring
                    // of bare glass all the way round, which reads as a picture
                    // dropped onto a button rather than as the button. Every other
                    // glass control in this bar fills its diameter, and this one now
                    // does too. Off glass there is no disc to fill, and 32 inside 44
                    // is the inset an `IconButton` would have applied anyway.
                    //
                    // **The emoji grows with the disc, which an earlier fix got
                    // wrong.** It was pinned at 16 here, on the theory that an emoji
                    // is a glyph and should match an 18pt SF Symbol beside it.
                    // Measured, that reasoning does not survive:
                    // `AvatarCircle` renders a 16pt emoji as a 22pt box, so pinning it
                    // filled 50% of a 44pt disc where the old 32pt circle filled 69% —
                    // the emoji came out *smaller* relative to its button than before
                    // the disc grew, which is the padding this was supposed to remove.
                    // Letting `AvatarCircle` do its own thing (half the diameter)
                    // restores 70%, matching the old proportion almost exactly.
                    //
                    // **Why this is its own widget.** The avatar is handed to the
                    // native button as PNG bytes so UIKit animates it on press like
                    // the two SF Symbols beside it — see [GlassAvatarButton], which
                    // owns the raster's lifecycle, and `AdaptiveGlassCircle`, which
                    // records the three failed attempts at doing this from Dart.
                    //
                    // The tap belongs to the button, not the avatar: one recogniser,
                    // and the semantics come with it. See [AvatarCircle], which adds
                    // no gesture of its own when given no callbacks — exactly this
                    // case.
                    GlassAvatarButton(
                      emoji: me?.emoji,
                      avatarPath: me?.avatarPath,
                      semanticLabel: l10n.profile,
                      onPressed: onProfilePressed,
                    ),
                  ],
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The density applies to a friend's shelves too — an unfamiliar
                    // library is where seeing all of a shelf helps most, not least —
                    // so the control travels into a visit.
                    // The density applies to a friend's shelves too — an unfamiliar
                    // library is where seeing all of a shelf helps most, not least —
                    // so the control travels into a visit.
                    _ShelfDensityButton(
                      density: density,
                      onPressed: onDensityPressed,
                    ),
                    const AdaptiveIconButtonGap(),
                    // **Poke is the only thing this side of the row carries, and that
                    // is the point of moving the friend menu into the title.** This
                    // slot held a gear, then a glass ellipsis; both were 44pt of the
                    // most contested row in the app spent on a control that could not
                    // say what it was about. Poke is the one thing a reader comes to
                    // a friend's library to *do*, so it gets the trailing edge alone.
                    if (onPokePressed != null)
                      GestureDetector(
                        onTap: onPokePressed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.brandFill,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            l10n.poke,
                            style: AppTextStyles.label.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chevron on a visit's title, and the menu it discloses.
///
/// **Deliberately material-less on both platforms.** Every other control in this bar
/// is a disc with something behind it — glass on iOS 26, `surfaceVariant` in the
/// fallback — and that is right for a control that stands on its own. This one does
/// not stand on its own: it is punctuation at the end of a phrase, and the phrase is
/// what it acts on. Give it a disc and it stops belonging to the title and starts
/// competing with Poke, which is the whole reason the two shapes before it (a gear,
/// then a glass ellipsis) were wrong.
///
/// **Still a native `UIMenu` on iOS 26, without the glass.** `CNButtonStyle.plain`
/// draws no material but keeps the part worth keeping: the popover morphs out of the
/// anchor, the destructive row is the system's own red, and the typography and haptics
/// are UIKit's. A Flutter menu on iOS looks like Android's. Elsewhere it is
/// [PopupMenuButton], which is the idiom `read_filter.dart` already uses for its own
/// label-plus-chevron popover.
///
/// **The title is not the trigger; the chevron is.** A tap target the width of a
/// username would be the largest one in the bar and would fire on a mis-aimed tap at
/// the name itself, which reads as a label rather than a control. So the target is
/// [_width] x [_height]: 44 tall for the thumb, and narrower than 44 because every
/// point of width here is taken from a title that already ellipsizes — the same
/// crowding argument that lets the end-visit ✕ sit below `kIconButtonDiameter`.
class _VisitMenuButton extends StatelessWidget {
  /// What the menu is *about*. A chevron says only that there is one.
  final String semanticLabel;

  final String removeLabel;
  final VoidCallback onRemove;

  const _VisitMenuButton({
    required this.semanticLabel,
    required this.removeLabel,
    required this.onRemove,
  });

  static const double _width = 34;
  static const double _height = 44;

  /// Sized against the 20pt title it punctuates rather than against the bar's other
  /// glyphs, which are 18–22 in 44pt discs. The symbol runs smaller than the Material
  /// icon for the usual reason: Apple's marks are inset in their box and Material's
  /// fill it — the same 15:20 ratio `kIconButtonSymbolSize` and `kIconButtonIconSize`
  /// already encode.
  static const double _symbolSize = 13;
  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    // The colour of the suffix beside it, not of the name: the chevron is the app
    // talking about the reader's content, exactly as `의 서재` is.
    final tint = context.colors.secondaryText;

    // Native only while nothing is over this control, as every other native control
    // in this bar is: a platform view under a sheet leaks its own rectangle through
    // the scrim and stays tappable behind it. See [ModalCoverBuilder].
    return ModalCoverBuilder(
      builder: (context, covered) => SizedBox(
        width: _width,
        height: _height,
        child: useNativeGlass && !covered
            ? _native(tint)
            : _fallback(context, tint),
      ),
    );
  }

  Widget _native(Color tint) => Center(
    child: Semantics(
      label: semanticLabel,
      button: true,
      container: true,
      child: CNPopupMenuButton.icon(
        buttonIcon: CNSymbol('chevron.down', size: _symbolSize, color: tint),
        // Square by construction, so it takes the narrower of the two dimensions:
        // a plain button has no material to look clipped, and the row is 56 tall.
        size: _width,
        buttonStyle: CNButtonStyle.plain,
        items: [
          CNPopupMenuItem(
            label: removeLabel,
            icon: const CNSymbol('person.badge.minus'),
            isDestructive: true,
          ),
        ],
        onSelected: (_) => onRemove(),
      ),
    ),
  );

  Widget _fallback(BuildContext context, Color tint) => PopupMenuButton<int>(
    // Doubles as the accessible name, as it does on `AdaptiveIconButton`'s
    // fallback. Without it `PopupMenuButton` announces Material's generic
    // "Show menu", which says nothing about whose menu it is.
    tooltip: semanticLabel,
    // Under, not over: a disclosure should drop away from the thing that
    // disclosed it rather than cover it.
    position: PopupMenuPosition.under,
    color: context.colors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    // Runs after the route has popped, which is what makes it safe to raise the
    // confirm dialog straight from here.
    onSelected: (_) => onRemove(),
    itemBuilder: (context) => [
      PopupMenuItem<int>(
        value: 0,
        child: Row(
          children: [
            const Icon(
              Icons.person_remove_outlined,
              size: 20,
              color: cancelRedColor,
            ),
            const SizedBox(width: 12),
            Text(
              removeLabel,
              style: AppTextStyles.body.copyWith(color: cancelRedColor),
            ),
          ],
        ),
      ),
    ],
    child: Center(
      child: Icon(Icons.keyboard_arrow_down, size: _iconSize, color: tint),
    ),
  );
}

/// Cycles the shelves through the [ShelfDensity] states, of which there are now two.
///
/// **One button, not two.** At two states this is a toggle, and the feedback is
/// unmissable because the whole library redraws — so the effect is the affordance. A
/// segmented pill would advertise the states better and cost 110–130pt of a row whose
/// own doc calls it "the most valuable row on screen".
///
/// Still built as a cycle rather than as a boolean, because that is where a third
/// state goes if one is ever added; a withdrawn overlapping density made this a
/// three-state control once already. See [ShelfDensityCycle].
///
/// **It shows the state you are in, not the one you would get.** This is a mode
/// indicator, so "what am I looking at" is the more useful question for it to answer.
/// The semantic label names the current state for the same reason, so the change is
/// announced rather than silent.
///
/// SF Symbols and Material glyphs rather than bundled SVGs: the catalog has marks for
/// both, so there is no reason to take on the raster/mask trap documented at
/// `kStretchHorizontalIconNativeAsset`.
///
/// `book.closed` needs iOS 14 and the floor is 15, so no availability check.
///
/// **`books.vertical` used to be the Library tab's mark too** (`shell_tab_bar.dart`),
/// so in the `spines` state this button and that tab carried the same glyph two rows
/// apart meaning different things. That resolved itself when the tab bar went to filled
/// glyphs: the tab is `books.vertical.fill` now and this button keeps the outline, which
/// is a real distinction rather than a rename. Still worth knowing they are neighbours —
/// if the bar ever drops back to outline marks, the collision comes back with it.
class _ShelfDensityButton extends StatelessWidget {
  const _ShelfDensityButton({required this.density, required this.onPressed});

  final ShelfDensity density;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // One record per state, so the glyph, the fallback and the label cannot drift
    // apart from each other.
    final (symbol, icon, label) = switch (density) {
      // A closed book, seen from its front cover — which is the drawing this state
      // makes. `book.closed` rather than `book`, whose SF Symbol is an *open* book and
      // therefore says "reading" rather than "cover"; and rather than
      // `rectangle.portrait`, which was accurate about the geometry and said nothing
      // about books.
      ShelfDensity.covers => (
        'book.closed',
        Icons.book,
        l10n.shelfDensityCovers,
      ),
      // Upright bars: books seen along their spines.
      ShelfDensity.spines => (
        'books.vertical',
        Icons.view_week,
        l10n.shelfDensitySpines,
      ),
    };

    return AdaptiveIconButton(
      symbol: symbol,
      icon: icon,
      diameter: 44,
      semanticLabel: label,
      onPressed: onPressed,
    );
  }
}
