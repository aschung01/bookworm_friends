// Maps every answer `read-book-cover` can give onto a `CoverReadResult`.
//
// This is the part of the cover path worth pinning in a test: the branch count is high,
// the branches are indistinguishable to the compiler (they all come back as a `Map`),
// and getting one wrong means telling a user with no signal that their book does not
// exist. No network and no camera — a fake client stands in for both.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bookworm_friends/services/cover_read.dart';

/// Returns a canned [FunctionResponse], or throws a canned [FunctionException].
///
/// Subclasses `FunctionsClient` rather than mocking the whole `SupabaseClient`: the
/// service only ever touches `.functions.invoke`, so that is the only seam that has to be
/// honest.
class _FakeFunctions extends FunctionsClient {
  _FakeFunctions({this.data, this.throws})
    : super('http://localhost', const {});

  final Object? data;
  final Object? throws;

  /// Captured so a test can assert what was actually sent.
  Object? lastBody;

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
  }) async {
    lastBody = body;
    if (throws != null) throw throws!;
    return FunctionResponse(data: data, status: 200);
  }
}

class _FakeClient extends SupabaseClient {
  _FakeClient(this._functions) : super('http://localhost', 'anon-key');

  final FunctionsClient _functions;

  @override
  FunctionsClient get functions => _functions;
}

/// Big enough to be a real payload, small enough to be free.
Uint8List _bytes([int length = 64]) =>
    Uint8List.fromList(List<int>.filled(length, 7));

Future<CoverReadResult> _read({
  Object? data,
  Object? throws,
  Uint8List? bytes,
  _FakeFunctions? functions,
}) {
  final fake = functions ?? _FakeFunctions(data: data, throws: throws);
  return readBookCover(bytes ?? _bytes(), client: _FakeClient(fake));
}

void main() {
  group('a cover the model could read', () {
    test('title and author come back as a query', () async {
      final result = await _read(
        data: {'query': '소년이 온다 한강', 'title': '소년이 온다', 'author': '한강'},
      );

      expect(result, isA<CoverReadQuery>());
      final query = result as CoverReadQuery;
      expect(query.query, '소년이 온다 한강');
      expect(query.title, '소년이 온다');
      expect(query.author, '한강');
    });

    test('a title with no author is still a usable query', () async {
      final result = await _read(
        data: {'query': 'Clean Code', 'title': 'Clean Code', 'author': ''},
      );

      expect((result as CoverReadQuery).query, 'Clean Code');
      expect(result.author, isEmpty);
    });

    test('the image is sent base64-encoded with its mime type', () async {
      final functions = _FakeFunctions(
        data: {'query': 'x', 'title': 'x', 'author': ''},
      );
      await readBookCover(
        _bytes(3),
        mimeType: 'image/png',
        client: _FakeClient(functions),
      );

      final body = functions.lastBody as Map;
      expect(body['mime_type'], 'image/png');
      expect(body['image'], base64Encode(_bytes(3)));
    });
  });

  group('a cover the model could not read', () {
    test('an unreadable answer is not treated as a failure', () async {
      // Comes back as HTTP 200 on purpose: it is an answer, not a fault, and its advice
      // is about the photo rather than about retrying.
      expect(
        await _read(data: {'error': 'unreadable'}),
        isA<CoverReadUnreadable>(),
      );
    });

    test('a blank query never reaches the search field', () async {
      // Should not happen, and must not put an empty search in front of the user — that
      // reads as the feature silently doing nothing.
      expect(
        await _read(data: {'query': '', 'title': '', 'author': ''}),
        isA<CoverReadUnreadable>(),
      );
      expect(
        await _read(data: {'query': '   ', 'title': 'x', 'author': ''}),
        isA<CoverReadUnreadable>(),
      );
    });
  });

  group('failures are told apart', () {
    test('429 is a rate limit, not a broken call', () async {
      // The distinction that matters: retrying cannot help, so the UI must not offer it.
      expect(
        await _read(
          throws: const FunctionException(status: 429, details: 'rate_limited'),
        ),
        isA<CoverReadRateLimited>(),
      );
    });

    test('any other function status is a failure', () async {
      for (final status in [401, 500, 502, 503]) {
        expect(
          await _read(throws: FunctionException(status: status)),
          isA<CoverReadFailed>(),
          reason: 'status $status',
        );
      }
    });

    test(
      'a thrown non-FunctionException is still a failure, not a crash',
      () async {
        // The offline case arrives as a SocketException from deep inside the http client.
        expect(
          await _read(throws: Exception('connection closed')),
          isA<CoverReadFailed>(),
        );
      },
    );

    test('a non-map response is a failure rather than a cast error', () async {
      expect(await _read(data: 'not json'), isA<CoverReadFailed>());
      expect(await _read(data: null), isA<CoverReadFailed>());
    });

    test(
      'an unrecognised error code is a failure, not a silent success',
      () async {
        expect(
          await _read(data: {'error': 'not_configured'}),
          isA<CoverReadFailed>(),
        );
      },
    );
  });

  group('the client refuses what the function would reject', () {
    test('an empty image never leaves the phone', () async {
      final functions = _FakeFunctions(data: const {});
      final result = await readBookCover(
        Uint8List(0),
        client: _FakeClient(functions),
      );

      expect(result, isA<CoverReadFailed>());
      expect(
        functions.lastBody,
        isNull,
        reason: 'nothing should have been invoked',
      );
    });

    test('an oversized image fails locally and for free', () async {
      // Checked client-side so this costs nothing, rather than uploading megabytes over
      // cellular to be told 413.
      final functions = _FakeFunctions(data: const {});
      final result = await readBookCover(
        _bytes(kMaxCoverImageBytes + 1),
        client: _FakeClient(functions),
      );

      expect(result, isA<CoverReadFailed>());
      expect(functions.lastBody, isNull);
    });

    test('an image exactly at the limit is still sent', () async {
      final functions = _FakeFunctions(
        data: {'query': 'x', 'title': 'x', 'author': ''},
      );
      final result = await readBookCover(
        _bytes(kMaxCoverImageBytes),
        client: _FakeClient(functions),
      );

      expect(result, isA<CoverReadQuery>());
      expect(functions.lastBody, isNotNull);
    });
  });
}
