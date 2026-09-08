import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// That last promise is narrower than it reads, and [withReadingFirst] below is
/// why: once a drag has persisted a promoted row, "where it was" is the promoted
/// position rather than the one the reader originally chose. Filtering here still
/// writes nothing — the qualification belongs to the drag, not to this function.
List<Shelf> withoutFinishedBooks(List<Shelf> shelves) => [
  for (final shelf in shelves)
    shelf.copyWith(
      books: shelf.books
          .where((book) => book.status != bookStatusFinished)
          .toList(),
    ),
];

/// How many of [shelf]'s books actually stand on its plank.
///
/// The count the shelf's name tab shows, and therefore **the number a reader will
/// check by scrolling the row to its end.** It has to be the length of the row they
/// are looking at, not the size of the shelf in the database: a finished book keeps
/// its `shelf_id` but is drawn in the read pile instead of on the plank
/// ([withoutFinishedBooks]), so counting the raw list would advertise covers that
/// are provably not there.
///
/// A function of one shelf rather than a getter on [Shelf], because it is a
/// statement about how the *library view* draws a shelf, and the model has no
/// opinion about that. It is also what lets the two ends of the shelf-tab hero
/// flight — the library and the book-details page — agree without sharing a widget.
int shelvedBookCount(Shelf shelf) =>
    shelf.books.where((book) => book.status != bookStatusFinished).length;

/// [shelves] with each shelf's in-progress books moved to the front of its row.
///
/// A display transform, exactly like [withoutFinishedBooks] above it, and applied
/// in the same place — see `LibraryPane.build`, which composes the two.
/// **`Book.position` is never written by this.** What is stored stays the order
/// the reader arranged; what is drawn puts the book they are actually reading
/// where they will see it first.
///
/// **Why the view needs it at all.** Two of the three shelf densities compress
/// every book that is not in progress — shingled in `ShelfDensity.leaning`,
/// spine-on in `ShelfDensity.spines` — so a reading book left in the middle of a
/// row would be compressed along with the rest and, on a long shelf, sit off the
/// end of it. Promotion is what makes the compression safe to apply. It runs in
/// `ShelfDensity.covers` too, so that switching density changes how a shelf is
/// drawn and never what order it is in.
///
/// **A stable partition, not a sort.** `List.sort` is not stable in Dart, so
/// sorting on a status key would let two books that compare equal swap places for
/// no reason a reader could account for. Both groups keep their authored order.
///
/// **One consequence worth knowing, because it is a real cost.** Edit mode draws
/// the promoted row, and `LibraryNotifier.reorderBooksInShelf` writes positions
/// from the row it is handed — so the first drag on a shelf persists the
/// promotion into `position`, and after that, clearing a book's reading status
/// leaves it where the promotion put it rather than where it originally sat. That
/// is narrower than what [withoutFinishedBooks] promises for the "Read" status,
/// and the difference is deliberate: a drag is an authoring act, the reader was
/// looking at the promoted row when they made it, and writing back an order they
/// were never shown would persist an arrangement nobody chose.
List<Shelf> withReadingFirst(List<Shelf> shelves) => [
  for (final shelf in shelves)
    shelf.copyWith(
      books: [
        ...shelf.books.where((book) => book.status == bookStatusReading),
        ...shelf.books.where((book) => book.status != bookStatusReading),
      ],
    ),
];

/// How many books stand at the head of [shelf] because they are in progress.
///
/// Where the reading block ends and the compressible remainder begins. Read by
/// `ShelfBooksRow` to place the compressed group, and by `_ShelfRowState` to clamp
/// a drag's drop index to the zone the dragged book belongs to — one function, so
/// the drawing and the drag cannot disagree about the boundary.
///
/// **Defined on an already-promoted shelf**, hence `takeWhile` and not `where`: it
/// measures the *leading run*, so a shelf that has not been through
/// [withReadingFirst] gets a wrong answer rather than an error. Callers get their
/// shelves from `LibraryPane`, which promotes them before anything sees them.
int readingHeadCount(Shelf shelf) =>
    shelf.books.takeWhile((book) => book.status == bookStatusReading).length;

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
        // The cover the user just picked, averaged, if whatever showed it to them
        // had decoded it by the time they saved. Null is ordinary and costs
        // nothing: the book falls back to a swatch derived from its ISBN until
        // something decodes its cover and reports the sample back.
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
