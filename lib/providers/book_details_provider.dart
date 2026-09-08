import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/core/supabase_config.dart';
import 'package:bookworm_friends/models/book_compliment.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';

/// Every reaction on a book, newest first, each carrying whoever left it.
///
/// The embed is named through the foreign key rather than the table, because
/// `book_compliments` has two FKs and PostgREST will not guess: the hint
/// `profiles!book_compliments_from_user_id_fkey` is what disambiguates. Aliased
/// to `reactor` so the JSON reads as what it means rather than as the table it
/// came from.
///
/// A to-one embed the policy withholds comes back as null rather than as an
/// error, so an unreadable profile costs the row nothing — see [BookCompliment].
final bookComplimentsProvider = FutureProvider.autoDispose
    .family<List<BookCompliment>, String>((ref, bookId) async {
      final data = await supabase
          .from('book_compliments')
          .select(
            '*, reactor:profiles!book_compliments_from_user_id_fkey'
            '(username, emoji, avatar_path)',
          )
          .eq('book_id', bookId)
          .order('created_at', ascending: false);

      return data.map((c) => BookCompliment.fromJson(c)).toList();
    });

/// What a tap on a palette emoji should do to the tapper's own praise.
enum PraiseTap { add, replace, remove }

/// One praise per person per book, so a tap is a three-way decision rather than
/// an insert. Tapping the emoji you already gave takes it back; tapping a
/// different one swaps it. Enforced in the database by
/// `UNIQUE (book_id, from_user_id)` (the `compliment_uniqueness` migration).
///
/// Pure and separate from [BookDetailsActions] because that class talks to the
/// global `supabase` client, which the test setup cannot fake — only providers
/// get overridden. This is the part worth pinning down, so it is kept reachable.
PraiseTap praiseTapFor({required String? current, required String tapped}) {
  if (current == null) return PraiseTap.add;
  return current == tapped ? PraiseTap.remove : PraiseTap.replace;
}

/// The praise [userId] left on this book, if any.
///
/// The uniqueness constraint means at most one row can match, so the first hit
/// is the answer.
String? praiseBy(List<BookCompliment> compliments, String? userId) {
  if (userId == null) return null;
  for (final c in compliments) {
    if (c.fromUserId == userId) return c.compliment;
  }
  return null;
}

/// How many reactions the capsule shows before it starts counting.
///
/// Two, because no book in production holds more than two: the collapsed form is
/// the complete form for every real book today, and `+N` is the escape hatch
/// rather than the normal case.
const int kVisibleReactions = 2;

/// Reactions in the order the capsule and the sheet should list them: yours
/// first, then everyone else's as the provider ordered them (newest first).
///
/// Yours has to lead rather than fall wherever `created_at` puts it. The capsule
/// only shows [kVisibleReactions] of them, so a reaction of yours sitting third
/// would be hidden behind the `+N` — and since the button disappears once you
/// have reacted, nothing else on the screen would be left to tell you that you
/// had.
List<BookCompliment> orderedReactions(
  List<BookCompliment> compliments,
  String? userId,
) {
  if (userId == null) return compliments;
  final mine = <BookCompliment>[];
  final theirs = <BookCompliment>[];
  for (final c in compliments) {
    (c.fromUserId == userId ? mine : theirs).add(c);
  }
  return [...mine, ...theirs];
}

final bookDetailsActionsProvider = Provider((ref) => BookDetailsActions(ref));

class BookDetailsActions {
  final Ref ref;
  BookDetailsActions(this.ref);

  /// Adds, swaps, or withdraws the caller's praise on a book.
  ///
  /// Reads the caller's existing row first so the tap can be classified, then
  /// writes through the unique constraint with an upsert — which is also what
  /// keeps a double tap from throwing. The previous `insert` would raise a
  /// duplicate-key error against the `compliment_uniqueness` constraint, and it
  /// had no `try`/`catch` above it.
  ///
  /// `created_at` is deliberately not touched on a replace: it records when this
  /// person praised the book, and swapping the emoji is not a new praise.
  Future<void> togglePraise(String bookId, String emoji) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final existing = await supabase
        .from('book_compliments')
        .select('id, compliment')
        .eq('book_id', bookId)
        .eq('from_user_id', userId)
        .maybeSingle();

    final decision = praiseTapFor(
      current: existing?['compliment'] as String?,
      tapped: emoji,
    );

    if (decision == PraiseTap.remove) {
      await deleteCompliment(existing!['id'] as String, bookId);
      return;
    }

    await supabase.from('book_compliments').upsert({
      'book_id': bookId,
      'from_user_id': userId,
      'compliment': emoji,
    }, onConflict: 'book_id,from_user_id');

    ref.invalidate(bookComplimentsProvider(bookId));
  }

  Future<void> deleteCompliment(String complimentId, String bookId) async {
    await supabase.from('book_compliments').delete().eq('id', complimentId);
    ref.invalidate(bookComplimentsProvider(bookId));
  }
}
