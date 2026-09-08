// Not a test — a renderer. Writes PNGs of the read pile to build/pile_preview/ so
// the hashed sizes, the per-book tones and the turn can be judged by eye.
//
//   flutter test test/read_pile_render_preview.dart
//
// This exists because of what measurements have already failed to catch on this
// widget. Flush spines and flush turned covers both measured correctly and looked
// wrong; a sign error in the turn renders a book inside out while every number
// stays plausible. Five frames: the resting row, three points through the turn, and
// a second book opening while the first closes.
//
// The app's real faces are loaded (see `_loadRealFonts`), so the rotated titles are
// type. That matters now in a way it did not when this file was written: the spine
// sets `AppTextStyles.spine`, which is a serif, and a preview that drew boxes
// could not have told anyone whether that was a good idea.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/read_pile.dart';

/// Covers chosen to exercise the tint: a dark saturated one, a washed-out pale
/// one, a mid-tone, and two with no stored colour at all so they fall back to
/// `generatedCoverColor`.
///
/// The last three exist for the *title* rules rather than the tint, and were added
/// when the spine became a typographic decision. In order: a parenthetical
/// original title, which `spineTitleOf` should cut at the bracket; a long comma
/// list, which no spine can hold and whose tail should therefore ramp away rather
/// than sprout an ellipsis; and a Korean title short enough to fit whole, so the
/// two are visibly different outcomes rather than one treatment applied to
/// everything.
const List<(String, String, int?)> _corpus = [
  ('Shoe Dog', '9788934972464', 0xFF2A1C14),
  ('Eragon', '9788937834158', 0xFF3D5A80),
  ('Brisingr', '9788937834165', 0xFF8A7F3D),
  ('Eldest', '9788937834172', 0xFF7B2E2E),
  ('The White Book', '9788954633767', 0xFFDCD8D1),
  ('Start With Why', '9788901219943', null),
  ('Kim Jiyoung', '9788937473135', 0xFF4A6C6F),
  ('The Hole', '9788954655170', null),
  ('Almond', '9788936434120', 0xFF1B1B1B),
  ('Pachinko', '9788901219950', 0xFFB4654A),
  ('그로스 해킹(Growth Hacking)', '9788968482236', 0xFFF7F5F0),
  ('인공지능, 머신러닝, 딥러닝 입문', '9791158391720', 0xFF2E4E7A),
  ('세이노의 가르침', '9791195343522', 0xFFFFFFFF),
];

List<Book> _books() => [
  for (var i = 0; i < _corpus.length; i++)
    Book(
      id: 'b$i',
      userId: 'u',
      shelfId: 's1',
      isbn: _corpus[i].$2,
      title: _corpus[i].$1,
      thumbnail: '',
      status: 2,
      position: i,
      createdAt: DateTime(2024),
      authors: const [],
      finishDate: DateTime(2024, 3, 1),
      coverColor: _corpus[i].$3 == null ? null : Color(_corpus[i].$3!),
    ),
];

Widget _host(List<Book> books) => ProviderScope(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: const Color(0xffE9ECEF),
      body: Center(
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.white),
            child: SizedBox(width: 402, child: ReadPile(books: books)),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _shoot(WidgetTester tester, Directory dir, String name) =>
    _shootAt(tester, dir, name, 2);

Future<void> _shootAt(
  WidgetTester tester,
  Directory dir,
  String name,
  double pixelRatio,
) async {
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

/// Registers the app's real faces so the rotated titles are type rather than
/// boxes.
///
/// **This used to be absent, and the file's own header used to say so** — "real
/// fonts are not loaded, so the rotated titles are boxes". That was tolerable
/// while the thing being judged was silhouettes and fills. It stopped being
/// tolerable when the spine became a *typographic* decision: a preview of a serif
/// that cannot show the serif is not evidence about anything.
///
/// One cut per family, not four. `FontLoader` registers everything it is given
/// under a single family with no weight information, so handing it all four
/// Pretendard statics would let the engine answer `w400` with whichever arrived
/// first. The spine asks for `w700`, so w700 is what is loaded.
Future<void> _loadRealFonts() async {
  Future<void> load(String family, String file) async {
    final path = 'assets/fonts/$file';
    final bytes = File(path).readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }

  // The serif the spine sets, and the sans it falls back to for hanja.
  await load('GowunBatang', 'GowunBatang-Bold.ttf');
  await load('Pretendard', 'Pretendard-Bold.otf');
}

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('render the pile at rest and through the turn', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 500 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory('build/pile_preview')..createSync(recursive: true);
    final books = _books();

    await tester.pumpWidget(_host(books));
    await tester.pumpAndSettle();
    await _shoot(tester, dir, '1_at_rest');

    // The fifth book — the washed-out cover, so the tint's floor is visible on the
    // face that carries the title.
    await tester.tap(find.text('The White Book'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    await _shoot(tester, dir, '2_turning_early');

    await tester.pump(const Duration(milliseconds: 90));
    await _shoot(tester, dir, '3_turning_late');

    await tester.pumpAndSettle();
    await _shoot(tester, dir, '4_turned_out');

    // A second book, so the outgoing one is caught mid-close.
    await tester.tap(find.text('Eragon'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    await _shoot(tester, dir, '5_switching');
  });

  testWidgets('render three identically toned spines, magnified', (
    tester,
  ) async {
    // The separator is the one thing in the resting row that a normal frame
    // cannot show: every book there has its own tone, so a missing hairline looks
    // exactly like a present one. Three books of the *same* colour either read as
    // three books or as one wide block, and there is no third possibility.
    tester.view.physicalSize = const Size(402 * 3, 500 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory('build/pile_preview')..createSync(recursive: true);
    final twins = [
      for (var i = 0; i < 3; i++)
        Book(
          id: 't$i',
          userId: 'u',
          shelfId: 's1',
          // Different ISBNs, so they are different sizes: the hairline has to be
          // visible between books of unequal height too.
          isbn: ['9788937834158', '9788954633767', '9788901219943'][i],
          title: 'Twin',
          thumbnail: '',
          status: 2,
          position: i,
          createdAt: DateTime(2024),
          authors: const [],
          finishDate: DateTime(2024, 3, 1),
          coverColor: const Color(0xFF3D5A80),
        ),
    ];

    await tester.pumpWidget(_host(twins));
    await tester.pumpAndSettle();
    await _shootAt(tester, dir, '6_separator', 6);
  });

  testWidgets('render the title rules, magnified', (tester) async {
    // Every outcome `AppTextStyles.spine` can produce, in one frame, because each
    // is invisible in a frame that does not contain its neighbour. A fade is only
    // legible as a *decision* next to a title that was left alone.
    //
    // The ISBNs are not arbitrary. Spine thickness is hashed from the ISBN (no
    // `pageCount` here), and thickness is what decides one line or two — so the
    // hash is the only handle on the case being set up. The numbers in the
    // comments below were measured, not guessed; `kSpineTwoLineMinThickness` is
    // 33 and the measure is `height - 17`.
    tester.view.physicalSize = const Size(402 * 3, 500 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory('build/pile_preview')..createSync(recursive: true);

    // (title, isbn). Titles 4 and 5 are real, from `migration_data/book.jsonl`:
    // inventing a title long enough to overflow would have proved only that a
    // long string overflows, and the question is whether *this library's* titles
    // do.
    const cases = <(String, String)>[
      // Fits whole on one line (80.6pt drawn into 93.3pt). The control: an
      // unconditional mask would ramp this one too, which reads as the type
      // dissolving for no reason, and that is the first thing the drawing got
      // wrong.
      ('세이노의 가르침', '9791195343522'),
      // `spineTitleOf` cuts at the bracket. What makes this legible as a rule
      // rather than as truncation is that the result is *not* faded: it fits.
      ('그로스 해킹(Growth Hacking)', '9788968482236'),
      // Thick enough for two lines, and wraps into them exactly. Fits, so no
      // fade — the case that proves wrapping is not itself treated as overflow.
      ('인공지능, 머신러닝, 딥러닝 입문', '9788937834158'),
      // Thin: one line, 30 syllables, hopeless. The tail ramps away. This is the
      // `didExceedMaxLines` branch.
      ('할 수 있을 때 하지 않으면 하고 싶을 때 하지 못한다', '9788934972464'),
      // Thick: two lines, 35 syllables, still hopeless. Ramps on the *second*
      // line, which is the case `TextOverflow.ellipsis` cannot express at all
      // and the reason the fade exists.
      ('누구나 하루 30분 투자로 월 100만 원 더 버는 블로그 부업', '9788901219943'),
    ];

    final books = [
      for (var i = 0; i < cases.length; i++)
        Book(
          id: 'r$i',
          userId: 'u',
          shelfId: 's1',
          isbn: cases[i].$2,
          title: cases[i].$1,
          thumbnail: '',
          status: 2,
          position: i,
          createdAt: DateTime(2024),
          authors: const [],
          finishDate: DateTime(2024, 3, 1),
          // One colour for all five, so nothing but the type differs.
          coverColor: const Color(0xFF23262B),
        ),
    ];

    await tester.pumpWidget(_host(books));
    await tester.pumpAndSettle();
    await _shootAt(tester, dir, '7_titles', 6);
  });
}
