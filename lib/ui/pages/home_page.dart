import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/views/library_view.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/friend_rail.dart';
import 'package:bookworm_friends/ui/widgets/friends_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_card_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/add_book_bottom_sheet.dart';
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
  final _pageController = PageController();

  @override
  void dispose() {
    _shelfNameController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _syncPageToFriend(List<Profile> following, Profile? friend) {
    int targetIndex;
    if (friend == null) {
      targetIndex = 0;
    } else {
      final idx = following.indexWhere((f) => f.id == friend.id);
      if (idx == -1) return;
      targetIndex = idx + 1;
    }
    if (!_pageController.hasClients) return;
    final current =
        _pageController.page?.round() ?? _pageController.initialPage;
    if (current != targetIndex) {
      _pageController.animateToPage(
        targetIndex,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Set when a long press opens edit mode, and cleared by the stray tap that
  /// same gesture produces on release.
  ///
  /// Entering edit mode replaces the shelf's whole list — the plain row becomes a
  /// `ReorderableListView` of `Draggable`s — so the `BookWidget` element holding
  /// the in-flight tap is destroyed at the moment the mode flips. Its arena entry
  /// goes with it, and the page-level "tap anywhere to leave edit mode" handler
  /// below inherits the release. Without this latch, letting go of the book you
  /// just long-pressed closes the mode it opened, which made long-press-to-edit
  /// look like it did nothing at all.
  bool _editOpenedByThisGesture = false;

  void _enterEditMode() {
    _editOpenedByThisGesture = true;
    ref.read(libraryModeProvider.notifier).state = LibraryMode.editLibrary;
  }

  Future<void> _onAddBookPressed() async {
    await showAddBookBottomSheet(context);
  }

  /// Ends a visit: back to your own library, which is always page 0.
  ///
  /// Clearing the selection is the whole of it — `_syncPageToFriend` listens and
  /// animates the pager home, the rail and Poke go with it, and the tab bar comes
  /// back. A visit is a selection, not a route, so there is nothing to pop.
  void _endVisit() {
    ref.read(selectedFriendProvider.notifier).state = null;
  }

  /// The sheet the selected tab puts above the library.
  ///
  /// Only the sheet changes here. The [LibraryPane] holding it is the same widget
  /// in the same place with the same shelves, which is what keeps the background
  /// persistent across a tab switch instead of merely looking persistent.
  Widget _sheetForTab(
    LibraryTab tab, {
    required LibraryMode mode,
    required List<Book> finishedBooks,
    required int filterYear,
    required List<Profile> following,
    required Profile? selectedFriend,
    required double maxExtent,
  }) {
    final isEditMode = mode == LibraryMode.editLibrary;
    // No bar to leave room for while editing, and the library wants every pixel
    // it can get to be rearranged in.
    final reserve = isEditMode ? 0.0 : ShellTabBar.reserve;
    switch (tab) {
      case LibraryTab.library:
        return FinishedBooksSheet(
          books: finishedBooks,
          isEditMode: isEditMode,
          filterYear: filterYear,
          maxExtent: maxExtent,
          bottomReserve: reserve,
          onFilterChanged: (year) =>
              ref.read(readsFilterYearProvider.notifier).state = year,
        );
      case LibraryTab.friends:
        return FriendsSheet(
          following: following,
          selectedFriend: selectedFriend,
          isEditMode: isEditMode,
          bottomReserve: reserve,
          onSelectFriend: (profile) {
            ref.read(selectedFriendProvider.notifier).state = profile;
            ref.read(libraryModeProvider.notifier).state = LibraryMode.library;
          },
          onAddFriend: () =>
              Navigator.pushNamed(context, AppRoutes.searchUsers),
        );
      case LibraryTab.card:
        return LibraryCardSheet(isEditMode: isEditMode, bottomReserve: reserve);
    }
  }

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
    final libraryAsync = ref.watch(libraryProvider);
    final filterYear = ref.watch(readsFilterYearProvider);
    final finishedBooksAsync = ref.watch(finishedBooksProvider);
    final mode = ref.watch(libraryModeProvider);
    final tab = ref.watch(libraryTabProvider);
    final selectedFriend = ref.watch(selectedFriendProvider);
    final followingAsync = ref.watch(followingListProvider);
    final following = followingAsync.valueOrNull ?? [];

    final isSelf = selectedFriend == null;

    // Keep the horizontal pager in sync when a friend is selected by tapping
    // an avatar (or when selection is cleared).
    ref.listen<Profile?>(selectedFriendProvider, (prev, next) {
      _syncPageToFriend(following, next);
    });

    // If the currently-viewed friend is no longer followed (e.g. after an
    // unfollow), fall back to our own library so the pager index stays valid.
    if (selectedFriend != null &&
        followingAsync.hasValue &&
        !following.any((f) => f.id == selectedFriend.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(selectedFriendProvider.notifier).state = null;
        }
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
            appBar: AppBar(
              backgroundColor: context.colors.surface,
              automaticallyImplyLeading: false,
              centerTitle: false,
              elevation: 0,
              titleSpacing: 0,
              // The rail exists only inside a visit, so outside one the toolbar row
              // collapses and the bar below is the whole of the chrome.
              toolbarHeight: isSelf ? 0 : 56,
              title: isSelf
                  ? null
                  : FriendRail(
                      following: following,
                      selectedFriend: selectedFriend,
                      onEndVisit: _endVisit,
                      onSelectFriend: (profile) {
                        ref.read(selectedFriendProvider.notifier).state =
                            profile;
                      },
                    ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: _LibraryBar(
                  isSelf: isSelf,
                  mode: mode,
                  username: selectedFriend?.username ?? '',
                  onDonePressed: () {
                    ref.read(libraryModeProvider.notifier).state =
                        LibraryMode.library;
                  },
                  onManageShelvesPressed: () =>
                      showManageShelvesBottomSheet(context),
                  onProfilePressed: () =>
                      Navigator.pushNamed(context, AppRoutes.settings),
                  onPokePressed: !isSelf
                      ? () => ref
                            .read(userActionsProvider)
                            .pokeUser(selectedFriend.username ?? '')
                      : null,
                ),
              ),
            ),
            body: LayoutBuilder(
              // The height the library and its sheet share, which is what the
              // expanded cap is taken from.
              builder: (context, constraints) => Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    physics: mode == LibraryMode.library
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    itemCount: following.length + 1,
                    onPageChanged: (index) {
                      if (index == 0) {
                        ref.read(selectedFriendProvider.notifier).state = null;
                      } else if (index - 1 < following.length) {
                        ref.read(selectedFriendProvider.notifier).state =
                            following[index - 1];
                      }
                    },
                    itemBuilder: (context, index) {
                      if (index != 0) {
                        return _FriendLibraryPage(friend: following[index - 1]);
                      }
                      return libraryAsync.when(
                        data: (shelves) => LibraryPane(
                          shelves: shelves,
                          finishedBooks: finishedBooksAsync.valueOrNull ?? [],
                          mode: mode,
                          sheet: _sheetForTab(
                            tab,
                            mode: mode,
                            finishedBooks: finishedBooksAsync.valueOrNull ?? [],
                            filterYear: filterYear,
                            following: following,
                            selectedFriend: selectedFriend,
                            maxExtent: constraints.maxHeight,
                          ),
                          onEditShelfName: _onEditShelfName,
                          onDeleteShelf: _onDeleteShelf,
                          onAddShelf: _onAddShelfPressed,
                          onEnterEditMode: _enterEditMode,
                          onMoveBook: (bookId, targetShelfId) {
                            ref
                                .read(libraryProvider.notifier)
                                .moveBookToShelf(bookId, targetShelfId);
                          },
                          onReorderBooks: (shelfId, bookIds) {
                            ref
                                .read(libraryProvider.notifier)
                                .reorderBooksInShelf(shelfId, bookIds);
                          },
                          onDeleteBook: _onDeleteBook,
                          onRefresh: () async {
                            ref.invalidate(libraryProvider);
                            ref.invalidate(finishedBooksProvider);
                          },
                        ),
                        loading: () => const LoadingLibrary(),
                        error: (e, _) => Center(
                          child: Text(l10n.errorWithMessage(e.toString())),
                        ),
                      );
                    },
                  ),
                  // Floats over the sheet, which reserves `ShellTabBar.reserve` at
                  // its bottom for exactly this. Both sides read the same constants,
                  // so the gap above and below the bar is fixed by construction
                  // rather than measured.
                  //
                  // Hidden while editing, and hidden inside a visit. A tab bar that
                  // is visible but cannot say where you are is the lie four rejected
                  // design rounds kept working around; both are focused contexts with
                  // their own way out, so both drop their chrome.
                  if (mode != LibraryMode.editLibrary && isSelf)
                    Positioned(
                      left: ShellTabBar.sideInset,
                      right: ShellTabBar.sideInset,
                      bottom: ShellTabBar.bottomOffset(context),
                      child: ShellTabBar(
                        current: tab,
                        onChanged: (next) =>
                            ref.read(libraryTabProvider.notifier).state = next,
                        onAddBook: _onAddBookPressed,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendLibraryPage extends ConsumerWidget {
  final Profile friend;

  const _FriendLibraryPage({required this.friend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final friendFilterYear = ref.watch(friendReadsFilterYearProvider);
    final friendLibraryAsync = ref.watch(userLibraryProvider(friend.id));
    final friendFinishedBooksAsync = ref.watch(
      userFinishedBooksProvider(friend.id),
    );

    return LayoutBuilder(
      builder: (context, constraints) => friendLibraryAsync.when(
        data: (shelves) => LibraryPane(
          shelves: shelves,
          finishedBooks: friendFinishedBooksAsync.valueOrNull ?? [],
          mode: LibraryMode.library,
          // A friend's library always shows their read books, whichever tab you
          // were on: the tabs describe *your* shell, and a visit leaves it.
          //
          // No `bottomReserve`: a visit hides the tab bar, so reserving room for
          // it would leave an empty white band under the pile.
          sheet: FinishedBooksSheet(
            books: friendFinishedBooksAsync.valueOrNull ?? [],
            isEditMode: false,
            filterYear: friendFilterYear,
            maxExtent: constraints.maxHeight,
            onFilterChanged: (year) =>
                ref.read(friendReadsFilterYearProvider.notifier).state = year,
          ),
          onEditShelfName: (_, __) {},
          onDeleteShelf: (_) {},
          onEnterEditMode: () {},
          onRefresh: () async {
            ref.invalidate(userLibraryProvider(friend.id));
            ref.invalidate(userFinishedBooksProvider(friend.id));
          },
        ),
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) =>
            Center(child: Text(l10n.errorWithMessage(e.toString()))),
      ),
    );
  }
}

/// The shell's bar: whose library you are looking at, and the actions for it.
///
/// Three states, and the title never moves between them — it keeps you oriented,
/// and it keeps actions out of the slot where users expect Cancel:
///
///  * your library — "My Library" and your profile
///  * a visit      — "jisoo's Library" and Poke
///  * an edit      — manage shelves and Done
///
/// Edit and `+` are gone. Long-pressing a book is how an edit starts (`ShelfRow`
/// already does it), and the tab bar's search button is how a book is added, so
/// both were duplicate entry points sitting in the most valuable row on screen.
class _LibraryBar extends StatelessWidget {
  final bool isSelf;
  final LibraryMode mode;

  /// The friend's name during a visit; ignored when [isSelf].
  final String username;

  final VoidCallback onDonePressed;
  final VoidCallback onManageShelvesPressed;
  final VoidCallback onProfilePressed;
  final VoidCallback? onPokePressed;

  const _LibraryBar({
    required this.isSelf,
    required this.mode,
    required this.username,
    required this.onDonePressed,
    required this.onManageShelvesPressed,
    required this.onProfilePressed,
    this.onPokePressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditing = mode == LibraryMode.editLibrary;

    return Material(
      color: context.colors.surface,
      elevation: 4,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: EdgeInsets.only(left: 15, right: isEditing ? 4 : 15),
          child: Row(
            children: [
              Expanded(
                child: isSelf
                    ? Text(
                        l10n.myLibrary,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text.rich(
                        TextSpan(
                          text: username.isEmpty ? l10n.library : username,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          children: [
                            TextSpan(
                              text: l10n.librarySuffixOther,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              if (isEditing)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A bare icon, matching the rest of this band. Glass capsules
                    // belong to sheet corners and the floating bar; using one here
                    // made the secondary action heavier than Done.
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        onPressed: onManageShelvesPressed,
                        tooltip: l10n.manageShelves,
                        splashRadius: 22,
                        icon: const Icon(Icons.swap_vert, size: 24),
                      ),
                    ),
                    TextButton(
                      onPressed: onDonePressed,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 44),
                        foregroundColor: context.colors.brandText,
                      ),
                      child: Text(
                        l10n.done,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                )
              else if (isSelf)
                // Share is drawn in the design beside this, and is deliberately
                // absent: there is nothing to share yet. The shareable artifacts
                // it would offer are the Library Card's, which is Phase 3, and a
                // share sheet that can only offer a screenshot is worse than no
                // button in the bar.
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    onPressed: onProfilePressed,
                    tooltip: l10n.profile,
                    splashRadius: 22,
                    icon: const Icon(Icons.person_outline, size: 24),
                  ),
                )
              else if (onPokePressed != null)
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
