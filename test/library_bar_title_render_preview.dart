// A drawing of the library bar's title, because "does a friend's name belong in
// the serif, and at what size?" is a typographic question and an opinion is not
// evidence. Writes `build/bar_title_preview/`.
//
// Two things it has to show, which a bare `Text` on a wide surface cannot:
//
//  * **the measure.** A visit's title shares its 390pt row with a leading ✕ and
//    three trailing controls, one of which is a word ("콕 찌르기" under `ko`).
//    Whether a name fits is a fact about the whole row, so the whole row is
//    drawn — at a real phone width, with those controls at their real sizes.
//  * **the coverage.** The last name in each ladder is deliberately outside
//    KS X 1001, so the serif hands it to Pretendard while the suffix beside it
//    stays serif. That row is what the serif costs, and it is the reason
//    `titleUser` exists and still does.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';

/// A 390pt phone: the narrowest current iPhone, so the measure shown is the one
/// that runs out first.
const _phoneWidth = 390.0;

const _ink = Color(0xFF212529);
const _dim = Color(0xFF626A72);
const _variant = Color(0xFFE9ECEF);
const _brandFill = Color(0xFF067657);
const _page = Color(0xFFF8F9FA);

Future<void> _loadRealFonts() async {
  Future<void> load(String family, String file) async {
    final bytes = File('assets/fonts/$file').readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }

  await load('GowunBatang', 'GowunBatang-Bold.ttf');
  // One cut only: `FontLoader` carries no weight information, so the sans is
  // registered at `titleUser`'s w600 and the serif's fallback borrows it.
  await load('Pretendard', 'Pretendard-SemiBold.otf');
}

/// A disc standing in for an `AdaptiveIconButton` at [diameter].
Widget _disc(double diameter) => Container(
  width: diameter,
  height: diameter,
  decoration: const BoxDecoration(color: _variant, shape: BoxShape.circle),
);

/// The Poke pill: `label` in white on `brandFill`, 12/6 padding, radius 16.
Widget _poke(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: _brandFill,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Text(
    text,
    style: AppTextStyles.label.copyWith(
      color: Colors.white,
      decoration: TextDecoration.none,
    ),
  ),
);

/// `_LibraryBar` at [_phoneWidth], in one of its two states.
///
/// The geometry is read off `home_page.dart` rather than eyeballed: 56pt tall,
/// 11pt of leading padding when the ✕ is present and 15 when it is not, a 36pt
/// ✕ with a 6pt gap, then density (44), the gear (40) and Poke on the trailing
/// side.
Widget _bar({
  required String name,
  required String suffix,
  required TextStyle style,
  required bool isSelf,
  required String pokeLabel,
}) => SizedBox(
  width: _phoneWidth,
  height: 56,
  child: Material(
    color: Colors.white,
    child: Padding(
      padding: EdgeInsets.only(left: isSelf ? 15 : 11, right: 15),
      child: Row(
        children: [
          if (!isSelf) ...[_disc(36), const SizedBox(width: 6)],
          Expanded(
            child: Text.rich(
              TextSpan(
                text: name,
                // Colour and `decoration` are the theme's job in the app;
                // without them `WidgetsApp`'s red-on-yellow unstyled-text
                // marker shows through.
                style: style.copyWith(
                  color: _ink,
                  decoration: TextDecoration.none,
                ),
                children: [
                  TextSpan(
                    text: suffix,
                    style: const TextStyle(color: _dim),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _disc(44),
          const SizedBox(width: 6),
          if (!isSelf) ...[
            SizedBox(width: 40, height: 44, child: Center(child: _disc(22))),
            _poke(pokeLabel),
          ] else
            _disc(44),
        ],
      ),
    ),
  ),
);

Widget _caption(String text) => Padding(
  padding: const EdgeInsets.only(left: 15, top: 10, bottom: 4),
  child: Text(
    text,
    style: const TextStyle(
      // Ahem is `flutter_test`'s default face and draws every glyph as a solid
      // block, so a caption has to name a real family too.
      fontFamily: 'Pretendard',
      fontSize: 11,
      color: Color(0xFF8A8A8F),
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.none,
    ),
  ),
);

void main() {
  setUpAll(_loadRealFonts);

  /// `title`'s size, then the token that ships, then two steps past it. 17 is
  /// [AppTextStyles.subtitle] — the sheet title stacked over this row — and is
  /// included as the floor the ladder must not reach.
  const ladder = <double>[22, 20, 18, 17];

  Future<void> shoot(WidgetTester tester, Widget child, String name) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: _page,
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dir = Directory('build/bar_title_preview')
      ..createSync(recursive: true);
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

  testWidgets('the visit title down the size ladder', (tester) async {
    tester.view.physicalSize = const Size(880 * 2, 960 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // `ko` first: it is the locale the measure runs out in, because the name is
    // followed by `의 서재` and Poke is four syllables rather than one word.
    const locales = [
      (
        'ko',
        '콕 찌를기',
        '의 서재',
        // A three-syllable name, then the four-syllable one a 22pt title
        // truncates, then one outside KS X 1001.
        ['아모개', '박서연진', '뷁솔똠'],
      ),
      ('en', 'Poke', "'s Library", ['jisoo', 'bartholomew', '뷁솔똠']),
    ];

    Widget column(
      String locale,
      String pokeLabel,
      String suffix,
      List<String> names,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption('$locale · your own title — title, 22'),
        _bar(
          name: locale == 'ko' ? '내 서재' : 'My Library',
          suffix: '',
          style: AppTextStyles.title,
          isSelf: true,
          pokeLabel: pokeLabel,
        ),
        for (final size in ladder) ...[
          _caption(
            size == AppTextStyles.titleVisit.fontSize
                ? '$locale · a visit — titleVisit, ${size.toInt()} (ships)'
                : '$locale · a visit — ${size.toInt()}',
          ),
          for (final name in names)
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: _bar(
                name: name,
                suffix: suffix,
                style: AppTextStyles.titleVisit.copyWith(
                  fontSize: size,
                  // Tracking follows the size, as the token's own does.
                  letterSpacing: -0.018 * size,
                ),
                isSelf: false,
                pokeLabel: pokeLabel,
              ),
            ),
        ],
      ],
    );

    await shoot(
      tester,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (locale, poke, suffix, names) in locales) ...[
            column(locale, poke, suffix, names),
            const SizedBox(width: 24),
          ],
        ],
      ),
      'ladder',
    );
  });

  testWidgets('the two states side by side at what ships', (tester) async {
    // The comparison that actually decides it: your own row above a visit's,
    // both at the size each ships at, so the step down is judged as a
    // transition rather than as a size in isolation.
    tester.view.physicalSize = const Size(440 * 2, 400 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await shoot(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _caption('ko · your own — title, 22'),
          _bar(
            name: '내 서재',
            suffix: '',
            style: AppTextStyles.title,
            isSelf: true,
            pokeLabel: '콕 찌르기',
          ),
          _caption('ko · a visit — titleVisit, 20'),
          _bar(
            name: '김하늘',
            suffix: '의 서재',
            style: AppTextStyles.titleVisit,
            isSelf: false,
            pokeLabel: '콕 찌르기',
          ),
          _caption('en · your own — title, 22'),
          _bar(
            name: 'My Library',
            suffix: '',
            style: AppTextStyles.title,
            isSelf: true,
            pokeLabel: 'Poke',
          ),
          _caption('en · a visit — titleVisit, 20'),
          _bar(
            name: 'jisoo',
            suffix: "'s Library",
            style: AppTextStyles.titleVisit,
            isSelf: false,
            pokeLabel: 'Poke',
          ),
        ],
      ),
      'transition',
    );
  });
}
