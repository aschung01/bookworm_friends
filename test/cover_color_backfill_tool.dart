// Not a test — a tool. Fills in and corrects `books.cover_color` by resolving every
// cover with **the app's own sampler**.
//
//   # 1. dump the rows.  Optionally scoped to one reader:
//   #      --dart-define=user=<uuid>  filters the dump the same way, and is how a
//   #      change is verified on one library before it is applied to everyone's.
//   mkdir -p build/backfill
//   supabase db query --linked --output json \
//     "select id, title, user_id, thumbnail, cover_color from books \
//      where coalesce(thumbnail,'') <> '' order by id" \
//     > build/backfill/books.json
//
//   # 2. resolve them  (add --dart-define=verify=true to only report, not write)
//   flutter test test/cover_color_backfill_tool.dart \
//     --dart-define=user=d1ca8213-3dc5-444d-baa7-9308064bfc7a
//
//   # 3. review, then apply
//   supabase db query --linked -f build/backfill/cover_colors.sql
//
// **Why this is a Flutter program and not SQL.** The stored colour has to equal what
// a live decode produces, or every book changes tone the day the backfill runs — a
// book's spine is derived from this value and sits beside the cover it came from. So
// the tool calls [coverToneColor], the same function `BookWidget` calls. There is no
// second implementation to drift. That is only trustworthy because that function is
// pure Dart: while the averaging was a 1x1 `drawImageRect` its answer depended on the
// renderer, and a tool could not have reproduced a phone's answer at all.
//
// It lives in `test/` because that is the only place `flutter test` will run a file
// from, and it needs the engine to decode images. `book_render_preview.dart` and
// `library_sheet_render_preview.dart` are here for the same reason.
//
// **It reads no credentials and touches no database.** Input is a JSON file, output
// is a SQL file, and what gets written is reviewable before it is applied.
//
// `--dart-define=verify=true` re-resolves without writing anything and reports how far
// the values already in the database are from the current policy. That is how the
// single-texel bug in the old sampler was found: 56 rows written by a real device,
// none of them within 8/255 of their cover's mean.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/cover_sample.dart';

const String _dir = 'build/backfill';

/// Report only; write no SQL.
const bool _verify = bool.fromEnvironment('verify');

/// Restrict to one reader's books, or empty for all of them.
///
/// The reason this exists is that the *rendering* change this backfill supports
/// cannot be scoped per user — only the data can. Filtering here is how one library
/// gets looked at by a human before 471 rows move.
const String _user = String.fromEnvironment('user');

/// Covers are fetched serially. There are a few hundred and no hurry, and a burst
/// of 400 parallel requests at one CDN is how a tool gets rate-limited into
/// producing a file full of holes.
Future<Uint8List?> _fetch(HttpClient client, String url) async {
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      // ignore: avoid_print
      print('  HTTP ${response.statusCode} for $url');
      return null;
    }
    final chunks = await response.toList();
    return Uint8List.fromList(chunks.expand((c) => c).toList());
  } catch (e) {
    // ignore: avoid_print
    print('  ${e.runtimeType}: $e');
    return null;
  }
}

Future<ui.Image?> _decode(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}

/// Largest per-channel difference, in 0-255 units.
int _channelDelta(Color a, Color b) {
  int c(double x) => (x * 255).round();
  final d = [
    (c(a.r) - c(b.r)).abs(),
    (c(a.g) - c(b.g)).abs(),
    (c(a.b) - c(b.b)).abs(),
  ];
  return d.reduce((x, y) => x > y ? x : y);
}

String _hex(Color c) => bookCoverColorToHex(c);

void main() {
  testWidgets('resolve every cover', (tester) async {
    final file = File('$_dir/books.json');
    if (!file.existsSync()) {
      fail(
        'missing ${file.path} — run the supabase db query in the header first',
      );
    }
    var rows = (jsonDecode(file.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    if (_user.isNotEmpty) {
      final all = rows.length;
      rows = rows.where((r) => r['user_id'] == _user).toList();
      // ignore: avoid_print
      print('scoped to user $_user: ${rows.length} of $all rows');
      if (rows.isEmpty) {
        fail('no rows for user $_user — is user_id in the dump?');
      }
    }

    // `flutter_test` installs an `HttpOverrides` that answers every request with a
    // 400 — deliberately, so that a *test* can never depend on the network. It is
    // also why `NetworkImage` fails in tests, which several tests in this repo rely
    // on. This is a tool rather than a test, and it needs the real client.
    //
    // **Before the client is constructed, not after.** `HttpClient()` is a factory
    // that resolves the override at construction, so a client built first is the
    // mock for its whole life however the override is changed afterwards. That
    // mistake reports "resolved 0 of 56" with a 400 for every URL, which looks
    // exactly like a CDN refusing the requests.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);

    final client = HttpClient()..userAgent = 'bookworm-cover-backfill';
    final resolved = <String, Color>{};
    final failures = <String>[];
    final drift = <int>[];
    var alreadyRight = 0;
    var fromBackground = 0;

    /// Every row's before/after, for the human who has to approve this.
    final ledger = <String>[];

    // All of it inside `runAsync`: HTTP, image decoding and `toByteData` are real
    // I/O and engine work, none of which completes inside the fake-async zone.
    await tester.runAsync(() async {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final id = row['id'] as String;

        final bytes = await _fetch(client, row['thumbnail'] as String);
        if (bytes == null) {
          failures.add('$id fetch');
          continue;
        }
        final image = await _decode(bytes);
        if (image == null) {
          failures.add('$id decode');
          continue;
        }

        // The ingredients are measured as well as the answer, so the ledger can say
        // *which* policy each book took. Without that a reviewer looking at a list of
        // hex codes has no way to tell a considered background from a mean.
        final mean = await averageCoverColor(image);
        final background = await coverBackgroundColor(image);
        final colour = await coverToneColor(image);
        image.dispose();
        if (colour == null) {
          failures.add('$id resolve');
          continue;
        }
        final usedBackground =
            background != null && background.share >= kCoverBackgroundMinShare;
        if (usedBackground) fromBackground++;
        resolved[id] = colour;

        final stored = bookCoverColorFromHex(row['cover_color'] as String?);
        if (stored != null) {
          final d = _channelDelta(colour, stored);
          drift.add(d);
          if (d == 0) alreadyRight++;
        }

        ledger.add(
          [
            (row['title'] as String? ?? '').replaceAll('\t', ' '),
            stored == null ? '-' : _hex(stored),
            _hex(colour),
            usedBackground ? 'background' : 'mean',
            background == null
                ? '-'
                : '${_hex(background.colour)}@'
                      '${(background.share * 100).round()}%',
            mean == null ? '-' : _hex(mean),
          ].join('\t'),
        );

        if ((i + 1) % 50 == 0) {
          // ignore: avoid_print
          print('  ${i + 1}/${rows.length}');
        }
      }
    });
    client.close();

    // ignore: avoid_print
    print('resolved ${resolved.length} of ${rows.length}');
    // ignore: avoid_print
    print(
      '$fromBackground took the border ring '
      '(${(100 * fromBackground / (resolved.isEmpty ? 1 : resolved.length)).round()}%), '
      '${resolved.length - fromBackground} fell back to the mean',
    );
    if (failures.isNotEmpty) {
      // ignore: avoid_print
      print(
        'could not resolve ${failures.length}: ${failures.take(8).join(', ')}',
      );
    }
    if (drift.isNotEmpty) {
      drift.sort();
      // ignore: avoid_print
      print(
        '${drift.length} rows already had a colour: $alreadyRight unchanged, '
        '${drift.where((d) => d <= 8).length} within 8/255, '
        'median ${drift[drift.length ~/ 2]}, worst ${drift.last}',
      );
    }

    // Written even in verify mode. The whole point of scoping to one user is that a
    // person reads this before anything is applied, so the review artefact must not
    // be the thing that only appears once you have committed to writing.
    File('$_dir/cover_colors.tsv').writeAsStringSync(
      'title\tstored\tresolved\tpolicy\tring\tmean\n${ledger.join('\n')}\n',
    );
    // ignore: avoid_print
    print('wrote $_dir/cover_colors.tsv (${ledger.length} rows)');
    if (_verify) return;

    final out = StringBuffer()
      ..writeln('-- Generated by test/cover_color_backfill_tool.dart.')
      ..writeln(
        '-- Values from the app\'s own coverToneColor, so these are what',
      )
      ..writeln(
        '-- a live decode produces. Re-running the tool regenerates this',
      )
      ..writeln('-- file, which is the rollback.')
      ..writeln('--')
      ..writeln(
        '-- Not guarded on IS NULL. Rows that already have a colour were',
      )
      ..writeln(
        '-- written by an earlier policy -- first a single texel of the cover,',
      )
      ..writeln(
        '-- then its mean -- so these are corrections rather than duplicates,',
      )
      ..writeln(
        '-- and recordCoverColor skips a book that has a colour, so nothing',
      )
      ..writeln('-- else would ever fix them.');
    if (_user.isNotEmpty) {
      out.writeln('--');
      out.writeln('-- Scoped to user $_user.');
    }
    out.writeln('begin;');
    resolved.forEach((id, colour) {
      out.writeln(
        "update books set cover_color = '${_hex(colour)}' where id = '$id';",
      );
    });
    out.writeln('commit;');
    File('$_dir/cover_colors.sql').writeAsStringSync(out.toString());
    // ignore: avoid_print
    print('wrote $_dir/cover_colors.sql (${resolved.length} statements)');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
