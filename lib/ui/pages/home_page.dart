import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:bookworm_friends/ui/widgets/wiggle.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/update_shelf_name_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_book_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_shelf_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/manage_shelves_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/adaptive_icon_button.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/adaptive_dialog_action.dart';
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

  void _onAddBookPressed() {
    Navigator.pushNamed(context, AppRoutes.search);
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
                    child: _FriendAvatarBar(
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
          body: PageView.builder(
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
                data: (shelves) => _LibraryWithFinishedBooks(
                  shelves: shelves,
                  finishedBooks: finishedBooksAsync.valueOrNull ?? [],
                  mode: mode,
                  filterYear: filterYear,
                  filterMonth: filterMonth,
                  onFilterPressed: () async {
                    final result = await showYearMonthFilterBottomSheet(
                      context,
                      currentYear: filterYear,
                      currentMonth: filterMonth,
                    );
                    if (result != null) {
                      ref.read(readsFilterYearProvider.notifier).state =
                          result.year;
                      ref.read(readsFilterMonthProvider.notifier).state =
                          result.month;
                    }
                  },
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
                error: (e, _) =>
                    Center(child: Text(l10n.errorWithMessage(e.toString()))),
              );
            },
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
      data: (shelves) => _LibraryWithFinishedBooks(
        shelves: shelves,
        finishedBooks: friendFinishedBooksAsync.valueOrNull ?? [],
        mode: LibraryMode.library,
        filterYear: friendFilterYear,
        filterMonth: friendFilterMonth,
        onFilterPressed: () async {
          final result = await showYearMonthFilterBottomSheet(
            context,
            currentYear: friendFilterYear,
            currentMonth: friendFilterMonth,
          );
          if (result != null) {
            ref.read(friendReadsFilterYearProvider.notifier).state = result.year;
            ref.read(friendReadsFilterMonthProvider.notifier).state = result.month;
          }
        },
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

class _FriendAvatarBar extends StatelessWidget {
  final Profile? myProfile;
  final List<Profile> following;
  final Profile? selectedFriend;
  final VoidCallback onSelectSelf;
  final ValueChanged<Profile> onSelectFriend;

  const _FriendAvatarBar({
    required this.myProfile,
    required this.following,
    required this.selectedFriend,
    required this.onSelectSelf,
    required this.onSelectFriend,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 10),
      itemCount: following.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          final isSelected = selectedFriend == null;
          return _AvatarCircle(
            emoji: myProfile?.emoji ?? '📚',
            isSelected: isSelected,
            onTap: onSelectSelf,
          );
        }
        final friend = following[index - 1];
        final isSelected = selectedFriend?.id == friend.id;
        return _AvatarCircle(
          emoji: friend.emoji ?? '📖',
          isSelected: isSelected,
          onTap: () => onSelectFriend(friend),
          onLongPress: () => _showFriendInfoDialog(context, friend),
        );
      },
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

class _AvatarCircle extends StatelessWidget {
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _AvatarCircle({
    required this.emoji,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? context.colors.brand.withValues(alpha: 0.15)
              : context.colors.surfaceVariant,
          border: Border.all(
            color: isSelected ? context.colors.brandText : Colors.transparent,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}

void _showFriendInfoDialog(BuildContext context, Profile friend) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final followerCount = ref.watch(followerCountProvider(friend.id));
        final followingCount = ref.watch(followingCountProvider(friend.id));

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(friend.emoji ?? '📖', style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text(
                friend.username ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Text(
                        followerCount.valueOrNull?.toString() ?? '-',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.followers,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Column(
                    children: [
                      Text(
                        followingCount.valueOrNull?.toString() ?? '-',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.following,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref
                          .read(userActionsProvider)
                          .pokeUser(friend.username ?? '');
                    },
                    child: Text(
                      l10n.poke,
                      style: TextStyle(color: context.colors.brandText),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showAdaptiveDialog<void>(
                        context: context,
                        builder: (confirmCtx) => AlertDialog.adaptive(
                          title: Text(l10n.unfollowConfirmTitle),
                          content: Text(l10n.unfollowConfirmMessage),
                          actions: [
                            AdaptiveDialogAction(
                              label: l10n.cancel,
                              onPressed: () => Navigator.pop(confirmCtx),
                            ),
                            AdaptiveDialogAction(
                              label: l10n.confirm,
                              isDestructive: true,
                              onPressed: () {
                                Navigator.pop(confirmCtx);
                                ref
                                    .read(userActionsProvider)
                                    .unfollow(friend.id);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                    child: Text(
                      l10n.unfollow,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _LibraryWithFinishedBooks extends StatelessWidget {
  final List<Shelf> shelves;
  final List<Book> finishedBooks;
  final LibraryMode mode;
  final int filterYear;
  final int filterMonth;
  final VoidCallback onFilterPressed;
  final void Function(String shelfId, String name) onEditShelfName;
  final void Function(String shelfId) onDeleteShelf;
  final VoidCallback onEnterEditMode;
  final VoidCallback? onAddShelf;
  final void Function(String bookId, String targetShelfId)? onMoveBook;
  final void Function(String shelfId, List<String> bookIds)? onReorderBooks;
  final void Function(String bookId)? onDeleteBook;
  final Future<void> Function()? onRefresh;

  const _LibraryWithFinishedBooks({
    required this.shelves,
    required this.finishedBooks,
    required this.mode,
    required this.filterYear,
    required this.filterMonth,
    required this.onFilterPressed,
    required this.onEditShelfName,
    required this.onDeleteShelf,
    required this.onEnterEditMode,
    this.onAddShelf,
    this.onMoveBook,
    this.onReorderBooks,
    this.onDeleteBook,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Read books live in the "Books read" pile at the bottom of this library, so
    // they are kept off the shelves above it: showing both listed every read
    // book twice.
    final shelvesOnDisplay = withoutFinishedBooks(shelves);
    // Deliberately measured against the *unfiltered* shelves. `finishedBooks` is
    // only the books matching the pile's year/month filter, so a library made up
    // entirely of read books must not offer to add a first book just because the
    // filter happens to exclude them all.
    final bool hasNoBooks =
        (shelves.isEmpty || shelves.every((s) => s.books.isEmpty)) &&
        finishedBooks.isEmpty;

    if (hasNoBooks) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SadCharacter(height: 100),
            const SizedBox(height: 16),
            Text(
              l10n.libraryEmptySelf,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 20, color: context.colors.secondaryText),
                const SizedBox(width: 4),
                Text(
                  l10n.addBookHintSuffix,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.secondaryText,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget shelfList = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: Column(
        children: [
          ...shelvesOnDisplay.map(
            (shelf) => _ShelfRow(
              shelf: shelf,
              mode: mode,
              onEditName: () => onEditShelfName(shelf.id, shelf.name),
              onDelete: () => onDeleteShelf(shelf.id),
              onLongPress: onEnterEditMode,
              onBookDropped: onMoveBook != null
                  ? (bookId) => onMoveBook!(bookId, shelf.id)
                  : null,
              onReorderBooks: onReorderBooks != null
                  ? (bookIds) => onReorderBooks!(shelf.id, bookIds)
                  : null,
              onDeleteBook: mode == LibraryMode.editLibrary
                  ? onDeleteBook
                  : null,
            ),
          ),
          if (mode == LibraryMode.editLibrary && onAddShelf != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: TextButton.icon(
                onPressed: onAddShelf,
                icon: const Icon(Icons.add, size: 20),
                label: Text(
                  l10n.addShelf,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (onRefresh != null) {
      shelfList = RefreshIndicator(
        color: context.colors.brandText,
        onRefresh: onRefresh!,
        child: shelfList,
      );
    }

    // NOTE: the background has to live *outside* RefreshIndicator. That widget
    // wraps its child in a loose Stack, which would let the container shrink to
    // the shelves' height and leave the rest of the library unpainted.
    final library = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        boxShadow: [
          BoxShadow(
            blurRadius: 4,
            offset: const Offset(0, -4),
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ],
      ),
      child: shelfList,
    );

    // The library only gets the height left over by the "Books read" sheet, so
    // the sheet is always fully visible without scrolling to the bottom. As the
    // sheet is dragged down the library grows into the freed space. The library
    // colour also backs the whole area so it shows through the sheet's rounded
    // top corners.
    return ColoredBox(
      color: context.colors.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: library),
          FinishedBooksSheet(
            books: finishedBooks,
            isEditMode: mode == LibraryMode.editLibrary,
            filterYear: filterYear,
            filterMonth: filterMonth,
            onFilterPressed: onFilterPressed,
          ),
        ],
      ),
    );
  }
}

class _ShelfRow extends StatefulWidget {
  final Shelf shelf;
  final LibraryMode mode;
  final VoidCallback onEditName;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final void Function(String bookId)? onBookDropped;
  final void Function(List<String> bookIds)? onReorderBooks;
  final void Function(String bookId)? onDeleteBook;

  const _ShelfRow({
    required this.shelf,
    required this.mode,
    required this.onEditName,
    required this.onDelete,
    required this.onLongPress,
    this.onBookDropped,
    this.onReorderBooks,
    this.onDeleteBook,
  });

  @override
  State<_ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<_ShelfRow> {
  bool _isDragOver = false;

  /// Builds a single book tile (cover + reading badge + edit-mode delete icon).
  Widget _buildBookContent(
    Book book,
    double bookHeight,
    bool isEditMode, {
    bool withHero = true,
  }) {
    final l10n = AppLocalizations.of(context);
    return Wiggle(
      enabled: isEditMode,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          BookWidget(
            imageUrl: book.thumbnail,
            isbn: book.isbn,
            title: book.title,
            height: bookHeight,
            heroTag: withHero ? 'book_${book.isbn}' : null,
            pressEffect: !isEditMode,
            // In edit mode the badge is the sole delete target. The no-op tap
            // handler keeps cover taps from bubbling to the page-level handler
            // and unintentionally leaving edit mode.
            onTap: isEditMode
                ? () {}
                : () => Navigator.pushNamed(
                    context,
                    AppRoutes.details,
                    arguments: book,
                  ),
            onLongPress: isEditMode ? null : widget.onLongPress,
          ),
          if (book.status == 1)
            Positioned(
              top: 0,
              right: 8,
              child: Stack(
                children: [
                  Transform.translate(
                    offset: const Offset(0, 4),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: const Opacity(
                        opacity: 0.5,
                        child: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            Colors.black,
                            BlendMode.srcATop,
                          ),
                          child: BookmarkIcon(),
                        ),
                      ),
                    ),
                  ),
                  const BookmarkIcon(),
                ],
              ),
            ),
          if (isEditMode)
            Positioned(
              top: -22,
              left: -22,
              child: _DeleteBookButton(
                key: ValueKey('delete_book_${book.id}'),
                label: l10n.deleteBookNamed(book.title),
                onPressed: () => widget.onDeleteBook?.call(book.id),
              ),
            ),
        ],
      ),
    );
  }

  /// Horizontal reorderable list used in edit mode. Long-press + horizontal
  /// drag reorders books within the shelf; a vertical drag (via the nested
  /// [Draggable] with vertical affinity) moves a book to another shelf.
  Widget _buildEditableBookList(double bookHeight) {
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      clipBehavior: Clip.none,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 7.5),
      itemCount: widget.shelf.books.length,
      onReorderItem: (oldIndex, newIndex) {
        final ids = widget.shelf.books.map((b) => b.id).toList();
        final id = ids.removeAt(oldIndex);
        ids.insert(newIndex, id);
        widget.onReorderBooks?.call(ids);
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          child: Material(color: Colors.transparent, child: child),
          builder: (context, child) {
            final t = Curves.easeInOut.transform(animation.value);
            return Transform.scale(scale: 1.0 + 0.1 * t, child: child);
          },
        );
      },
      itemBuilder: (context, index) {
        final book = widget.shelf.books[index];
        return _DelayedReorderableListener(
          key: ValueKey(book.id),
          index: index,
          // Bottom-aligned so a book that hashes short sits on the shelf line
          // instead of floating, and so the row's tight height constraint is
          // loosened — without this the book would be stretched to the row
          // extent and the height jitter would vanish.
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 7.5),
              child: Draggable<String>(
                data: book.id,
                affinity: Axis.vertical,
                feedback: Material(
                  color: Colors.transparent,
                  child: BookWidget(
                    imageUrl: book.thumbnail,
                    isbn: book.isbn,
                    title: book.title,
                    height: bookHeight * 1.1,
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: _buildBookContent(
                    book,
                    bookHeight,
                    true,
                    withHero: false,
                  ),
                ),
                child: _buildBookContent(book, bookHeight, true),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final bookHeight = screenHeight * 0.15;
    // Books can hash up to 6% taller than the base, so the row has to reserve
    // that or every tall book gets clipped along the top.
    final rowExtent = bookRowExtent(bookHeight);
    final isEditMode = widget.mode == LibraryMode.editLibrary;

    final Widget innerContent = Column(
      children: [
        SizedBox(
          height: rowExtent,
          width: screenWidth * 0.95,
          child: Stack(
            alignment: Alignment.bottomLeft,
            children: [
              Positioned(
                top: 0,
                child: SizedBox(
                  height: rowExtent,
                  width: screenWidth * 0.95,
                  child: widget.shelf.books.isEmpty
                      ? const SizedBox.shrink()
                      : isEditMode
                      ? _buildEditableBookList(bookHeight)
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.only(left: 15, right: 15),
                          itemCount: widget.shelf.books.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 15),
                          itemBuilder: (context, index) => Align(
                            alignment: Alignment.bottomCenter,
                            child: _buildBookContent(
                              widget.shelf.books[index],
                              bookHeight,
                              false,
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: isEditMode ? widget.onEditName : null,
                  onLongPress: isEditMode ? widget.onDelete : null,
                  child: ShelfLabel(label: widget.shelf.name),
                ),
              ),
            ],
          ),
        ),
        const ShelfWidget(),
      ],
    );

    if (isEditMode) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 26),
        child: DragTarget<String>(
          onWillAcceptWithDetails: (details) {
            final bookId = details.data;
            final isFromThisShelf = widget.shelf.books.any(
              (b) => b.id == bookId,
            );
            if (!isFromThisShelf) {
              setState(() => _isDragOver = true);
            }
            return !isFromThisShelf;
          },
          onLeave: (_) => setState(() => _isDragOver = false),
          onAcceptWithDetails: (details) {
            setState(() => _isDragOver = false);
            widget.onBookDropped?.call(details.data);
          },
          builder: (context, candidateData, rejectedData) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _isDragOver
                    ? context.colors.brand.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: _isDragOver
                    ? Border.all(color: context.colors.brandText, width: 2)
                    : null,
              ),
              child: innerContent,
            );
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: innerContent,
    );
  }
}

class _DeleteBookButton extends StatelessWidget {
  const _DeleteBookButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onPressed,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Align(
              alignment: Alignment.center,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Like [ReorderableDelayedDragStartListener] but with a shorter, iOS-style
/// long-press delay before a reorder drag begins.
class _DelayedReorderableListener extends ReorderableDelayedDragStartListener {
  const _DelayedReorderableListener({
    super.key,
    required super.child,
    required super.index,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(
      delay: const Duration(milliseconds: 250),
      debugOwner: this,
    );
  }
}
