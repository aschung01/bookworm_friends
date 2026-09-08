// THROWAWAY PROBE — delete after the band-selection question is settled.
//
// Which pixels should `coverBackgroundColor` look at, and at what bin width?
//
// Measures each edge of the border independently, then four pooled policies:
//
//   all    shipped: top + bottom + left + right
//   noB    drop the bottom (obi / 띠지 / paper margin lives there)
//   LR     the two vertical edges only
//   L      the left edge only
//
// Each is evaluated at 5-bit bins (shipped) and 4-bit bins, because dark grainy
// backgrounds fragment across 5-bit bins and that is a separate defect from
// which region gets sampled. Everything falls back to averageCoverColor when its
// band is unconvincing, so the only variables are region and bin width.
//
// Reads build/backfill/books.json ([{id,title,thumbnail}, ...]).
// Writes build/backfill/edges.tsv.
//
// Opt-in, because it lives in `test/` (the only place `flutter test` runs a file
// from) but fetches real covers over the network:
//
//   flutter test test/_left_band_probe.dart --dart-define=probe=true

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/cover_sample.dart';

const String _dir = 'build/backfill';
const double _borderFraction = 0.08;

/// Off unless asked for, so a bare `flutter test` neither hits the network nor
/// fails on a missing dump.
const bool _enabled = bool.fromEnvironment('probe');

typedef Mode = ({Color colour, double share});

Mode? _mode(
  ui.Image image,
  Uint8List px,
  bool Function(int x, int y) include, {
  required int bits,
}) {
  final w = image.width, h = image.height;
  final shift = 8 - bits;
  final counts = <int, int>{};
  final sumR = <int, int>{};
  final sumG = <int, int>{};
  final sumB = <int, int>{};
  var opaque = 0;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!include(x, y)) continue;
      final i = (y * w + x) * 4;
      if (i + 3 >= px.length || px[i + 3] < 128) continue;
      final r = px[i], g = px[i + 1], b = px[i + 2];
      final key =
          ((r >> shift) << (bits * 2)) | ((g >> shift) << bits) | (b >> shift);
      counts[key] = (counts[key] ?? 0) + 1;
      sumR[key] = (sumR[key] ?? 0) + r;
      sumG[key] = (sumG[key] ?? 0) + g;
      sumB[key] = (sumB[key] ?? 0) + b;
      opaque++;
    }
  }
  if (opaque == 0) return null;

  var best = 0, bestCount = 0;
  counts.forEach((key, n) {
    if (n > bestCount) {
      bestCount = n;
      best = key;
    }
  });
  return (
    colour: Color.fromARGB(
      255,
      (sumR[best]! / bestCount).round(),
      (sumG[best]! / bestCount).round(),
      (sumB[best]! / bestCount).round(),
    ),
    share: bestCount / opaque,
  );
}

Future<Uint8List?> _fetch(HttpClient client, String url) async {
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) return null;
    final chunks = await response.toList();
    return Uint8List.fromList(chunks.expand((c) => c).toList());
  } catch (_) {
    return null;
  }
}

String _hex(Color c) => bookCoverColorToHex(c);
String _cell(Mode? m) =>
    m == null ? '-' : '${_hex(m.colour)}@${(m.share * 100).round()}%';

int _delta(Color? a, Color? b) {
  if (a == null || b == null) return a == b ? 0 : 255;
  int c(double x) => (x * 255).round();
  return [
    (c(a.r) - c(b.r)).abs(),
    (c(a.g) - c(b.g)).abs(),
    (c(a.b) - c(b.b)).abs(),
  ].reduce((x, y) => x > y ? x : y);
}

void main() {
  testWidgets('probe the border regions', (tester) async {
    if (!_enabled) {
      markTestSkipped('pass --dart-define=probe=true to run the probe');
      return;
    }
    final rows =
        (jsonDecode(File('$_dir/books.json').readAsStringSync()) as List)
            .cast<Map<String, dynamic>>();

    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    final client = HttpClient()..userAgent = 'bookworm-edge-probe';

    /// The policies under test: region × bin width.
    const policies = <String>[
      'all5', 'noB5', 'LR5', 'L5', //
      'all4', 'noB4', 'LR4', 'L4',
    ];
    final confident = {for (final p in policies) p: 0};
    final material = {for (final p in policies) p: 0};
    final ledger = <String>[];
    var failed = 0;

    await tester.runAsync(() async {
      for (final row in rows) {
        final bytes = await _fetch(client, row['thumbnail'] as String);
        if (bytes == null) {
          failed++;
          continue;
        }
        final ui.Image image;
        try {
          image = (await (await ui.instantiateImageCodec(
            bytes,
          )).getNextFrame()).image;
        } catch (_) {
          failed++;
          continue;
        }
        final data = await image.toByteData();
        if (data == null) {
          failed++;
          image.dispose();
          continue;
        }

        final px = data.buffer.asUint8List();
        final w = image.width, h = image.height;
        final shorter = w < h ? w : h;
        final b = (shorter * _borderFraction).round().clamp(1, shorter);

        bool left(int x, int y) => x < b;
        bool right(int x, int y) => x >= w - b;
        bool top(int x, int y) => y < b;
        bool bottom(int x, int y) => y >= h - b;
        bool all(int x, int y) =>
            left(x, y) || right(x, y) || top(x, y) || bottom(x, y);
        bool noB(int x, int y) => left(x, y) || right(x, y) || top(x, y);
        bool lr(int x, int y) => left(x, y) || right(x, y);

        final regions = <String, bool Function(int, int)>{
          'all': all,
          'noB': noB,
          'LR': lr,
          'L': left,
        };
        final answers = <String, Mode?>{};
        for (final bits in [5, 4]) {
          regions.forEach((name, include) {
            answers['$name$bits'] = _mode(image, px, include, bits: bits);
          });
        }

        // Each edge on its own, at 4-bit, to see what is actually there.
        final perEdge = <String, Mode?>{
          'T': _mode(image, px, top, bits: 4),
          'L': _mode(image, px, left, bits: 4),
          'R': _mode(image, px, right, bits: 4),
          'B': _mode(image, px, bottom, bits: 4),
        };

        final mean = await averageCoverColor(image);
        image.dispose();

        Color? answer(Mode? m) =>
            m != null && m.share >= kCoverBackgroundMinShare ? m.colour : mean;

        for (final p in policies) {
          final m = answers[p];
          if (m != null && m.share >= kCoverBackgroundMinShare) {
            confident[p] = confident[p]! + 1;
          }
        }
        final shipped = answer(answers['all5']);
        for (final p in policies) {
          if (_delta(shipped, answer(answers[p])) > 8) {
            material[p] = material[p]! + 1;
          }
        }

        ledger.add(
          [
            (row['title'] as String? ?? '').replaceAll('\t', ' '),
            _cell(perEdge['T']),
            _cell(perEdge['L']),
            _cell(perEdge['R']),
            _cell(perEdge['B']),
            mean == null ? '-' : _hex(mean),
            for (final p in policies)
              switch (answer(answers[p])) {
                final Color c => _hex(c),
                null => '-',
              },
          ].join('\t'),
        );
      }
    });
    client.close();

    File('$_dir/edges.tsv').writeAsStringSync(
      'title\tT\tL\tR\tB\tmean\t${policies.join('\t')}\n${ledger.join('\n')}\n',
    );

    final report = StringBuffer('covers ${ledger.length} (failed $failed)\n');
    report.writeln('  policy  confident  changed_vs_shipped');
    for (final p in policies) {
      report.writeln(
        '  ${p.padRight(7)} ${confident[p].toString().padLeft(9)} '
        '${material[p].toString().padLeft(18)}',
      );
    }
    // ignore: avoid_print
    print(report);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
