import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/models/profile.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/profile_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/update_shelf_name_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/delete_shelf_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/loading_blocks.dart';

enum LibraryMode { library, editLibrary, editShelf }

final _libraryModeProvider = StateProvider.autoDispose<LibraryMode>((ref) => LibraryMode.library);
final _selectedFriendProvider = StateProvider.autoDispose<Profile?>((ref) => null);
final _filterYearProvider = StateProvider.autoDispose<int>((ref) => 0);
final _filterMonthProvider = StateProvider.autoDispose<int>((ref) => 0);
final _friendFilterYearProvider = StateProvider.autoDispose<int>((ref) => 0);
final _friendFilterMonthProvider = StateProvider.autoDispose<int>((ref) => 0);

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _shelfNameController = TextEditingController();

  @override
  void dispose() {
    _shelfNameController.dispose();
    super.dispose();
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
    showDeleteShelfBottomSheet(context, onDeletePressed: () async {
      Navigator.pop(context);
      await ref.read(libraryActionsProvider).deleteShelf(shelfId);
    });
  }

  Future<void> _onReorderShelves(List<Shelf> reordered) async {
    final shelfIds = reordered.map((s) => s.id).toList();
    await ref.read(libraryActionsProvider).updateShelfOrder(shelfIds);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final libraryAsync = ref.watch(libraryProvider);
    final filterYear = ref.watch(_filterYearProvider);
    final filterMonth = ref.watch(_filterMonthProvider);
    final finishedBooksAsync = ref.watch(finishedBooksProvider((year: filterYear, month: filterMonth)));
    final mode = ref.watch(_libraryModeProvider);
    final selectedFriend = ref.watch(_selectedFriendProvider);
    final myProfile = ref.watch(profileProvider);
    final followingAsync = ref.watch(followingListProvider);

    final friendFilterYear = ref.watch(_friendFilterYearProvider);
    final friendFilterMonth = ref.watch(_friendFilterMonthProvider);

    final isSelf = selectedFriend == null;
    final friendLibraryAsync = selectedFriend != null
        ? ref.watch(userLibraryProvider(selectedFriend.id))
        : null;
    final friendFinishedBooksAsync = selectedFriend != null
        ? ref.watch(userFinishedBooksProvider((userId: selectedFriend.id, year: friendFilterYear, month: friendFilterMonth)))
        : null;

    return GestureDetector(
      onTap: () {
        if (mode == LibraryMode.editLibrary || mode == LibraryMode.editShelf) {
          ref.read(_libraryModeProvider.notifier).state = LibraryMode.library;
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.white,
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
                    following: followingAsync.valueOrNull ?? [],
                    selectedFriend: selectedFriend,
                    onSelectSelf: () {
                      ref.read(_selectedFriendProvider.notifier).state = null;
                    },
                    onSelectFriend: (profile) {
                      ref.read(_selectedFriendProvider.notifier).state = profile;
                      ref.read(_libraryModeProvider.notifier).state = LibraryMode.library;
                    },
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Material(
                    type: MaterialType.circle,
                    color: lightGrayColor,
                    child: IconButton(
                      onPressed: () => Navigator.pushNamed(context, AppRoutes.searchUsers),
                      splashRadius: 20,
                      icon: const Icon(Icons.search, size: 22, color: darkPrimaryColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 15),
              child: SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
                  splashRadius: 20,
                  icon: const Icon(Icons.menu, color: darkPrimaryColor, size: 26),
                ),
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
                ref.read(_libraryModeProvider.notifier).state = LibraryMode.editLibrary;
              },
              onAddPressed: _onAddBookPressed,
              onDonePressed: () {
                ref.read(_libraryModeProvider.notifier).state = LibraryMode.library;
              },
              onReorderPressed: () {
                ref.read(_libraryModeProvider.notifier).state = LibraryMode.editShelf;
              },
              onPokePressed: !isSelf && selectedFriend != null
                  ? () => ref.read(userActionsProvider).pokeUser(selectedFriend.username ?? '')
                  : null,
            ),
          ),
        ),
        body: isSelf
            ? libraryAsync.when(
                data: (shelves) => mode == LibraryMode.editShelf
                    ? _ReorderableShelfList(
                        shelves: shelves,
                        onReorderDone: _onReorderShelves,
                      )
                    : _LibraryWithFinishedBooks(
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
                            ref.read(_filterYearProvider.notifier).state = result.year;
                            ref.read(_filterMonthProvider.notifier).state = result.month;
                          }
                        },
                        onEditShelfName: _onEditShelfName,
                        onDeleteShelf: _onDeleteShelf,
                        onAddShelf: _onAddShelfPressed,
                        onEnterEditMode: () {
                          ref.read(_libraryModeProvider.notifier).state = LibraryMode.editLibrary;
                        },
                        onMoveBook: (bookId, targetShelfId) {
                          ref.read(libraryActionsProvider).moveBookToShelf(bookId, targetShelfId);
                        },
                        onRefresh: () async {
                          ref.invalidate(libraryProvider);
                          ref.invalidate(finishedBooksProvider((year: filterYear, month: filterMonth)));
                        },
                      ),
                loading: () => const LoadingLibrary(),
                error: (e, _) => Center(child: Text(l10n.errorWithMessage(e.toString()))),
              )
            : friendLibraryAsync!.when(
                data: (shelves) => _LibraryWithFinishedBooks(
                  shelves: shelves,
                  finishedBooks: friendFinishedBooksAsync?.valueOrNull ?? [],
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
                      ref.read(_friendFilterYearProvider.notifier).state = result.year;
                      ref.read(_friendFilterMonthProvider.notifier).state = result.month;
                    }
                  },
                  onEditShelfName: (_, __) {},
                  onDeleteShelf: (_) {},
                  onEnterEditMode: () {},
                  onRefresh: () async {
                    ref.invalidate(userLibraryProvider(selectedFriend!.id));
                    ref.invalidate(userFinishedBooksProvider((userId: selectedFriend.id, year: friendFilterYear, month: friendFilterMonth)));
                  },
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(l10n.errorWithMessage(e.toString()))),
              ),
      ),
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
  final VoidCallback onReorderPressed;
  final VoidCallback? onPokePressed;

  const _LibrarySubHeader({
    required this.isSelf,
    required this.mode,
    required this.username,
    required this.onEditPressed,
    required this.onAddPressed,
    required this.onDonePressed,
    required this.onReorderPressed,
    this.onPokePressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.white,
      elevation: 4,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: mode == LibraryMode.editLibrary
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: onReorderPressed,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_vert, size: 20, color: greenThemeColor),
                          const SizedBox(width: 4),
                          Text(
                            l10n.reorder,
                            style: const TextStyle(
                              color: greenThemeColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: onDonePressed,
                      child: Text(
                        l10n.done,
                        style: const TextStyle(
                          color: greenThemeColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                )
              : mode == LibraryMode.editShelf
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: onDonePressed,
                        child: Text(
                          l10n.done,
                          style: const TextStyle(
                            color: greenThemeColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text.rich(
                          TextSpan(
                            text: username.isEmpty ? l10n.library : username,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: darkPrimaryColor,
                            ),
                            children: [
                              TextSpan(
                                text: isSelf ? l10n.librarySuffixSelf : l10n.librarySuffixOther,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.normal,
                                  color: darkPrimaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelf)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: IconButton(
                                  onPressed: onEditPressed,
                                  splashRadius: 20,
                                  icon: const Icon(Icons.edit_outlined, size: 22, color: darkPrimaryColor),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: IconButton(
                                  onPressed: onAddPressed,
                                  splashRadius: 20,
                                  icon: const Icon(Icons.add, size: 24, color: darkPrimaryColor),
                                ),
                              ),
                            ],
                          ),
                        if (!isSelf && onPokePressed != null)
                          GestureDetector(
                            onTap: onPokePressed,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: greenThemeColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                l10n.poke,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
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
          color: isSelected ? greenThemeColor.withValues(alpha: 0.15) : Colors.grey.shade100,
          border: Border.all(
            color: isSelected ? greenThemeColor : Colors.transparent,
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
  showDialog(
    context: context,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final followerCount = ref.watch(followerCountProvider(friend.id));
        final followingCount = ref.watch(followingCountProvider(friend.id));

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                friend.emoji ?? '📖',
                style: const TextStyle(fontSize: 40),
              ),
              const SizedBox(height: 8),
              Text(
                friend.username ?? '',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkPrimaryColor),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Text(
                        followerCount.valueOrNull?.toString() ?? '-',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(l10n.followers, style: const TextStyle(fontSize: 12, color: grayColor)),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Column(
                    children: [
                      Text(
                        followingCount.valueOrNull?.toString() ?? '-',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(l10n.following, style: const TextStyle(fontSize: 12, color: grayColor)),
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
                      ref.read(userActionsProvider).pokeUser(friend.username ?? '');
                    },
                    child: Text(l10n.poke, style: const TextStyle(color: greenThemeColor)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showDialog(
                        context: context,
                        builder: (confirmCtx) => AlertDialog(
                          title: Text(l10n.unfollowConfirmTitle),
                          content: Text(l10n.unfollowConfirmMessage),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(confirmCtx),
                              child: Text(l10n.cancel),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(confirmCtx);
                                ref.read(userActionsProvider).unfollow(friend.id);
                              },
                              child: Text(l10n.confirm, style: const TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Text(l10n.unfollow, style: const TextStyle(color: Colors.red)),
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

void _showDeleteBookDialog(BuildContext context, String bookId) {
  showDialog(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return AlertDialog(
        title: Text(l10n.deleteBookTitle),
        content: Text(l10n.deleteBookConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ProviderScope.containerOf(context).read(libraryActionsProvider).deleteBook(bookId);
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      );
    },
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
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isLibraryEmpty = shelves.isEmpty || shelves.every((s) => s.books.isEmpty);

    if (isLibraryEmpty && finishedBooks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SadCharacter(height: 100),
            const SizedBox(height: 16),
            Text(l10n.libraryEmptySelf, style: const TextStyle(fontSize: 14, color: grayColor)),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 20, color: grayColor),
                const SizedBox(width: 4),
                Text(l10n.addBookHintSuffix, style: const TextStyle(fontSize: 14, color: grayColor)),
              ],
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget scrollView = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: lightGrayColor,
            boxShadow: [
              BoxShadow(blurRadius: 4, offset: const Offset(0, -4), color: Colors.black.withValues(alpha: 0.3)),
            ],
          ),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      children: [
                        ...shelves.map((shelf) => _ShelfRow(
                              shelf: shelf,
                              mode: mode,
                              onEditName: () => onEditShelfName(shelf.id, shelf.name),
                              onDelete: () => onDeleteShelf(shelf.id),
                              onLongPress: onEnterEditMode,
                              onBookDropped: onMoveBook != null
                                  ? (bookId) => onMoveBook!(bookId, shelf.id)
                                  : null,
                              onDeleteBook: mode == LibraryMode.editLibrary
                                  ? (bookId) => _showDeleteBookDialog(context, bookId)
                                  : null,
                            )),
                        if (mode == LibraryMode.editLibrary && onAddShelf != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: TextButton.icon(
                              onPressed: onAddShelf,
                              icon: const Icon(Icons.add, size: 20, color: darkPrimaryColor),
                              label: Text(
                                l10n.addShelf,
                                style: const TextStyle(
                                  color: darkPrimaryColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _FinishedBooksSection(
                    books: finishedBooks,
                    isEditMode: mode == LibraryMode.editLibrary,
                    filterYear: filterYear,
                    filterMonth: filterMonth,
                    onFilterPressed: onFilterPressed,
                  ),
                ],
              ),
            ),
          ),
        );

        if (onRefresh != null) {
          return RefreshIndicator(
            color: greenThemeColor,
            onRefresh: onRefresh!,
            child: scrollView,
          );
        }
        return scrollView;
      },
    );
  }
}

class _FinishedBooksSection extends StatelessWidget {
  final List<Book> books;
  final bool isEditMode;
  final int filterYear;
  final int filterMonth;
  final VoidCallback onFilterPressed;

  const _FinishedBooksSection({
    required this.books,
    required this.isEditMode,
    required this.filterYear,
    required this.filterMonth,
    required this.onFilterPressed,
  });

  String _filterText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (filterYear == 0) return l10n.all;
    if (filterMonth == 0) return l10n.yearLabel(filterYear);
    return l10n.yearMonthLabel(filterYear, filterMonth);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 4,
            offset: const Offset(0, -4),
            color: Colors.black.withValues(alpha: 0.15),
          ),
        ],
      ),
      padding: const EdgeInsets.only(left: 25, right: 25, top: 20, bottom: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    l10n.finishedBooksTitle,
                    style: const TextStyle(color: darkPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${books.length}',
                    style: const TextStyle(color: greenThemeColor, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onFilterPressed,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _filterText(context),
                      style: const TextStyle(color: darkPrimaryColor, fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down, size: 18, color: darkPrimaryColor),
                  ],
                ),
              ),
            ],
          ),
          if (books.isNotEmpty && !isEditMode)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: SizedBox(
                height: 124 + 13,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final opacityList = bookOpacityList;
                    final opacity = opacityList[index % opacityList.length];
                    return BookVertical(
                      title: books[index].title,
                      opacity: opacity,
                      onTap: () => Navigator.pushNamed(context, AppRoutes.details, arguments: books[index]),
                    );
                  },
                ),
              ),
            )
          else if (books.isEmpty)
            SizedBox(
              height: 124 + 20 + 13,
              child: Center(
                child: Text(l10n.noFinishedBooks, style: const TextStyle(color: grayColor, fontSize: 14)),
              ),
            ),
          const ShelfWidget(),
        ],
      ),
    );
  }
}


class _ReorderableShelfList extends StatefulWidget {
  final List<Shelf> shelves;
  final Future<void> Function(List<Shelf> reordered) onReorderDone;

  const _ReorderableShelfList({
    required this.shelves,
    required this.onReorderDone,
  });

  @override
  State<_ReorderableShelfList> createState() => _ReorderableShelfListState();
}

class _ReorderableShelfListState extends State<_ReorderableShelfList> {
  late List<Shelf> _shelves;

  @override
  void initState() {
    super.initState();
    _shelves = List.of(widget.shelves);
  }

  @override
  void didUpdateWidget(_ReorderableShelfList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shelves != widget.shelves) {
      _shelves = List.of(widget.shelves);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      color: lightGrayColor,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: _shelves.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final item = _shelves.removeAt(oldIndex);
            _shelves.insert(newIndex, item);
          });
          widget.onReorderDone(_shelves);
        },
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 4,
            color: Colors.transparent,
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final shelf = _shelves[index];
          return Container(
            key: ValueKey(shelf.id),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.drag_handle, color: grayColor, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    shelf.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: darkPrimaryColor,
                    ),
                  ),
                ),
                Text(
                  l10n.bookCountLabel(shelf.books.length),
                  style: const TextStyle(fontSize: 13, color: grayColor),
                ),
              ],
            ),
          );
        },
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
  final void Function(String bookId)? onDeleteBook;

  const _ShelfRow({
    required this.shelf,
    required this.mode,
    required this.onEditName,
    required this.onDelete,
    required this.onLongPress,
    this.onBookDropped,
    this.onDeleteBook,
  });

  @override
  State<_ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<_ShelfRow> {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final bookHeight = screenHeight * 0.15;
    final isEditMode = widget.mode == LibraryMode.editLibrary;

    Widget shelfContent = Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        children: [
          SizedBox(
            height: bookHeight,
            width: screenWidth * 0.95,
            child: Stack(
              alignment: Alignment.bottomLeft,
              children: [
                Positioned(
                  top: 0,
                  child: SizedBox(
                    height: bookHeight,
                    width: screenWidth * 0.95,
                    child: widget.shelf.books.isEmpty
                        ? const SizedBox.shrink()
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.only(left: 15, right: 15),
                            itemCount: widget.shelf.books.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 15),
                            itemBuilder: (context, index) {
                              final book = widget.shelf.books[index];
                              Widget bookWidget = Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  BookWidget(
                                    imageUrl: book.thumbnail,
                                    height: bookHeight,
                                    heroTag: 'book_${book.isbn}',
                                    onTap: isEditMode
                                        ? () => widget.onDeleteBook?.call(book.id)
                                        : () => Navigator.pushNamed(context, AppRoutes.details, arguments: book),
                                    onLongPress: widget.onLongPress,
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
                                                  colorFilter: ColorFilter.mode(Colors.black, BlendMode.srcATop),
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
                                      top: -6,
                                      left: -6,
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                                      ),
                                    ),
                                ],
                              );
                              if (isEditMode) {
                                bookWidget = LongPressDraggable<String>(
                                  data: book.id,
                                  feedback: Material(
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(4),
                                    child: BookWidget(imageUrl: book.thumbnail, height: bookHeight * 0.9),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.3,
                                    child: bookWidget,
                                  ),
                                  child: bookWidget,
                                );
                              }
                              return bookWidget;
                            },
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
      ),
    );

    if (isEditMode) {
      shelfContent = DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          final bookId = details.data;
          final isFromThisShelf = widget.shelf.books.any((b) => b.id == bookId);
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
              color: _isDragOver ? greenThemeColor.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: _isDragOver
                  ? Border.all(color: greenThemeColor, width: 2)
                  : null,
            ),
            child: shelfContent,
          );
        },
      );
    }

    return shelfContent;
  }
}
