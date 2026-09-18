// Not a test — a tool. Measures candidate policies for `books.cover_color` against a
// real corpus, and is the thing to re-run when the corpus grows or a constant is
// questioned.
//
// ## Why it exists
//
// The design this replaced was pinned by twelve green tests, all of which passed on
// synthetic fixtures while the policy they were pinning stored a colour that was nowhere
// on the book for a third of a real library. `test/spine_tone_test.dart` opens with the
// same warning: a green suite is only worth its corpus. So every constant in
// `cover_sample.dart` was chosen by running this over the whole `books` table —
// **460 distinct covers belonging to 74 readers**, not one person's shelf.
//
// ## The policies
//
// The earlier round of this tool compared the four-sided border against each correction
// in isolation (`bits`, `noB`, `frame`, `tie`) and settled the stack. Those columns are
// gone; their conclusions are recorded in `cover_sample.dart`. What is left is the
// pre-change design, kept as the fixed reference every headline number in that file is
// quoted against, the shipped policy, and the questions still open:
//
//   all5     the design this replaced: plain four-sided border, 5-bit bins, no
//            corrections. The reference, because the absolute metrics below cannot
//            settle anything on their own — both of them reward accepting the border
//            more often, so they favour a lower threshold all the way down to zero. Only
//            regressions against a fixed baseline push back.
//   base     the shipped policy: 4-bit bins, foot and foot-corners dropped, paper
//            margin excluded by colour, split border decided by area
//   noTie    base without the area tie-break, so correction 3 can be scored *in situ*
//            rather than against the uncorrected border
//   hbRaw    base, plus a uniform strip at the **head** is dropped and the border read
//            from underneath it, on depth alone — a row walk down from row 0
//   hb       the same, gated on the strip's colour being absent from the flanks below
//            it — the difference between the two is the whole argument for the gate
//   sym      band detection at head *and* foot, replacing the unconditional foot drop
//            with a plain four-sided ring on the band-stripped rectangle — the test of
//            whether the foot drop was only ever a crude band detector
//   reach    base, but a *winning* candidate that does not reach the flanks is struck and
//            the border re-read without it
//   hs       base, plus a head band struck **by colour**: the mode of the head strip,
//            when it fills that strip and stays out of the flanks below it. The mirror of
//            the paper margin, and the shape that was adopted
//   hsNT     hs without the tie-break, to check the two corrections compose
//
// ## The quality metric
//
// Confidence counts are not correctness: a policy can be sure and wrong. So each answer
// is scored by **coverage** — the fraction of the jacket actually within tolerance of the
// stored colour. It is the honest proxy for "is this the colour of the book": a foot band
// scores low because it is a band, and a mean scores near zero, because an average is
// usually a colour that appears nowhere on the cover.
//
// That metric has one blind spot worth knowing, because it is where the remaining
// disagreements live: it counts a photographic paper margin as part of the cover, so on a
// letterboxed image it rewards storing the paper. `피터 드러커` is dark brown over its top
// 60% with white padding below, and coverage prefers the white.
//
// ## Running it
//
//   # 1. dump the covers (deduplicated by thumbnail; no credentials in this file)
//   mkdir -p build/backfill
//   printf '%s' "select json_agg(json_build_object('id', id, 'title', title, \
//     'thumbnail', thumbnail))::text from (select distinct on (thumbnail) id, title, \
//     thumbnail from public.books where coalesce(thumbnail,'') <> '' \
//     order by thumbnail, id) t;" > build/backfill/dump.sql
//   supabase db query --linked -f build/backfill/dump.sql --output json \
//     > build/backfill/raw.json
//   # then unwrap raw.json's single json_agg string into books-distinct.json
//
//   # 2. measure. Covers are cached under build/backfill/cache, so a sweep is seconds.
//   flutter test test/cover_policy_probe_tool.dart --dart-define=probe=true
//   flutter test test/cover_policy_probe_tool.dart --dart-define=probe=true \
//     --dart-define=depth=16 --dart-define=row=90 --dart-define=split=22
//
// **Deduplicated deliberately.** A cover shared by nine readers is one piece of evidence
// about the sampler, not nine, and the popular books are exactly the ones with clean flat
// jackets — measuring the raw table lets a handful of bestsellers vote repeatedly for
// whichever policy happens to suit them.
//
// Opt-in, because it lives in `test/` (the only place `flutter test` runs a file from)
// but fetches real covers over the network. Without `--dart-define=probe=true` it skips,
// so a bare `flutter test` neither hits the network nor fails on a missing dump.
//
// Reads  build/backfill/books-distinct.json  ([{title, thumbnail}, ...])
// Writes build/backfill/policies.tsv

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/cover_sample.dart';

const String _dir = 'build/backfill';
const bool _enabled = bool.fromEnvironment('probe');

/// The corpus. One row per distinct cover — see the note in the header.
const String _books = String.fromEnvironment(
  'books',
  defaultValue: 'books-distinct.json',
);

/// Acceptance threshold, overridable so it can be swept. Percent.
const int _sharePct = int.fromEnvironment('share', defaultValue: 35);

/// Paper-margin constants, mirroring the shipped ones.
const int _tol = 20;
const int _paperProbe = 2;
const double _paperMinSideShare = 0.55;
const int _paperInnerMaxPct = int.fromEnvironment('inner', defaultValue: 10);
const double _paperMinLuminance = 0.75;
const int _paperMaxChroma = 20;
const int _paperMaxCoveragePct = int.fromEnvironment(
  'framecov',
  defaultValue: 25,
);

/// How much each of the border's top two must hold before it counts as *split*.
const int _splitMinPct = int.fromEnvironment('split', defaultValue: 22);

/// Fraction of the shorter side treated as border. The shipped value.
const double _borderFraction = 0.08;

/// How deep a head band may be before it stops being a band, as a percent of height.
///
/// **The only thing keeping head-band detection safe**, and it does all the work the
/// paper margin needed four gates for. A uniform jacket matches its own first row all
/// the way down, so its band "depth" is the whole image and the cap rejects it; a
/// two-tone cover like `세대를 뛰어넘어 함께 일하기`, white across its top quarter, is
/// rejected the same way and left to the area tie-break. Only a genuine printed band
/// comes in under the cap.
const int _bandMaxDepthPct = int.fromEnvironment('depth', defaultValue: 16);

/// How much of a row must be the band's colour for the row to still be in the band.
///
/// Under 1.0 because a band usually carries type — a black bar with the series name
/// reversed out of it is still a band.
const int _bandRowSharePct = int.fromEnvironment('row', defaultValue: 90);

/// How much of the flanks *below* the strip its colour may hold and still be a band.
///
/// **The gate, and depth alone is nowhere near enough without it.** "A uniform strip at
/// the top that ends" describes a printed band, and it equally describes the top slice
/// of an ordinary background that happens to be interrupted by one — so on depth alone
/// the detector fires on 302 of 460 covers and strips `역행자`'s orange, which is the
/// background, because a black band starts 7px down. The discriminator is the premise of
/// the whole file: a background reaches around, a band does not. Orange runs down both
/// flanks; a head band does not appear in them at all.
const int _bandMaxFlankPct = int.fromEnvironment('flank', defaultValue: 10);

/// How much of the flanks a *winning* candidate must hold to be believed.
///
/// The `reach` policy, which turns out to move nothing: a head band never wins the
/// pooled border in the first place. See the `hs` note below.
const int _reachMinFlankPct = int.fromEnvironment('reach', defaultValue: 10);

/// How much of the head strip a band candidate must fill. The `hs` policy.
///
/// **The damage a head band does is dilution, not victory.** The head strip is the full
/// width by [_borderFraction] of the shorter side, and the flanks are two such widths by
/// nearly the full height, so on a 120x174 thumbnail the head is only 28% of the pooled
/// border — it cannot reach the 35% threshold however solid it is, and the area tie-break
/// beats it on the rare occasion it comes close. What it can do is take 28% of the
/// evidence away from the background, leaving it at 30% instead of 42% and dropping the
/// whole cover to its mean. Striking the band renormalises what is left, which is the
/// same move the paper margin makes.
const int _bandMinStripPct = int.fromEnvironment('strip', defaultValue: 55);

typedef Mode = ({Color colour, double share});

class Px {
  final Uint8List px;
  final int w, h;
  const Px(this.px, this.w, this.h);
  bool opaque(int x, int y) {
    final i = (y * w + x) * 4;
    return i + 3 < px.length && px[i + 3] >= 128;
  }

  List<int> rgb(int x, int y) {
    final i = (y * w + x) * 4;
    return [px[i], px[i + 1], px[i + 2]];
  }
}

bool _near(List<int> a, List<int> b, int tol) {
  for (var i = 0; i < 3; i++) {
    if ((a[i] - b[i]).abs() > tol) return false;
  }
  return true;
}

List<int> _rgbOf(Color c) => [
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
];

/// Top [n] bins, biggest first, each carrying the exact mean of its own pixels so the
/// quantisation never reaches the returned value.
///
/// [exclude] drops pixels near any of several colours — the paper margin, and in `hbX`
/// the head band as well.
List<Mode> _modes(
  Px p,
  bool Function(int, int) include, {
  int bits = 4,
  List<List<int>> exclude = const [],
  int n = 1,
}) {
  final shift = 8 - bits;
  final counts = <int, int>{};
  final sums = <int, List<int>>{};
  var total = 0;
  for (var y = 0; y < p.h; y++) {
    for (var x = 0; x < p.w; x++) {
      if (!include(x, y) || !p.opaque(x, y)) continue;
      final c = p.rgb(x, y);
      if (exclude.any((e) => _near(c, e, _tol))) continue;
      final key =
          ((c[0] >> shift) << (bits * 2)) |
          ((c[1] >> shift) << bits) |
          (c[2] >> shift);
      counts[key] = (counts[key] ?? 0) + 1;
      final s = sums[key] ??= [0, 0, 0];
      for (var i = 0; i < 3; i++) {
        s[i] += c[i];
      }
      total++;
    }
  }
  if (total == 0) return const [];
  final keys = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [
    for (final k in keys.take(n))
      (
        colour: Color.fromARGB(
          255,
          (sums[k]![0] / counts[k]!).round(),
          (sums[k]![1] / counts[k]!).round(),
          (sums[k]![2] / counts[k]!).round(),
        ),
        share: counts[k]! / total,
      ),
  ];
}

/// Fraction of the whole jacket within tolerance of [c]. The quality metric.
double _coverage(Px p, Color? c) {
  if (c == null) return 0;
  final rgb = _rgbOf(c);
  var hit = 0, all = 0;
  for (var y = 0; y < p.h; y++) {
    for (var x = 0; x < p.w; x++) {
      if (!p.opaque(x, y)) continue;
      all++;
      if (_near(p.rgb(x, y), rgb, _tol)) hit++;
    }
  }
  return all == 0 ? 0 : hit / all;
}

/// The paper margin's colour, nominated per side. Mirrors the shipped `_paperMargin`.
({List<int> rgb, String side})? _paper(Px p) {
  final sides = <String, bool Function(int, int)>{
    'B': (x, y) => y >= p.h - _paperProbe,
    'T': (x, y) => y < _paperProbe,
    'L': (x, y) => x < _paperProbe,
    'R': (x, y) => x >= p.w - _paperProbe,
  };
  ({List<int> rgb, String side})? best;
  var bestShare = 0.0;
  for (final e in sides.entries) {
    final m = _modes(p, e.value);
    if (m.isEmpty || m.first.share < _paperMinSideShare) continue;
    final rgb = _rgbOf(m.first.colour);
    final chroma =
        rgb.reduce((a, b) => a > b ? a : b) -
        rgb.reduce((a, b) => a < b ? a : b);
    if (m.first.colour.computeLuminance() < _paperMinLuminance ||
        chroma > _paperMaxChroma) {
      continue;
    }
    var hit = 0, all = 0;
    for (var y = (p.h * 0.25).round(); y < p.h * 0.75; y++) {
      for (var x = (p.w * 0.25).round(); x < p.w * 0.75; x++) {
        if (!p.opaque(x, y)) continue;
        all++;
        if (_near(p.rgb(x, y), rgb, _tol)) hit++;
      }
    }
    if (all == 0 || hit * 100 / all > _paperInnerMaxPct) continue;
    if (_coverage(p, m.first.colour) * 100 > _paperMaxCoveragePct) continue;
    if (m.first.share > bestShare) {
      bestShare = m.first.share;
      best = (rgb: rgb, side: e.key);
    }
  }
  return best;
}

/// Depth in pixels of a uniform horizontal band at one end of the image, or 0.
///
/// [rowOf] maps a step away from the edge to an image row, so the same walk serves the
/// head (`d`) and the foot (`h - 1 - d`).
({int depth, List<int> rgb})? _band(Px p, int Function(int) rowOf) {
  final probe = _modes(p, (x, y) => y == rowOf(0) || y == rowOf(1));
  if (probe.isEmpty) return null;
  final rgb = _rgbOf(probe.first.colour);
  final cap = (p.h * _bandMaxDepthPct / 100).floor();
  var d = 0;
  while (d < p.h) {
    final y = rowOf(d);
    var hit = 0, all = 0;
    for (var x = 0; x < p.w; x++) {
      if (!p.opaque(x, y)) continue;
      all++;
      if (_near(p.rgb(x, y), rgb, _tol)) hit++;
    }
    if (all == 0 || hit * 100 / all < _bandRowSharePct) break;
    d++;
    // Past the cap this is not a band but the jacket itself. Bail rather than finish
    // the walk: a uniform cover would otherwise run to the far edge.
    if (d > cap) return null;
  }
  return d == 0 ? null : (depth: d, rgb: rgb);
}

/// Share of the flanks — both full-height edges, short of the foot — within tolerance
/// of [rgb].
double _flankShare(Px p, List<int> rgb, int b, {int from = 0}) {
  var hit = 0, all = 0;
  for (var y = from; y < p.h - b; y++) {
    for (var x = 0; x < p.w; x++) {
      if (x >= b && x < p.w - b) continue;
      if (!p.opaque(x, y)) continue;
      all++;
      if (_near(p.rgb(x, y), rgb, _tol)) hit++;
    }
  }
  return all == 0 ? 0 : hit / all;
}

/// Whether a strip's colour stays out of the flanks beside and below it.
/// See [_bandMaxFlankPct].
bool _staysOffTheFlanks(Px p, int depth, List<int> rgb, int b) =>
    _flankShare(p, rgb, b, from: depth) * 100 <= _bandMaxFlankPct;

/// Border mode with the split tie-break: when no single candidate carries the border,
/// but two each carry a real part of it, the larger by area wins and is reported at
/// its area share.
Mode? _read(
  Px p,
  bool Function(int, int) region, {
  List<List<int>> exclude = const [],
  bool tieBreak = true,
}) {
  final top = _modes(p, region, exclude: exclude, n: 2);
  if (top.isEmpty) return null;
  if (top.first.share * 100 >= _sharePct) return top.first;
  if (tieBreak &&
      top.length == 2 &&
      top[0].share * 100 >= _splitMinPct &&
      top[1].share * 100 >= _splitMinPct) {
    final a = _coverage(p, top[0].colour), b = _coverage(p, top[1].colour);
    return a >= b
        ? (colour: top[0].colour, share: a)
        : (colour: top[1].colour, share: b);
  }
  return top.first;
}

/// The colour of a printed band across the head, when there is one. The `hs` policy.
///
/// Nominated from the head strip and gated on **reach**: a background runs down the sides
/// of a jacket, so a colour that fills the head and then stays out of the flanks is a
/// band. No row walk and no depth cap — see `hbRaw` for what those cost.
List<int>? _headBand(Px p, int b) {
  final m = _modes(p, (x, y) => y < b);
  if (m.isEmpty || m.first.share * 100 < _bandMinStripPct) return null;
  final rgb = _rgbOf(m.first.colour);
  if (_flankShare(p, rgb, b, from: b) * 100 > _bandMaxFlankPct) return null;
  return rgb;
}

/// [_read], with any candidate that fails to reach the flanks struck out and the border
/// re-read without it. See [_reachMinFlankPct].
///
/// Struck rather than skipped, so the survivor's share is renormalised over the evidence
/// that is left — the same move [_paper] makes. Skipping instead leaves the band's pixels
/// in the denominator, which is how a background that *is* believable ends up looking
/// like it holds only a quarter of its own border.
Mode? _readReaching(
  Px p,
  bool Function(int, int) region,
  int b, {
  List<List<int>> exclude = const [],
  bool tieBreak = true,
}) {
  final struck = [...exclude];
  // Two strikes: a cover can have a band at each end, and past that the border has
  // nothing left to say.
  for (var i = 0; i < 2; i++) {
    final m = _read(p, region, exclude: struck, tieBreak: tieBreak);
    if (m == null) return null;
    final rgb = _rgbOf(m.colour);
    if (_flankShare(p, rgb, b) * 100 >= _reachMinFlankPct) return m;
    struck.add(rgb);
  }
  return _read(p, region, exclude: struck, tieBreak: tieBreak);
}

Future<Uint8List?> _bytes(HttpClient c, String url) async {
  final key = sha1.convert(utf8.encode(url)).toString();
  final f = File('$_dir/cache/$key');
  if (f.existsSync()) return f.readAsBytesSync();
  try {
    final r = await (await c.getUrl(Uri.parse(url))).close();
    if (r.statusCode != 200) return null;
    final b = Uint8List.fromList((await r.toList()).expand((e) => e).toList());
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(b);
    return b;
  } catch (_) {
    return null;
  }
}

String _hex(Color c) => bookCoverColorToHex(c);
String _pct(double d) => (d * 100).round().toString();

/// One policy's answer for one cover, already resolved through the threshold.
typedef Answer = ({Mode? mode, Color? colour, double coverage});

void main() {
  testWidgets('measure the policies', (tester) async {
    if (!_enabled) {
      markTestSkipped('pass --dart-define=probe=true to run the probe');
      return;
    }
    final rows = (jsonDecode(File('$_dir/$_books').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    final client = HttpClient()..userAgent = 'bookworm-policy-probe';

    const names = [
      'all5',
      'base',
      'noTie',
      'hbRaw',
      'hb',
      'sym',
      'reach',
      'hs',
      'hsNT',
    ];
    final ledger = <String>[];
    final scores = {for (final n in names) n: <double>[]};
    // How often each policy gave up and took the mean. `mean!` in the report.
    final fallbacks = {for (final n in names) n: 0};
    final fired = <String>[];
    // The structural census. See the report at the end.
    final headShare = <double>[];
    final ratios = <double>[];
    var failed = 0, papers = 0, raw = 0, walked = 0, footBands = 0, bands = 0;
    var fellBack = 0, addressable = 0;

    await tester.runAsync(() async {
      for (final row in rows) {
        final bytes = await _bytes(client, row['thumbnail'] as String);
        if (bytes == null) {
          failed++;
          continue;
        }
        final ui.Image img;
        try {
          img = (await (await ui.instantiateImageCodec(
            bytes,
          )).getNextFrame()).image;
        } catch (_) {
          failed++;
          continue;
        }
        final data = await img.toByteData();
        if (data == null) {
          failed++;
          img.dispose();
          continue;
        }
        final mean = await averageCoverColor(img);
        img.dispose();
        final p = Px(data.buffer.asUint8List(), img.width, img.height);

        final shorter = p.w < p.h ? p.w : p.h;
        final b = (shorter * _borderFraction).round().clamp(1, shorter);

        final paper = _paper(p);
        if (paper != null) papers++;
        final exclude = [if (paper != null) paper.rgb];

        final head = _band(p, (d) => d);
        final foot = _band(p, (d) => p.h - 1 - d);
        if (head != null) raw++;
        if (foot != null) footBands++;
        // The gate. See [_bandMaxFlankPct].
        final gated =
            head != null && _staysOffTheFlanks(p, head.depth, head.rgb, b);
        if (gated) walked++;

        // The shipped shape: head strip plus flanks, both stopping short of the foot.
        bool base(int x, int y) =>
            y < b || ((x < b || x >= p.w - b) && y < p.h - b);

        // The design this replaced: all four edges, no corrections.
        bool ring(int x, int y) =>
            x < b || x >= p.w - b || y < b || y >= p.h - b;

        // The same shape, slid below a head band. Falls back to [base] when the band
        // leaves no room, which is the degenerate case the cap already makes rare.
        bool slidBy(int t) => t > 0 && t + b <= p.h - b;
        bool Function(int, int) below(int t) =>
            (x, y) => y >= t && base(x, y - t);

        final tRaw = head?.depth ?? 0;
        final tGated = gated ? tRaw : 0;

        // Bands stripped from both ends, then a plain four-sided ring on what is left.
        final lo = tRaw, hi = p.h - (foot?.depth ?? 0);
        final symOk = hi - lo > 3 * b;
        bool symRing(int x, int y) =>
            y >= lo &&
            y < hi &&
            (x < b || x >= p.w - b || y < lo + b || y >= hi - b);

        final band = _headBand(p, b);
        if (band != null) bands++;

        // How much of the pooled border the head strip is, which is the ceiling on what
        // a band across the head can ever claim. Counted rather than derived, so
        // transparency and odd aspect ratios are in the number.
        var headPx = 0, borderPx = 0;
        for (var y = 0; y < p.h; y++) {
          for (var x = 0; x < p.w; x++) {
            if (!base(x, y) || !p.opaque(x, y)) continue;
            borderPx++;
            if (y < b) headPx++;
          }
        }
        if (borderPx > 0) headShare.add(headPx / borderPx);
        ratios.add(p.w / p.h);

        final answers = <String, Mode?>{
          'all5': _modes(p, ring, bits: 5).firstOrNull,
          'base': _read(p, base, exclude: exclude),
          'noTie': _read(p, base, exclude: exclude, tieBreak: false),
          'hbRaw': _read(
            p,
            slidBy(tRaw) ? below(tRaw) : base,
            exclude: exclude,
          ),
          'hb': _read(
            p,
            slidBy(tGated) ? below(tGated) : base,
            exclude: exclude,
          ),
          'sym': _read(p, symOk ? symRing : base, exclude: exclude),
          'reach': _readReaching(p, base, b, exclude: exclude),
          'hs': _read(p, base, exclude: [...exclude, if (band != null) band]),
          'hsNT': _read(
            p,
            base,
            exclude: [...exclude, if (band != null) band],
            tieBreak: false,
          ),
        };

        Answer resolve(Mode? m, {int threshold = _sharePct}) {
          final c = m != null && m.share * 100 >= threshold ? m.colour : mean;
          return (mode: m, colour: c, coverage: _coverage(p, c));
        }

        // `all5` is resolved at the threshold it shipped with, not at whatever is being
        // swept, or the reference moves with the thing it is meant to hold still.
        final out = {
          for (final name in names)
            name: resolve(
              answers[name],
              threshold: name == 'all5' ? 35 : _sharePct,
            ),
        };
        for (final name in names) {
          scores[name]!.add(out[name]!.coverage);
          final m = answers[name];
          final t = name == 'all5' ? 35 : _sharePct;
          if (m == null || m.share * 100 < t) {
            fallbacks[name] = fallbacks[name]! + 1;
          }
        }

        // The population a head-band correction could possibly help: a cover that gave
        // up and took its mean, *and* has a band across the head to blame for it.
        final baseMode = answers['base'];
        final tookMean = baseMode == null || baseMode.share * 100 < _sharePct;
        if (tookMean) {
          fellBack++;
          if (band != null) addressable++;
        }

        final title = (row['title'] as String? ?? '').replaceAll('\t', ' ');
        // Every cover the head-band rule moves, named and signed, so the wins and the
        // losses can both be looked at rather than trusted.
        if (out['hs']!.colour != out['base']!.colour) {
          final d = out['hs']!.coverage - out['base']!.coverage;
          fired.add(
            '${d > 0.005 ? '+' : (d < -0.005 ? '-' : '=')} $title\t'
            '${band == null ? '-' : _hex(Color.fromARGB(255, band[0], band[1], band[2]))}\t'
            'base ${out['base']!.colour == null ? '-' : _hex(out['base']!.colour!)}'
            '@${_pct(out['base']!.coverage)}\t'
            'hs ${out['hs']!.colour == null ? '-' : _hex(out['hs']!.colour!)}'
            '@${_pct(out['hs']!.coverage)}',
          );
        }

        ledger.add(
          [
            title,
            paper == null
                ? 'none'
                : '${_hex(Color.fromARGB(255, paper.rgb[0], paper.rgb[1], paper.rgb[2]))}@${paper.side}',
            head == null ? '-' : '${head.depth}${gated ? '!' : ''}',
            foot == null ? '-' : '${foot.depth}',
            band == null
                ? '-'
                : _hex(Color.fromARGB(255, band[0], band[1], band[2])),
            mean == null ? '-' : _hex(mean),
            _pct(_coverage(p, mean)),
            for (final n in names) ...[
              answers[n] == null
                  ? '-'
                  : '${_hex(answers[n]!.colour)}@${_pct(answers[n]!.share)}',
              out[n]!.colour == null ? '-' : _hex(out[n]!.colour!),
              _pct(out[n]!.coverage),
            ],
          ].join('\t'),
        );
      }
    });
    client.close();

    File('$_dir/policies.tsv').writeAsStringSync(
      [
            'title',
            'paper',
            'head',
            'foot',
            'band',
            'mean',
            'cov_mean',
            for (final n in names) ...['m_$n', 'A_$n', 'cov_$n'],
          ].join('\t') +
          '\n${ledger.join('\n')}\n',
    );

    // ignore: avoid_print
    void say(String s) => print(s);

    final n = ledger.length;
    say(
      'covers $n (failed $failed), paper margins $papers, '
      'head strips $raw of which $walked survive the depth walk, '
      'foot strips $footBands, head bands $bands\n'
      'threshold $_sharePct%, split $_splitMinPct%, band depth<=$_bandMaxDepthPct% '
      'row>=$_bandRowSharePct% flank<=$_bandMaxFlankPct%, reach>=$_reachMinFlankPct%, '
      'strip>=$_bandMinStripPct%',
    );
    say('');
    say('policy    median  <5%  mean!    vs base        vs all5');
    say('                             better worse   better worse   net');
    for (final name in names) {
      final s = [...scores[name]!]..sort();
      var b1 = 0, w1 = 0, b2 = 0, w2 = 0;
      for (var i = 0; i < n; i++) {
        final v = scores[name]![i];
        if (v > scores['base']![i] + 0.005) b1++;
        if (v < scores['base']![i] - 0.005) w1++;
        if (v > scores['all5']![i] + 0.005) b2++;
        if (v < scores['all5']![i] - 0.005) w2++;
      }
      say(
        '${name.padRight(9)} '
        '${_pct(s[s.length ~/ 2]).padLeft(5)}% '
        '${scores[name]!.where((c) => c < 0.05).length.toString().padLeft(4)} '
        '${fallbacks[name]!.toString().padLeft(5)} '
        '${b1.toString().padLeft(9)} '
        '${w1.toString().padLeft(5)} '
        '${b2.toString().padLeft(8)} '
        '${w2.toString().padLeft(5)} '
        '${(b2 - w2).toString().padLeft(5)}',
      );
    }
    say('');
    final hs = [...headShare]..sort();
    final ar = [...ratios]..sort();
    say(
      'the head strip is ${_pct(hs.first)}-${_pct(hs.last)}% of the pooled border '
      '(median ${_pct(hs[hs.length ~/ 2])}%), so a band across the head cannot reach '
      'the $_sharePct% threshold. Aspect ratios ${ar.first.toStringAsFixed(2)}-'
      '${ar.last.toStringAsFixed(2)}.',
    );
    say(
      '$fellBack covers fell back to the mean; $addressable of them have a head band '
      'to blame.',
    );
    say('');
    say('the head-band rule moves ${fired.length}:');
    for (final f in fired) {
      say('  $f');
    }
    say('wrote $_dir/policies.tsv');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
