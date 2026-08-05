import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/book_memo.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/notification_service.dart' show navigatorKey;
import 'package:intl/intl.dart';

final libraryProvider = FutureProvider.autoDispose<List<Shelf>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final data = await supabase
      .from('shelves')
      .select('*, books(*)')
      .eq('user_id', userId)
      .order('position');

  return data.map((s) => Shelf.fromJson(s)).toList();
});

final finishedBooksProvider =
    FutureProvider.autoDispose.family<List<Book>, ({int year, int month})>(
  (ref, filter) async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return [];

    var query = supabase
        .from('books')
        .select()
        .eq('user_id', userId)
        .eq('status', 2);

    if (filter.year > 0) {
      final start = DateTime(filter.year, filter.month > 0 ? filter.month : 1);
      final end = filter.month > 0
          ? DateTime(filter.year, filter.month + 1)
          : DateTime(filter.year + 1);
      query = query
          .gte('finish_date', DateFormat('yyyy-MM-dd').format(start))
          .lt('finish_date', DateFormat('yyyy-MM-dd').format(end));
    }

    final data = await query.order('finish_date', ascending: false);
    return data.map((b) => Book.fromJson(b)).toList();
  },
);

final userFinishedBooksProvider = FutureProvider.autoDispose
    .family<List<Book>, ({String userId, int year, int month})>(
  (ref, params) async {
    var query = supabase
        .from('books')
        .select()
        .eq('user_id', params.userId)
        .eq('status', 2);

    if (params.year > 0) {
      final start = DateTime(params.year, params.month > 0 ? params.month : 1);
      final end = params.month > 0
          ? DateTime(params.year, params.month + 1)
          : DateTime(params.year + 1);
      query = query
          .gte('finish_date', DateFormat('yyyy-MM-dd').format(start))
          .lt('finish_date', DateFormat('yyyy-MM-dd').format(end));
    }

    final data = await query.order('finish_date', ascending: false);
    return data.map((b) => Book.fromJson(b)).toList();
  },
);

final libraryActionsProvider = Provider((ref) => LibraryActions(ref));

class LibraryActions {
  final Ref ref;
  LibraryActions(this.ref);

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

  Future<void> updateShelfOrder(List<String> shelfIds) async {
    try {
      for (var i = 0; i < shelfIds.length; i++) {
        await supabase
            .from('shelves')
            .update({'position': i})
            .eq('id', shelfIds[i]);
      }

      ref.invalidate(libraryProvider);
    } catch (e) {
      EasyLoading.showError(AppLocalizations.of(navigatorKey.currentContext!).reorderFailed);
    }
  }

  Future<void> moveBookToShelf(String bookId, String targetShelfId) async {
    try {
      await supabase
          .from('books')
          .update({'shelf_id': targetShelfId})
          .eq('id', bookId);

      ref.invalidate(libraryProvider);
    } catch (e) {
      EasyLoading.showError(AppLocalizations.of(navigatorKey.currentContext!).moveFailed);
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
        'start_date': startDate != null
            ? DateFormat('yyyy-MM-dd').format(startDate)
            : null,
        'finish_date': finishDate != null
            ? DateFormat('yyyy-MM-dd').format(finishDate)
            : null,
      });

      ref.invalidate(libraryProvider);
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
    EasyLoading.show();
    try {
      await supabase.from('books').update({
        'status': status,
        'start_date': startDate != null
            ? DateFormat('yyyy-MM-dd').format(startDate)
            : null,
        'finish_date': finishDate != null
            ? DateFormat('yyyy-MM-dd').format(finishDate)
            : null,
      }).eq('id', bookId);

      ref.invalidate(libraryProvider);
      EasyLoading.dismiss();
    } catch (e) {
      EasyLoading.showError(AppLocalizations.of(navigatorKey.currentContext!).statusChangeFailed);
    }
  }

  Future<void> deleteBook(String bookId) async {
    final l10n = AppLocalizations.of(navigatorKey.currentContext!);
    EasyLoading.show();
    try {
      await supabase.from('books').delete().eq('id', bookId);
      ref.invalidate(libraryProvider);
      EasyLoading.showSuccess(l10n.bookDeleted);
    } catch (e) {
      EasyLoading.showError(l10n.bookDeleteFailed);
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
      EasyLoading.showError(AppLocalizations.of(navigatorKey.currentContext!).memoAddFailed);
    }
  }

  Future<void> updateMemo(String memoId, String content) async {
    try {
      await supabase
          .from('book_memos')
          .update({'content': content})
          .eq('id', memoId);
    } catch (e) {
      EasyLoading.showError(AppLocalizations.of(navigatorKey.currentContext!).memoEditFailed);
    }
  }

  Future<void> deleteMemo(String memoId) async {
    try {
      await supabase.from('book_memos').delete().eq('id', memoId);
    } catch (e) {
      EasyLoading.showError(AppLocalizations.of(navigatorKey.currentContext!).memoDeleteFailed);
    }
  }
}

final bookMemosProvider =
    FutureProvider.autoDispose.family<List<BookMemo>, String>(
  (ref, bookId) async {
    final data = await supabase
        .from('book_memos')
        .select()
        .eq('book_id', bookId)
        .order('created_at', ascending: false);

    return data.map((m) => BookMemo.fromJson(m)).toList();
  },
);
