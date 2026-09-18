import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bookworm_friends/constants/constants.dart';

/// Which upstream catalog a [BookSearchProvider] queries.
enum BookSearchSource { kakao, googleBooks }

/// Normalized book search result shared across all providers so the UI and
/// persistence layer stay source-agnostic.
class BookSearchResult {
  final String title;
  final String isbn;
  final String thumbnail;
  final String? url;
  final List<String> authors;
  final String? publisher;
  final DateTime? datetime;
  final String? contents;

  /// Google Books' own id for this volume, when the result came from there.
  ///
  /// **The only per-book identifier the app can get without a second request**,
  /// and the reason it is worth carrying: it names both the Play Store page
  /// (`/store/books/details?id=`) and the Play Books reader
  /// (`/books/reader?id=`), which makes Play Books the one shop that can be
  /// reached exactly for either intent. Every other shop falls back to a search.
  ///
  /// Null for Kakao and Open Library, which have no equivalent. Note this is a
  /// *different* thing from the volume id occasionally ending up in [isbn]: that
  /// happens when a volume lists no ISBN at all and something non-empty is needed
  /// as a key (see [GoogleBooksSearchProvider._mapVolume]), and it is exactly why
  /// `looksLikeIsbn` exists.
  final String? volumeId;

  /// Pages, when the provider reports a credible count.
  ///
  /// Null for Kakao, which has no page field at all — its book document carries
  /// eleven keys and none of them is a page count. Google Books has one but
  /// returns `pageCount: 0` for volumes it does not know, which is normalised to
  /// null here so a zero cannot be mistaken for a very thin book. Open Library
  /// reports a median across editions.
  ///
  /// Only consumer today is the book's rendered thickness, which falls back to a
  /// hash of the ISBN when this is null.
  final int? pageCount;

  const BookSearchResult({
    required this.title,
    required this.isbn,
    required this.thumbnail,
    this.url,
    this.authors = const [],
    this.publisher,
    this.datetime,
    this.contents,
    this.pageCount,
    this.volumeId,
  });

  factory BookSearchResult.fromJson(Map<String, dynamic> json) {
    return BookSearchResult(
      title: json['title'] as String? ?? '',
      isbn: (json['isbn'] as String? ?? '').split(' ').first,
      thumbnail: json['thumbnail'] as String? ?? '',
      url: json['url'] as String?,
      authors:
          (json['authors'] as List<dynamic>?)
              ?.map((a) => a as String)
              .toList() ??
          [],
      publisher: json['publisher'] as String?,
      datetime: json['datetime'] != null
          ? DateTime.tryParse(json['datetime'] as String)
          : null,
      contents: json['contents'] as String?,
    );
  }
}

/// Common interface implemented by every book catalog backend.
abstract class BookSearchProvider {
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  });

  Future<BookSearchResult?> getByIsbn(String isbn);
}

/// Kakao Book Search — best coverage/cover images for Korean titles.
class KakaoBookSearchProvider implements BookSearchProvider {
  static const _baseUrl = kakaoBookSearchBaseUrl;
  static const _apiKey = kakaoRestApiKey;

  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async {
    final uri = Uri.parse('$_baseUrl/v3/search/book').replace(
      queryParameters: {
        'query': query,
        'page': page.toString(),
        'size': size.toString(),
      },
    );

    final response = await http.get(
      uri,
      headers: {'Authorization': 'KakaoAK $_apiKey'},
    );

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final documents = data['documents'] as List<dynamic>? ?? [];

    return documents
        .map((d) => BookSearchResult.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async {
    final results = await search(isbn, size: 1);
    if (results.isEmpty) return null;
    return results.first;
  }
}

/// Google Books — broad international/English coverage. Used keyless (basic
/// quota); a free API key can be added later to raise the daily limit.
class GoogleBooksSearchProvider implements BookSearchProvider {
  static const _baseUrl = googleBooksBaseUrl;
  static const _maxResults = 40; // Google Books hard cap per request.

  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async {
    if (query.trim().isEmpty) return [];

    final effectiveSize = size > _maxResults ? _maxResults : size;
    final startIndex = (page - 1) * size;

    final params = {
      'q': query,
      'startIndex': startIndex.toString(),
      'maxResults': effectiveSize.toString(),
      'printType': 'books',
      'country': 'US',
    };
    if (googleBooksApiKey.isNotEmpty) {
      params['key'] = googleBooksApiKey;
    }

    final uri = Uri.parse('$_baseUrl/volumes').replace(queryParameters: params);

    final response = await http.get(uri);
    // Throw on error (e.g. 429 quota exceeded in keyless mode) so a wrapping
    // provider can fall back to another catalog. A 200 with no items is a
    // legitimate empty result and must NOT trigger fallback (breaks paging).
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Google Books returned ${response.statusCode}',
        uri,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];

    return items
        .map((item) => _mapVolume(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async {
    final results = await search('isbn:$isbn', size: 1);
    if (results.isEmpty) return null;
    return results.first;
  }

  BookSearchResult _mapVolume(Map<String, dynamic> item) {
    final volume = item['volumeInfo'] as Map<String, dynamic>? ?? {};

    // Prefer ISBN-13, fall back to ISBN-10, then the volume id so the book can
    // still be saved with a stable, non-empty identifier.
    final identifiers =
        (volume['industryIdentifiers'] as List<dynamic>?) ?? const [];
    String? isbn13;
    String? isbn10;
    for (final raw in identifiers) {
      final id = raw as Map<String, dynamic>;
      final type = id['type'] as String?;
      final value = id['identifier'] as String?;
      if (type == 'ISBN_13') isbn13 = value;
      if (type == 'ISBN_10') isbn10 = value;
    }
    final isbn = isbn13 ?? isbn10 ?? (item['id'] as String? ?? '');

    // Google returns `pageCount: 0` for volumes it has no count for rather than
    // omitting the key, so a zero is absence and not a thin book. Normalised here
    // because it is a quirk of this provider; the threshold for what counts as a
    // *plausible* page count is a display concern and lives with the geometry.
    final rawPages = volume['pageCount'];
    final pageCount = rawPages is int && rawPages > 0 ? rawPages : null;

    // Force https so iOS App Transport Security doesn't block cover images.
    final imageLinks = volume['imageLinks'] as Map<String, dynamic>?;
    var thumbnail =
        (imageLinks?['thumbnail'] ?? imageLinks?['smallThumbnail'] ?? '')
            as String;
    if (thumbnail.startsWith('http://')) {
      thumbnail = thumbnail.replaceFirst('http://', 'https://');
    }

    return BookSearchResult(
      title: volume['title'] as String? ?? '',
      isbn: isbn,
      pageCount: pageCount,
      thumbnail: thumbnail,
      // Kept in its own field as well as being the ISBN fallback above. The two
      // uses are unrelated: there it is standing in for a missing key, here it is
      // the identifier that makes an exact Play Books link possible.
      volumeId: item['id'] as String?,
      url:
          volume['infoLink'] as String? ??
          volume['canonicalVolumeLink'] as String?,
      authors:
          (volume['authors'] as List<dynamic>?)
              ?.map((a) => a as String)
              .toList() ??
          const [],
      publisher: volume['publisher'] as String?,
      datetime: _parsePublishedDate(volume['publishedDate'] as String?),
      contents: volume['description'] as String?,
    );
  }

  /// Google returns publishedDate as `yyyy`, `yyyy-MM`, or `yyyy-MM-dd`.
  DateTime? _parsePublishedDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;
    final year = int.tryParse(raw.split('-').first);
    if (year != null) return DateTime(year);
    return null;
  }
}

/// Open Library (Internet Archive) — fully keyless with no per-day quota.
/// Used as a resilient fallback for the international source.
class OpenLibrarySearchProvider implements BookSearchProvider {
  static const _baseUrl = 'https://openlibrary.org';
  static const _coverUrl = 'https://covers.openlibrary.org';

  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/search.json').replace(
      queryParameters: {
        'q': query,
        'page': page.toString(),
        'limit': size.toString(),
        'fields':
            'title,author_name,isbn,cover_i,first_publish_year,publisher,key,'
            'number_of_pages_median',
      },
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final docs = data['docs'] as List<dynamic>? ?? [];

    return docs.map((d) => _mapDoc(d as Map<String, dynamic>)).toList();
  }

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async {
    final results = await search('isbn:$isbn', size: 1);
    if (results.isEmpty) return null;
    return results.first;
  }

  BookSearchResult _mapDoc(Map<String, dynamic> doc) {
    final isbns = (doc['isbn'] as List<dynamic>?)?.cast<String>() ?? const [];
    // Prefer a 13-digit ISBN when available.
    final isbn = isbns.firstWhere(
      (i) => i.length == 13,
      orElse: () => isbns.isNotEmpty ? isbns.first : '',
    );

    final coverId = doc['cover_i'];
    String thumbnail = '';
    if (coverId != null) {
      thumbnail = '$_coverUrl/b/id/$coverId-M.jpg';
    } else if (isbn.isNotEmpty) {
      thumbnail = '$_coverUrl/b/isbn/$isbn-M.jpg';
    }

    final year = doc['first_publish_year'] as int?;
    final key = doc['key'] as String?;

    // A median across every edition of the work rather than this edition's count.
    // Approximate by construction, which is fine for the one thing it feeds: a
    // book's drawn thickness.
    final rawPages = doc['number_of_pages_median'];
    final pageCount = rawPages is int && rawPages > 0 ? rawPages : null;

    return BookSearchResult(
      title: doc['title'] as String? ?? '',
      isbn: isbn,
      pageCount: pageCount,
      thumbnail: thumbnail,
      url: key != null ? '$_baseUrl$key' : null,
      authors:
          (doc['author_name'] as List<dynamic>?)?.cast<String>() ?? const [],
      publisher: (doc['publisher'] as List<dynamic>?)?.isNotEmpty ?? false
          ? (doc['publisher'] as List<dynamic>).first as String
          : null,
      datetime: year != null ? DateTime(year) : null,
    );
  }
}

/// Tries each provider in order, falling back to the next only when one throws
/// (e.g. a quota error). A successful-but-empty result is returned as-is so
/// pagination stays consistent within a single provider.
class FallbackBookSearchProvider implements BookSearchProvider {
  final List<BookSearchProvider> providers;
  const FallbackBookSearchProvider(this.providers);

  @override
  Future<List<BookSearchResult>> search(
    String query, {
    int page = 1,
    int size = 10,
  }) async {
    for (final provider in providers) {
      try {
        return await provider.search(query, page: page, size: size);
      } catch (_) {
        // Provider failed (e.g. quota error) — try the next one.
      }
    }
    return [];
  }

  @override
  Future<BookSearchResult?> getByIsbn(String isbn) async {
    for (final provider in providers) {
      try {
        final result = await provider.getByIsbn(isbn);
        if (result != null) return result;
      } catch (_) {
        // try next
      }
    }
    return null;
  }
}
