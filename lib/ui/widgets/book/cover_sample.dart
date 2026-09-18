import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Pixels of a decoded cover, so the several questions asked of one image share a
/// single `toByteData`.
///
/// [coverToneColor] used to read the pixels twice — once for the border, once for the
/// mean — and the border now asks more than one question of them. Decoding once and
/// passing this around costs fewer passes than the two-function version did, not more.
class _Pixels {
  final Uint8List px;
  final int w, h;
  const _Pixels(this.px, this.w, this.h);

  static Future<_Pixels?> of(ui.Image image) async {
    final data = await image.toByteData();
    if (data == null || image.width == 0 || image.height == 0) return null;
    return _Pixels(data.buffer.asUint8List(), image.width, image.height);
  }

  /// Half-transparent counts as absent, so a jacket with a cut-out background is
  /// measured on the pixels it actually has.
  bool opaque(int x, int y) {
    final i = (y * w + x) * 4;
    return i + 3 < px.length && px[i + 3] >= 128;
  }

  int r(int x, int y) => px[(y * w + x) * 4];
  int g(int x, int y) => px[(y * w + x) * 4 + 1];
  int b(int x, int y) => px[(y * w + x) * 4 + 2];
}

/// The average colour of a decoded cover: an alpha-weighted arithmetic mean of
/// every pixel, computed in Dart.
///
/// The fallback rather than the answer — see [coverToneColor] — but still the value a
/// cover lands on when its border says nothing, so it has to be right.
///
/// **This used to be a 1×1 `drawImageRect`, handing the averaging to the
/// rasteriser, and that was wrong on the device.** The theory was that a huge
/// downscale builds a mipmap chain and the last level is the average. Skia's
/// software backend does roughly that — measured within ~20/255 of a true mean on 56
/// real covers. Impeller, which is what iOS actually runs, does not: at a 1×1
/// destination it effectively returns a single texel. Measured against the same 56
/// covers the device's answers were **up to 110/255 away from the mean, and more
/// saturated than any average can be** — a mostly-white jacket with black type
/// stored as near-white `#EFEAEB` where its mean is `#A6A3A4`. Every back board in
/// the app was tinted from an arbitrary pixel of its cover.
///
/// So it is done in Dart, and the reasons are worth keeping:
///
///  * **Correct.** It is the mean, not an approximation of one.
///  * **Deterministic.** No renderer, no backend, no platform in the answer. A
///    value sampled on a phone, in a widget test, and by a command-line tool are
///    the same value, which is the only thing that makes a backfill honest.
///  * **Cheap enough.** The old comment justified the GPU by "walking a few hundred
///    thousand pixels in Dart", but the covers this app loads are Kakao's
///    `R120x174` thumbnails — 21k pixels, one pass, once per book per session.
///
/// Averaged in **sRGB** rather than in linear light, deliberately. Linear averaging
/// is the physically correct way to average *light*, and it is the wrong answer for
/// this: it weights bright pixels by their true luminance, so any cover with a light
/// background comes out near-white and loses the book's identity — which is the same
/// failure the device's single-texel sampling produced. This value is used as a
/// *surface tone*, and a gamma-space mean is the one that reads as "the colour of
/// that book".
///
/// Alpha-weighted, so a cover with transparency is averaged over the pixels it
/// actually has rather than being dragged toward black. `rawRgba` is premultiplied,
/// which makes that fall out for free: `Σ(r·a/255) / Σ(a) · 255` is the
/// straight-alpha mean without a per-pixel divide.
///
/// Returns null when the pixels cannot be read, or when the image is fully
/// transparent. The caller should treat that as "no colour yet" rather than as an
/// error: the cover still draws.
Future<Color?> averageCoverColor(ui.Image image) async {
  final data = await image.toByteData();
  if (data == null) return null;
  return _average(data.buffer.asUint8List());
}

Color? _average(Uint8List px) {
  var r = 0, g = 0, b = 0, a = 0;
  for (var i = 0; i + 3 < px.length; i += 4) {
    r += px[i];
    g += px[i + 1];
    b += px[i + 2];
    a += px[i + 3];
  }
  if (a == 0) return null;

  int channel(int sum) => ((sum * 255) / a).round().clamp(0, 255);
  return Color.fromARGB(255, channel(r), channel(g), channel(b));
}

/// Bin width for every histogram in this file, in bits per channel.
///
/// **4, not 5, and that is a correction rather than a tuning.** Uniform-width RGB bins
/// are perceptually uneven: because of gamma, an 8-level gap among near-blacks is a far
/// smaller visual step than the same gap at the light end, so a dark grainy background
/// fragments across many bins while looking perfectly flat to the eye. `The House of
/// the Scorpion` is a black jacket whose border is 66% one near-black at 4 bits and only
/// 31% at 5 — under 5 bits it failed the threshold and stored `#651614`, a dark red
/// mixed out of its scorpion.
///
/// Measured across 460 covers: widening the bins moves 56 of them and **improves all 56**
/// by the coverage measure below, with no cover made worse. The principled version of
/// this is to bin in a perceptually uniform space; 4 bits is the cheap approximation
/// that captures most of it.
const int _binBits = 4;

/// The top [n] bins of a histogram over the pixels [include] accepts, biggest first.
///
/// Each result carries the exact mean of the pixels *in its own bin*, so the
/// quantisation never reaches a returned value.
///
/// [exclude] drops pixels near a colour — used to take a paper margin out of the
/// reckoning. See [_paperMargin].
List<({Color colour, double share})> _modes(
  _Pixels p,
  bool Function(int x, int y) include, {
  int bits = _binBits,
  ({int r, int g, int b})? exclude,
  int n = 1,
}) {
  final shift = 8 - bits;
  final counts = <int, int>{};
  final sumR = <int, int>{};
  final sumG = <int, int>{};
  final sumB = <int, int>{};
  var total = 0;

  for (var y = 0; y < p.h; y++) {
    for (var x = 0; x < p.w; x++) {
      if (!include(x, y) || !p.opaque(x, y)) continue;
      final r = p.r(x, y), g = p.g(x, y), b = p.b(x, y);
      if (exclude != null &&
          (r - exclude.r).abs() <= _paperTolerance &&
          (g - exclude.g).abs() <= _paperTolerance &&
          (b - exclude.b).abs() <= _paperTolerance) {
        continue;
      }
      final key =
          ((r >> shift) << (bits * 2)) | ((g >> shift) << bits) | (b >> shift);
      counts[key] = (counts[key] ?? 0) + 1;
      sumR[key] = (sumR[key] ?? 0) + r;
      sumG[key] = (sumG[key] ?? 0) + g;
      sumB[key] = (sumB[key] ?? 0) + b;
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
          (sumR[k]! / counts[k]!).round(),
          (sumG[k]! / counts[k]!).round(),
          (sumB[k]! / counts[k]!).round(),
        ),
        share: counts[k]! / total,
      ),
  ];
}

/// What fraction of the whole jacket is within [_paperTolerance] of [c].
///
/// **The measure of whether a colour is really the book's**, and the tie-break and the
/// paper gate both rest on it. A printed foot-band scores low because it is a band; a
/// mean often scores near zero, because an average is usually a colour that appears
/// nowhere on the cover. Across the 460-cover corpus the median coverage of the stored
/// value rose from 25% to 40% under the policy below, and the number of books storing a
/// colour present on under 5% of their own jacket fell from 160 to 94.
///
/// **It has one bias, and it is load-bearing when reading any sweep against it: it is
/// monotone in [kCoverBackgroundMinShare].** Accepting a border almost always beats
/// falling back to a mean by this measure, so lowering the threshold always improves it —
/// see the note there. Coverage can rank two ways of *reading* a border; it cannot decide
/// how much agreement to demand.
double _coverage(_Pixels p, Color c) {
  final cr = (c.r * 255).round(), cg = (c.g * 255).round();
  final cb = (c.b * 255).round();
  var hit = 0, all = 0;
  for (var y = 0; y < p.h; y++) {
    for (var x = 0; x < p.w; x++) {
      if (!p.opaque(x, y)) continue;
      all++;
      if ((p.r(x, y) - cr).abs() <= _paperTolerance &&
          (p.g(x, y) - cg).abs() <= _paperTolerance &&
          (p.b(x, y) - cb).abs() <= _paperTolerance) {
        hit++;
      }
    }
  }
  return all == 0 ? 0 : hit / all;
}

/// The cover's **dominant** colour, and what share of the cover it occupies.
///
/// Not used to store anything, and the measurements are the reason. As a policy this
/// loses badly to the border: over 460 covers it is confident about 185 against the
/// border's 307, because a whole jacket rarely has any one colour at
/// [kCoverBackgroundMinShare]. Worse, where it *is* confident it is often confident
/// about type — the mode of `주식투자 안내서`, a bright yellow book, is its black
/// lettering.
///
/// Kept because it is the honest statement of "the biggest single colour on this
/// cover", it is what the tie-break in [coverBackgroundColor] reaches for in spirit,
/// and a future reader will otherwise reinvent it. Runs at 5 bits, unlike everything
/// else here, so its answer is unchanged from when it was measured.
Future<({Color colour, double share})?> dominantCoverColor(
  ui.Image image,
) async {
  final p = await _Pixels.of(image);
  if (p == null) return null;
  final modes = _modes(p, (x, y) => true, bits: 5);
  return modes.isEmpty ? null : modes.first;
}

/// How much of the cover counts as its border, as a fraction of the shorter side.
///
/// 8% of a 120px-wide thumbnail is ~10px in from each edge. Wide enough to survive
/// JPEG ringing and a scanned cover's slightly ragged edge, narrow enough that a
/// title set near the top does not reach into it.
///
/// **It also carries the invariant that makes correction 1's asymmetry safe**, so it is
/// worth more than its one line suggests. The foot is dropped unconditionally and the
/// head is read, and the obvious objection is that a band across the head is no more
/// trustworthy than one across the foot — `역행자` is an orange jacket banded in black at
/// head *and* foot. It is no more trustworthy, and it is already harmless, because
/// pooling the edges bounds how much of the border a head band can ever be:
///
///     head strip     w·b
///     flanks         2b·(h − 2b)
///     head's share   w / (w + 2(h − 2b))  =  1 / (1 + 2k − 4f)
///
/// for aspect ratio k = h/w and this fraction f. Counted over the 460-cover corpus, whose
/// ratios run 0.65–0.69, the head strip is **27–28% of the pooled border** — so a band
/// across the head cannot reach [kCoverBackgroundMinShare] however solid it is, and where
/// it comes close enough to split the border with the real background, [_kSplitMinShare]
/// hands the decision to area, which a band loses. `역행자` stores its orange.
///
/// The bound holds while `1 / (1 + 2k − 4f) < kCoverBackgroundMinShare`, which at f = 0.08
/// is every cover taller than about 1.09× its width. **Widening f erodes it** — f would
/// have to pass 0.26 to let a head band through at k = 1.45 — so a future reader
/// stretching this to cope with raggeder edges should know that is part of what they are
/// spending, and should re-run the probe rather than reason about it.
///
/// **Four ways of correcting the head anyway were measured, and all four rejected.** They
/// are recorded because "handle a band at the top too" is the obvious next request, and
/// because three of them look right on paper. Net figures are covers improved minus
/// covers made worse against the pre-change design, over the same 460 covers; the shipped
/// policy scores +106.
///
///  * *Walk down from row 0 while the rows stay uniform, then read the border from below
///    the strip.* **Net +87, and 30 covers worse than shipped.** It fires on 302 of 460
///    covers, because "a uniform strip that ends" describes an ordinary background
///    interrupted by a band exactly as well as it describes the band: it strips `역행자`'s
///    orange — the background — because the black starts 7px down.
///  * *The same, gated on the strip's colour being absent from the flanks below it.* The
///    gate is the right idea and cuts 302 firings to 10, but **all 10 change nothing.**
///  * *Strike a winning candidate that does not reach the flanks.* Moves **nothing** at
///    any cap up to 20%, because a colour that fails to reach the flanks never wins in the
///    first place. The bound above is why.
///  * *Strike the head strip's mode by colour when it fills that strip and stays off the
///    flanks — the exact mirror of [_paperMargin].* The most promising of the four and
///    still a **no-op**: 3 covers of 460 have such a band, and none of them is among the
///    153 that fall back to a mean. Swept over strip shares 35–55% and flank caps 5–25%;
///    the only settings that move anything are the loose ones that have started striking
///    real backgrounds, at 4 better against 2 worse.
///
/// Symmetry was tested too — detect bands at head *and* foot and read a plain four-sided
/// ring on what is left, instead of dropping the foot unconditionally — and it is much
/// worse: **net +68, with 53 covers worse than shipped.** The foot drop is not a crude
/// band detector that real band detection improves on. The foot is *systematically*
/// untrustworthy in a way the head is not, and a detector that has to fire is a detector
/// that can miss.
const double _borderFraction = 0.08;

/// Per-channel slack when deciding two pixels are the same colour.
///
/// Loose enough to bridge JPEG ringing across a flat scan, tight enough that a cream
/// and a white stay apart.
const int _paperTolerance = 20;

/// Depth of the strip a paper margin is nominated from.
///
/// The outermost two lines only. A margin is trim, so the evidence for it is at the very
/// edge; looking deeper starts reading the jacket.
const int _paperProbe = 2;

/// How much of its own side a margin candidate must hold.
const double _paperMinSideShare = 0.55;

/// ...and at most this much of the middle of the cover.
///
/// A background reaches the interior; trim does not.
const double _paperMaxInteriorShare = 0.10;

/// ...and at most this much of the whole jacket.
///
/// **The gate that makes the rule safe, and it was learnt the hard way.** Without it,
/// "uniform at the edge and absent in the middle" also describes a white book with
/// central artwork, and the rule deletes the book's own background: measured over 460
/// covers, `김대중 자서전` went from storing `#FFFFFD`, present on 66% of its jacket, to a
/// grey present on 0% of it, and twelve more failed the same way. The interior test
/// cannot separate those — a white cover with a big illustration also has little white
/// in the middle — but area can. Trim is a few percent of an image; a white cover is a
/// quarter of it or more.
///
/// 0.25 swept against 0.10, 0.15, 0.20 and no gate at all: it removes ten of the sixteen
/// regressions the ungated rule caused and keeps every improvement.
const double _paperMaxCoverage = 0.25;

/// A margin also has to *look* like paper: light, and with no hue of its own.
///
/// Without these two, the rule nominated Eldest's crimson, `Work Rules!`'s yellow,
/// Eragon's navy and Scorpion's near-black — every one of them the background the
/// sampler exists to find.
const double _paperMinLuminance = 0.75;
const int _paperMaxChroma = 20;

/// The colour of the paper a cover was photographed on, when the image has some.
///
/// Book images are often shot or composited on white, so the jacket sits inside a light
/// frame that belongs to the photograph rather than to the book. It is not confined to
/// one edge, which is why it has to be identified by colour and removed rather than by
/// dropping a side: `매치메이커스` is a dark jacket whose *bottom* is 94% white and whose
/// left and right edges are 32% white each.
///
/// Nominated **per side**, not from the pooled border, because a margin is often on one
/// side only — `피터 드러커` is dark across its head and white across its foot, so the
/// pooled mode is the jacket and the margin never gets considered at all.
///
/// A candidate must clear four gates, and each one exists because of a specific way an
/// earlier version was wrong: [_paperMinSideShare], [_paperMinLuminance] with
/// [_paperMaxChroma], [_paperMaxInteriorShare], and [_paperMaxCoverage].
({int r, int g, int b})? _paperMargin(_Pixels p) {
  final probe = _paperProbe.clamp(1, (p.w < p.h ? p.w : p.h));
  final sides = <bool Function(int, int)>[
    (x, y) => y >= p.h - probe,
    (x, y) => y < probe,
    (x, y) => x < probe,
    (x, y) => x >= p.w - probe,
  ];

  ({int r, int g, int b})? best;
  var bestShare = 0.0;
  for (final side in sides) {
    final modes = _modes(p, side);
    if (modes.isEmpty || modes.first.share < _paperMinSideShare) continue;
    final c = modes.first.colour;
    final r = (c.r * 255).round(), g = (c.g * 255).round();
    final b = (c.b * 255).round();

    final hi = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final lo = r < g ? (r < b ? r : b) : (g < b ? g : b);
    if (c.computeLuminance() < _paperMinLuminance ||
        hi - lo > _paperMaxChroma) {
      continue;
    }

    var hit = 0, all = 0;
    for (var y = (p.h * 0.25).round(); y < p.h * 0.75; y++) {
      for (var x = (p.w * 0.25).round(); x < p.w * 0.75; x++) {
        if (!p.opaque(x, y)) continue;
        all++;
        if ((p.r(x, y) - r).abs() <= _paperTolerance &&
            (p.g(x, y) - g).abs() <= _paperTolerance &&
            (p.b(x, y) - b).abs() <= _paperTolerance) {
          hit++;
        }
      }
    }
    if (all == 0 || hit / all > _paperMaxInteriorShare) continue;
    if (_coverage(p, c) > _paperMaxCoverage) continue;

    if (modes.first.share > bestShare) {
      bestShare = modes.first.share;
      best = (r: r, g: g, b: b);
    }
  }
  return best;
}

/// How much of the border's top two candidates must each hold before the border counts
/// as *split* rather than merely unconvincing.
///
/// A two-tone jacket divides its own border, so neither half reaches
/// [kCoverBackgroundMinShare] and the cover falls to a mean that is on neither half.
/// `세대를 뛰어넘어 함께 일하기` is white across its top quarter and yellow below; its border
/// is 93% white along the head and yellow down both sides.
///
/// **Validated in place rather than in isolation**, which is the only honest way to score
/// the last rule in a stack: with the other two corrections left on and this one removed,
/// **9 of the 460 covers get worse and none get better**, and the number storing a colour
/// present on under 5% of their own jacket goes from 94 to 97. The corpus is the whole
/// `books` table — 460 distinct covers across 74 readers — not one shelf, and
/// `test/cover_policy_probe_tool.dart` reproduces the figure as its `noTie` column.
///
/// It also does quiet work at the head. A band across the top can reach 28% of the pooled
/// border but no more (see [_borderFraction]), so where it comes close enough to split the
/// border with the real background, this is the rule that hands the decision to area — and
/// a band loses on area, because a band is a band. No cover in the corpus needs that,
/// which is the point: it is the reason none does.
const double _kSplitMinShare = 0.22;

/// The colour of the cover's **background**, and what share of the evidence agrees.
///
/// The answer a person means by "what colour is that book". [averageCoverColor] mixes
/// everything on the jacket, so bright yellow with black type comes out olive;
/// [dominantCoverColor] is worse than it sounds, because black lettering beats a real
/// background.
///
/// A book cover's background is the thing that reaches its edges, so this histograms the
/// border — [_borderFraction] of the shorter side — and returns its mode. Type, artwork
/// and photographs sit inside that border and are not counted.
///
/// Three things then correct the border, each measured over 460 real covers and each
/// answering a different way the plain version was wrong:
///
///  1. **The foot is not read.** The bottom edge is the least trustworthy part of a
///     book image: an obi, a printed foot-band, or the paper the book was photographed
///     on. Of 77 covers examined by hand, 14 had a bottom edge both highly uniform and
///     nothing like any other edge. `주식투자 안내서` has a bottom edge that is 100% black
///     on a bright yellow book. The flanks stop short of the foot as well, since trim
///     and obi both wrap the corners — measured, that is worth another three covers.
///
///     **The foot only, and the asymmetry is measured rather than assumed.** A band
///     across the *head* is just as much a lie about the jacket, and needs no correction
///     because pooling the edges already bounds it below the acceptance threshold — the
///     algebra and the four rejected attempts are in [_borderFraction].
///  2. **A paper margin is excluded by colour.** [_paperMargin], because trim is not
///     confined to the bottom.
///  3. **A split border is decided by area.** Where the top two candidates each hold a
///     real part of the border but neither carries it, the one covering more of the
///     whole jacket wins, and is reported at that *coverage* rather than at its border
///     share — so [kCoverBackgroundMinShare] still decides whether the cover really is
///     mostly that colour. Worth 9 covers and no regressions on its own; see
///     [_kSplitMinShare].
///
/// [share] is returned rather than acted on, because the policy belongs to the caller.
/// See [coverToneColor].
///
/// As in [dominantCoverColor], the winning bin's exact mean is returned, so the
/// quantisation never reaches the result.
Future<({Color colour, double share})?> coverBackgroundColor(
  ui.Image image,
) async {
  final p = await _Pixels.of(image);
  return p == null ? null : _background(p);
}

({Color colour, double share})? _background(_Pixels p) {
  final shorter = p.w < p.h ? p.w : p.h;
  final band = (shorter * _borderFraction).round().clamp(1, shorter);

  // Head and flanks, with the flanks stopping short of the foot. See correction 1.
  bool border(int x, int y) =>
      y < band || ((x < band || x >= p.w - band) && y < p.h - band);

  final top = _modes(p, border, exclude: _paperMargin(p), n: 2);
  if (top.isEmpty) return null;
  if (top.first.share >= kCoverBackgroundMinShare) return top.first;

  if (top.length == 2 &&
      top[0].share >= _kSplitMinShare &&
      top[1].share >= _kSplitMinShare) {
    final a = _coverage(p, top[0].colour);
    final b = _coverage(p, top[1].colour);
    return a >= b
        ? (colour: top[0].colour, share: a)
        : (colour: top[1].colour, share: b);
  }
  return top.first;
}

/// How much of the evidence must agree before it is taken as the cover's background
/// rather than falling back to the mean.
///
/// **Measured, not guessed** — but not by the obvious measure, and the reason matters. The
/// coverage score in [_coverage] is *monotone* in this constant: swept from 50% down to
/// 5% it improves without ever turning over (net +34, +58, +81, +106, +116, +134, +158,
/// +177, +197, +220), because accepting a border almost always beats falling back to a
/// mean by that measure. Read on its own it argues for a threshold of zero, which would
/// abolish the fallback and with it every cover that genuinely has no background.
///
/// The count of covers made **worse** than the pre-change design is not monotone, and
/// that is what chooses the value. Over the same sweep it runs 13, 10, 9, 8, 9, 10, **7**,
/// 11, 20, 23 for 5%, 10%, ... 50% — a clear minimum at **0.35**. Above it the threshold
/// starts rejecting real backgrounds; below it the border starts being believed when it
/// has not earned it.
///
/// That it survived every correction above unchanged is worth stating: none of them
/// needed the threshold moved to pay off.
///
/// The honest hard case is `역행자`: an orange jacket banded in black at head and foot.
/// Its border is 23% black at 5 bits and no method found the orange at all — the top
/// edge turns out to be 59% orange once the bins are widened, and dropping the foot lets
/// it win.
///
/// Cheap to revisit — `test/cover_policy_probe_tool.dart` reproduces the whole sweep
/// against a warm cache in seconds, and `test/cover_color_backfill_tool.dart` prints the
/// before and after for the library.
const double kCoverBackgroundMinShare = 0.35;

/// **The one colour the app stores for a book.** The other functions in this file are
/// ingredients; this is the answer.
///
/// [coverBackgroundColor] when the evidence is convincing, [averageCoverColor]
/// otherwise. Both paths exist because neither is right on its own:
///
///  * The border alone cannot express a cover that has no background. A photograph
///    bleeding to the edges has a border, but that border is not the book's colour, and
///    the mean of the whole jacket is much closer to what a person would say.
///  * The mean alone cannot express a flat cover. `주식투자 안내서` is a bright yellow
///    jacket; its mean is `#979015`, an olive that is not anywhere on the book.
///
/// The second failure is much the more common of the two. Over the 460-cover corpus the
/// mean is a colour present on a median of **3%** of its own jacket, so the fallback is
/// genuinely a last resort: it is reached 153 times, down from 242 before the corrections
/// in [coverBackgroundColor].
///
/// **Every writer of `books.cover_color` must go through here, and that is
/// load-bearing.** `BookWidget` writes this value from a render path and
/// `test/cover_color_backfill_tool.dart` writes it from a dump. If the two resolved
/// differently, a book sampled on a device would get a visibly different spine from
/// an identical book that was backfilled, and nothing would ever reconcile them —
/// `recordCoverColor` skips any book that already has a colour.
Future<Color?> coverToneColor(ui.Image image) async {
  final p = await _Pixels.of(image);
  if (p == null) return null;
  final background = _background(p);
  if (background != null && background.share >= kCoverBackgroundMinShare) {
    return background.colour;
  }
  return _average(p.px);
}
