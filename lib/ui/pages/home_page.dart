import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/views/library_view.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/friend_rail.dart';
import 'package:bookworm_friends/ui/widgets/friends_sheet.dart';
import 'package:bookworm_friends/ui/widgets/library_card_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shell_tab_bar.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/update_shelf_name_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_shelf_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/manage_shelves_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
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

  Future<void> _onAddBookPressed() async {
    await Navigator.pushNamed(context, AppRoutes.search);
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
    required int filterMonth,
    required List<Profile> following,
    required Profile? selectedFriend,
  }) {
    switch (tab) {
      case LibraryTab.library:
        return FinishedBooksSheet(
          books: finishedBooks,
          isEditMode: mode == LibraryMode.editLibrary,
          filterYear: filterYear,
          filterMonth: filterMonth,
          bottomReserve: ShellTabBar.reserve,
          onFilterPressed: () async {
            final result = await showYearMonthFilterBottomSheet(
              context,
              currentYear: filterYear,
              currentMonth: filterMonth,
            );
            if (result != null) {
              ref.read(readsFilterYearProvider.notifier).state = result.year;
              ref.read(readsFilterMonthProvider.notifier).state = result.month;
            }
          },
        );
      case LibraryTab.friends:
        return FriendsSheet(
          following: following,
          selectedFriend: selectedFriend,
          bottomReserve: ShellTabBar.reserve,
          onSelectFriend: (profile) {
            ref.read(selectedFriendProvider.notifier).state = profile;
            ref.read(libraryModeProvider.notifier).state = LibraryMode.library;
          },
          onAddFriend: () =>
              Navigator.pushNamed(context, AppRoutes.searchUsers),
        );
      case LibraryTab.card:
        return LibraryCardSheet(bottomReserve: ShellTabBar.reserve);
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
    final filterMonth = ref.watch(readsFilterMonthProvider);
    final finishedBooksAsync = ref.watch(
      finishedBooksProvider((year: filterYear, month: filterMonth)),
    );
    final mode = ref.watch(libraryModeProvider);
    final tab = ref.watch(libraryTabProvider);
    final selectedFriend = ref.watch(selectedFriendProvider);
    final myProfile = ref.watch(profileProvider);
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
      // Android back / iOS predictive back should leave edit mode, not the page.
      canPop: mode == LibraryMode.library,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mode != LibraryMode.library) {
          ref.read(libraryModeProvider.notifier).state = LibraryMode.library;
        }
      },
      child: GestureDetector(
        onTap: () {
          if (mode == LibraryMode.editLibrary) {
            ref.read(libraryModeProvider.notifier).state = LibraryMode.library;
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
            title: SizedBox(
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: FriendRail(
                      myProfile: myProfile.valueOrNull,
                      following: following,
                      selectedFriend: selectedFriend,
                      onSelectSelf: () {
                        ref.read(selectedFriendProvider.notifier).state = null;
                      },
                      onSelectFriend: (profile) {
                        ref.read(selectedFriendProvider.notifier).state =
                            profile;
                        ref.read(libraryModeProvider.notifier).state =
                            LibraryMode.library;
                      },
                    ),
                  ),
                  AdaptiveIconButton(
                    symbol: 'magnifyingglass',
                    icon: Icons.search,
                    filledFallback: true,
                    semanticLabel: l10n.searchFriends,
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.searchUsers),
                  ),
                  // Keeps the search button off the settings button next to it,
                  // which the glass rendering would otherwise sit flush against.
                  const AdaptiveIconButtonGap(),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 15),
                child: AdaptiveIconButton(
                  symbol: 'line.3.horizontal',
                  icon: Icons.menu,
                  iconSize: 26,
                  semanticLabel: l10n.settings,
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.settings),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: _LibrarySubHeader(
                isSelf: isSelf,
                mode: mode,
                username: isSelf
                    ? (myProfile.valueOrNull?.username ?? '')
                    : (selectedFriend.username ?? ''),
                onEditPressed: () {
                  ref.read(libraryModeProvider.notifier).state =
                      LibraryMode.editLibrary;
                },
                onAddPressed: _onAddBookPressed,
                onDonePressed: () {
                  ref.read(libraryModeProvider.notifier).state =
                      LibraryMode.library;
                },
                onManageShelvesPressed: () =>
                    showManageShelvesBottomSheet(context),
                onPokePressed: !isSelf
                    ? () => ref
                          .read(userActionsProvider)
                          .pokeUser(selectedFriend.username ?? '')
                    : null,
              ),
            ),
          ),
          body: Stack(
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
                        filterMonth: filterMonth,
                        following: following,
                        selectedFriend: selectedFriend,
                      ),
                      onEditShelfName: _onEditShelfName,
                      onDeleteShelf: _onDeleteShelf,
                      onAddShelf: _onAddShelfPressed,
                      onEnterEditMode: () {
                        ref.read(libraryModeProvider.notifier).state =
                            LibraryMode.editLibrary;
                      },
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
                        ref.invalidate(
                          finishedBooksProvider((
                            year: filterYear,
                            month: filterMonth,
                          )),
                        );
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
    final friendFilterMonth = ref.watch(friendReadsFilterMonthProvider);
    final friendLibraryAsync = ref.watch(userLibraryProvider(friend.id));
    final friendFinishedBooksAsync = ref.watch(
      userFinishedBooksProvider((
        userId: friend.id,
        year: friendFilterYear,
        month: friendFilterMonth,
      )),
    );

    return friendLibraryAsync.when(
      data: (shelves) => LibraryPane(
        shelves: shelves,
        finishedBooks: friendFinishedBooksAsync.valueOrNull ?? [],
        mode: LibraryMode.library,
        // A friend's library always shows their read books, whichever tab you
        // were on: the tabs describe *your* shell, and a visit leaves it. Once
        // Task 5 lands, the bar is hidden here and `bottomReserve` goes with it.
        sheet: FinishedBooksSheet(
          books: friendFinishedBooksAsync.valueOrNull ?? [],
          isEditMode: false,
          filterYear: friendFilterYear,
          filterMonth: friendFilterMonth,
          bottomReserve: ShellTabBar.reserve,
          onFilterPressed: () async {
            final result = await showYearMonthFilterBottomSheet(
              context,
              currentYear: friendFilterYear,
              currentMonth: friendFilterMonth,
            );
            if (result != null) {
              ref.read(friendReadsFilterYearProvider.notifier).state =
                  result.year;
              ref.read(friendReadsFilterMonthProvider.notifier).state =
                  result.month;
            }
          },
        ),
        onEditShelfName: (_, __) {},
        onDeleteShelf: (_) {},
        onEnterEditMode: () {},
        onRefresh: () async {
          ref.invalidate(userLibraryProvider(friend.id));
          ref.invalidate(
            userFinishedBooksProvider((
              userId: friend.id,
              year: friendFilterYear,
              month: friendFilterMonth,
            )),
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => Center(child: Text(l10n.errorWithMessage(e.toString()))),
    );
  }
}

class _LibrarySubHeader extends StatelessWidget {
  final bool isSelf;
  final LibraryMode mode;
  final String username;
  final VoidCallback onEditPressed;
  final VoidCallback onAddPressed;
  final VoidCallback onDonePressed;
  final VoidCallback onManageShelvesPressed;
  final VoidCallback? onPokePressed;

  const _LibrarySubHeader({
    required this.isSelf,
    required this.mode,
    required this.username,
    required this.onEditPressed,
    required this.onAddPressed,
    required this.onDonePressed,
    required this.onManageShelvesPressed,
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
              // The title stays put in every mode: it keeps the user oriented,
              // and it keeps actions out of the slot where users expect Cancel.
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: username.isEmpty ? l10n.library : username,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    children: [
                      TextSpan(
                        text: isSelf
                            ? l10n.librarySuffixSelf
                            : l10n.librarySuffixOther,
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
                    // A bare icon, matching the pencil/plus in this same band.
                    // Glass capsules (AdaptiveIconButton) belong to the app bar
                    // above; using one here made the secondary action heavier
                    // than Done.
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        onPressed: onEditPressed,
                        tooltip: l10n.edit,
                        splashRadius: 22,
                        icon: const Icon(Icons.edit_outlined, size: 22),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        onPressed: onAddPressed,
                        splashRadius: 22,
                        icon: const Icon(Icons.add, size: 24),
                      ),
                    ),
                  ],
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
