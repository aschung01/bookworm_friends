// The jacket thumbnail the home-screen widget draws, and the reason every failure here is silent.
//
// **`build` returning null is the designed outcome of a bad day, not an error path nobody
// exercises.** The widget's fallback is the `coverColor` rectangle it drew before thumbnails
// existed, so a 404, an offline phone, a CDN error page served as HTTP 200, or a body that is not
// an image at all must all come back null rather than throw -- because the caller is a `build`
// method and an exception there is a red screen over a home-screen surface the reader may not even
// have installed. Each of those is a case below.
//
// The size assertion is the other half: a WidgetKit extension gets a memory budget in the tens of
// megabytes and is killed rather than degraded when it misses one, so shipping a publisher's
// full-resolution artwork into the App Group is a crash rather than a slow tile.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bookworm_friends/services/streak_cover_thumbnail.dart';

/// A real PNG, encoded through the same engine the production path uses.
///
/// Built rather than pasted as a base64 blob so the fixture cannot rot into something the decoder
/// rejects for a reason no one can see.
Future<Uint8List> _png({required int width, required int height}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF8A5A2B),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

StreakCoverThumbnail _serving(
  Uint8List body, {
  int status = 200,
  List<Uri>? seen,
}) => StreakCoverThumbnail(
  client: MockClient((request) async {
    seen?.add(request.url);
    return http.Response.bytes(body, status);
  }),
);

void main() {
  const url = 'https://covers.example/piranesi.jpg';

  group('the happy path', () {
    test(
      'Given a cover, When a thumbnail is built, Then it is a PNG at the widget width',
      () async {
        final source = await _png(width: 900, height: 1350);

        final bytes = await _serving(source).build(url);

        expect(bytes, isNotNull);
        final decoded = await ui.instantiateImageCodec(bytes!);
        final frame = await decoded.getNextFrame();
        addTearDown(() {
          frame.image.dispose();
          decoded.dispose();
        });
        expect(frame.image.width, StreakCoverThumbnail.targetWidth);
        // The aspect is preserved rather than squared off: `targetWidth` alone scales the height,
        // and the widget decides the crop. 900x1350 is 2:3, so 120 wide is 180 tall.
        expect(frame.image.height, 180);
      },
    );

    // The point of resizing at all. A 900x1350 PNG is not large, and it is still far larger than
    // the tens of kilobytes a 120px jacket costs.
    test(
      'Given a large cover, When a thumbnail is built, Then it is much smaller than the source',
      () async {
        final source = await _png(width: 1600, height: 2400);

        final bytes = await _serving(source).build(url);

        expect(bytes, isNotNull);
        expect(bytes!.lengthInBytes, lessThan(source.lengthInBytes ~/ 4));
      },
    );
  });

  group('every failure is null, and none of them throws', () {
    test('Given a 404, When a thumbnail is built, Then it is null', () async {
      final bytes = await _serving(Uint8List(0), status: 404).build(url);

      expect(bytes, isNull);
    });

    // A CDN error page served with HTTP 200 is the realistic version of this: the status says the
    // body is fine and the body is HTML.
    test(
      'Given a 200 that is not an image, When a thumbnail is built, Then it is null',
      () async {
        final html = Uint8List.fromList(
          utf8.encode('<html><body>nope</body></html>'),
        );

        final bytes = await _serving(html).build(url);

        expect(bytes, isNull);
      },
    );

    test(
      'Given an empty body, When a thumbnail is built, Then it is null',
      () async {
        expect(await _serving(Uint8List(0)).build(url), isNull);
      },
    );

    test(
      'Given a socket failure, When a thumbnail is built, Then it is null rather than thrown',
      () async {
        final thumbnail = StreakCoverThumbnail(
          client: MockClient((_) async => throw http.ClientException('down')),
        );

        expect(await thumbnail.build(url), isNull);
      },
    );

    // `Book.thumbnail` is a non-nullable String, so "no cover" arrives as an empty or junk value
    // rather than as null -- and a bare `Uri.parse` of it would hand the client a relative URI.
    test(
      'Given a url that is not one, When a thumbnail is built, Then nothing is requested',
      () async {
        final seen = <Uri>[];
        final source = await _png(width: 60, height: 90);
        final thumbnail = _serving(source, seen: seen);

        expect(await thumbnail.build(''), isNull);
        expect(await thumbnail.build('not a url'), isNull);
        expect(await thumbnail.build('/relative/path.jpg'), isNull);
        expect(seen, isEmpty);
      },
    );
  });
}
