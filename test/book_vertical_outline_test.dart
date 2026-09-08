// Pixel guards for the pale-spine outline.
//
// **These have to read pixels, and that is the whole point of the file.** The outline
// shipped broken: a `Border.all` inside the `ClipPath`, with a comment asserting that
// the clip made it trace the arched head. It did not. A box border's top edge is a
// straight line at y = 0, while the arch only reaches y = 0 at its centre and sits at
// y = 5 at both corners — so the clip erased almost the entire top edge. Pale books
// rendered with two vertical hairlines and no head, and on a white jacket that is a
// spine whose top has dissolved into the sheet.
//
// No tree-shaped test could have caught it. The `DecoratedBox` was in the tree, with
// the right colour and the right border width; `find.byType` would have found it and
// every assertion about it would have passed. The pixels were the only witness, and it
// took a screenshot from a device to notice.
//
// ## Both spines are drawn on pure white, deliberately
//
// The real background is `sheetBackground`, `#EFF5EF`. Rendering against it makes these
// tests **unable to fail**, and the first draft of this file proved it by passing
// against a deliberately reintroduced version of the bug: the outline over a white fill
// is about `#E3E3E3`, the sheet is `#EFF5EF`, and once antialiasing spreads the two into
// each other no threshold separates "outline" from "background showing outside the
// arch". A white fill on a white background leaves exactly one thing in the frame that
// is not white, which is the thing under test.
//
// So the pixel tests use white-on-white — which is also the honest worst case, since
// `surface` *is* pure white and `BookVertical` is drawn on it elsewhere. Whether the
// outline appears at all on the real sheet colour is a separate question, and a
// tree-shaped assertion is the right tool for it; see the last group.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';

const double _width = 30;
const double _height = 120;
const Color _white = Color(0xFFFFFFFF);

/// The colour the read pile is really seen against: a sheet's `collapsedBody`.
const Color _sheet = Color(0xffEFF5EF);

Future<void> _pump(
  WidgetTester tester, {
  required Color fill,
  required Color background,
  bool arch = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: background,
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey('shot'),
            child: ColoredBox(
              color: background,
              child: BookVertical(
                // Empty, so no glyph can land in the rows being counted. The title is
                // 15pt down from the head anyway, but a test that depends on font
                // metrics to stay out of its own way is a test waiting to flake.
                title: '',
                width: _width,
                height: _height,
                fill: fill,
                titleColor: Colors.black,
                background: background,
                arch: arch,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The rendered spine as straight RGBA, one sample per logical pixel.
///
/// pixelRatio 1 on purpose. At 3 the stroke antialiases across three device rows, so a
/// threshold tuned at one ratio means something else at another; at 1 a sample is a
/// logical pixel and the counts below count the thing a reader would point at.
Future<({Uint8List px, int w, int h})> _shoot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List px;
  late int w, h;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    px = data!.buffer.asUint8List();
    w = image.width;
    h = image.height;
    image.dispose();
  });
  return (px: px, w: w, h: h);
}

/// Mean of the RGB channels, 0-255.
///
/// Gamma-space and crude on purpose. `computeLuminance` would be more principled and is
/// the wrong tool: mixing a linear-light luminance with a gamma-space channel mean is
/// what made the first version of this file unable to fail.
double _v(({Uint8List px, int w, int h}) shot, int x, int y) {
  final i = (y * shot.w + x) * 4;
  return (shot.px[i] + shot.px[i + 1] + shot.px[i + 2]) / 3;
}

/// On a white fill over a white background, anything below this is the outline.
const double _inkThreshold = 250;

void main() {
  group('the arched head is outlined', () {
    testWidgets(
      'Given a white spine, When it is drawn, Then most columns of the head '
      'carry an outline pixel',
      (tester) async {
        // The arch spans the full width, so a stroke along it puts a mark in nearly
        // every column of the top few rows.
        await _pump(tester, fill: _white, background: _white);
        final shot = await _shoot(tester);

        var columnsWithInk = 0;
        for (var x = 0; x < shot.w; x++) {
          for (var y = 0; y < 8 && y < shot.h; y++) {
            if (_v(shot, x, y) < _inkThreshold) {
              columnsWithInk++;
              break;
            }
          }
        }

        expect(
          columnsWithInk,
          greaterThan((shot.w * 0.8).floor()),
          reason:
              'only $columnsWithInk of ${shot.w} columns have an outline pixel '
              'in the top 8 rows — the head is not outlined across its width',
        );
      },
    );

    testWidgets('Given a white spine, When it is drawn, Then the outline reaches both '
        'shoulders and not just the apex', (tester) async {
      // **The assertion that fails on the specific bug** rather than on "no outline
      // at all". The clipped border did leave marks near the centre, where the
      // straight top edge grazed the inside of the curve. What it could not leave was
      // a mark two columns in from each edge: the arch has descended to about y = 4.4
      // there, so the border's top edge at y = 0.5 was outside the shape and clipped
      // away, while its vertical edges are at x = 0.5 and never reach x = 2.
      await _pump(tester, fill: _white, background: _white);
      final shot = await _shoot(tester);

      bool inkInColumn(int x) {
        for (var y = 0; y < 10 && y < shot.h; y++) {
          if (_v(shot, x, y) < _inkThreshold) return true;
        }
        return false;
      }

      expect(
        inkInColumn(2),
        isTrue,
        reason: 'the left shoulder of the arch is not outlined',
      );
      expect(
        inkInColumn(shot.w - 3),
        isTrue,
        reason: 'the right shoulder of the arch is not outlined',
      );
    });

    testWidgets(
      'Given a white spine, When it is drawn, Then nothing is drawn above the '
      'arch',
      (tester) async {
        // The mirror of the tests above, and what stops them being satisfied by simply
        // filling the top rows in. Outside the curve is the background, and a stroke
        // centred on the clip boundary would put half its width out there — which is
        // why the painter insets by half a stroke. At the very corner, x = 0, the arch
        // starts at y = 5, so rows 0 to 3 must be untouched.
        await _pump(tester, fill: _white, background: _white);
        final shot = await _shoot(tester);

        for (final x in [0, shot.w - 1]) {
          for (var y = 0; y < 3; y++) {
            expect(
              _v(shot, x, y),
              greaterThanOrEqualTo(_inkThreshold),
              reason:
                  'ink at ($x, $y), which is outside the arch — the outline is '
                  'boxing the spine rather than tracing its head',
            );
          }
        }
      },
    );

    testWidgets(
      'Given a chassis spine face, When it is drawn, Then the head is outlined '
      'straight across',
      (tester) async {
        // `arch: false` means one face of a solid `BookChassis`, whose head is square
        // because the cover beside it is full height. The outline has to follow that,
        // or a turned-out book gets a curved line across a straight head — the same
        // class of mismatch the arch itself caused. See `BookVertical.arch`.
        await _pump(tester, fill: _white, background: _white, arch: false);
        final shot = await _shoot(tester);

        var inkInTopRow = 0;
        for (var x = 0; x < shot.w; x++) {
          if (_v(shot, x, 0) < _inkThreshold) inkInTopRow++;
        }
        expect(
          inkInTopRow,
          greaterThan((shot.w * 0.8).floor()),
          reason:
              'only $inkInTopRow of ${shot.w} columns are inked in the very top '
              'row — a square head should be outlined straight across',
        );
      },
    );
  });

  group('the outline is an accommodation, not decoration', () {
    /// The painter, matched on its type.
    ///
    /// `Scaffold` contributes `CustomPaint`s with foreground painters of its own, so a
    /// predicate that only checks `foregroundPainter != null` finds two widgets here and
    /// one in the negative case. Matching the type is what makes the `findsNothing`
    /// assertion below mean anything.
    Finder outlinePainter() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.foregroundPainter is BookSpineOutlinePainter,
    );

    testWidgets('Given a dark spine, Then no outline is drawn', (tester) async {
      // A navy spine has a silhouette of its own; a line around it would read as a
      // border on a rectangle. Asserted on the tree rather than on pixels because a
      // faint dark outline on a dark fill is invisible either way — the question here
      // is whether it was *asked for*, which is a tree-shaped question.
      await _pump(tester, fill: const Color(0xFF1E3A5C), background: _sheet);
      expect(outlinePainter(), findsNothing);
    });

    testWidgets(
      'Given a white spine on the real sheet colour, Then an outline is drawn',
      (tester) async {
        // The pixel tests above use white-on-white so that they can fail at all. This
        // is the one that pins the *real* case: `#FFFFFF` on `#EFF5EF` scores 1.11:1,
        // under the 1.25 threshold, so the outline fires.
        await _pump(tester, fill: _white, background: _sheet);
        expect(outlinePainter(), findsOneWidget);
      },
    );

    testWidgets(
      'Given a spine that clears white but not the sheet, Then an outline is '
      'still drawn',
      (tester) async {
        // Why `background` had to become a parameter. `#E4E4E4` scores 1.27:1 against
        // `surface` and 1.15:1 against the sheet the pile actually sits on, so the old
        // hardcoded `context.colors.surface` said "no outline needed" for a spine that
        // genuinely has no edge where it is drawn.
        await _pump(tester, fill: const Color(0xFFE4E4E4), background: _sheet);
        expect(
          outlinePainter(),
          findsOneWidget,
          reason:
              'measured against surface instead of the background it was given',
        );
      },
    );
  });
}
