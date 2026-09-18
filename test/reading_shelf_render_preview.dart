// Not a test — a renderer. Writes PNGs of the Reading shelf to
// build/reading_shelf_preview/ so the lamp, the lean, the ribbon and the day stamp can
// be judged by eye.
//
//   flutter test test/reading_shelf_render_preview.dart
//
// **This exists because the whole device is light.** `reading_shelf_row_test.dart` can
// measure that the pivot corner sits on the plank, that the row reserves the height the
// tilt needs and that the plank carries a warm shadow — and none of those say whether the
// shelf reads as *lit*. The design record's own notes reversed themselves twice on
// exactly that question after seeing frames: the bloom over a single dark cover turned out
// to be the loudest thing on the screen rather than "a smudge", and most of its warm
// pixels turned out to be background rather than book. Both were predictions from
// arithmetic, and both were wrong.
//
// Four frames: the common case of one open book, the three the exploration was drawn on,
// an overflowing row (where the clip and the edge fades are the subject), and the library
// with nothing open at all — the control for all three. Then three more of the same
// library scrolled, which is the only way to see that the light is a fixture and that it
// dims as the shelf it belongs to leaves. Then one of the row in **edit mode**, which is
// the only way to check the thing arithmetic cannot: the remove badge is a 44pt disc hung
// 22pt outside its cover's top-left, so it lands ~7pt *above* the row's own box, and a row
// that kept clipping there would shear the top off every badge on the shelf.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/models/shelf.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show bookStatusReading;
import 'package:bookworm_friends/ui/widgets/reading_shelf_lamp.dart';
import 'package:bookworm_friends/ui/widgets/reading_shelf_row.dart';
import 'package:bookworm_friends/ui/widgets/shelf_row.dart'
    show kShelfLiftDelay;

import 'support/home_page_harness.dart';

/// Real ISBNs, because `testBook` uses the id as the ISBN and the ISBN is what the
/// height and thickness jitter hash. Ids like `b0`..`b7` would still jitter, but not over
/// a spread anyone would meet.
const List<(String, String)> _corpus = [
  ('9788934972464', 'Shoe Dog'),
  ('9788937834158', 'Eragon'),
  ('9788954633767', 'The White Book'),
  ('9788901219943', 'Start With Why'),
  ('9788937473135', 'Kim Jiyoung'),
  ('9788954655170', 'The Hole'),
  ('9788936434120', 'Almond'),
  ('9788901219950', 'Pachinko'),
];

/// A library whose first [reading] books are open, the rest waiting on one shelf.
List<Shelf> _library({required int reading}) => [
  testShelf('s1', [
    for (var i = 0; i < _corpus.length; i++)
      testBook(
        _corpus[i].$1,
        's1',
        position: i,
        title: _corpus[i].$2,
        status: i < reading ? bookStatusReading : 0,
        // Staggered, so the stamps on one row are not all the same number — which is
        // the only way to see that they are per-book rather than decorative.
        startDate: i < reading
            ? DateTime.now().subtract(Duration(days: 2 + i * 9))
            : null,
      ),
  ], name: 'Dev'),
];

/// The whole surface, or [crop] of it in logical units.
///
/// The row cannot be wrapped: `pumpHome` builds its own tree and offers no hook for a
/// [RepaintBoundary] around one shelf. So this rasterises the root layer, which is an
/// [OffsetLayer].
///
/// **The rect is in physical pixels, not logical ones.** `RenderView` lays out in logical
/// units and then its layer applies the device pixel ratio, so the root layer's coordinate
/// space is the physical one. Passing `view.size` here captures the top-left third of the
/// frame and scales it up, which looks enough like a legitimate close-up to be believed.
/// Copied from `shelf_density_render_preview.dart`, whose note this is.
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

/// The Reading shelf and the first queue shelf under it, in logical units.
///
/// Both, deliberately: the claim the lamp makes is *comparative* — this row is lit and the
/// ones below it are not — so a frame of the Reading shelf alone cannot show it. Tall
/// enough to include the bloom above the row, which is drawn outside the row's own box.
const Rect _band = Rect.fromLTWH(0, 40, 402, 380);

/// What the library gives a book on the 700pt-tall phone below — `LibraryPane` takes 15% of
/// the screen's height — and so what the lamp's reach and its fade are measured from.
const double _bookHeight = 700 * 0.15;

void main() {
  setUpAll(_loadRealFonts);

  Directory dir() =>
      Directory('build/reading_shelf_preview')..createSync(recursive: true);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(402 * 4, 700 * 4);
    tester.view.devicePixelRatio = 4;
    addTearDown(tester.view.reset);
  }

  /// One frame per count, in its own `testWidgets`.
  ///
  /// Not a loop inside one test, and that is a trap worth recording: pumping a second
  /// `pumpHome` into the same test re-parents the harness's `GlobalKey` navigator and the
  /// tree keeps the first library, so all three frames came out byte-identical. Identical
  /// file sizes were the only clue.
  void frame(String name, int reading, String why) {
    testWidgets('render the shelf at $reading open ${_plural(reading)}', (
      tester,
    ) async {
      phone(tester);
      debugPrint(why);
      await pumpHome(tester, shelves: _library(reading: reading));
      await tester.pumpAndSettle();
      await _shoot(tester, dir(), name, crop: _band);
    });
  }

  // One is the state the shelf spends most of its life in; three is what every device in
  // the exploration was drawn on; seven is the overflow, where the row clips at about
  // three covers and the edge fade is the subject. Zero is the control for all of them.
  frame('reading_1', 1, 'one open book: the common case');
  frame('reading_3', 3, 'three: the state the devices were drawn on');
  frame('reading_7', 7, 'seven: the clip and the edge fades');
  frame('reading_none', 0, 'nothing open: no shelf at all');

  testWidgets('render the shelf in edit mode, to check the badge is not clipped', (
    tester,
  ) async {
    phone(tester);
    debugPrint(
      'edit mode: three open books, wobbling, each with its remove badge',
    );
    await pumpHome(tester, shelves: _library(reading: 3));
    await tester.pumpAndSettle();
    await enterEditMode(tester);

    // **No `pumpAndSettle` past here.** The covers are inside a `Wiggle`, which repeats for
    // as long as edit mode lasts, so there is no quiescent frame to settle to — which also
    // means this frame catches each cover at a random point in its own tilt. That is the
    // right thing for a preview and the wrong thing for a golden, so this stays a preview.
    await tester.pump(const Duration(milliseconds: 120));
    await _shoot(tester, dir(), 'reading_3_edit', crop: _band);
  });

  testWidgets('render a cover in the air, to check it kept its ribbon', (
    tester,
  ) async {
    phone(tester);
    debugPrint('mid-drag: the lifted cover, its ribbon, and the gap it left');
    await pumpHome(tester, shelves: _library(reading: 3));
    await tester.pumpAndSettle();
    await enterEditMode(tester);
    await tester.pump(const Duration(milliseconds: 120));

    // **The frame `_DraggedCover` needed and did not have.** It builds the flying cover from
    // scratch instead of reusing the widget that draws the resting one, and what fell out of
    // that was a book losing its ribbon for exactly as long as it was under the finger —
    // which no still frame of a resting shelf can show, and no widget test noticed either
    // until one was written for it.
    final cover = find
        .descendant(
          of: find.byType(ReadingShelfRow),
          matching: find.byType(LongPressDraggable<ReadingBookDrag>),
        )
        .first;
    final start = tester.getCenter(cover);
    final gesture = await tester.startGesture(start);
    await tester.pump(kShelfLiftDelay + const Duration(milliseconds: 60));
    // Up and along, so the cover is clear of the row it came from and the gap is visible
    // beside it rather than underneath.
    await gesture.moveTo(start + const Offset(70, -24));
    await tester.pump(const Duration(milliseconds: 200));

    await _shoot(tester, dir(), 'reading_3_edit_lifted', crop: _band);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('render the library scrolled, to show the light dimming in place', (
    tester,
  ) async {
    phone(tester);
    debugPrint('scrolled: the shelves move, the light stays and goes out');

    // **The frames the lamp was rebuilt for, twice.** The light is a fixture at the top of
    // the library rather than part of the Reading shelf, so scrolling has to move the
    // shelves *under* it — two earlier drafts had it inside the row, where it travelled up
    // the screen with the books. That is invisible in any still frame of an unscrolled
    // library, which is why these exist.
    //
    // And then the fixture had a cost of its own: a light that stays put does not stop
    // lighting things when its shelf leaves, so at full strength it ends up over a *queue*
    // shelf. Hence the middle and last frames — the same fixed light, dimming as the row
    // it belongs to goes.
    //
    // Seven shelves, because the point cannot be drawn on a library that fits — and this
    // is the second time that has bitten. The first attempt reused the three-book fixture,
    // which does not overflow, so the drag bounced back and the "scrolled" frame came out
    // identical to the resting one. The second used four shelves, which scroll about 110pt
    // — less than the fade — so the "out" frame was really "as far as this library goes",
    // with the lamp still faintly on. The guard below is what makes that visible instead of
    // something to notice in a PNG.
    await pumpHome(
      tester,
      shelves: [
        ..._library(reading: 3),
        for (final name in const ['Fic', 'Biz', 'Ref', 'Art', 'Sci', 'Hist'])
          testShelf(name, [
            for (var i = 0; i < 5; i++)
              testBook('$name-$i', name, position: i, title: _corpus[i].$2),
          ], name: name),
      ],
    );
    await tester.pumpAndSettle();
    await _shoot(tester, dir(), 'scroll_0_rest', crop: _band);

    // Both drags are fractions of the fade distance rather than round numbers, so these
    // stay the states they are meant to be if the tokens are ever retuned: a little under
    // half of the way out, then past the end of it.
    final fade = readingLampFadeDistance(_bookHeight);
    final list = find.byType(SingleChildScrollView).first;
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(
      position.maxScrollExtent,
      greaterThan(fade),
      reason:
          'this library cannot scroll far enough to put the light out, so the '
          'last frame would show the scroll limit rather than the fade',
    );

    // **A drag scrolls `kDragSlopDefault` less than it asks for**, and that is worth
    // stating rather than absorbing: `Scrollable` uses `DragStartBehavior.start`, so the
    // move that crosses the slop is where the drag *begins* and only what comes after it
    // scrolls. The first version of these frames lost 20pt per drag that way — 40pt across
    // the pair — and the one named "out" still had the lamp faintly on. Hence the extra
    // slop here and the assertions either side.
    Future<void> dragBy(double dy) async {
      await tester.drag(list, Offset(0, -(dy + kDragSlopDefault)));
      await tester.pumpAndSettle();
    }

    await dragBy(fade * 0.45);
    expect(position.pixels, closeTo(fade * 0.45, 0.5));
    await _shoot(tester, dir(), 'scroll_1_dimmed', crop: _band);

    await dragBy(fade * 0.7);
    expect(position.pixels, greaterThan(fade));
    await _shoot(tester, dir(), 'scroll_2_out', crop: _band);
  });
}

String _plural(int n) => n == 1 ? 'book' : 'books';
