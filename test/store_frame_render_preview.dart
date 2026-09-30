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

/// The iPad 13" requirement: 1032x1376 at 2 is 2064x2752.
const _tabletLogical = Size(1032, 1376);
const _tabletRatio = 2.0;

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

  const _Treatment(this.name, this.anchor, this.align);
}

/// **Chosen by rendering four of these and looking**; the argument is in
/// `docs/store/listing-1.1.0.md` under "The layout, decided by looking". Top because
/// Apple crops the top in search results, so a bottom caption is invisible exactly where
/// the frame has to work; centre because the device is centred and a left-hang reads
/// unresolved at thumbnail size without Flighty's dark editorial ground beneath it.
///
/// Kept as a type rather than inlined so the comparison can be re-run if it is
/// questioned — the losing three are `top/left`, `bottom/centre` and `top/centre`
/// without a supporting line.
const _chosen = _Treatment('chosen', _Anchor.top, TextAlign.center);

/// One frame: a capture, a headline, and the line under it.
///
/// **No two headlines and no two supporting lines share an idea**, which is the
/// benchmark's observation 2 applied one level down — the strong listings never spend a
/// character twice. Slot 1's supporting line was `Covers, spines, or leaning.` for one
/// round, which is slot 2's *headline* verbatim, so the first two frames a reviewer sees
/// would have said the same thing twice. It carries the objection-removal move instead:
/// free, no ads, no subscription is what Flighty spends its own opening on, it is true
/// here, and nothing else in the set says it.
class _Slot {
  final String capture;
  final String headline;
  final String supporting;

  const _Slot(this.capture, this.headline, this.supporting);
}

const _phoneSlots = <_Slot>[
  _Slot(
    'iphone69/01-library-covers',
    'A bookshelf you actually keep',
    'Free. No ads, no subscription.',
  ),
  _Slot(
    'iphone69/02-library-spines',
    'Covers, spines, or leaning',
    'Drag them into the order you want.',
  ),
  _Slot(
    'iphone69/03-library-card',
    'Your reading becomes a card',
    'Books, days, pace, most-read author.',
  ),
  _Slot(
    'iphone69/05-book-details',
    'Log the page you\u2019re on',
    'By page or percent, in one drag.',
  ),
  // Headline changed from `Share it, or keep it`: "it" had no referent this side of slot
  // 3, and the second clause described the absence of an action.
  _Slot(
    'iphone69/07-share-card',
    'Made to be handed over',
    'Nothing is public until you send it.',
  ),
  _Slot(
    'iphone69/04-friends',
    'Read alongside your friends',
    'See what they have open right now.',
  ),
  _Slot(
    'iphone69/06-search-results',
    'Scan the barcode to add',
    'Or search by title, author, or ISBN.',
  ),
];

/// The iPad reuses four of the seven captions against its four captures rather than
/// writing four more: this is one system at two sizes, not two sets.
const _tabletSlots = <_Slot>[
  _Slot(
    'ipad13/01-library',
    'A bookshelf you actually keep',
    'Free. No ads, no subscription.',
  ),
  _Slot(
    'ipad13/02-library-card',
    'Your reading becomes a card',
    'Books, days, pace, most-read author.',
  ),
  _Slot(
    'ipad13/03-friends',
    'Read alongside your friends',
    'See what they have open right now.',
  ),
  _Slot(
    'ipad13/04-book-details',
    'Log the page you\u2019re on',
    'By page or percent, in one drag.',
  ),
];

/// **The captures are stale and these frames are still worth rendering.** Five of the
/// eleven draw the rust flame or the unfilled grey streak tile, and the two frames Apple
/// shows in search results have the finished-books sheet half open across the bottom
/// third. What this pass settles is the copy and the fit — neither of which depends on
/// what is inside the screen. Re-capture, then re-run.
const _captureRoot = 'docs/store/screenshots/1.1.0/capture';

// --------------------------------------------------------------------------- the frame

/// One store frame: ground, caption, and a bezelled device bleeding off an edge.
class _StoreFrame extends StatelessWidget {
  final ui.Image shot;
  final _Slot slot;
  final _Treatment treatment;

  const _StoreFrame({
    required this.shot,
    required this.slot,
    required this.treatment,
  });

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
            slot.headline,
            textAlign: treatment.align,
            style: AppTextStyles.hero.copyWith(
              fontSize: headline,
              height: 1.14,
              letterSpacing: -headline * 0.018,
              color: colors.primaryText,
            ),
          ),
          SizedBox(height: w * 0.035),
          Text(
            slot.supporting,
            textAlign: treatment.align,
            style: AppTextStyles.body.copyWith(
              fontSize: headline * 0.40,
              height: 1.35,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
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

Widget _host(ui.Image shot, _Slot slot) => MaterialApp(
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
      child: _StoreFrame(shot: shot, slot: slot, treatment: _chosen),
    ),
  ),
);

/// Renders [slots] at [logical] x [ratio] into `build/store_frames/<prefix>-NN.png`.
Future<List<ui.Image>> _renderSet(
  WidgetTester tester,
  Directory dir, {
  required String prefix,
  required List<_Slot> slots,
  required Size logical,
  required double ratio,
  required Size required,
}) async {
  tester.view.physicalSize = logical * ratio;
  tester.view.devicePixelRatio = ratio;

  final written = <ui.Image>[];
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];

    late ui.Image shot;
    await tester.runAsync(() async {
      shot = await _decode('$_captureRoot/${slot.capture}.png');
    });

    await tester.pumpWidget(_host(shot, slot));
    await tester.pumpAndSettle();

    // Slot order is the upload order, so it leads the filename: Apple shows the first
    // three and nothing in the image says which one it is. The device prefix is there
    // because the two sets reuse captions, so the numbers alone repeat.
    final name = '${i + 1}'.padLeft(2, '0');
    final path =
        '${dir.path}/$prefix-$name-${slot.capture.split('/').last}.png';
    File(path).writeAsBytesSync(await _shoot(tester, ratio));

    final decoded = await tester.runAsync(() => _decode(path));
    expect(
      Size(decoded!.width.toDouble(), decoded.height.toDouble()),
      required,
      reason: 'store sizes are exact; Apple rejects anything else',
    );
    written.add(decoded);
  }
  return written;
}

/// All of [frames] side by side on a dark ground, scaled to [cell].
///
/// Judging 1320x2868 files one at a time is how a set ends up inconsistent, and a
/// thumbnail is closer to how Apple serves them in search results anyway.
Future<void> _contactSheet(
  WidgetTester tester,
  Directory dir, {
  required String name,
  required List<ui.Image> frames,
  required List<_Slot> slots,
  required Size cell,
}) async {
  tester.view.physicalSize = Size(cell.width * frames.length, cell.height + 46);
  tester.view.devicePixelRatio = 1;

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
              for (var i = 0; i < frames.length; i++)
                SizedBox(
                  width: cell.width,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Text(
                          '${i + 1}. ${slots[i].headline}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.sans,
                            fontSize: 14,
                            color: Color(0xFFE8EAED),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cell.width - 16,
                        height: cell.height - 16,
                        child: RawImage(image: frames[i], fit: BoxFit.contain),
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
  File('${dir.path}/$name').writeAsBytesSync(await _shoot(tester, 1));
}

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('render the seven iPhone frames and the four iPad frames', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final dir = Directory('build/store_frames')..createSync(recursive: true);
    // Stale output from an earlier run is worse than none: a renamed slot leaves a file
    // behind and the contact sheet is the only place anyone would notice.
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        f.deleteSync();
      }
    }

    final phone = await _renderSet(
      tester,
      dir,
      prefix: 'iphone69',
      slots: _phoneSlots,
      logical: _phoneLogical,
      ratio: _phoneRatio,
      required: const Size(1320, 2868),
    );
    final tablet = await _renderSet(
      tester,
      dir,
      prefix: 'ipad13',
      slots: _tabletSlots,
      logical: _tabletLogical,
      ratio: _tabletRatio,
      required: const Size(2064, 2752),
    );

    await _contactSheet(
      tester,
      dir,
      name: '_sheet-iphone69.png',
      frames: phone,
      slots: _phoneSlots,
      cell: const Size(210, 456),
    );
    await _contactSheet(
      tester,
      dir,
      name: '_sheet-ipad13.png',
      frames: tablet,
      slots: _tabletSlots,
      cell: const Size(300, 400),
    );

    // ignore: avoid_print
    print('wrote ${dir.absolute.path}');
  });
}
