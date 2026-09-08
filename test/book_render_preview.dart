// Not a test — a renderer. Writes PNGs of the chassis to build/book_preview/ so
// the turn angle, the square and the fore-edge can be judged by eye instead of
// inferred from a device screenshot.
//
//   flutter test test/book_render_preview.dart
//
// No title text: widget tests fall back to a font that draws every glyph as a
// filled box, which would obscure exactly the area being inspected. The stripe
// (colour band over a white lower half) is kept, because near-white pages next
// to a near-white cover half is the hardest case for the fore-edge to read.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

/// The Geist demo's `color="#9D2127"` book, which is the reference image most
/// directly comparable to these renders.
const Color _band = Color(0xFF9D2127);
const Color _page = Color(0xFFF8F9FA);

/// Turn angles to compare, in degrees. 16 is what the app ships
/// ([kBookTurnAngle]); the rest bracket the angle the published Geist stills
/// appear to be rendered at.
const List<int> _angles = [16, 20, 26, 30];

/// The reference's own cover height, so the squares can be compared at the size
/// they were calibrated against rather than across a size change.
const double _referenceHeight = kBookReferenceHeight;

double _rad(num deg) => deg * 3.1415926535897932 / 180;

Widget _book(double baseHeight, double turn) => BookChassis(
  metrics: BookMetrics.from(
    baseHeight: baseHeight,
    coverAspect: 2 / 3,
    jitter: BookJitter.neutral,
  ),
  turn: turn,
  // Derived from the cover exactly as BookWidget does it, so the board tone in
  // these renders is the tone the app draws.
  boardColor: bookBoardColorFor(_band),
  cover: const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: ColoredBox(color: _band)),
      Expanded(child: ColoredBox(color: Color(0xFFFFFFFF))),
    ],
  ),
);

Future<void> _shoot(
  WidgetTester tester,
  Directory dir,
  String name,
  double pixelRatio,
  Widget child,
) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: _page,
        child: Center(
          child: RepaintBoundary(
            key: const ValueKey('shot'),
            child: Padding(padding: const EdgeInsets.all(28), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  File('${dir.path}/$name.png').writeAsBytesSync(png);
}

void main() {
  testWidgets('render the chassis across turn angles', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dir = Directory('build/book_preview')..createSync(recursive: true);

    // All four angles in one frame, so the fore-edge widths can be compared
    // directly rather than across images.
    await _shoot(
      tester,
      dir,
      'ladder',
      3,
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final deg in _angles) ...[
            _book(180, _rad(deg)),
            const SizedBox(width: 44),
          ],
        ],
      ),
    );

    // One book per angle, at the reference's own height, for close inspection of
    // the squares against the published stills.
    for (final deg in _angles) {
      await _shoot(
        tester,
        dir,
        'angle$deg',
        4,
        _book(_referenceHeight, _rad(deg)),
      );
    }

    // Shelf size at the shipped angle: the case the app actually draws most.
    await _shoot(tester, dir, 'shelf16', 8, _book(86, kBookTurnAngle));

    // What the device actually draws, at the device's own pixel density. The
    // `angle*` renders above are 240pt at 4x, which is roughly 8x the linear
    // scale of a shelf book's squares — useful for judging proportion, useless
    // for judging whether a band is visible in practice.
    //
    // 131pt is `MediaQuery.size.height * 0.15` on an 874pt-tall iPhone 17 Pro,
    // per shelf_row.dart:196. 180pt is the details page.
    for (final c in {'shelf131': 131.0, 'details180': 180.0}.entries) {
      for (final s in {'rest': 0.0, 'held': kBookTurnAngle}.entries) {
        await _shoot(
          tester,
          dir,
          'device_${c.key}_${s.key}',
          3,
          _book(c.value, s.value),
        );
      }
      // Same geometry, magnified, so the bands can be measured rather than
      // squinted at.
      await _shoot(
        tester,
        dir,
        'zoom_${c.key}_held',
        12,
        _book(c.value, kBookTurnAngle),
      );
    }

    // ignore: avoid_print
    print('wrote PNGs to ${dir.absolute.path}');
  });
}
