import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/book_memo.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/notification_service.dart'
    show navigatorKey;
import 'package:intl/intl.dart';

final libraryProvider =
    AsyncNotifierProvider.autoDispose<LibraryNotifier, List<Shelf>>(
      LibraryNotifier.new,
    );

/// The status a book carries once its owner has finished reading it.
const int bookStatusFinished = 2;

/// [shelves] with the finished books left out.
///
/// A finished book is represented by the "Books read" pile at the bottom of the
/// library, so leaving its cover on the shelf as well listed every read book
/// twice. The book keeps its shelf in the database — the details page still
/// shows which shelf it belongs to, and clearing the "Read" status puts the
/// cover straight back where it was.
List<Shelf> withoutFinishedBooks(List<Shelf> shelves) => [
  for (final shelf in shelves)
    shelf.copyWith(
      books: shelf.books
          .where((book) => book.status != bookStatusFinished)
          .toList(),
    ),
];

/// A book taken out of local state but not yet deleted from the database, held
/// so the library's undo can put it back at the exact shelf and position.
class PendingBookRemoval {
  final Book book;
  final String shelfId;
  final int index;

  const PendingBookRemoval({
    required this.book,
    required this.shelfId,
    required this.index,
  });
}

class LibraryNotifier extends AutoDisposeAsyncNotifier<List<Shelf>> {
  @override
  Future<List<Shelf>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return [];

    final data = await supabase
        .from('shelves')
        .select('*, books(*)')
        .eq('user_id', userId)
        .order('position');

    final shelves = data.map((s) => Shelf.fromJson(s)).toList();
    // Books are ordered by their `position` within each shelf.
    for (final shelf in shelves) {
      shelf.books.sort((a, b) => a.position.compareTo(b.position));
    }
    return shelves;
  }

  /// Reorders shelves optimistically, then persists the new positions.
  Future<void> reorderShelves(List<String> shelfIds) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final byId = {for (final s in current) s.id: s};
    final reordered = <Shelf>[
      for (var i = 0; i < shelfIds.length; i++)
        if (byId[shelfIds[i]] != null) byId[shelfIds[i]]!.copyWith(position: i),
    ];
    state = AsyncData(reordered);

    try {
      for (var i = 0; i < shelfIds.length; i++) {
        await supabase
            .from('shelves')
            .update({'position': i})
            .eq('id', shelfIds[i]);
      }
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).reorderFailed,
      );
      ref.invalidateSelf();
    }
  }

  /// Reorders books within a single shelf optimistically, then persists.
  ///
  /// [bookIds] only has to cover the books the caller can see: finished books
  /// are hidden from the shelves, so the ones left out keep their stored
  /// position instead of being dropped from state.
  Future<void> reorderBooksInShelf(String shelfId, List<String> bookIds) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.map((shelf) {
      if (shelf.id != shelfId) return shelf;
      final byId = {for (final b in shelf.books) b.id: b};
      final reordered = <Book>[
        for (var i = 0; i < bookIds.length; i++)
          if (byId.remove(bookIds[i]) case final book?)
            book.copyWith(position: i),
      ];
      // Whatever wasn't listed is hidden from this shelf, so where it lands in
      // the list doesn't matter — only that it survives the reorder.
      return shelf.copyWith(books: [...reordered, ...byId.values]);
    }).toList();
    state = AsyncData(updated);

    try {
      for (var i = 0; i < bookIds.length; i++) {
        await supabase
            .from('books')
            .update({'position': i})
            .eq('id', bookIds[i]);
      }
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).reorderFailed,
      );
      ref.invalidateSelf();
    }
  }

  /// Removes a book from local state *without* touching the database, returning
  /// what's needed to put it back. Paired with [restoreBookLocally] and
  /// [LibraryActions.deleteBookSilently] this lets the library delete a
  /// confirmed book optimistically: the cover disappears on the same frame as
  /// the tap, and a failed database delete rolls the removal back.
  PendingBookRemoval? removeBookLocally(String bookId) {
    final current = state.valueOrNull;
    if (current == null) return null;

    for (final shelf in current) {
      final index = shelf.books.indexWhere((b) => b.id == bookId);
      if (index == -1) continue;

      final book = shelf.books[index];
      final remaining = [...shelf.books]..removeAt(index);
      state = AsyncData([
        for (final s in current)
          if (s.id == shelf.id) s.copyWith(books: remaining) else s,
      ]);
      return PendingBookRemoval(book: book, shelfId: shelf.id, index: index);
    }
    return null;
  }

  /// Puts a [removeBookLocally] result back where it came from.
  void restoreBookLocally(PendingBookRemoval pending) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.any((s) => s.books.any((b) => b.id == pending.book.id))) return;

    state = AsyncData([
      for (final s in current)
        if (s.id == pending.shelfId)
          s.copyWith(
            books: [...s.books]
              ..insert(pending.index.clamp(0, s.books.length), pending.book),
          )
        else
          s,
    ]);
  }

  /// Moves a book to another shelf optimistically, then persists.
  Future<void> moveBookToShelf(String bookId, String targetShelfId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    Book? book;
    for (final shelf in current) {
      for (final b in shelf.books) {
        if (b.id == bookId) book = b;
      }
    }
    if (book == null || book.shelfId == targetShelfId) return;
    final sourceShelfId = book.shelfId;

    final targetBooks = current.firstWhere((s) => s.id == targetShelfId).books;
    final newPosition = targetBooks.isEmpty
        ? 0
        : targetBooks.map((b) => b.position).reduce((a, b) => a > b ? a : b) +
              1;
    final movedBook = book.copyWith(
      shelfId: targetShelfId,
      position: newPosition,
    );

    final updated = current.map((shelf) {
      if (shelf.id == sourceShelfId) {
        return shelf.copyWith(
          books: shelf.books.where((b) => b.id != bookId).toList(),
        );
      }
      if (shelf.id == targetShelfId) {
        return shelf.copyWith(books: [...shelf.books, movedBook]);
      }
      return shelf;
    }).toList();
    state = AsyncData(updated);

    try {
      await supabase
          .from('books')
          .update({'shelf_id': targetShelfId, 'position': newPosition})
          .eq('id', bookId);
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).moveFailed,
      );
      ref.invalidateSelf();
    }
  }
}

final finishedBooksProvider = FutureProvider.autoDispose
    .family<List<Book>, ({int year, int month})>((ref, filter) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return [];

      var query = supabase
          .from('books')
          .select()
          .eq('user_id', userId)
          .eq('status', bookStatusFinished);

      if (filter.year > 0) {
        final start = DateTime(
          filter.year,
          filter.month > 0 ? filter.month : 1,
        );
        final end = filter.month > 0
            ? DateTime(filter.year, filter.month + 1)
            : DateTime(filter.year + 1);
        query = query
            .gte('finish_date', DateFormat('yyyy-MM-dd').format(start))
            .lt('finish_date', DateFormat('yyyy-MM-dd').format(end));
      }

      final data = await query.order('finish_date', ascending: false);
      return data.map((b) => Book.fromJson(b)).toList();
    });

final userFinishedBooksProvider = FutureProvider.autoDispose
    .family<List<Book>, ({String userId, int year, int month})>((
      ref,
      params,
    ) async {
      var query = supabase
          .from('books')
          .select()
          .eq('user_id', params.userId)
          .eq('status', bookStatusFinished);

      if (params.year > 0) {
        final start = DateTime(
          params.year,
          params.month > 0 ? params.month : 1,
        );
        final end = params.month > 0
            ? DateTime(params.year, params.month + 1)
            : DateTime(params.year + 1);
        query = query
            .gte('finish_date', DateFormat('yyyy-MM-dd').format(start))
            .lt('finish_date', DateFormat('yyyy-MM-dd').format(end));
      }

      final data = await query.order('finish_date', ascending: false);
      return data.map((b) => Book.fromJson(b)).toList();
    });

final libraryActionsProvider = Provider((ref) => LibraryActions(ref));

/// Enforces the reading-date invariant on the way to the database: a book can
/// never be finished before it was started.
///
/// The date pickers already stop an inverted pair being *chosen*, but they only
/// guard new input. Saving a book that was already stored inverted — or any
/// future code path that writes dates without going through a picker — would
/// otherwise persist it. When the pair is inverted the finish date is pulled up
/// to the start date, which is the smallest correction that keeps both values.
///
/// Compared by calendar day, because these are stored as `yyyy-MM-dd` and a
/// stray time component must not decide the outcome.
({DateTime? startDate, DateTime? finishDate}) clampReadingDates({
  DateTime? startDate,
  DateTime? finishDate,
}) {
  if (startDate == null || finishDate == null) {
    return (startDate: startDate, finishDate: finishDate);
  }

  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final finish = DateTime(finishDate.year, finishDate.month, finishDate.day);

  return finish.isBefore(start)
      ? (startDate: startDate, finishDate: startDate)
      : (startDate: startDate, finishDate: finishDate);
}

class LibraryActions {
  final Ref ref;
  LibraryActions(this.ref);

  /// The "Books read" pile is its own query rather than a slice of the library,
  /// so anything that can change which books are finished has to refetch it —
  /// otherwise a book that just left the shelves wouldn't show up in the pile
  /// until the next pull-to-refresh. Every year/month filter is invalidated,
  /// because the caller doesn't know which one is on screen.
  void _invalidateFinishedBooks() {
    ref.invalidate(finishedBooksProvider);
  }

  Future<void> addShelf(String name) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    EasyLoading.show();
    try {
      final shelves = await ref.read(libraryProvider.future);
      final nextPosition = shelves.isEmpty ? 0 : shelves.last.position + 1;

      await supabase.from('shelves').insert({
        'user_id': userId,
        'name': name,
        'position': nextPosition,
      });

      ref.invalidate(libraryProvider);
      EasyLoading.showSuccess(l10n.shelfAdded);
    } catch (e) {
      EasyLoading.showError(l10n.shelfAddFailed);
    }
  }

  Future<void> updateShelfName(String shelfId, String newName) async {
    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    EasyLoading.show();
    try {
      await supabase
          .from('shelves')
          .update({'name': newName})
          .eq('id', shelfId);

      ref.invalidate(libraryProvider);
      EasyLoading.showSuccess(l10n.renamed);
    } catch (e) {
      EasyLoading.showError(l10n.renameFailed);
    }
  }

  Future<void> deleteShelf(String shelfId) async {
    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    EasyLoading.show();
    try {
      await supabase.from('shelves').delete().eq('id', shelfId);
      ref.invalidate(libraryProvider);
      EasyLoading.showSuccess(l10n.shelfDeleted);
    } catch (e) {
      EasyLoading.showError(l10n.shelfDeleteFailed);
    }
  }

  Future<void> addBook({
    required String shelfId,
    required String isbn,
    required String title,
    required String thumbnail,
    required int status,
    DateTime? startDate,
    DateTime? finishDate,
  }) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final dates = clampReadingDates(
      startDate: startDate,
      finishDate: finishDate,
    );

    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    EasyLoading.show();
    try {
      await supabase.from('books').insert({
        'user_id': userId,
        'shelf_id': shelfId,
        'isbn': isbn,
        'title': title,
        'thumbnail': thumbnail,
        'status': status,
        'start_date': dates.startDate != null
            ? DateFormat('yyyy-MM-dd').format(dates.startDate!)
            : null,
        'finish_date': dates.finishDate != null
            ? DateFormat('yyyy-MM-dd').format(dates.finishDate!)
            : null,
      });

      ref.invalidate(libraryProvider);
      _invalidateFinishedBooks();
      EasyLoading.showSuccess(l10n.bookAdded);
    } catch (e) {
      EasyLoading.showError(l10n.bookAddFailed);
    }
  }

  Future<void> updateBookStatus(
    String bookId,
    int status, {
    DateTime? startDate,
    DateTime? finishDate,
  }) async {
    final dates = clampReadingDates(
      startDate: startDate,
      finishDate: finishDate,
    );

    EasyLoading.show();
    try {
      await supabase
          .from('books')
          .update({
            'status': status,
            'start_date': dates.startDate != null
                ? DateFormat('yyyy-MM-dd').format(dates.startDate!)
                : null,
            'finish_date': dates.finishDate != null
                ? DateFormat('yyyy-MM-dd').format(dates.finishDate!)
                : null,
          })
          .eq('id', bookId);

      ref.invalidate(libraryProvider);
      _invalidateFinishedBooks();
      EasyLoading.dismiss();
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).statusChangeFailed,
      );
    }
  }

  Future<void> deleteBook(String bookId) async {
    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    EasyLoading.show();
    try {
      await supabase.from('books').delete().eq('id', bookId);
      ref.invalidate(libraryProvider);
      _invalidateFinishedBooks();
      EasyLoading.showSuccess(l10n.bookDeleted);
    } catch (e) {
      EasyLoading.showError(l10n.bookDeleteFailed);
    }
  }

  /// Commits a delete with no loading overlay and no success toast, for callers
  /// that already removed the book from local state with [
  /// LibraryNotifier.removeBookLocally] — the cover disappearing is the
  /// feedback. Returns false if the row couldn't be deleted, so the caller can
  /// put the book back.
  ///
  /// Prefer [deleteBook] anywhere the book isn't visibly on screen.
  Future<bool> deleteBookSilently(String bookId) async {
    try {
      await supabase.from('books').delete().eq('id', bookId);
      return true;
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).bookDeleteFailed,
      );
      return false;
    }
  }

  Future<void> addMemo(String bookId, String content) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      await supabase.from('book_memos').insert({
        'book_id': bookId,
        'user_id': userId,
        'content': content,
      });
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).memoAddFailed,
      );
    }
  }

  Future<void> updateMemo(String memoId, String content) async {
    try {
      await supabase
          .from('book_memos')
          .update({'content': content})
          .eq('id', memoId);
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).memoEditFailed,
      );
    }
  }

  Future<void> deleteMemo(String memoId) async {
    try {
      await supabase.from('book_memos').delete().eq('id', memoId);
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).memoDeleteFailed,
      );
    }
  }
}

final bookMemosProvider = FutureProvider.autoDispose
    .family<List<BookMemo>, String>((ref, bookId) async {
      final data = await supabase
          .from('book_memos')
          .select()
          .eq('book_id', bookId)
          .order('created_at', ascending: false);

      return data.map((m) => BookMemo.fromJson(m)).toList();
    });
