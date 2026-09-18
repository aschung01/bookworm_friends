/// Resolving an exact OverDrive title id for a book, so the Libby row can name a
/// title instead of running a search.
///
/// **Why this is a separate file**, and why it is not in `store_links_service.dart`:
/// same reason as `apple_books_lookup.dart`. The link builder is pure string
/// algebra over ids the app already holds; this needs the network, so it stays out.
///
/// **Two requests, and the split is deliberate.** OverDrive publishes no global
/// search API — `thunder`'s `/v2/media/search` refuses outright with *"Must specify
/// at least 1 libraryKey"*, and asking the reader for their library is a feature,
/// not a URL fix. But `overdrive.com/search?q=` **is** global, needs no key, and
/// its results page exposes `/media/<id>/` links whose ids are global too (verified:
/// the same id resolves under `sfpl`, `lapl`, `chipublib`). So:
///
///  1. **Harvest candidate ids from the search page's HTML.** Fragile, and known
///     to be.
///  2. **Ask `thunder`'s keyless `media/bulk` about them**, which answers clean
///     JSON — `id`, `type`, `title`, `firstCreatorName`.
///
/// **The fragility fails safe, which is the only reason it is acceptable.** Every
/// judgement about *which* book we found is made against the JSON in step 2, never
/// against the HTML. If OverDrive changes its markup, step 1 yields no candidates,
/// the lookup returns [OverDriveResult.none] and the Libby row degrades to the
/// search it does today. A markup change can therefore cause a **miss**, never a
/// wrong book.
///
/// **Two outcomes, not three — the asymmetry with Apple is intentional.**
/// `appleBooksLookup` distinguishes "Apple does not sell this" from "we could not
/// ask", because a confirmed absence makes the Apple row *disappear*: its fallback
/// opens the Books app on an empty search tab, so offering it is worse than
/// offering nothing. Libby has no such problem — its fallback,
/// `overdrive.com/search?q=`, is a real results page that reads honestly. Nothing
/// here acts differently on "no edition" versus "could not ask", so inventing the
/// distinction would be a state no caller reads. It would also be **unsafe to
/// trust**, because with candidates coming from HTML we cannot honestly tell a
/// genuine zero-result page from a markup change.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bookworm_friends/services/book_match.dart';

/// How long to wait before giving up and letting the caller degrade.
///
/// Short on purpose, and shared with the Apple lookup's reasoning: this runs while
/// the reader waits for a sheet to appear after tapping the app-bar icon, and an
/// exact link is a *nicety*. A slow network must cost a better URL, never a
/// visibly stalled tap. `overdrive.com` was also observed dropping a connection
/// outright under rapid repeat queries, so this path has to be genuinely
/// disposable.
const _timeout = Duration(seconds: 4);

/// How many candidates to carry from the search page into the bulk request.
///
/// The page yields 24 for a normal query, which is where this number comes from:
/// it is "one page", not a guess. Keeping the cap explicit matters because the ids
/// go into a URL.
const _maxCandidates = 24;

/// Which kind of thing a library lends.
///
/// **`ebook` and `audiobook` are the complete set** for our purposes, and the
/// third case people expect — a physical book — does not exist anywhere in
/// OverDrive. Its `type.id` takes only `ebook`, `audiobook` and `magazine`; across
/// 100 results for one author at one library the distribution was
/// `{ebook: 62, audiobook: 38}` and nothing else. A library's print catalogue lives
/// in a different system entirely (BiblioCommons and friends), which Libby cannot
/// see and does not link to.
enum OverDriveFormat { ebook, audiobook }

/// The outcome of asking OverDrive about one book.
///
/// [titleId] is non-null exactly when [format] is, and their presence is the whole
/// signal: an id means the Libby row can name this title, and no id means it falls
/// back to a search.
class OverDriveResult {
  const OverDriveResult(this.titleId, this.format);
  const OverDriveResult.none() : titleId = null, format = null;

  final String? titleId;
  final OverDriveFormat? format;

  bool get found => titleId != null;

  @override
  String toString() => 'OverDriveResult($titleId, ${format?.name})';
}

/// Asks OverDrive for the global title id of a book, if any library lends it.
///
/// **Never send an ISBN.** Alone among every shop this app links to, OverDrive's
/// web search does not index them: `overdrive.com/search?q=9780143127741` returns
/// *0 results* where the title and author return 462. Passing the ISBN-preferring
/// `term` that the other shops share would send every properly-scanned book to an
/// empty page. Matching later is on title and author for the same underlying
/// reason — **an ebook's ISBN is not its print ISBN** (`9781101608302` versus
/// `9780143127741` for the same work), so the number in our column frequently
/// belongs to an edition OverDrive has never heard of.
///
/// Never throws. Offline, a timeout, a dropped connection, a markup change and a
/// book no library lends all produce [OverDriveResult.none], which costs the reader
/// a better URL and nothing else.
Future<OverDriveResult> overDriveLookup({
  required String title,
  required List<String> authors,
  http.Client? client,
}) async {
  final author = authors.isEmpty ? '' : authors.first;
  final query = [
    title,
    author,
  ].where((s) => s.trim().isNotEmpty).join(' ').trim();
  // An author is required to confirm a match, so a book with none can never
  // produce a result and the requests would be pure waste.
  if (query.isEmpty || author.trim().isEmpty) {
    return const OverDriveResult.none();
  }

  Future<String?> get(Uri uri) async {
    final response = await (client?.get(uri) ?? http.get(uri)).timeout(
      _timeout,
    );
    if (response.statusCode != 200) return null;
    // Decoded explicitly as UTF-8 for the same reason as the Apple lookup: titles
    // are compared here, and a Latin-1 fallback mangles every non-ASCII one into
    // something that matches nothing.
    return utf8.decode(response.bodyBytes);
  }

  try {
    final html = await get(
      Uri.https('www.overdrive.com', '/search', {'q': query}),
    );
    if (html == null) return const OverDriveResult.none();

    final candidates = overDriveCandidateIds(html);
    if (candidates.isEmpty) return const OverDriveResult.none();

    final json = await get(
      Uri.https('thunder.api.overdrive.com', '/v2/media/bulk', {
        'titleIds': candidates.join(','),
      }),
    );
    if (json == null) return const OverDriveResult.none();

    return overDriveMatchFromBulkJson(
      json,
      candidates: candidates,
      title: title,
      author: author,
    );
  } catch (_) {
    return const OverDriveResult.none();
  }
}

/// Global title ids linked from a search results page, in the order the page
/// listed them — which is OverDrive's own relevance order and is used as the
/// tie-break below.
///
/// Deliberately a blunt scan for `/media/<digits>` rather than any attempt to
/// parse the document: there is nothing to gain from understanding the markup when
/// every candidate is verified against JSON afterwards, and a blunt scan has fewer
/// ways to break. Duplicates are collapsed because a result links its own id more
/// than once (cover, title, byline).
///
/// A genuine miss really does yield nothing — a nonsense query returns a 200 page
/// with **zero** `/media/` links, so there is no navigational chrome to filter out.
List<String> overDriveCandidateIds(String html) {
  final seen = <String>[];
  for (final match in RegExp(r'/media/(\d+)').allMatches(html)) {
    final id = match.group(1)!;
    if (seen.contains(id)) continue;
    seen.add(id);
    if (seen.length == _maxCandidates) break;
  }
  return seen;
}

/// The best matching title in a `media/bulk` response, or [OverDriveResult.none].
///
/// Split from the request so the response shape is testable without a network.
/// The shape, confirmed against the live endpoint — note it is a bare list, not an
/// object with a `results` key:
///
/// ```json
/// [ { "id": 1344919,
///     "type": { "id": "ebook", "name": "eBook" },
///     "title": "The Hard Thing About Hard Things",
///     "firstCreatorName": "Ben Horowitz" } ]
/// ```
///
/// **Ranking is ours, because the response does not preserve the order of the ids
/// it was sent.** Twenty ids came back reordered, so "the first record" means
/// nothing. Two rules, in order:
///
///  1. **An ebook beats an audiobook.** This is a reading app; where a library
///     lends both, the ebook is the one to open.
///  2. **Otherwise the search page's order wins**, that being the only relevance
///     signal available.
///
/// **Audiobooks are accepted, and that was a bug worth fixing before it shipped.**
/// An earlier plan filtered to `ebook` only. Libraries lend audiobooks as
/// first-class stock — for one title at one library, 4 ebook licences against 19
/// audiobook — so an ebook-only filter would have reported "no edition" for a book
/// the library demonstrably lends, and for audio-only titles would have done so
/// every time.
OverDriveResult overDriveMatchFromBulkJson(
  String body, {
  required List<String> candidates,
  required String title,
  required String author,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const OverDriveResult.none();
  }
  if (decoded is! List) return const OverDriveResult.none();

  OverDriveResult? best;
  var bestRank = -1;
  for (final record in decoded.whereType<Map<String, dynamic>>()) {
    final format = _formatOf(record['type']);
    // `magazine`, and anything OverDrive adds later, is not a book.
    if (format == null) continue;

    final matched = sameBook(
      candidateTitle: record['title'],
      candidateAuthor: record['firstCreatorName'],
      title: title,
      author: author,
    );
    if (!matched) continue;

    // `id` is a number in the JSON but a path segment in the URL.
    final id = record['id'];
    if (id is! int && id is! String) continue;
    final titleId = '$id';

    final rank = candidates.indexOf(titleId);
    if (rank < 0) continue; // Not one we asked about.

    if (best == null || _beats(format, rank, best.format!, bestRank)) {
      best = OverDriveResult(titleId, format);
      bestRank = rank;
    }
  }
  return best ?? const OverDriveResult.none();
}

/// Whether one matched candidate should displace another. Format first, then the
/// search page's order.
bool _beats(
  OverDriveFormat format,
  int rank,
  OverDriveFormat bestFormat,
  int bestRank,
) {
  if (format != bestFormat) return format == OverDriveFormat.ebook;
  return rank < bestRank;
}

/// The format of a `type` object, or null for anything that is not a book.
OverDriveFormat? _formatOf(Object? type) {
  if (type is! Map) return null;
  return switch (type['id']) {
    'ebook' => OverDriveFormat.ebook,
    'audiobook' => OverDriveFormat.audiobook,
    _ => null,
  };
}
