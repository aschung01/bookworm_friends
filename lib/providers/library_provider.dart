import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
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

/// The status a book carries while its owner is part-way through it.
///
/// Spelled out here rather than as a literal `1`, because two features now depend
/// on agreeing about it: the Friends row's "Reading …" subtitle and
/// `book_info_bottom_sheet`'s status selector.
const int bookStatusReading = 1;

/// The status a book carries once its owner has finished reading it.
const int bookStatusFinished = 2;

/// [shelves] with the finished books left out.
///
/// A finished book is represented by the "Books read" pile at the bottom of the
/// library, so leaving its cover on the shelf as well listed every read book
/// twice. The book keeps its shelf in the database — the details page still
/// shows which shelf it belongs to, and clearing the "Read" status puts the
/// cover straight back where it was.
///
/// That last promise is narrower than it reads, and the promotion that used to sit
/// below was why: `withReadingFirst` moved an in-progress book to the head of its own
/// row, and once a drag had persisted a promoted row, "where it was" was the promoted
/// position rather than the one the reader chose. That function is gone — see
/// [withoutReadingBooks] — so the qualification no longer applies. Filtering here still
/// writes nothing either way: the qualification belonged to the drag, not to this
/// function.
List<Shelf> withoutFinishedBooks(List<Shelf> shelves) => [
  for (final shelf in shelves)
    shelf.copyWith(
      books: shelf.books
          .where((book) => book.status != bookStatusFinished)
          .toList(),
    ),
];

/// [shelves] with the books that are in progress left out.
///
/// The same shape as [withoutFinishedBooks] above, applied to status 1 instead of
/// status 2, and for the same reason: a book at [bookStatusReading] is drawn on the
/// Reading shelf at the top of the library, so leaving its cover on its own plank as
/// well would list every open book twice.
///
/// **This is what retired `withReadingFirst`.** That function moved an in-progress
/// book to the *head of its own row* rather than off the row, which made every shelf
/// two regions with a barrier between them — `readingHeadCount` found the boundary,
/// [clampDropIndex] defended it, and `shelf_row.dart` drew across it at five sites.
/// Once the books leave, every shelf row is one homogeneous region again. It also
/// retired the wart that function documented on itself: edit mode wrote positions
/// from the *promoted* row, so the first drag on a shelf persisted the promotion and
/// clearing a book's reading status left it where the promotion put it.
///
/// The book keeps its `shelf_id`, exactly as a finished one does. The details page
/// still names the shelf it belongs to, and clearing the status puts the cover back
/// on that plank in the position it was authored in — a promise this filter can keep
/// and `withReadingFirst` could not.
///
/// **Shelves are a queue.** That is the decision this filter encodes: a shelf holds
/// what you have not started, the Reading shelf holds what you are reading, and the
/// read pile holds what you have finished. Status decides where a book is drawn, and
/// `shelf_id` only places it while its status is 0.
List<Shelf> withoutReadingBooks(List<Shelf> shelves) => [
  for (final shelf in shelves)
    shelf.copyWith(
      books: shelf.books
          .where((book) => book.status != bookStatusReading)
          .toList(),
    ),
];

/// Every book at [bookStatusReading], across all of [shelves], in the reader's own order.
///
/// **A pure function over shelves, not a provider**, because two callers need it from
/// different places and only one of them can watch a provider: `LibraryPane` is the
/// layer the shell keeps persistent and reads no shell state itself, so it derives
/// this from the `shelves` it was handed. [readingBooksProvider] below is the same
/// answer for callers that do have a `ref`.
///
/// **Ordered by `reading_shelf_index`, which the reader arranges by dragging.** That
/// column exists because this shelf is a view over books drawn from several shelves, so
/// `position` — a book's place within its *own* shelf — cannot order it: two open books
/// off different planks can hold the same one. See [Book.readingShelfIndex].
///
/// **Nulls sort last, with shelf order as the tiebreak.** A book with no stored index has
/// never been arranged — a row written before the column existed, or by a build that
/// predates it — so it falls back to exactly where it used to be drawn: the order the
/// reader arranged their *shelves* in, which was the only authored order there was before
/// this column, and is still the sanest default.
///
/// The tiebreak is applied explicitly rather than leaning on the sort preserving the walk
/// below, because `List.sort` is not guaranteed stable: "falls back to shelf order" has to
/// be a rule or it is luck.
List<Book> readingBooksOf(List<Shelf> shelves) {
  final collected = <Book>[
    for (final shelf in shelves)
      ...shelf.books.where((book) => book.status == bookStatusReading),
  ];
  final ranked = [
    for (var i = 0; i < collected.length; i++)
      (book: collected[i], shelfOrder: i),
  ];
  ranked.sort((a, b) {
    final ai = a.book.readingShelfIndex;
    final bi = b.book.readingShelfIndex;
    if (ai != bi) {
      if (ai == null) return 1;
      if (bi == null) return -1;
      final byIndex = ai.compareTo(bi);
      if (byIndex != 0) return byIndex;
    }
    return a.shelfOrder.compareTo(b.shelfOrder);
  });
  return [for (final entry in ranked) entry.book];
}

/// How many of [shelf]'s books actually stand on its plank.
///
/// The count the shelf's name tab shows, and therefore **the number a reader will
/// check by scrolling the row to its end.** It has to be the length of the row they
/// are looking at, not the size of the shelf in the database.
///
/// **Excludes both statuses, and that is the whole point.** A finished book is drawn
/// in the read pile ([withoutFinishedBooks]) and an in-progress one on the Reading
/// shelf ([withoutReadingBooks]); counting either would advertise covers that are
/// provably not on this plank. The visible consequence is that opening a book drops
/// its shelf's count by one, which is correct — the book has left the queue.
///
/// A function of one shelf rather than a getter on [Shelf], because it is a
/// statement about how the *library view* draws a shelf, and the model has no
/// opinion about that. It is also what lets the two ends of the shelf-tab hero
/// flight — the library and the book-details page — agree without sharing a widget.
int shelvedBookCount(Shelf shelf) => shelf.books
    .where(
      (book) =>
          book.status != bookStatusFinished && book.status != bookStatusReading,
    )
    .length;

/// Where a book entering [bookStatusReading] lands on the Reading shelf: one before
/// whatever is currently at its head, or 0 when nothing is open.
///
/// **Opening a book puts it at the head, not the tail.** The Reading row clips at about
/// three covers behind `ShelfEdgeFades`, so appending would land a newly opened book
/// off-screen — and the shelf visibly changing is the only feedback that opening a book did
/// anything, which is the same reasoning the zero state rests on.
///
/// `min - 1` rather than shifting every other book up by one: it costs a single UPDATE
/// instead of *n*, and cannot half-apply. The values drift negative over time, which is
/// harmless for ordering — [readingBooksOf] only compares them — and
/// [LibraryNotifier.reorderReadingBooks] renumbers the set to `0…n-1` on the next drag.
///
/// Nulls are ignored when taking the minimum, because a book with no stored index sorts
/// *last* and so is not at the head for a new book to get in front of. [excluding] omits one
/// book from the reckoning, so re-confirming the status of a book already in progress does
/// not shuffle it to the front; a book being inserted has nothing to exclude.
///
/// A pure function over the reading set rather than a method that fetches one, so the rule
/// can be tested without a database — the arithmetic is the whole substance here, and the
/// query around it is one line.
int readingHeadIndexFor(List<Book> readingBooks, {String? excluding}) {
  final indices = <int>[
    for (final book in readingBooks)
      if (book.id != excluding)
        if (book.readingShelfIndex case final index?) index,
  ];
  if (indices.isEmpty) return 0;
  return indices.reduce((a, b) => a < b ? a : b) - 1;
}

/// [index] confined to the region of a row a book is allowed to land in.
///
/// **Now a single region, and this function is what is left of two.** A shelf used to
/// be drawn as the books in progress followed by everything else, with a barrier
/// between them that a drag could not cross; `withReadingFirst` built that head and
/// `readingHeadCount` measured it. Both are gone — [withoutReadingBooks] takes the
/// in-progress books off the shelf entirely, so every row is homogeneous and the only
/// clamp still needed is to the row's own ends.
///
/// Kept as a function rather than inlined at the call site because the drawing and the
/// drag have to agree about where a book may land, and one definition is how that was
/// guaranteed before. It is also the seam to widen again if a shelf ever grows regions
/// for some other reason.
///
/// [rowLength] is measured on the row **with the dragged book taken out**, because that
/// is the row an insertion index refers to.
///
/// **Clamped rather than corrected on release.** The index drives the gap the row
/// opens to preview a drop, so clamping here is what makes the preview the truth. A
/// gap that opens where the book cannot land is a promise the drop then breaks, and
/// the book visibly springs somewhere else.
int clampDropIndex(int index, {required int rowLength}) =>
    index.clamp(0, rowLength);

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

  /// Reorders the Reading shelf optimistically, then persists.
  ///
  /// **Nothing is reordered — only renumbered**, which is the whole difference from
  /// [reorderBooksInShelf]. The Reading shelf is a *derived* row: every book stays in the
  /// shelf it belongs to, and [readingBooksOf] sorts them by `reading_shelf_index` on the
  /// way out. So this writes an index onto each book where it already sits, and the row
  /// rebuilds in the new order.
  ///
  /// Unlike [reorderBooksInShelf], [bookIds] is the **whole** reading set rather than only
  /// what the caller can see. That method's caveat exists because finished books are hidden
  /// from a shelf and must keep their stored position; here the row clips visually but
  /// every open book is in its list, so there is nothing absent to protect.
  ///
  /// **`position` is never written.** That is what keeps `withoutReadingBooks`' promise
  /// that clearing a book's status puts it back on its own plank in the position it was
  /// authored in — see [Book.readingShelfIndex].
  Future<void> reorderReadingBooks(List<String> bookIds) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final indexOf = {for (var i = 0; i < bookIds.length; i++) bookIds[i]: i};
    final updated = [
      for (final shelf in current)
        shelf.copyWith(
          books: [
            for (final book in shelf.books)
              if (indexOf[book.id] case final index?)
                book.copyWith(readingShelfIndex: index)
              else
                book,
          ],
        ),
    ];
    state = AsyncData(updated);

    try {
      for (var i = 0; i < bookIds.length; i++) {
        await supabase
            .from('books')
            .update({'reading_shelf_index': i})
            .eq('id', bookIds[i]);
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

  /// Moves a book to another shelf, at a chosen place in that shelf's row,
  /// optimistically, then persists.
  ///
  /// [orderedBookIds] is the target shelf's row as it should read *after* the drop,
  /// the moved book included. A place rather than an append, because a drag can now
  /// be dropped between two covers on a shelf it did not come from, and "where the
  /// reader let go" is a fact only the receiving shelf knows.
  ///
  /// Like [reorderBooksInShelf] it only has to cover the books the caller can see:
  /// whatever it leaves out is a finished book, hidden from the shelves, and keeps
  /// its stored position.
  Future<void> moveBookToShelf(
    String bookId,
    String targetShelfId,
    List<String> orderedBookIds,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return;

    Book? found;
    for (final shelf in current) {
      for (final b in shelf.books) {
        if (b.id == bookId) found = b;
      }
    }
    if (found == null || found.shelfId == targetShelfId) return;
    final book = found;
    final sourceShelfId = book.shelfId;

    final updated = current.map((shelf) {
      if (shelf.id == sourceShelfId) {
        return shelf.copyWith(
          books: shelf.books.where((b) => b.id != bookId).toList(),
        );
      }
      if (shelf.id == targetShelfId) {
        final byId = {
          for (final b in shelf.books) b.id: b,
          bookId: book.copyWith(shelfId: targetShelfId),
        };
        final ordered = <Book>[
          for (var i = 0; i < orderedBookIds.length; i++)
            if (byId.remove(orderedBookIds[i]) case final b?)
              b.copyWith(position: i),
        ];
        // Whatever wasn't listed is hidden from this shelf, so where it lands in
        // the list doesn't matter — only that it survives the move.
        return shelf.copyWith(books: [...ordered, ...byId.values]);
      }
      return shelf;
    }).toList();
    state = AsyncData(updated);

    try {
      await supabase
          .from('books')
          .update({'shelf_id': targetShelfId})
          .eq('id', bookId);
      for (var i = 0; i < orderedBookIds.length; i++) {
        await supabase
            .from('books')
            .update({'position': i})
            .eq('id', orderedBookIds[i]);
      }
    } catch (e) {
      EasyLoading.showError(
        AppLocalizations.of(navigatorKey.currentContext!).moveFailed,
      );
      ref.invalidateSelf();
    }
  }
}

/// Every finished book, newest finish date first.
///
/// Deliberately **unfiltered**, where this used to take a year and a month. The
/// read view groups by month and filters by year on the client, and it needs the
/// whole set to do either: the year capsules are the set of years you have
/// finished books in, which a year-filtered query cannot tell you. It is also what
/// the library itself wants — whether to offer "add your first book" depends on
/// whether you have read anything at all, not on whether the current filter
/// happens to exclude it.
///
/// Unbounded by design, and bounded in practice by how much one person has read.
final finishedBooksProvider = FutureProvider.autoDispose<List<Book>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final data = await supabase
      .from('books')
      .select()
      .eq('user_id', userId)
      .eq('status', bookStatusFinished)
      .order('finish_date', ascending: false);
  return data.map((b) => Book.fromJson(b)).toList();
});

/// The books the reader has open right now, across every shelf.
///
/// **Derived rather than queried.** [libraryProvider] already holds every shelf with its
/// books, so a second round trip would buy nothing but a second answer free to disagree
/// with the shelves on screen. Unlike [finishedBooksProvider] this is not sorted by date:
/// a book being read has no finish date to sort by, and shelf order is the order the
/// reader themselves put them in.
///
/// Read by the Library Card, which draws these at the front of its shelf wearing a
/// bookmark and **does not count them** — the hero figure counts books read. See
/// `CardCoverRow.reading`.
final readingBooksProvider = Provider.autoDispose<List<Book>>((ref) {
  final shelves = ref.watch(libraryProvider).valueOrNull ?? const <Shelf>[];
  return [
    for (final shelf in shelves)
      ...shelf.books.where((book) => book.status == bookStatusReading),
  ];
});

/// The same, for someone else's library. Keyed by user id alone.
///
/// **Kept alive on purpose, against the `autoDispose` the rest of this file uses.**
/// The family is keyed by user id and revisiting the same reader is the common
/// case: the Friends sheet is the shell's one switcher, so moving between two
/// friends and back is three taps in the same list. Left to `autoDispose` each of
/// those taps was a fresh round trip and a fresh loading state, which the pane
/// above it has to draw as *something* — and the honest something is the outgoing
/// library held and faded, which only works if the incoming one is usually already
/// there.
///
/// The memory this costs is one list of shelves per friend looked at in a session,
/// which is bounded by how many people one reader follows.
final userFinishedBooksProvider = FutureProvider.autoDispose
    .family<List<Book>, String>((ref, userId) async {
      ref.keepAlive();
      final data = await supabase
          .from('books')
          .select()
          .eq('user_id', userId)
          .eq('status', bookStatusFinished)
          .order('finish_date', ascending: false);
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

  /// Book ids whose cover colour has already been written this session.
  ///
  /// [recordCoverColor] deliberately does not invalidate anything, so the `Book`
  /// objects on screen keep their null `coverColor` until the next fetch and every
  /// later decode of the same book would look like a book that still needs one. A
  /// shelf scrolled past twice, or the same book shown on a shelf and in the read
  /// grid at once, would otherwise write two or three times.
  ///
  /// Safe as instance state because [libraryActionsProvider] is a plain [Provider]
  /// and so lives as long as the container. It is a write-once cache, not a source
  /// of truth: losing it costs one redundant UPDATE.
  final Set<String> _coverColorWritten = <String>{};

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
    List<String> authors = const [],
    int? pageCount,
    Color? coverColor,
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
        // A book saved straight into "reading" needs a place on the Reading shelf like any
        // other, or it would arrive with a null index and sort to the end of a row it is
        // supposed to be heading. See [_readingHeadIndex].
        'reading_shelf_index': status == bookStatusReading
            ? await _readingHeadIndex()
            : null,
        'start_date': dates.startDate != null
            ? DateFormat('yyyy-MM-dd').format(dates.startDate!)
            : null,
        'finish_date': dates.finishDate != null
            ? DateFormat('yyyy-MM-dd').format(dates.finishDate!)
            : null,
        // Captured at save time, from the search result the user picked. The
        // catalogue was already asked; not storing this is what forced the detail
        // page to ask again on every open, and made an author aggregate
        // impossible.
        'authors': authors,
        // Nullable on purpose: null means "no credible count", which the book's
        // drawn thickness treats differently from a real number by falling back to
        // a hash. Kakao never supplies one, so for most Korean titles this stays
        // null and the shelf looks exactly as it did before.
        'page_count': pageCount,
        // The cover the reader just picked, resolved by the sheet that showed it to
        // them. Populated for the ordinary add, because `showBookInfoBottomSheet` draws
        // that cover and reports its sample; null when the thumbnail had not decoded by
        // the time they tapped Save, or when the book has no thumbnail at all.
        //
        // Null costs nothing: the book falls back to a swatch derived from its ISBN
        // until something decodes its cover and reports the sample back through
        // [recordCoverColor]. It is worth filling in here anyway, because a book saved
        // as *finished* never reaches the shelves -- `withoutFinishedBooks` keeps it off
        // them -- so the path that colours most books would never see it, and it would
        // sit in the read pile under an ISBN swatch instead.
        'cover_color': coverColor == null
            ? null
            : bookCoverColorToHex(coverColor),
      });

      ref.invalidate(libraryProvider);
      _invalidateFinishedBooks();
      EasyLoading.showSuccess(l10n.bookAdded);
    } catch (e) {
      EasyLoading.showError(l10n.bookAddFailed);
    }
  }

  /// Fills in `books.cover_color` from a cover that has just been decoded.
  ///
  /// The backfill for rows written before the column existed, and for every row
  /// added by a path that had no decoded image to sample. Called from a *render*
  /// path — [BookWidget.onCoverSampled] — which dictates everything about how it
  /// behaves:
  ///
  ///  * **Silent.** No [EasyLoading], no rethrow, no error surfaced. Nothing the
  ///    reader did caused this write, so nothing they see should depend on it: a
  ///    book scrolling into view on a train with no signal must not raise a
  ///    failure toast over the shelf. This is the one write in this class that
  ///    swallows its error on purpose.
  ///  * **No invalidation.** Refetching the library because a cosmetic column was
  ///    filled in would rebuild every shelf and re-resolve every image, from a
  ///    callback that fires *while the first frame of that image is being drawn*.
  ///    The value is already on screen — it came from the pixels. The database is
  ///    just catching up, and the next ordinary fetch will carry it.
  ///  * **Idempotent, twice over.** Skipped outright for a book that already has a
  ///    colour, and remembered in [_coverColorWritten] so the same book decoding
  ///    again in another widget does not write again.
  ///
  /// Only for books the signed-in user owns. A friend's library renders through
  /// the same [BookWidget], so without this check scrolling their shelves would
  /// attempt to write rows that are not yours — rejected by RLS, but the right
  /// place to decline is here, before the request.
  Future<void> recordCoverColor(Book book, Color color) async {
    if (book.coverColor != null) return;
    if (_coverColorWritten.contains(book.id)) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null || book.userId != userId) return;

    // Claimed before the await, not after: two books' decodes can land in the
    // same frame, and an async gap between the check and the mark is long enough
    // for both to pass it.
    _coverColorWritten.add(book.id);
    try {
      await writeCoverColor(book.id, color);
    } catch (_) {
      // Left in the written set. A retry would need a fresh decode to be worth
      // anything, and the cost of not retrying is a book that keeps deriving its
      // tone from its ISBN -- which is exactly what it did before this column
      // existed.
    }
  }

  /// The write itself, split from the rules above it.
  ///
  /// A seam, and the reason for it is that the rules are the whole substance of
  /// [recordCoverColor] — who may write, when, and how often — while the UPDATE is
  /// one line. Overriding this in a test asserts all four rules against the real
  /// method rather than against a reimplementation of it.
  @visibleForTesting
  Future<void> writeCoverColor(String bookId, Color color) => supabase
      .from('books')
      .update({'cover_color': bookCoverColorToHex(color)})
      .eq('id', bookId);

  /// Records which shop the owner's copy of a book lives in, or clears it when
  /// [storeKey] is null.
  ///
  /// **Inferred from a tap, which is the only signal available.** Ownership cannot
  /// be detected: `canLaunchUrl` proves a reader app is installed, never that this
  /// book is in it. So tapping a shop is taken as "my copy is there", which is
  /// right often enough to be useful and wrong often enough that clearing has to
  /// be one tap away — somebody checking a price is recorded identically to
  /// somebody buying. Passing null is that escape hatch.
  ///
  /// Only for books the signed-in user owns, and the guard is here rather than
  /// left to RLS for the same reason [recordCoverColor]'s is: a friend's book
  /// renders through the same sheet, so without it every tap on their book would
  /// fire a request that is certain to be refused.
  ///
  /// Invalidates, unlike [recordCoverColor]. The value is not already on screen —
  /// it *is* the screen: the sheet retitles itself and collapses to one action, so
  /// the page has to see the new row.
  Future<void> setReaderApp(Book book, String? storeKey) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null || book.userId != userId) return;
    if (book.readerApp == storeKey) return;

    try {
      await supabase
          .from('books')
          .update({'reader_app': storeKey})
          .eq('id', book.id);
      ref.invalidate(libraryProvider);
      _invalidateFinishedBooks();
    } on PostgrestException catch (error) {
      // **Narrowed, because the blanket swallow below hid a real defect for the
      // whole life of this feature.** `books.reader_app` was missing from
      // production — its migration had never been applied — so every one of these
      // writes failed and said nothing. Reading degraded harmlessly (an absent
      // column reads as null, which is the acquire list), so the symptom was that
      // no shop was ever remembered: no "Your copy" title, no check, no way to
      // open a copy. The feature's entire second half was dead and looked like a
      // design choice.
      //
      // A missing column or a refused policy is a deployment bug, not a transient
      // failure, so it fails loudly in debug and stays silent in release. `42703`
      // is Postgres' undefined_column; `PGRST204` is PostgREST's own for a column
      // absent from its schema cache.
      assert(
        error.code != '42703' && error.code != 'PGRST204',
        'setReaderApp could not write books.reader_app — this database is '
        'missing the column. Apply '
        'supabase/migrations/20260915130000_book_reader_app.sql. $error',
      );
    } catch (_) {
      // Swallowed on purpose, and this is the one write in this class that says
      // nothing when it fails. Everything the reader asked for has already
      // happened — the shop opened — and this is a note-to-self about where their
      // copy lives. An error toast would report the failure of something they did
      // not ask for, over a book they are no longer looking at.
    }
  }

  /// Where a book entering [bookStatusReading] lands, read off the library as it stands.
  ///
  /// The rule itself is [readingHeadIndexFor]; this only supplies it with the reading set.
  Future<int> _readingHeadIndex({String? excluding}) async {
    final shelves = await ref.read(libraryProvider.future);
    return readingHeadIndexFor(readingBooksOf(shelves), excluding: excluding);
  }

  Future<void> updateBookStatus(
    String bookId,
    int status, {
    DateTime? startDate,
    DateTime? finishDate,

    /// The reading position as a fraction 0..1, or null to leave the column alone.
    ///
    /// **Null means "do not write", not "clear"**, which is the one place this
    /// parameter differs from the dates beside it. `start_date` and `finish_date`
    /// are *derived* from the status here, so passing null for them is a real
    /// instruction and nulls the column. A position is not derived from anything:
    /// it is a fact about the text that the status has no opinion on, so a reader
    /// changing a date must not have their bookmark thrown away as a side effect,
    /// and a book put back on the shelf and reopened should be where they left it.
    ///
    /// Which also means there is currently no way to *clear* a position. That is
    /// deliberate rather than missing: the wheel's lowest stop is 0%, which means
    /// "at the very start" and is an answer, not an erasure.
    double? progress,

    /// Which unit [progress] arrived in: the page the reader typed, or null when they
    /// answered in percent.
    ///
    /// **Written only when [progress] is**, and inside that branch null is a real
    /// instruction — it clears the column. That is the opposite of what null means for
    /// [progress] itself, and deliberately so: answering in percent is *news* about
    /// provenance, so a book last set to p.200 and then set to 46% must stop claiming
    /// the reader said p.200. Outside the branch the column is not mentioned, so a
    /// date edit leaves the page alone exactly as it leaves the fraction alone.
    int? progressPage,
  }) async {
    final dates = clampReadingDates(
      startDate: startDate,
      finishDate: finishDate,
    );

    EasyLoading.show();
    try {
      // A place on the Reading shelf exists only while the book is in progress, so this
      // is cleared on the way out. The local `Book` keeps its stale value, which is
      // deliberate and harmless — see [Book.readingShelfIndex].
      final readingShelfIndex = status == bookStatusReading
          ? await _readingHeadIndex(excluding: bookId)
          : null;

      await supabase
          .from('books')
          .update({
            'status': status,
            'reading_shelf_index': readingShelfIndex,
            'start_date': dates.startDate != null
                ? DateFormat('yyyy-MM-dd').format(dates.startDate!)
                : null,
            'finish_date': dates.finishDate != null
                ? DateFormat('yyyy-MM-dd').format(dates.finishDate!)
                : null,
            // One UPDATE, one Save. The key is omitted rather than sent as null
            // when there is nothing to write — see [progress]. The page rides in
            // the same branch so the two can never disagree about which unit the
            // stored fraction came from.
            if (progress != null) ...{
              'progress': progress,
              'progress_page': progressPage,
            },
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
