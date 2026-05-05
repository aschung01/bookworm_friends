import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bookworm_friends/constants/constants.dart';

class BookSearchResult {
  final String title;
  final String isbn;
  final String thumbnail;
  final String? url;
  final List<String> authors;
  final String? publisher;
  final DateTime? datetime;
  final String? contents;

  const BookSearchResult({
    required this.title,
    required this.isbn,
    required this.thumbnail,
    this.url,
    this.authors = const [],
    this.publisher,
    this.datetime,
    this.contents,
  });

  factory BookSearchResult.fromJson(Map<String, dynamic> json) {
    return BookSearchResult(
      title: json['title'] as String? ?? '',
      isbn: (json['isbn'] as String? ?? '').split(' ').first,
      thumbnail: json['thumbnail'] as String? ?? '',
      url: json['url'] as String?,
      authors: (json['authors'] as List<dynamic>?)
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

class BookSearchService {
  static const _baseUrl = kakaoBookSearchBaseUrl;
  static const _apiKey = kakaoRestApiKey;

  static Future<List<BookSearchResult>> search(
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

    final response = await http.get(uri, headers: {
      'Authorization': 'KakaoAK $_apiKey',
    });

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final documents = data['documents'] as List<dynamic>;

    return documents
        .map((d) => BookSearchResult.fromJson(d as Map<String, dynamic>))
        .toList();
  }
}
