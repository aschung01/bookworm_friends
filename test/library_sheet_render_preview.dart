// Not a test — a renderer. Writes PNGs of the sheet's floating gutter to
// build/sheet_preview/ so the inset, the corners and the tab bar's overlap can be
// judged by eye rather than inferred from four numbers in
// `library_sheet_test.dart`.
//
//   flutter test test/library_sheet_render_preview.dart
//
// Four frames: `expanded` (as open as this sheet's snap position goes, which is
// short of the screen — so it keeps a few points of gutter rather than going flush),
// `collapsed` (the full gutter), `midway` (the gap half closed under a live finger)
// and `collapsed_edge`, which drops the fake tab bar and shortens the screen so the
// bottom corners are visible at all — above, the bar floats over exactly that edge.
//
// The short screen in the last frame is doing double duty: it is also the only frame
// here where the sheet covers most of the screen, which is what closes the gutter.
//
// The library behind it is stand-in blocks, and the tab bar a translucent pill at
// the fallback path's geometry (14 in from each side, 8 up from the bottom, 50
// tall). Neither is the real widget: what is being looked at is the sheet's edge
// against something, and covers under a test font would only be black boxes.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

/// The shell's fallback reservation: 8 + 50 + 8.
const double _reserve = 66;

Widget _shell({bool bar = true}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light,
  home: Scaffold(
    body: RepaintBoundary(
      key: const ValueKey('shot'),
      child: Stack(
        children: [
          ColoredBox(
            color: const Color(0xffE9ECEF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    color: const Color(0xffE9ECEF),
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          for (var row = 0; row < 3; row++)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Row(
                                children: [
                                  for (var i = 0; i < 4; i++)
                                    Container(
                                      margin: const EdgeInsets.only(right: 10),
                                      width: 56,
                                      height: 86,
                                      color: Color(0xff9D2127 + row * 0x2200),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const LibrarySheet(
                  bottomReserve: _reserve,
                  header: Row(
                    children: [
                      LibrarySheetTitle(title: 'Books read', count: 12),
                    ],
                  ),
                  body: SizedBox(height: 220),
                ),
              ],
            ),
          ),
          if (bar)
            Positioned(
              left: 14,
              right: 14,
              bottom: 8,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  // Deliberately not the bar's real colour: translucent, so the
                  // card's own bottom edge stays readable underneath it.
                  color: const Color(0x552B3A67),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: const Color(0xAA2B3A67)),
                ),
              ),
            ),
        ],
      ),
    ),
  ),
);

Future<void> _shoot(WidgetTester tester, Directory dir, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  File('${dir.path}/$name.png').writeAsBytesSync(png);
}

void main() {
  testWidgets('render the sheet at both positions', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory('build/sheet_preview')..createSync(recursive: true);

    await tester.pumpWidget(_shell());
    await tester.pumpAndSettle();
    await _shoot(tester, dir, 'expanded');

    await tester.drag(find.text('Books read'), const Offset(0, 300));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, 'collapsed');

    // Partway, so the gap can be seen closing rather than inferred. Two moves,
    // because the first is eaten by the touch slop and is not a known distance.
    final gesture = await tester.startGesture(
      tester.getRect(find.byType(LibrarySheet)).topCenter + const Offset(0, 12),
    );
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -90));
    await tester.pump();
    await _shoot(tester, dir, 'midway');
    await gesture.up();
    await tester.pumpAndSettle();

    // The bottom edge on its own, on a short screen so the card fills the frame:
    // the lift and the bottom corners are what the tab bar covers up above.
    tester.view.physicalSize = const Size(393 * 3, 320 * 3);
    await tester.pumpWidget(_shell(bar: false));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Books read'), const Offset(0, 300));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, 'collapsed_edge');

    // ignore: avoid_print
    print('wrote PNGs to ${dir.absolute.path}');
  });
}
