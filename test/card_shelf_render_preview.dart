// Not a test — a renderer. Writes PNGs of the Library Card's shelf to
// build/card_shelf_preview/ so the thing the reader actually gets can be compared with
// `docs/mockups/card-cover-crop/index.html` by eye.
//
//   flutter test test/card_shelf_render_preview.dart
//
// **This exists because the defect it replaces was invisible to every other check.**
// `_tierFor` drew 0.36-aspect boxes for 0.67-aspect covers and `BoxFit.cover` threw
// 20.7pt of jacket off each one, and the widget tests passed throughout because 17pt was
// exactly what the code meant to do. The mockup only failed to show it because it filled
// each cover with a flat swatch, and a flat 0.36 rectangle reads as a spine. So the
// covers here carry *content* — a band, a rule and a block of body — which is the one
// thing a crop cannot hide.
//
// One file per setting per count, plus the two lights, because the decision the drawings
// record is "one geometry, three settings" and a render of the default alone would not
// show whether that is true.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/library_card_stats.dart';
import 'package:bookworm_friends/services/cover_image.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_cover_row.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_shelf_plan.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';

/// Jackets with something printed on them, so a crop has something to eat.
///
/// Drawn rather than fetched: a widget test has no network, and a solid colour is
/// precisely the fixture that hid the original fault. Each is a band across the top, a
/// rule under it and a paragraph block — the layout every real cover has, which goes
/// visibly lopsided the moment a box is not cover-shaped.
Future<ui.Image> _jacket(Color ink, Color ground) async {
  final recorder = ui.PictureRecorder();
  const w = 200.0;
  const h = 300.0;
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = ground);
  final paint = Paint()..color = ink;
  // The band, inset from both edges: if the box is narrower than the jacket, the inset
  // on one side survives and the other does not, which is the tell.
  canvas.drawRect(const Rect.fromLTWH(24, 30, w - 48, 46), paint);
  canvas.drawRect(const Rect.fromLTWH(24, 96, w - 48, 4), paint);
  for (var i = 0; i < 6; i++) {
    canvas.drawRect(
      Rect.fromLTWH(24, 130 + i * 18, (w - 48) * (i.isEven ? 1 : 0.7), 8),
      paint,
    );
  }
  // A frame, which is the strongest crop indicator there is: one that has lost a side
  // is unmistakable at any size.
  canvas.drawRect(
    const Rect.fromLTWH(8, 8, w - 16, h - 16),
    Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  return recorder.endRecording().toImage(w.toInt(), h.toInt());
}

/// Resolves on the first frame, so nothing here depends on decode timing.
class _Ready extends ImageProvider<_Ready> {
  _Ready(this.key, this.image);

  final String key;
  final ui.Image image;

  @override
  Future<_Ready> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_Ready>(this);

  @override
  bool operator ==(Object other) => other is _Ready && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  ImageStreamCompleter loadImage(_Ready key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
      );
}

Book _read(String isbn, DateTime finish) => Book(
  id: isbn,
  userId: 'u',
  shelfId: 's',
  isbn: isbn,
  title: 'Book $isbn',
  thumbnail: 'jacket://$isbn',
  status: 2,
  position: 0,
  startDate: finish.subtract(const Duration(days: 9)),
  finishDate: finish,
  createdAt: DateTime(2024),
);

Book _open(String isbn) => Book(
  id: isbn,
  userId: 'u',
  shelfId: 's',
  isbn: isbn,
  title: 'Open $isbn',
  thumbnail: 'jacket://$isbn',
  status: 1,
  position: 0,
  startDate: DateTime(2026, 8, 1),
  createdAt: DateTime(2024),
);

/// Finished books spread over a year, so the stamps do not all read the same month.
List<Book> _books(int count) => [
  for (var i = 0; i < count; i++)
    _read('b$i', DateTime(2026, 1 + (i * 7) % 12, 1 + (i * 3) % 28)),
];

Future<void> _shoot(
  WidgetTester tester,
  Directory dir,
  String name,
  Widget child,
) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ColoredBox(
        color: const Color(0xFF6E6E73),
        child: Center(
          child: RepaintBoundary(key: const ValueKey('shot'), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await _capture(tester, dir, name);
}

/// Rasterises whatever is under the `shot` boundary.
Future<void> _capture(WidgetTester tester, Directory dir, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  late Uint8List png;
  // `runAsync`, and it is the whole reason this compiles into something that finishes.
  // `toImage` completes on the real event loop, which `testWidgets`' fake clock does not
  // pump — awaiting it directly hangs until the ten-minute test timeout with no error.
  await tester.runAsync(() async {
    // 3x, matching the export's own scale: the covers are small and a 1x render would
    // make the resampling the thing being judged instead of the geometry.
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
  });
  File('${dir.path}/$name.png').writeAsBytesSync(png);
}

void main() {
  final dir = Directory('build/card_shelf_preview');

  setUpAll(() async {
    dir.createSync(recursive: true);
    final jackets = <String, ui.Image>{};
    const inks = [
      [Color(0xFF1D3557), Color(0xFFF1FAEE)],
      [Color(0xFF6A040F), Color(0xFFFFE8D6)],
      [Color(0xFF1B4332), Color(0xFFE9F5DB)],
      [Color(0xFF3D348B), Color(0xFFFDF0D5)],
      [Color(0xFF7F5539), Color(0xFFEDEDE9)],
    ];
    // Built ahead of the resolver being asked, because the resolver is synchronous.
    for (var i = 0; i < 120; i++) {
      final pair = inks[i % inks.length];
      jackets['jacket://b$i'] = await _jacket(pair[0], pair[1]);
    }
    for (var i = 0; i < 8; i++) {
      final pair = inks[(i + 2) % inks.length];
      jackets['jacket://r$i'] = await _jacket(pair[0], pair[1]);
    }
    coverImageProvider = (url) => _Ready(url, jackets[url]!);
  });

  tearDownAll(() {
    coverImageProvider = networkCoverImage;
  });

  testWidgets('the shelf, at every count', (tester) async {
    // The counts that matter: the median reader's two, the boundary where growing stops,
    // the reported card's 22, and a library past capacity so the count of what is not
    // shown has to appear.
    for (final count in const [2, 5, 8, 9, 17, 18, 22, 90]) {
      await _shoot(
        tester,
        dir,
        'shelf-$count',
        SizedBox(
          width: 360,
          child: CardCoverRow(books: _books(count), unit: 360 / kCardUnits),
        ),
      );
    }
  });

  testWidgets('the shelf with books the reader still has open', (tester) async {
    await _shoot(
      tester,
      dir,
      'shelf-open',
      SizedBox(
        width: 360,
        child: CardCoverRow(
          books: _books(22),
          reading: [_open('r0'), _open('r1')],
          unit: 360 / kCardUnits,
        ),
      ),
    );
  });

  testWidgets('the whole card, which is what actually leaves the phone', (
    tester,
  ) async {
    for (final count in const [2, 22, 90]) {
      for (final lighting in CardLighting.values) {
        final books = _books(count);
        await _shoot(
          tester,
          dir,
          'card-$count-${lighting.name}',
          ShareableLibraryCard(
            stats: libraryCardStats(books),
            books: books,
            reading: count > 2 ? [_open('r0')] : const [],
            displayName: 'Alex Smith',
            handle: 'alexsmith',
            memberSince: DateTime(2026, 6, 26),
            issuedOn: DateTime(2026, 8, 21),
            lighting: lighting,
          ),
        );
      }
    }
  });

  testWidgets('the in-app hero tile, which previews the artifact', (
    tester,
  ) async {
    // A different geometry on purpose: one board, no board drawn, and a ceiling of the
    // hero figure's own 46pt. Rendered so the two can be compared, because the whole
    // point of the preview is that the reader recognises what they shared.
    for (final count in const [2, 22]) {
      await _shoot(
        tester,
        dir,
        'hero-$count',
        SizedBox(
          width: 300,
          child: CardCoverRow(
            books: _books(count),
            maxBoards: 1,
            showBoards: false,
            maxHeight: 46,
            alignment: MainAxisAlignment.start,
          ),
        ),
      );
    }
  });

  testWidgets('the reader who crashed it: 22 read and six on the go', (
    tester,
  ) async {
    // The card from the bug report. Six open books is one more than a board holds, and
    // the front group is capped there — so this is both the crash's fixture and the
    // drawing of what the cap actually produces, which is a top board of nothing but
    // unfinished reading. Worth looking at before deciding the cap is right.
    await _shoot(
      tester,
      dir,
      'reported',
      SizedBox(
        width: 360,
        child: CardCoverRow(
          books: _books(22),
          reading: [for (var i = 0; i < 6; i++) _open('r$i')],
          unit: 360 / kCardUnits,
        ),
      ),
    );
  });

  testWidgets('the shelf tone, as a ladder', (tester) async {
    // The board used to be a wash of `kCardInk`, which made it the one grey thing on a
    // cream-and-flame card. This is the ladder from that to invisible, in the card's own
    // colours — no new hexes — so "a bit brighter" can be answered with a step rather than
    // with a guess. Top to bottom:
    //
    //   1  kCardInk at 0.22        the old wash, roughly #C7C6BB
    //   2  kCardStockLine          what ships now, #DDD3BD
    //   3  halfway to the stock    #E7E0CF
    //   4  kCardStock              #F2EDE0, which is the card's own paper and all but
    //                              disappears against the well
    const tones = <Color>[
      Color(0x381F2D27),
      kCardStockLine,
      Color(0xFFE7E0CF),
      kCardStock,
    ];
    await _shoot(
      tester,
      dir,
      'shelf-tone-ladder',
      DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kCardWellTop, kCardWellBottom],
          ),
        ),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tone in tones)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Two books, so the board is judged with something standing on it.
                      // A flat bar with nothing on it is how the crop bug got approved.
                      SizedBox(
                        height: 34,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final c in const [
                              Color(0xFF1D3557),
                              Color(0xFF6A040F),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: SizedBox(
                                  width: 23,
                                  child: ColoredBox(color: c),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 5.4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tone,
                            borderRadius: BorderRadius.circular(3.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  });

  testWidgets('the card\'s board against the library\'s plank', (tester) async {
    // Answering "why do these look different?" with a drawing rather than an opinion.
    // Left: `ShelfWidget`, the library's plank — 8pt, the theme's `surface`, square ends,
    // and a drop shadow. Middle: the card's board as it *used* to ship — 5.4pt, the card's
    // own stock line, fully rounded, no shadow. Right: what ships now, drawn off the same
    // constants and palette the widget reads, so this panel cannot drift from it.
    //
    // Books at each shelf's own scale, because a plank is judged by whether things look
    // like they are standing on it.
    Widget plank({
      required double height,
      required Color colour,
      required double radius,
      required bool shadow,
      required double bookHeight,
      required Color ground,
      Color shadowColour = const Color(0x40000000),
    }) => ColoredBox(
      color: ground,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: bookHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in const [
                    Color(0xFF1D3557),
                    Color(0xFF6A040F),
                    Color(0xFF1B4332),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: bookHeight * (26 / 124),
                        child: ColoredBox(color: c),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: bookHeight * (4.75 / 124)),
            SizedBox(
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: shadow
                      ? [
                          BoxShadow(
                            offset: Offset(0, height * 0.25),
                            blurRadius: height * 0.25,
                            color: shadowColour,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );

    await _shoot(
      tester,
      dir,
      'plank-vs-board',
      SizedBox(
        width: 620,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: plank(
                // ShelfWidget: 8pt, `colors.surface`, square, shadow at (0,2) blur 2.
                height: 8,
                colour: const Color(0xFFFFFFFF),
                radius: 0,
                shadow: true,
                bookHeight: 124,
                ground: const Color(0xFFF8F9FA),
              ),
            ),
            Expanded(
              child: plank(
                // The board as it used to ship: radius `1 * unit` on a 1.6u bar, which is
                // a pill, and no shadow at all.
                height: kCardBoardUnits * (360 / kCardUnits),
                colour: kCardStockLine,
                radius: 1 * (360 / kCardUnits),
                shadow: false,
                bookHeight: kCardTwoBoardCoverUnits * (360 / kCardUnits),
                ground: kCardWellBottom,
              ),
            ),
            Expanded(
              child: plank(
                // What ships now: the card's own colour under the library's shape and
                // shadow. Every number read back from the constants the widget uses.
                height: kCardBoardUnits * (360 / kCardUnits),
                colour: cardPalette(CardLighting.daylight).shelf,
                radius: 0,
                shadow: true,
                shadowColour: cardPalette(CardLighting.daylight).boardShadow!,
                bookHeight: kCardTwoBoardCoverUnits * (360 / kCardUnits),
                ground: kCardWellBottom,
              ),
            ),
          ],
        ),
      ),
    );
  });
}
