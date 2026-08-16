import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_shell_provider.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/shelf_label.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:bookworm_friends/ui/widgets/wiggle.dart';

/// One shelf: its label, its books face-out on a plank, and in edit mode a
/// drag-reorderable list with delete badges.
class ShelfRow extends StatefulWidget {
  final Shelf shelf;
  final LibraryMode mode;
  final VoidCallback onEditName;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final void Function(String bookId)? onBookDropped;
  final void Function(List<String> bookIds)? onReorderBooks;
  final void Function(String bookId)? onDeleteBook;

  const ShelfRow({
    super.key,
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
  State<ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<ShelfRow> {
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
