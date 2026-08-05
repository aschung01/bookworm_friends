import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/providers/user_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';

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

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, color: darkPrimaryColor, size: 22),
        ),
        title: Text(
          l10n.userLibraryTitle(username),
          style: const TextStyle(color: darkPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (currentUserId != null && currentUserId != userId)
            isFollowingAsync.when(
              data: (isFollowing) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: ElevatedActionButton(
                    width: 80,
                    height: 32,
                    borderRadius: 16,
                    buttonText: isFollowing ? l10n.following : l10n.follow,
                    backgroundColor: isFollowing ? lightGrayColor : greenThemeColor,
                    textStyle: TextStyle(
                      color: isFollowing ? darkPrimaryColor : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    onPressed: () async {
                      final actions = ref.read(userActionsProvider);
                      if (isFollowing) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(l10n.unfollowConfirmTitle),
                            content: Text(l10n.unfollowConfirmMessage),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(l10n.no, style: const TextStyle(color: grayColor)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(l10n.unfollow, style: const TextStyle(color: cancelRedColor)),
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
        data: (shelves) => _UserLibraryBody(shelves: shelves),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _UserLibraryBody extends StatelessWidget {
  final List<Shelf> shelves;
  const _UserLibraryBody({required this.shelves});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (shelves.isEmpty) {
      return Center(
        child: Text(l10n.libraryEmptyOther, style: const TextStyle(color: grayColor)),
      );
    }

    return Container(
      width: double.infinity,
      color: lightGrayColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 16, bottom: 40),
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: shelves.map((shelf) => _UserShelfRow(shelf: shelf)).toList(),
        ),
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

    return Padding(
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
                    child: shelf.books.isEmpty
                        ? const SizedBox.shrink()
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.only(left: 15, right: 15),
                            itemCount: shelf.books.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 15),
                            itemBuilder: (context, index) {
                              final book = shelf.books[index];
                              return BookWidget(
                                imageUrl: book.thumbnail,
                                height: bookHeight,
                                heroTag: 'book_${book.isbn}',
                                onTap: () => Navigator.pushNamed(context, AppRoutes.details, arguments: book),
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
