import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/book_memo.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';
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

final libraryActionsProvider = Provider((ref) => LibraryActions(ref));

class LibraryActions {
  final Ref ref;
  LibraryActions(this.ref);

  Future<void> addShelf(String name) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final shelves = await ref.read(libraryProvider.future);
    final nextPosition = shelves.isEmpty ? 0 : shelves.last.position + 1;

    await supabase.from('shelves').insert({
      'user_id': userId,
      'name': name,
      'position': nextPosition,
    });

    ref.invalidate(libraryProvider);
  }

  Future<void> updateShelfName(String shelfId, String newName) async {
    await supabase
        .from('shelves')
        .update({'name': newName})
        .eq('id', shelfId);

    ref.invalidate(libraryProvider);
  }

  Future<void> updateShelfOrder(List<String> shelfIds) async {
    for (var i = 0; i < shelfIds.length; i++) {
      await supabase
          .from('shelves')
          .update({'position': i})
          .eq('id', shelfIds[i]);
    }

    ref.invalidate(libraryProvider);
  }

  Future<void> deleteShelf(String shelfId) async {
    await supabase.from('shelves').delete().eq('id', shelfId);
    ref.invalidate(libraryProvider);
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
  }

  Future<void> updateBookStatus(
    String bookId,
    int status, {
    DateTime? startDate,
    DateTime? finishDate,
  }) async {
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
  }

  Future<void> deleteBook(String bookId) async {
    await supabase.from('books').delete().eq('id', bookId);
    ref.invalidate(libraryProvider);
  }

  Future<void> addMemo(String bookId, String content) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase.from('book_memos').insert({
      'book_id': bookId,
      'user_id': userId,
      'content': content,
    });
  }

  Future<void> updateMemo(String memoId, String content) async {
    await supabase
        .from('book_memos')
        .update({'content': content})
        .eq('id', memoId);
  }

  Future<void> deleteMemo(String memoId) async {
    await supabase.from('book_memos').delete().eq('id', memoId);
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
