import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';

final bookComplimentsProvider =
    FutureProvider.autoDispose.family<List<BookCompliment>, String>(
  (ref, bookId) async {
    final data = await supabase
        .from('book_compliments')
        .select()
        .eq('book_id', bookId)
        .order('created_at', ascending: false);

    return data.map((c) => BookCompliment.fromJson(c)).toList();
  },
);

final bookDetailsActionsProvider = Provider((ref) => BookDetailsActions(ref));

class BookDetailsActions {
  final Ref ref;
  BookDetailsActions(this.ref);

  Future<void> addCompliment(String bookId, String emoji) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    await supabase.from('book_compliments').insert({
      'book_id': bookId,
      'from_user_id': userId,
      'compliment': emoji,
    });

    ref.invalidate(bookComplimentsProvider(bookId));
  }

  Future<void> deleteCompliment(String complimentId, String bookId) async {
    await supabase.from('book_compliments').delete().eq('id', complimentId);
    ref.invalidate(bookComplimentsProvider(bookId));
  }
}
