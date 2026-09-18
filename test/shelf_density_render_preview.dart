// Not a test — a renderer. Writes PNGs of a shelf row at each `ShelfDensity` to
// build/shelf_preview/ so the spines, the turn and the one-forward rule can be judged
// by eye.
//
//   flutter test test/shelf_density_render_preview.dart
//
// This exists because of what measurements have failed to catch on this row. A
// withdrawn third density measured correctly by every number its design named and was
// still unusable: its hit slots sat on each cover's *leading* edge, which was the edge
// hidden under the neighbour, so tapping one book surfaced another. Every assertion
// about steps and widths passed. A frame showed it in a second.
//
// Three groups: both densities at rest, a spine turning out, and the one-book-forward
// rule across two shelves — which is the other bug that no single-shelf frame could
// have shown.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show bookStatusReading;
import 'package:bookworm_friends/providers/shelf_density_provider.dart';
import 'package:bookworm_friends/ui/widgets/shelf/shelf_spine_tile.dart';

import 'support/home_page_harness.dart';
import 'support/prefs.dart';

/// Real ISBNs, because `testBook` uses the id as the ISBN and the ISBN is what the
/// height and thickness jitter hash. Ids like `b0`..`b11` would still jitter, but not
/// over a spread anyone would meet — and a row of spines is mostly a picture of that
/// spread.
const List<(String, String)> _corpus = [
  ('9788934972464', 'Shoe Dog'),
  ('9788937834158', 'Eragon'),
  ('9788937834165', 'Brisingr'),
  ('9788937834172', 'Eldest'),
  ('9788954633767', 'The White Book'),
  ('9788901219943', 'Start With Why'),
  ('9788937473135', 'Kim Jiyoung'),
  ('9788954655170', 'The Hole'),
  ('9788936434120', 'Almond'),
  ('9788901219950', 'Pachinko'),
  ('9788968482236', 'Growth Hacking'),
  ('9791158391720', 'Deep Learning'),
];

List<Book> _books({int reading = 1}) => [
  for (var i = 0; i < _corpus.length; i++)
    testBook(
      _corpus[i].$1,
      's1',
      position: i,
      title: _corpus[i].$2,
      status: i < reading ? bookStatusReading : 0,
    ),
];

/// Two shelves' worth of compressible books and nothing in progress, so every book on
/// screen is one that *could* be brought forward.
List<Shelf> _twoShelves() => [
  testShelf('s1', [
    for (var i = 0; i < 5; i++)
      testBook(_corpus[i].$1, 's1', position: i, title: _corpus[i].$2),
  ], name: 'Dev'),
  testShelf('s2', [
    for (var i = 5; i < 10; i++)
      testBook(_corpus[i].$1, 's2', position: i - 5, title: _corpus[i].$2),
  ], name: 'Fic'),
];

/// The whole surface, or [crop] of it in logical units.
///
/// The row cannot be wrapped: `pumpHome` builds its own tree and offers no hook for a
/// [RepaintBoundary] around one shelf. So this rasterises the root layer, which is an
/// [OffsetLayer].
///
/// **The rect is in physical pixels, not logical ones.** `RenderView` lays out in
/// logical units and then its layer applies the device pixel ratio, so the root layer's
/// coordinate space is the physical one. Passing `view.size` here captures the top-left
/// third of the frame and scales it up, which looks enough like a legitimate close-up
/// to be believed.
Future<void> _shoot(
  WidgetTester tester,
  Directory dir,
  String name, {
  Rect? crop,
}) async {
  final view = tester.binding.renderViews.first;
  final dpr = tester.view.devicePixelRatio;
  final rect = crop == null
      ? Offset.zero & tester.view.physicalSize
      : Rect.fromLTWH(
          crop.left * dpr,
          crop.top * dpr,
          crop.width * dpr,
          crop.height * dpr,
        );
  late ui.Image image;
  await tester.runAsync(() async {
    image = await (view.debugLayer! as OffsetLayer).toImage(
      rect,
      pixelRatio: 1,
    );
  });
  late ByteData data;
  await tester.runAsync(() async {
    data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  });
  File('${dir.path}/$name.png').writeAsBytesSync(data.buffer.asUint8List());
  debugPrint('wrote ${dir.path}/$name.png');
}

/// One cut per family. See the read pile's preview for why not four.
Future<void> _loadRealFonts() async {
  Future<void> load(String family, String file) async {
    final bytes = File('assets/fonts/$file').readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('GowunBatang', 'GowunBatang-Bold.ttf');
  await load('Pretendard', 'Pretendard-Bold.otf');
}

Future<void> _pump(
  WidgetTester tester, {
  required ShelfDensity density,
  List<Book> books = const [],
  List<Shelf>? shelves,
}) async => pumpHome(
  tester,
  shelves: shelves ?? [testShelf('s1', books, name: 'Dev')],
  extraOverrides: [
    await sharedPreferencesOverride({'shelf_density': density.name}),
  ],
);

/// The spine drawn for the book titled [title].
Finder _spineOf(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ShelfSpineTile));

/// The shelf band alone, in logical units. A whole-surface frame puts the row in about
/// a tenth of the image, which is not enough to tell a correct row from a broken one.
const Rect _row = Rect.fromLTWH(0, 55, 402, 130);

/// Two shelves, for the rule that spans them.
const Rect _rows = Rect.fromLTWH(0, 55, 402, 260);

void main() {
  setUpAll(_loadRealFonts);

  Directory dir() =>
      Directory('build/shelf_preview')..createSync(recursive: true);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(402 * 4, 640 * 4);
    tester.view.devicePixelRatio = 4;
    addTearDown(tester.view.reset);
  }

  testWidgets('render each density at rest', (tester) async {
    phone(tester);

    for (final density in ShelfDensity.values) {
      await _pump(tester, density: density, books: _books());
      await tester.pumpAndSettle();
      await _shoot(tester, dir(), 'rest_${density.name}');
      await _shoot(tester, dir(), 'row_${density.name}', crop: _row);
    }
  });

  testWidgets('render a spine turning out', (tester) async {
    phone(tester);

    await _pump(tester, density: ShelfDensity.spines, books: _books());
    await tester.pumpAndSettle();

    // A spine in the middle of the run, so the margins it opens either side of itself
    // are both in frame.
    await tester.tap(_spineOf('Kim Jiyoung'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    await _shoot(tester, dir(), 'row_turn_midway', crop: _row);

    await tester.pumpAndSettle();
    await _shoot(tester, dir(), 'row_turn_settled', crop: _row);
  });

  testWidgets('render the row with nothing in progress', (tester) async {
    phone(tester);

    // No face-out head, so the whole shelf is spines and the row's density is what it
    // is at its best.
    await _pump(
      tester,
      density: ShelfDensity.spines,
      books: _books(reading: 0),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, dir(), 'row_spines_none_reading', crop: _row);
  });

  testWidgets('render the turn between densities', (tester) async {
    phone(tester);

    // The transition itself: every compressed book rotating on its spine, in a wave
    // from the left, with the row narrowing as they go. Frames rather than a
    // measurement, because "does this read as books turning" is not a number.
    await _pump(tester, density: ShelfDensity.covers, books: _books());
    await tester.pumpAndSettle();
    await _shoot(tester, dir(), 'turn_0_covers', crop: _row);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.book),
      ),
    );
    await tester.pump();

    // kShelfDensityTurnDuration is 400ms; five frames across it show the wave.
    for (final ms in const [80, 160, 240, 320]) {
      await tester.pump(const Duration(milliseconds: 80));
      await _shoot(tester, dir(), 'turn_${ms}ms', crop: _row);
    }

    await tester.pumpAndSettle();
    await _shoot(tester, dir(), 'turn_5_spines', crop: _row);
  });

  testWidgets('render the turn back to covers', (tester) async {
    phone(tester);

    // The way back, with one book already turned out — which is the case the forward turn
    // does not have. That book is *excused*: it is the one book on the row that is
    // already cover-on, so posing it with the rest would snap it to spine-on on the first
    // frame and walk it back through 90° a reader can see it did not need to travel.
    await _pump(tester, density: ShelfDensity.spines, books: _books());
    await tester.pumpAndSettle();
    await tester.tap(_spineOf('Eldest'));
    await tester.pumpAndSettle();
    await _shoot(tester, dir(), 'back_0_spines', crop: _row);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.view_week),
      ),
    );
    await tester.pump();

    for (final ms in const [80, 160, 240, 320]) {
      await tester.pump(const Duration(milliseconds: 80));
      await _shoot(tester, dir(), 'back_${ms}ms', crop: _row);
    }

    await tester.pumpAndSettle();
    await _shoot(tester, dir(), 'back_5_covers', crop: _row);
  });

  testWidgets('render one book forward across two shelves', (tester) async {
    phone(tester);

    // The rule is one book forward in the whole **library**, not one per shelf. It was
    // one per shelf at first, and every single-shelf frame looks identical either way —
    // so this is the frame that shows it.
    await _pump(tester, density: ShelfDensity.spines, shelves: _twoShelves());
    await tester.pumpAndSettle();

    await tester.tap(_spineOf('Brisingr'));
    await tester.pumpAndSettle();
    await _shoot(tester, dir(), 'rows_one_forward', crop: _rows);

    // A spine on the *other* shelf. The first has to go back down.
    await tester.tap(_spineOf('The Hole'));
    await tester.pumpAndSettle();
    await _shoot(tester, dir(), 'rows_forward_moved', crop: _rows);
  });
}
