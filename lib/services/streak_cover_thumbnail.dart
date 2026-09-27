import 'dart:ui' as ui;

// `Uint8List` comes from here rather than from `dart:typed_data`, which `foundation` re-exports.
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Builds the small PNG the home-screen widget draws as a jacket.
///
/// **Why this exists at all: `cover_color` is not a cover.** It is one colour sampled from the
/// jacket, and for the very many books whose cover is white paper it comes back near-white — so
/// the widget's jacket was a blank rectangle. The colour stays as the fallback; this upgrades it
/// to the real thing when the network allows.
///
/// **It re-fetches rather than reading the app's image cache, and that was a decision.** The
/// alternative was threading bytes out of the decode that `cover_sample.dart` already performs
/// for every cover on the shelves. That is free, and it permanently entangles the widget-sync
/// path with the shelf-rendering path: two features that have no reason to change together would
/// share a data flow, and a change to how shelves decode would be able to break the widget. One
/// request, on a book change only, buys that separation. (Reaching into
/// `cached_network_image_ce`'s own on-disk cache was never on the table — it couples us to
/// package internals that move on a version bump.)
///
/// **The widget itself never does any of this.** The extension is read-only and touches no
/// network; it loads a file the app has already written. That rule is why the fetch lives here.
class StreakCoverThumbnail {
  const StreakCoverThumbnail({http.Client? client}) : _client = client;

  /// Injected only so a test can answer without a socket. Null means "one client per call",
  /// which is right for a call that happens when the reader's book changes and not otherwise.
  final http.Client? _client;

  /// 120px, which is the 40pt jacket at @3x.
  ///
  /// **Sized for the widget, not for the source.** A WidgetKit extension gets a memory budget in
  /// the tens of megabytes and is killed rather than degraded when it misses, so shipping a
  /// full-resolution jacket into the App Group would put a publisher's 2000px artwork in a
  /// process that cannot afford to decode it. It is also the only reason the file is small enough
  /// that writing it on every book change is unremarkable.
  static const int targetWidth = 120;

  /// Refuse anything implausible for a cover before spending a decode on it.
  static const int _maxSourceBytes = 8 * 1024 * 1024;

  /// The encoded PNG, or null if anything at all went wrong.
  ///
  /// **Every failure is null and none of them throw.** The caller's fallback is the colour
  /// rectangle that shipped before this existed, so a 404, an offline phone or a corrupt body all
  /// degrade to the previous behaviour. Surfacing any of it would be an error about a home-screen
  /// surface the reader may not have installed, raised during a session they did not ask for it
  /// in — the same argument `StreakWidgetChannel` already makes for swallowing its own failures.
  Future<Uint8List?> build(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.host.isNotEmpty) return null;

    final client = _client ?? http.Client();
    Uint8List source;
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      source = response.bodyBytes;
    } catch (error) {
      debugPrint('streak cover: fetch failed ($error)');
      return null;
    } finally {
      // Only a client this method made is a client this method may close.
      if (_client == null) client.close();
    }

    if (source.isEmpty || source.lengthInBytes > _maxSourceBytes) return null;
    return _encode(source);
  }

  /// Decode at [targetWidth], re-encode as PNG.
  ///
  /// `targetWidth` alone scales the height proportionally, which matters: jackets are not one
  /// ratio, and pinning both axes here would distort every cover that is not 40:58. The widget
  /// crops to its frame instead, where the aspect is a layout decision rather than a baked-in one.
  Future<Uint8List?> _encode(Uint8List source) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(source, targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (error) {
      // A body that is not an image at all, which a CDN error page reached over HTTP 200 is.
      debugPrint('streak cover: decode failed ($error)');
      return null;
    } finally {
      // Both are native handles; `dart:ui` leaks them for as long as the isolate lives if the
      // frame throws between allocation and use.
      image?.dispose();
      codec?.dispose();
    }
  }
}
