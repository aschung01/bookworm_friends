import 'package:bookworm_friends/ui/widgets/buttons/adaptive_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/finished_books_sheet.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/dialogs/adaptive_dialog_action.dart';

/// Year/month the "Books read" pile is filtered by. Zero means "all".
final _filterYearProvider = StateProvider.autoDispose<int>((ref) => 0);
final _filterMonthProvider = StateProvider.autoDispose<int>((ref) => 0);

class UserLibraryPage extends ConsumerWidget {
  const UserLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final userId = args?['user_id'] as String? ?? '';
    final username = args?['username'] as String? ?? l10n.library;

    final libraryAsync = ref.watch(userLibraryProvider(userId));
    final isFollowingAsync = ref.watch(isFollowingProvider(userId));
    final currentUserId = ref.watch(currentUserIdProvider);
    final filterYear = ref.watch(_filterYearProvider);
    final filterMonth = ref.watch(_filterMonthProvider);
    final finishedBooksAsync = ref.watch(
      userFinishedBooksProvider((
        userId: userId,
        year: filterYear,
        month: filterMonth,
      )),
    );

    return Scaffold(
      backgroundColor: context.colors.pageBackground,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        leading: const AdaptiveBackButton(),
        title: Text(
          l10n.userLibraryTitle(username),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (currentUserId != null && currentUserId != userId)
            isFollowingAsync.when(
              data: (isFollowing) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: ElevatedActionButton(
                    width: 104,
                    height: 32,
                    borderRadius: 16,
                    buttonText: isFollowing ? l10n.following : l10n.follow,
                    backgroundColor: isFollowing
                        ? context.colors.surfaceVariant
                        : context.colors.brandFill,
                    textStyle: TextStyle(
                      color: isFollowing
                          ? context.colors.primaryText
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    onPressed: () async {
                      final actions = ref.read(userActionsProvider);
                      if (isFollowing) {
                        final confirmed = await showAdaptiveDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog.adaptive(
                            title: Text(l10n.unfollowConfirmTitle),
                            content: Text(l10n.unfollowConfirmMessage),
                            actions: [
                              AdaptiveDialogAction(
                                label: l10n.no,
                                textColor: context.colors.secondaryText,
                                onPressed: () => Navigator.pop(ctx, false),
                              ),
                              AdaptiveDialogAction(
                                label: l10n.unfollow,
                                isDestructive: true,
                                onPressed: () => Navigator.pop(ctx, true),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await actions.unfollow(userId);
                        }
                      } else {
                        await actions.follow(userId);
                      }
                    },
                  ),
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
        ],
      ),
      body: libraryAsync.when(
        data: (shelves) => _UserLibraryBody(
          shelves: shelves,
          finishedBooks: finishedBooksAsync.valueOrNull ?? const [],
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
          onRefresh: () async {
            ref.invalidate(userLibraryProvider(userId));
            ref.invalidate(
              userFinishedBooksProvider((
                userId: userId,
                year: filterYear,
                month: filterMonth,
              )),
            );
          },
        ),
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _UserLibraryBody extends StatelessWidget {
  final List<Shelf> shelves;
  final List<Book> finishedBooks;
  final int filterYear;
  final int filterMonth;
  final VoidCallback onFilterPressed;
  final Future<void> Function() onRefresh;

  const _UserLibraryBody({
    required this.shelves,
    required this.finishedBooks,
    required this.filterYear,
    required this.filterMonth,
    required this.onFilterPressed,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Read books belong to the "Books read" pile at the bottom, so they are kept
    // off the shelves above it. The emptiness check still looks at the unfiltered
    // shelves: `finishedBooks` only covers the pile's year/month filter, and a
    // library of nothing but read books isn't empty.
    final shelvesOnDisplay = withoutFinishedBooks(shelves);
    final hasNoBooks =
        (shelves.isEmpty || shelves.every((s) => s.books.isEmpty)) &&
        finishedBooks.isEmpty;

    if (hasNoBooks) {
      return Center(
        child: Text(
          l10n.libraryEmptyOther,
          style: TextStyle(color: context.colors.secondaryText),
        ),
      );
    }

    // NOTE: the background has to live *outside* RefreshIndicator, which wraps
    // its child in a loose Stack that would otherwise let the container shrink to
    // the shelves' height and leave the rest of the library unpainted.
    final library = Container(
      width: double.infinity,
      color: context.colors.surfaceVariant,
      child: RefreshIndicator(
        color: context.colors.brandText,
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 16, bottom: 16),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: shelvesOnDisplay
                .map((shelf) => _UserShelfRow(shelf: shelf))
                .toList(),
          ),
        ),
      ),
    );

    // The library only gets the height the pile leaves over, so the pile is
    // always fully visible without scrolling to the bottom of the page.
    return ColoredBox(
      color: context.colors.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: library),
          FinishedBooksSheet(
            books: finishedBooks,
            isEditMode: false,
            filterYear: filterYear,
            filterMonth: filterMonth,
            onFilterPressed: onFilterPressed,
          ),
        ],
      ),
    );
  }
}

class _UserShelfRow extends StatelessWidget {
  final Shelf shelf;
  const _UserShelfRow({required this.shelf});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final bookHeight = screenHeight * 0.15;
    // Same reservation as the home shelves: jitter can add 6%.
    final rowExtent = bookRowExtent(bookHeight);

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
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
                    child: shelf.books.isEmpty
                        ? const SizedBox.shrink()
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.only(left: 15, right: 15),
                            itemCount: shelf.books.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 15),
                            itemBuilder: (context, index) {
                              final book = shelf.books[index];
                              return Align(
                                alignment: Alignment.bottomCenter,
                                child: BookWidget(
                                  imageUrl: book.thumbnail,
                                  isbn: book.isbn,
                                  title: book.title,
                                  height: bookHeight,
                                  heroTag: 'book_${book.isbn}',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.details,
                                    arguments: book,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: ShelfLabel(label: shelf.name),
                ),
              ],
            ),
          ),
          const ShelfWidget(),
        ],
      ),
    );
  }
}
