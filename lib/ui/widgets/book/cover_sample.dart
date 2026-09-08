import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The average colour of a decoded cover: an alpha-weighted arithmetic mean of
/// every pixel, computed in Dart.
///
/// There is exactly **one** implementation of this, and two callers with very
/// different jobs — `BookWidget`, which samples whatever it has just drawn, and the
/// backfill tool in `test/cover_color_backfill_tool.dart`, which samples a whole
/// library at once. A stored colour that disagreed with a live one would be worse
/// than no stored colour, because a book's spine is derived from this value and sits
/// directly beside the cover it was averaged from.
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
  final px = data.buffer.asUint8List();

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

/// The cover's **dominant** colour, and what share of the cover it occupies.
///
/// The complement to [averageCoverColor], and the two answer genuinely different
/// questions. A mean mixes everything on the jacket — background, type, artwork,
/// margins — so a bright yellow cover with black type and a small illustration
/// averages to olive. This finds the colour the cover mostly *is*.
///
/// A quantised histogram mode, not a clustering algorithm: each channel is reduced
/// to 5 bits (32 levels, 32,768 bins), the fullest bin wins, and the answer is the
/// exact mean of the pixels *in that bin*, so the quantisation never reaches the
/// returned value. One pass and one map, no iteration to convergence — k-means or
/// median-cut would produce a whole palette, and this needs one colour.
///
/// [share] is the fraction of opaque pixels in the winning bin, and it is returned
/// rather than acted on because the policy belongs to the caller. It is the honest
/// measure of whether a cover *has* a dominant colour at all: a flat background
/// scores high, a photograph or a gradient scores low and the caller should prefer
/// the mean.
///
/// Fully transparent pixels are skipped, so a jacket with a cut-out background is
/// measured on the pixels it actually has. Returns null when there are none.
Future<({Color colour, double share})?> dominantCoverColor(
  ui.Image image,
) async {
  final data = await image.toByteData();
  if (data == null) return null;
  final px = data.buffer.asUint8List();

  final counts = <int, int>{};
  final sumR = <int, int>{};
  final sumG = <int, int>{};
  final sumB = <int, int>{};
  var opaque = 0;

  for (var i = 0; i + 3 < px.length; i += 4) {
    if (px[i + 3] < 128) continue;
    final r = px[i], g = px[i + 1], b = px[i + 2];
    final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    counts[key] = (counts[key] ?? 0) + 1;
    sumR[key] = (sumR[key] ?? 0) + r;
    sumG[key] = (sumG[key] ?? 0) + g;
    sumB[key] = (sumB[key] ?? 0) + b;
    opaque++;
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

/// How much of the cover counts as its border, as a fraction of the shorter side.
///
/// 8% of a 120px-wide thumbnail is ~10px in from each edge. Wide enough to survive
/// JPEG ringing and a scanned cover's slightly ragged edge, narrow enough that a
/// title set near the top does not reach into it.
const double _borderFraction = 0.08;

/// The colour of the cover's **background**, taken from its border, and what share
/// of that border agrees.
///
/// The third answer to "what colour is this book", and the one that matches what a
/// person means by it. [averageCoverColor] mixes everything on the jacket, so bright
/// yellow with black type averages to olive. [dominantCoverColor] is worse than it
/// sounds: 5-bit quantisation collapses every dark pixel into a handful of bins
/// while a real background spreads across many of them (gradients, JPEG ringing), so
/// **black type reliably beats the background** — measured on real covers, a
/// brown-and-black jacket returned `#020101` on 21% of its pixels, and a pink one
/// returned the white of its margin on 13%.
///
/// A book cover's background is the thing that reaches its edges. So this histograms
/// the outer ring only, [_borderFraction] of the shorter side. Type, artwork and
/// photographs sit inside that ring and are not counted at all.
///
/// [share] is the fraction of the ring in the winning bin, and the caller decides
/// what to do with it. It is a real signal rather than a formality: a flat background
/// scores very high, a cover whose art bleeds to the edges scores low, and below some
/// threshold the mean is the better answer.
///
/// As in [dominantCoverColor], the winning bin's exact mean is returned, so the
/// quantisation never reaches the result.
Future<({Color colour, double share})?> coverBackgroundColor(
  ui.Image image,
) async {
  final data = await image.toByteData();
  if (data == null) return null;
  final px = data.buffer.asUint8List();
  final w = image.width, h = image.height;
  if (w == 0 || h == 0) return null;

  final shorter = w < h ? w : h;
  final ringPx = (shorter * _borderFraction).round();
  final ring = ringPx < 1 ? 1 : ringPx;

  final counts = <int, int>{};
  final sumR = <int, int>{};
  final sumG = <int, int>{};
  final sumB = <int, int>{};
  var opaque = 0;

  for (var y = 0; y < h; y++) {
    final band = y < ring || y >= h - ring;
    for (var x = 0; x < w; x++) {
      if (!band && x >= ring && x < w - ring) continue;
      final i = (y * w + x) * 4;
      if (i + 3 >= px.length || px[i + 3] < 128) continue;
      final r = px[i], g = px[i + 1], b = px[i + 2];
      final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
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

/// How much of a cover's border ring must agree before its colour is taken as the
/// cover's background rather than falling back to the mean.
///
/// **Measured, not guessed.** Across the 471 covers in the real library this sits on
/// a smooth curve, so the number is a judgement about where a ring stops being
/// evidence: 0.30 sends 56% of the library down the background path, 0.35 sends 47%,
/// 0.40 sends 41%, 0.50 sends 32%. 0.35 is where the covers still choosing the mean
/// are, on inspection, the ones that should — art bleeding to the edges, photographs,
/// and jackets banded in two colours.
///
/// The honest hard case is `역행자`: an orange jacket with black bands across the top
/// *and* the bottom, so its ring is 23% black and no method finds the orange at all.
/// It falls back to a brown mean, which is the best answer available rather than a
/// good one.
///
/// Cheap to revisit — re-sampling the whole library takes about three minutes, so this
/// is not a threshold anyone is stuck with.
const double kCoverBackgroundMinShare = 0.35;

/// **The one colour the app stores for a book.** The other three functions in this
/// file are ingredients; this is the answer.
///
/// [coverBackgroundColor] when the border ring is convincing, [averageCoverColor]
/// otherwise. Both paths exist because neither is right on its own:
///
///  * The mean alone cannot express a flat cover. `주식투자 안내서` is a bright yellow
///    jacket whose ring is 48% `#FEEE02`; its mean is `#979015`, an olive that is not
///    anywhere on the book.
///  * The ring alone cannot express a cover that has no background. A photograph
///    bleeding to the edges has a ring, but that ring is not the book's colour, and
///    the mean of the whole jacket is much closer to what a person would say.
///
/// **Every writer of `books.cover_color` must go through here, and that is
/// load-bearing.** `BookWidget` writes this value from a render path and
/// `test/cover_color_backfill_tool.dart` writes it from a dump. If the two resolved
/// differently, a book sampled on a device would get a visibly different spine from
/// an identical book that was backfilled, and nothing would ever reconcile them —
/// `recordCoverColor` skips any book that already has a colour.
///
/// Reads the pixels twice, once per ingredient. Left that way deliberately: these are
/// Kakao `R120x174` thumbnails, so it is two passes over 21k pixels once per book per
/// session, and fusing the loops would produce one function that could not be tested
/// against either of the questions it answers.
Future<Color?> coverToneColor(ui.Image image) async {
  final background = await coverBackgroundColor(image);
  if (background != null && background.share >= kCoverBackgroundMinShare) {
    return background.colour;
  }
  return averageCoverColor(image);
}
