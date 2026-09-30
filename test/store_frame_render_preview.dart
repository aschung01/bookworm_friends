// Not a test — a renderer. Composites App Store frames from the device captures under
// `docs/store/screenshots/1.1.0/capture/` and writes them to `build/store_frames/`.
//
//   flutter test test/store_frame_render_preview.dart
//
// **Why this is a Flutter renderer and not an image editor.** The captions have to be set
// in the app's own type and colour — `AppFonts.serif`, `context.colors.primaryText`,
// `brandText` — or the storefront and the product drift apart, which is the whole failure
// mode a hand-composited set has. It also makes the Korean set a re-run rather than 11
// more frames of hand-set Hangul, and a reworded caption a re-run rather than a redraw.
//
// Sizes are exact, not approximate: 440x956 logical at pixelRatio 3 is **1320x2868**,
// which is the iPhone 6.9" requirement. The iPad 13" pass is 1032x1376 at 2.
//
// This pass renders one capture in four caption treatments so the layout can be chosen by
// looking, which is the only way it can be chosen. See `_treatments`.
//
// Two traps this file is deliberately built around, both of which have already cost this
// repo a round:
//
//   * `FontLoader` carries no weight information, so one cut per family. Two Pretendard
//     statics would let the engine answer any weight with whichever arrived first — which
//     is how a preview once drew the w600 that had just been rejected while the app
//     shipped w400.
//   * The ground goes *inside* the `RepaintBoundary`. On the `Scaffold` it is painted
//     outside, the capture comes back transparent, and every value gets judged against
//     the viewer's white matte instead of the ground it actually sits on.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// `FontLoader` lives here, not in `flutter_test`.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';

/// The 6.9" requirement, in logical points at [_phoneRatio].
const _phoneLogical = Size(440, 956);
const _phoneRatio = 3.0;

/// Where the caption sits, and which edge the device bleeds off.
///
/// The device always bleeds off **one** edge. A fully contained phone floating in the
/// middle is what a template looks like; both references crop. Flighty crops off the
/// bottom and right for its hero frames and off the top and bottom for its feature
/// frames, and Duolingo has no device at all — so the cropping is the part the two
/// agree on, at opposite ends of everything else.
enum _Anchor { top, bottom }

class _Treatment {
  final String name;
  final _Anchor anchor;
  final TextAlign align;

  /// Flighty's pattern: a big line, then a lighter supporting line under it. Worth one
  /// of the four because a 4-6 word caption alone may read thin at this size.
  final bool supporting;

  const _Treatment(
    this.name,
    this.anchor,
    this.align, {
    this.supporting = false,
  });
}

const _treatments = <_Treatment>[
  _Treatment('a_top_centre', _Anchor.top, TextAlign.center),
  _Treatment('b_top_left', _Anchor.top, TextAlign.left),
  _Treatment('c_bottom_centre', _Anchor.bottom, TextAlign.center),
  _Treatment(
    'd_top_centre_sub',
    _Anchor.top,
    TextAlign.center,
    supporting: true,
  ),
];

/// Slot 1's caption and its supporting line, from `docs/store/listing-1.1.0.md`.
const _caption = 'A bookshelf you actually keep';
const _supporting = 'Covers, spines, or leaning.';

/// Slot 1's capture. Stale — it draws the rust flame the app replaced with
/// `kCandleFlame` — and that is fine here: this pass chooses a *layout*, and the layout
/// does not depend on what is inside the screen.
const _capture =
    'docs/store/screenshots/1.1.0/capture/iphone69/01-library-covers.png';

// --------------------------------------------------------------------------- the frame

/// One store frame: ground, caption, and a bezelled device bleeding off an edge.
class _StoreFrame extends StatelessWidget {
  final ui.Image shot;
  final _Treatment treatment;

  const _StoreFrame({required this.shot, required this.treatment});

  /// Fraction of the canvas width the whole device occupies, bezel included.
  static const _deviceWidthFraction = 0.82;

  /// Bezel thickness in logical points at [_phoneLogical]'s width.
  static const _bezel = 9.0;

  /// Screen corner radius as a fraction of screen width. An iPhone 16 Pro Max is about
  /// 62pt on 440, so 0.141 — measured off the hardware rather than picked, because a
  /// radius that is merely "rounded" is the tell that a mockup is drawn rather than real.
  static const _screenRadiusFraction = 0.141;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        final deviceWidth = w * _deviceWidthFraction;
        final screenWidth = deviceWidth - _bezel * 2;
        // The screen's aspect is the capture's aspect, so the screenshot is never
        // stretched — the one distortion a reviewer would notice immediately.
        final screenHeight = screenWidth * shot.height / shot.width;
        final screenRadius = screenWidth * _screenRadiusFraction;

        final caption = _caption(colors, w);
        // **The device takes what the caption leaves, and bleeds off by the difference.**
        // Positioning it from the frame's edge instead — which is what this did first —
        // ignores the caption's height, so the supporting-line variant drew its second
        // line underneath the phone with the last word clipped. A taller caption now
        // means a deeper crop rather than a collision, which is also the honest trade:
        // the more you say, the less app you show.
        final device = Expanded(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: treatment.anchor == _Anchor.top ? 0 : null,
                bottom: treatment.anchor == _Anchor.bottom ? 0 : null,
                left: (w - deviceWidth) / 2,
                width: deviceWidth,
                height: screenHeight + _bezel * 2,
                child: _Device(
                  shot: shot,
                  bezel: _bezel,
                  screenRadius: screenRadius,
                ),
              ),
            ],
          ),
        );

        return DecoratedBox(
          // A flat cream ground gives a near-white screenshot nothing to sit on. The
          // faintest green cast at the far end hints the brand without competing with
          // the covers, which are the loudest thing in this frame by design.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: treatment.anchor == _Anchor.top
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              end: treatment.anchor == _Anchor.top
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              colors: [Colors.white, const Color(0xFFE7F0EC)],
            ),
          ),
          child: Column(
            children: treatment.anchor == _Anchor.top
                ? [caption, device]
                : [device, caption],
          ),
        );
      },
    );
  }

  Widget _caption(AppColors colors, double w) {
    // Sized against the canvas rather than in absolute points, so the iPad pass and the
    // phone pass produce the same *proportions* instead of the same numbers. 10.2% of
    // width lands the headline near Flighty's, which sets its hero line at roughly a
    // tenth of frame width.
    final headline = w * 0.102;

    return Padding(
      // The top figure is generous on purpose: Flighty leaves about 9% of the frame's
      // height clear above its first mark, and that air is most of why the frame reads
      // as composed rather than as a screenshot with a label on it.
      padding: EdgeInsets.fromLTRB(w * 0.085, w * 0.155, w * 0.085, w * 0.11),
      child: Column(
        crossAxisAlignment: treatment.align == TextAlign.left
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Text(
            _StoreFrameCopy.caption,
            textAlign: treatment.align,
            style: AppTextStyles.hero.copyWith(
              fontSize: headline,
              height: 1.14,
              letterSpacing: -headline * 0.018,
              color: colors.primaryText,
            ),
          ),
          if (treatment.supporting) ...[
            SizedBox(height: w * 0.035),
            Text(
              _StoreFrameCopy.supporting,
              textAlign: treatment.align,
              style: AppTextStyles.body.copyWith(
                fontSize: headline * 0.40,
                height: 1.35,
                color: colors.secondaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Held apart from the widget so the strings are in one place when the Korean pass lands.
abstract final class _StoreFrameCopy {
  static const caption = _caption;
  static const supporting = _supporting;
}

/// The bezel, the screen, and the shadow that separates a light device from a light ground.
class _Device extends StatelessWidget {
  final ui.Image shot;
  final double bezel;
  final double screenRadius;

  const _Device({
    required this.shot,
    required this.bezel,
    required this.screenRadius,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(screenRadius + bezel),
        // Not pure black. A titanium rail reads as a very dark warm grey, and true black
        // against a cream ground is a hole rather than an object.
        color: const Color(0xFF1B1B1E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 42,
            spreadRadius: 2,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(bezel),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(screenRadius),
          // `RawImage` takes a decoded `dart:ui` image directly. `Image.memory` would
          // need its load to complete inside the pump, which a widget test does not
          // drive — the frame captures before the bytes resolve and the screen is blank.
          child: RawImage(image: shot, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------- plumbing

Future<ui.Image> _decode(String path) async {
  final bytes = File(path).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _shoot(WidgetTester tester, double pixelRatio) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  return png;
}

/// One cut per family: `AppFonts.serif` for the headline, `AppFonts.sans` for the
/// supporting line. Registering a second Pretendard static would make every weight
/// resolve to whichever loaded first.
Future<void> _loadRealFonts() async {
  for (final entry in const {
    AppFonts.serif: 'assets/fonts/GowunBatang-Bold.ttf',
    AppFonts.sans: 'assets/fonts/Pretendard-Regular.otf',
  }.entries) {
    final bytes = File(entry.value).readAsBytesSync();
    final loader = FontLoader(entry.key)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }
}

Widget _host(ui.Image shot, _Treatment treatment) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light,
  locale: const Locale('en'),
  home: RepaintBoundary(
    key: const ValueKey('shot'),
    // **`Material` is not optional here, and its absence does not look like its absence.**
    // It is where `AnimatedDefaultTextStyle` comes from; without it the ambient default is
    // `MaterialApp`'s `_errorTextStyle`, and `Text` merges that with the style given here.
    // The explicit colour, family and size win — so the headline came out correct in every
    // respect except the `decoration: underline` and yellow `decorationColor` that nothing
    // here overrides, i.e. a frame that looks *selectively* broken and reads as a font bug.
    // Transparent because `_StoreFrame` paints the ground itself, inside this boundary.
    child: Material(
      color: Colors.transparent,
      child: _StoreFrame(shot: shot, treatment: treatment),
    ),
  ),
);

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('render the four caption treatments at 1320x2868', (
    tester,
  ) async {
    tester.view.physicalSize = _phoneLogical * _phoneRatio;
    tester.view.devicePixelRatio = _phoneRatio;
    addTearDown(tester.view.reset);

    final dir = Directory('build/store_frames')..createSync(recursive: true);

    late ui.Image shot;
    await tester.runAsync(() async {
      shot = await _decode(_capture);
    });

    for (final treatment in _treatments) {
      await tester.pumpWidget(_host(shot, treatment));
      await tester.pumpAndSettle();
      final png = await _shoot(tester, _phoneRatio);
      File('${dir.path}/${treatment.name}.png').writeAsBytesSync(png);

      final decoded = await tester.runAsync(
        () => _decode('${dir.path}/${treatment.name}.png'),
      );
      expect(
        Size(decoded!.width.toDouble(), decoded.height.toDouble()),
        const Size(1320, 2868),
        reason: 'the 6.9" requirement is exact; Apple rejects anything else',
      );
    }

    // ignore: avoid_print
    print('wrote ${dir.absolute.path}');
  });

  testWidgets('contact sheet of the four treatments', (tester) async {
    // Judging four 1320x2868 frames means opening four files one at a time, which is how
    // a set ends up inconsistent. Side by side at a tenth the size is also closer to how
    // Apple actually serves them in search results.
    const cell = Size(330, 717);
    tester.view.physicalSize = Size(
      cell.width * _treatments.length,
      cell.height + 46,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory('build/store_frames');
    final frames = <String, ui.Image>{};
    await tester.runAsync(() async {
      for (final treatment in _treatments) {
        frames[treatment.name] = await _decode(
          '${dir.path}/${treatment.name}.png',
        );
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: const ValueKey('shot'),
          child: Material(
            color: const Color(0xFF15171A),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in frames.entries)
                  SizedBox(
                    width: cell.width,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontFamily: AppFonts.sans,
                              fontSize: 15,
                              color: Color(0xFFE8EAED),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: cell.width - 16,
                          height: cell.height - 16,
                          child: RawImage(
                            image: entry.value,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    File('${dir.path}/_sheet.png').writeAsBytesSync(await _shoot(tester, 1));

    // ignore: avoid_print
    print('wrote ${dir.path}/_sheet.png');
  });
}
