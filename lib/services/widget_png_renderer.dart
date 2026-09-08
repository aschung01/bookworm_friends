import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Rasterises a widget to PNG bytes by hosting it off-screen in the [Overlay].
///
/// Built for the Library Card's share, and it does not screenshot the sheet for two
/// reasons, either of which would be enough.
///
/// **The sheet is not the artifact.** It carries a grab handle, a share button, a
/// year filter and whatever scroll offset the reader left it at, and its width is
/// the phone's. The exported card has none of those and a pinned size.
///
/// **`RepaintBoundary.toImage` cannot capture platform views.** The selected year
/// capsule above the card puts a native glass `CNButton` behind its label on
/// iOS 26 — a real `UIView` composited by the platform, not something Flutter
/// paints — so a screenshot of the live sheet would arrive with a hole where it is. It would also only ever show up on a
/// device: `flutter test` reports Android, so a test captures the painted
/// fallback. Hence a separate, pure-Flutter tree, and [widget] must stay free of
/// native controls for the same reason.
///
/// **Why the overlay rather than a pipeline of its own.** The tidier design is to
/// build a `RenderView` with a `BuildOwner` and `PipelineOwner` this function owns,
/// which needs no tree at all and no frame timing. It does not work: mounting a
/// `View` widget calls `RendererBinding.addRenderView`, which asserts the view id is
/// not already registered — and the app's own window is already registered under it.
/// A second `ui.FlutterView` would be needed, and there is only one. So the subtree
/// is hosted in the overlay instead, positioned off the left edge.
///
/// Positioning off-screen is enough, and specifically **`Offstage`, `Visibility` and
/// `Opacity(0)` are not**: all three skip painting, and a boundary that never
/// painted has no layer to rasterise. An out-of-bounds `Positioned` still lays out
/// and paints; only the compositor declines to show it. Any clip an ancestor applies
/// is irrelevant, because `toImage` re-renders from the boundary's own layer
/// downward.
///
/// The size is pinned rather than taken from the phone, so the same card comes out
/// of a 375pt SE and a 440pt Pro Max identically — which matters for an image that
/// leaves the app and is looked at beside other people's.
///
/// **The overlay gives the subtree no ancestor `Material`,** and `MaterialApp`
/// installs a fallback `DefaultTextStyle` for that case carrying a yellow double
/// underline (its own `debugLabel` says "consider putting your text in a Material").
/// A `Text` that sets its size and colour but not its decoration inherits the
/// underline, and it shows up nowhere except the exported file. [widget] must
/// therefore provide its own `Material`; [ShareableLibraryCard] does.
///
/// **[precache] is not optional in spirit.** `RepaintBoundary.toImage` re-renders
/// from the boundary's layer and paints only what is already decoded, so any
/// [ImageProvider] in [widget] that has not resolved by capture time is exported as a
/// hole. A caller that draws network images and passes nothing here gets that hole,
/// silently, and only ever sees it by opening the file. Hand it every provider the
/// subtree will draw — `cardCoverProviders` builds that list for the cover row.
///
/// **[warm] is the same promise for everything that is not an [ImageProvider].** An
/// `SvgPicture` loads its bytes asynchronously and paints nothing until they arrive, so a
/// vector in [widget] needs its own warm-up handed in here — see `warmReadingBookmark`.
/// Awaited together with [precache], because they are the same wait.
Future<Uint8List> captureWidgetToPng({
  required BuildContext context,
  required Widget widget,
  required Size logicalSize,
  double pixelRatio = 3.0,
  List<ImageProvider> precache = const [],
  List<Future<void>> warm = const [],
}) async {
  final overlay = Overlay.of(context);
  final boundaryKey = GlobalKey();
  final directionality = Directionality.of(context);

  // Before the subtree is mounted, not after: an image decoded while the overlay is
  // already up would repaint the boundary a frame or two later, and the two frames
  // waited on below would have gone by.
  await Future.wait([precacheAll(context, precache), ...warm]);

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Far enough left that no plausible screen reaches it. The offset is what
      // hides it; see the class doc for why the obvious alternatives do not work.
      left: -logicalSize.width - 64,
      top: 0,
      child: IgnorePointer(
        child: MediaQuery(
          // Its own MediaQuery, so the export is not restyled by the reader's
          // accessibility text scale. The card is laid out to a fixed size; at
          // 200% text it would clip, and the reader would have no way to know why
          // the image they shared is missing a line. What they see in the app is
          // still scaled — this governs the artifact only.
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
            size: logicalSize,
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
          ),
          child: Directionality(
            textDirection: directionality,
            child: SizedBox.fromSize(
              size: logicalSize,
              child: RepaintBoundary(key: boundaryKey, child: widget),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  try {
    // Two frames, not one. The first builds and lays the subtree out; the boundary
    // does not reliably have a painted layer until the frame after that, and
    // `toImage` on an unpainted boundary throws.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'the card was never laid out, so there is nothing to share',
      );
    }
    return rasterizeBoundary(boundary, pixelRatio: pixelRatio);
  } finally {
    entry.remove();
    entry.dispose();
  }
}

/// How long [precacheAll] waits for the images an export needs.
///
/// A budget rather than no limit, because the alternative failure is worse than a
/// hole: a single cover URL that never answers would hang the share behind its
/// spinner with nothing to cancel. Five seconds is long enough for a cold fetch of a
/// dozen thumbnails on a bad connection and short enough that a stuck one still
/// produces a card.
const Duration kPrecacheBudget = Duration(seconds: 5);

/// Waits for every provider a capture is about to draw to finish decoding.
///
/// Split out of [captureWidgetToPng] for the same reason [rasterizeBoundary] is: the
/// hosting half cannot be exercised under `flutter test`, and both halves either side
/// of it are where the "exported card with holes in it" bug lives. See
/// `test/widget_png_renderer_test.dart`.
///
/// **Errors are swallowed on purpose.** A cover whose URL is dead must not fail the
/// share; it is handled where it is drawn, by an `errorBuilder` that falls back to a
/// generated cover. Letting the error through here would turn one bad thumbnail into
/// a reader who cannot share at all.
Future<void> precacheAll(
  BuildContext context,
  List<ImageProvider> providers, {
  Duration budget = kPrecacheBudget,
}) async {
  if (providers.isEmpty) return;
  await Future.wait(
    providers.map(
      (provider) => precacheImage(provider, context, onError: (_, __) {}),
    ),
  ).timeout(budget, onTimeout: () => const <void>[]);
}

/// Turns an already-painted [RenderRepaintBoundary] into PNG bytes.
///
/// Split out from [captureWidgetToPng] so that the half where "blank image" bugs
/// actually live is testable. The hosting half is not: it waits on two real frames,
/// which under `flutter test` only arrive when the test pumps, while PNG encoding
/// needs `WidgetTester.runAsync` — and a test cannot pump from inside `runAsync`.
/// A test can, however, mount a boundary itself, pump it, and call this. See
/// `test/widget_png_renderer_test.dart`; the hosting half is verified on a device,
/// which the share flow requires anyway.
Future<Uint8List> rasterizeBoundary(
  RenderRepaintBoundary boundary, {
  double pixelRatio = 3.0,
}) async {
  ui.Image? image;
  try {
    image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('the rendered card produced no PNG bytes');
    }
    return data.buffer.asUint8List();
  } finally {
    image?.dispose();
  }
}
