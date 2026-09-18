/// Resolving an exact Apple Books URL for a book, which takes a request.
///
/// **Why this is a separate file.** `store_links_service.dart` is pure string
/// algebra over ids the app already holds, and it stays that way: it takes a URL
/// and asks no questions about where it came from. Apple is the one shop whose
/// per-book URL cannot be derived from anything the app knows, because the id in
/// `books.apple.com/../id731076045` is Apple's own and appears in no catalogue the
/// app already reads. So it has to be looked up, and the lookup lives here rather
/// than contaminating the algebra with a network call.
///
/// The endpoint is the iTunes Search API, which is **keyless** — the same property
/// that makes the Google Books volume-id lookup affordable.
///
/// **Three outcomes, not two, and the third one earns its keep.** "Apple does not
/// sell this book" and "we could not ask Apple" look identical if you only return
/// a nullable URL, and they call for opposite behaviour: the first means the Apple
/// row should not be offered at all, the second means it must be, because hiding a
/// shop on the strength of a dropped connection is worse than offering a weak link.
/// See [AppleBooksAvailability].
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bookworm_friends/services/book_match.dart';
import 'package:bookworm_friends/services/isbn.dart';

/// How long to wait before giving up and letting the caller degrade.
///
/// Short on purpose. This runs while the reader is waiting for a sheet to appear
/// after tapping the app-bar icon, and an exact link is a *nicety* — a slow
/// network must cost the reader a better URL, never a visibly stalled tap.
const _timeout = Duration(seconds: 4);

/// What Apple said about a book.
enum AppleBooksAvailability {
  /// Apple sells it, and [AppleBooksResult.url] names it.
  found,

  /// Apple answered, and does not sell it. **A positive fact, not a failure.**
  ///
  /// Two very ordinary causes. Apple's Books store is not a full catalogue
  /// everywhere — notably South Korea, which Apple lists as *"Public domain books
  /// only"*, so no commercial Korean title is sold there at all — and plenty of
  /// print-only or small-press books are sold nowhere digital.
  ///
  /// Callers may act on this: it is the only evidence the app ever gets that a
  /// shop genuinely does not stock a title.
  notSold,

  /// Apple was not asked, or did not answer. Offline, a timeout, a non-200, a
  /// malformed body, or a book whose ISBN field holds something that is not one.
  ///
  /// **Must be treated as "no information"**, never as [notSold].
  unknown,
}

/// The outcome of asking Apple about one book.
class AppleBooksResult {
  const AppleBooksResult(this.availability, [this.url]);

  const AppleBooksResult.notSold() : this(AppleBooksAvailability.notSold, null);
  const AppleBooksResult.unknown() : this(AppleBooksAvailability.unknown, null);

  final AppleBooksAvailability availability;

  /// Non-null exactly when [availability] is [AppleBooksAvailability.found].
  final Uri? url;

  @override
  String toString() => 'AppleBooksResult(${availability.name}, $url)';
}

/// Asks Apple whether it sells a book, and for the URL if it does.
///
/// [country] is a two-letter storefront code — use `storeCountryFor` so this and
/// the link builder cannot disagree. **It is load-bearing, not cosmetic:** a book
/// URL is scoped to the storefront that sold it, and `books.apple.com/kr/book/
/// id731076045` returns 404 for the very id that resolves under `/us/`. Which is
/// why the URL is taken verbatim from Apple's response instead of being rebuilt
/// from a path and an id.
///
/// Two questions are asked, in order, and the second is why this is worth doing:
///
///  1. **By ISBN**, which cannot mismatch. Preferred whenever the field really
///     holds one.
///  2. **By title and author**, guarded. Apple's ISBN index is incomplete even for
///     books it sells, so an ISBN miss alone is not evidence of absence. This
///     recovers those, and [_matches] is what stops it recovering the wrong book.
Future<AppleBooksResult> appleBooksLookup({
  required String isbn,
  required String title,
  required List<String> authors,
  required String country,
  http.Client? client,
}) async {
  Future<String?> get(Uri uri) async {
    final response = await (client?.get(uri) ?? http.get(uri)).timeout(
      _timeout,
    );
    if (response.statusCode != 200) return null;
    // `bodyBytes` decoded explicitly as UTF-8: the endpoint answers
    // `text/javascript` with no charset, which makes `response.body` fall back to
    // Latin-1 and mangle every non-ASCII title. Titles are compared here, so
    // this is not cosmetic — a mangled Korean title matches nothing.
    return utf8.decode(response.bodyBytes);
  }

  try {
    // ---- 1. By ISBN. Apple's `isbn=` matches THIRTEEN DIGITS ONLY: a lookup
    // for the ISBN-10 `0143127741` returns nothing while its 978-prefixed form
    // returns the book. Not a detail worth skipping, because Google's mapper
    // falls back to ISBN-10 and Kakao keeps whichever form came first, so the
    // ten-digit shape is common in this column rather than rare.
    final normalised = normalisedIsbn13(isbn);
    var asked = false;
    if (normalised != null) {
      final body = await get(
        Uri.https('itunes.apple.com', '/lookup', {
          'isbn': normalised,
          'entity': 'ebook',
          'country': country,
        }),
      );
      if (body == null) return const AppleBooksResult.unknown();
      asked = true;
      final url = appleBookUrlFromLookupJson(body);
      if (url != null)
        return AppleBooksResult(AppleBooksAvailability.found, url);
    }

    // ---- 2. By title and author.
    final author = authors.isEmpty ? '' : authors.first;
    final term = [
      title,
      author,
    ].where((s) => s.trim().isNotEmpty).join(' ').trim();
    if (term.isEmpty) {
      return asked
          ? const AppleBooksResult.notSold()
          : const AppleBooksResult.unknown();
    }
    final body = await get(
      Uri.https('itunes.apple.com', '/search', {
        'term': term,
        'entity': 'ebook',
        'country': country,
        // Enough to see past a knock-off sitting above the real edition, few
        // enough to stay a small response.
        'limit': '10',
      }),
    );
    if (body == null) {
      return asked
          ? const AppleBooksResult.notSold()
          : const AppleBooksResult.unknown();
    }
    final url = appleBookUrlFromSearchJson(body, title: title, author: author);
    if (url != null) return AppleBooksResult(AppleBooksAvailability.found, url);

    // Apple answered both questions and has no edition of this book.
    return const AppleBooksResult.notSold();
  } catch (_) {
    // Offline, DNS failure, timeout, malformed body. None of them are evidence
    // of anything, and none may stop the sheet from opening.
    return const AppleBooksResult.unknown();
  }
}

/// The book URL in an iTunes **lookup** response body, or null.
///
/// Split out from the request so the response shape can be tested without a
/// network. The shape, confirmed against the live endpoint:
///
/// ```json
/// { "resultCount": 1, "results": [ {
///     "kind": "ebook",
///     "trackName": "The Body Keeps the Score",
///     "trackViewUrl": "https://books.apple.com/us/book/the-body-keeps-the-score/id731076045?uo=4"
/// } ] }
/// ```
///
/// Safe to take `results[0]` unguarded **only because the query was an ISBN**,
/// which identifies an edition. The search variant below cannot do that.
Uri? appleBookUrlFromLookupJson(String body) {
  final results = _results(body);
  return results.isEmpty ? null : _urlOf(results.first);
}

/// The book URL in an iTunes **search** response body, or null if nothing in it
/// is confidently the book asked for.
///
/// **The guard is the whole point.** A title search returns near-misses ahead of
/// the real edition often enough that taking `results[0]` would be worse than
/// returning nothing: for *The Body Keeps the Score* the live endpoint returns the
/// real book first but then `"… by Bessel van der Kolk, MD - Summary and
/// Analysis"` by *Summary Life* and `"… By Bessel Van der kolk, M.D"` by *Easy
/// Reads*. Sending a reader to a third-party study guide while the row says
/// "Opens this book" is exactly the failure `StoreReach` exists to prevent, so an
/// unmatched search is treated as no answer at all.
Uri? appleBookUrlFromSearchJson(
  String body, {
  required String title,
  required String author,
}) {
  for (final result in _results(body)) {
    final matched = sameBook(
      candidateTitle: result['trackName'],
      candidateAuthor: result['artistName'],
      title: title,
      author: author,
    );
    if (!matched) continue;
    final url = _urlOf(result);
    if (url != null) return url;
  }
  return null;
}

/// The `results` list, or empty for anything that is not a usable response.
///
/// `resultCount: 0` with an empty list is exactly what a miss looks like, so an
/// empty return is the ordinary case and not an error.
List<Map<String, dynamic>> _results(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map<String, dynamic>) return const [];
  final results = decoded['results'];
  if (results is! List) return const [];
  return results.whereType<Map<String, dynamic>>().toList();
}

/// The usable `trackViewUrl` on one result, or null.
///
/// Three guards, each earning its place:
///
///  * **`kind` must be `ebook`.** `entity=ebook` is a request, not a guarantee,
///    and an audiobook of the same title is a different product.
///  * **The host must be `books.apple.com`.** This URL is handed to `launchUrl`
///    with `externalApplication`, so an unexpected host would be an arbitrary
///    redirect out of the app on the strength of a third-party response.
///  * **`uo=4` is dropped.** Apple's own affiliate/analytics marker, echoed into
///    every `trackViewUrl`, asked for by nobody, and it would sit in a URL the
///    reader can see and share.
Uri? _urlOf(Map<String, dynamic> result) {
  if (result['kind'] != 'ebook') return null;
  final raw = result['trackViewUrl'];
  if (raw is! String || raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host != 'books.apple.com') return null;

  final query = Map.of(uri.queryParameters)..remove('uo');
  // Rebuilt rather than `replace(query: '')`, which leaves a bare trailing `?`.
  return query.isEmpty
      ? Uri(scheme: uri.scheme, host: uri.host, path: uri.path)
      : uri.replace(queryParameters: query);
}
