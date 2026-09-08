import 'package:bookworm_friends/models/book.dart';

/// What the Friends list shows about one friend, beyond their name.
///
/// Two facts, and they come from the same rows: what they are part-way through, and
/// how many books they have finished. The drawing (`EVERYONE` in `decided.html`) puts
/// the first in the row's subtitle and the second at its trailing edge in brand green.
class FriendReading {
  /// Books at `bookStatusReading`, newest start first.
  ///
  /// A list, not a single book, because the drawing has a friend reading two at once
  /// — `minho` is `Reading Snow · Circe`. Empty is a drawn state too, and renders as
  /// "nothing in progress" with **no** cover.
  final List<Book> inProgress;

  /// How many books this friend has finished.
  ///
  /// The same definition as the Library Card's hero figure — `status ==
  /// bookStatusFinished` — so the two cannot show a different number for the same
  /// person.
  final int finishedCount;

  const FriendReading({this.inProgress = const [], this.finishedCount = 0});

  /// What a friend with nothing visible looks like.
  ///
  /// Reached in two different ways that must render identically: a friend who has no
  /// books, and a friend absent from the response entirely. The second happens when
  /// `is_profile_visible` excludes them — RLS filters per row, so a friend who has
  /// gone private simply is not in the result rather than erroring.
  static const none = FriendReading();

  /// Whether there is anything to say in the row's subtitle beyond a placeholder.
  bool get hasInProgress => inProgress.isNotEmpty;
}

/// Groups a flat list of books into per-owner reading summaries.
///
/// A pure function over rows, split out from the query so the grouping is a unit test
/// rather than something only an integration test can reach — the same split that made
/// `libraryCardStats` cheap to trust.
///
/// [friendIds] is passed in so that **every** friend gets an entry, including ones with
/// no rows at all. A map that silently omits them would make the widget handle a
/// missing key and an empty value differently, and one of those two paths would go
/// untested.
Map<String, FriendReading> groupFriendReading(
  Iterable<String> friendIds,
  List<Book> books, {
  required int readingStatus,
  required int finishedStatus,
}) {
  final inProgress = <String, List<Book>>{};
  final finished = <String, int>{};

  for (final book in books) {
    if (book.status == readingStatus) {
      inProgress.putIfAbsent(book.userId, () => []).add(book);
    } else if (book.status == finishedStatus) {
      finished[book.userId] = (finished[book.userId] ?? 0) + 1;
    }
  }

  return {
    for (final id in friendIds)
      id: FriendReading(
        inProgress: inProgress[id] ?? const [],
        finishedCount: finished[id] ?? 0,
      ),
  };
}
