// Guards for `spineToneFor`.
//
// This file replaces `spine_tint_test.dart`, whose twelve tests all encoded the
// design this function removed: a chroma lift toward the brand, `bookBoardColorFor`
// on top of it, and a darkening walk to clear *white* type. Every one of those tests
// passed. They passed on a corpus of thirteen drawn books, and on a real library of
// 471 covers the design they were pinning turned `#FAFAFA` and `#F9F7F2` into the
// same dark sage. **A green suite is only worth its corpus.**
//
// So the properties asserted here are chosen to be the ones that would have caught
// that, and they are mostly about *direction* rather than about contrast ratios:
//
//  * A pale cover comes out pale. This is the assertion the old suite could not make,
//    because the old function could not satisfy it.
//  * A dark cover comes out dark. The mirror, and the reason the fix is a direction
//    rather than a threshold.
//  * Hue survives. `#FEEE02` has to stay yellow, because 48% of the border ring of
//    `주식투자 안내서` is that yellow and a spine is meant to be the colour of the book.
//  * The fill and the returned ink clear AA *against each other*. Not against white,
//    which is what the old suite checked and is now wrong for about half the library.
//  * The answer does not depend on the theme, which is a property the first draft of
//    this design got wrong — see the group at the bottom.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/book_chassis.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book/generated_cover.dart';

const Color _white = Color(0xFFFFFFFF);
const Color _black = Color(0xFF000000);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double _saturation(Color c) {
  final max = math.max(c.r, math.max(c.g, c.b));
  final min = math.min(c.r, math.min(c.g, c.b));
  return max == 0 ? 0 : (max - min) / max;
}

/// HSV hue in degrees, or null for a neutral, where hue is meaningless.
double? _hue(Color c) {
  final max = math.max(c.r, math.max(c.g, c.b));
  final min = math.min(c.r, math.min(c.g, c.b));
  final d = max - min;
  if (d < 1 / 255) return null;
  final double h;
  if (max == c.r) {
    h = 60 * (((c.g - c.b) / d) % 6);
  } else if (max == c.g) {
    h = 60 * ((c.b - c.r) / d + 2);
  } else {
    h = 60 * ((c.r - c.g) / d + 4);
  }
  return h % 360;
}

/// Deterministic covers spanning the whole cube, so a sweep does not depend on a
/// seed. Reuses `bookHash` rather than `Random` for the reason the pile does: the
/// same input has to give the same answer on every run and on every device.
Iterable<Color> _sweep(int count) => Iterable.generate(count, (i) {
  final h = bookHash('cover-$i');
  return Color.fromARGB(255, h & 0xFF, (h >> 8) & 0xFF, (h >> 16) & 0xFF);
});

/// The real cover tones this design was measured against, from the user's library.
///
/// Named rather than anonymous because each one is a different failure of the design
/// this replaced, and a regression here should say which book broke.
const _realCovers = <String, Color>{
  '세이노의 가르침': Color(0xFFFFFFFF), // pure-white jacket; 100% of the border ring
  'Clean Code': Color(0xFFFFFFFE), // near-white, 82%
  '주식투자 안내서': Color(0xFFFEEE02), // saturated yellow, 48%
  '5000일 후의 세계': Color(0xFF040001), // near-black, 42%
  '역행자': Color(0xFF855029), // the mean; no method finds the orange jacket
  '어떤 화장실이 좋아': Color(0xFF83ABDC), // mid blue
  '곰돌이 팬티': Color(0xFFDDA7A4), // pale pink — the tone that became #8E6B69
};

void main() {
  group('spineToneFor', () {
    test('Given any cover, Then the ink is legible on the fill', () {
      // The one contrast assertion, and note what it is *against*: the ink the
      // function itself returned. The old suite measured against white
      // unconditionally, which is the assumption that cost the library its pale half.
      //
      // This is also the termination test. The walk's exit condition is a ratio
      // rather than an arithmetic target, so a cover that ran out of its 24 steps
      // surfaces here as a fill under 4.6:1 rather than as a hang.
      for (final cover in _sweep(400)) {
        final tone = spineToneFor(cover);
        expect(
          _contrast(tone.fill, tone.title),
          greaterThanOrEqualTo(kSpineTintMinContrast - 0.001),
          reason:
              'cover $cover produced fill ${tone.fill}, which its own ink '
              '${tone.title} cannot sit on — the walk ran out of steps',
        );
      }
    });

    test('Given a pale cover, Then the spine stays pale and takes dark ink', () {
      // **The assertion the old design could not satisfy.** `spineTintFor` lifted a
      // near-white cover 43% toward the brand and then darkened it to make room for
      // white type; `#FAFAFA` and `#F9F7F2` both landed on the same dark sage, so two
      // different white books were indistinguishable on the shelf.
      for (final cover in const <Color>[
        Color(0xFFFFFFFF),
        Color(0xFFFAFAFA),
        Color(0xFFF9F7F2),
        Color(0xFFE4E2C9),
        Color(0xFFDDA7A4),
      ]) {
        final tone = spineToneFor(cover);

        expect(
          tone.title,
          kSpineInkDark,
          reason: 'pale cover $cover was given white type',
        );
        expect(
          tone.fill.computeLuminance(),
          greaterThanOrEqualTo(cover.computeLuminance() - 0.001),
          reason:
              'pale cover $cover was darkened to ${tone.fill} — this is the '
              'defect the whole redesign exists to remove',
        );
      }
    });

    test('Given a dark cover, Then the spine stays dark and takes light ink', () {
      // The mirror of the case above, and the reason the fix is a *direction*: a rule
      // that only ever lightened would wreck the dark half exactly as the old one
      // wrecked the light half.
      for (final cover in const <Color>[
        Color(0xFF000000),
        Color(0xFF040001),
        Color(0xFF23262B),
        Color(0xFF2E4E7A),
        Color(0xFF20553F),
      ]) {
        final tone = spineToneFor(cover);

        expect(
          tone.title,
          kSpineInkLight,
          reason: 'dark cover $cover was given dark type',
        );
        expect(
          tone.fill.computeLuminance(),
          lessThanOrEqualTo(cover.computeLuminance() + 0.001),
          reason: 'dark cover $cover was lightened to ${tone.fill}',
        );
      }
    });

    test('Given a pure white cover, Then the fill is still white', () {
      // A white book is a white book. Stated as its own test because it is the single
      // clearest sentence about what changed, and because it is the case a reader
      // will look for first: `세이노의 가르침` has a border ring that is 100% #FFFFFF and
      // used to render as a dark sage spine.
      final tone = spineToneFor(_white);

      expect(tone.fill, _white);
      expect(tone.title, kSpineInkDark);
    });

    test('Given a pure black cover, Then the fill is still black', () {
      // The other corner. Under the old design this one was *nearly* right by
      // accident — black has no chroma, so the lift fired on it as hard as on white
      // and a black jacket came out dark green until the luminance factor was added.
      // Here nothing fires at all: black already clears 4.6:1 against white.
      final tone = spineToneFor(_black);

      expect(tone.fill, _black);
      expect(tone.title, kSpineInkLight);
    });

    test('Given a saturated cover, Then its hue is unchanged', () {
      // The spine is the colour of the book, and hue is what carries that. The walk
      // lerps toward a neutral pole, which cannot rotate a hue — so this is really a
      // guard against anyone reintroducing a blend toward the brand, which is
      // precisely what shifted pale lavender, grey-green and grey-sage onto a single
      // hue near #617570.
      for (final entry in _realCovers.entries) {
        final before = _hue(entry.value);
        if (before == null) continue; // neutral: no hue to preserve

        expect(
          _hue(spineToneFor(entry.value).fill),
          closeTo(before, 1.0),
          reason:
              '${entry.key} changed hue: ${entry.value} → '
              '${spineToneFor(entry.value).fill}',
        );
      }
    });

    test('Given the yellow cover of 주식투자 안내서, Then it stays recognisably yellow', () {
      // A hue check alone would pass on a yellow washed out to near-grey, so this
      // pins chroma too. 48% of that cover's border ring is #FEEE02, which is the
      // single strongest argument for using the background colour rather than the
      // mean: the mean of the same cover is #979015, an olive that is not anywhere on
      // the book.
      final tone = spineToneFor(const Color(0xFFFEEE02));

      expect(
        _saturation(tone.fill),
        greaterThan(0.8),
        reason: 'the yellow washed out to ${tone.fill}',
      );
      expect(
        tone.title,
        kSpineInkDark,
        reason: 'a yellow this bright cannot carry white type',
      );
    });

    test('Given most covers, Then the fill is the cover unchanged', () {
      // The claim that makes this a floor rather than a treatment. Under the old
      // design 76% of the 471 real covers were being modified; if a change to the
      // constants pushed this back above half, the pile would again be wearing a
      // colour nobody chose.
      final moved = _sweep(400).where((c) => spineToneFor(c).fill != c).length;

      expect(
        moved,
        lessThan(200),
        reason:
            '$moved of 400 covers were adjusted — the contrast floor has become '
            'a recolouring',
      );
    });

    test('Given every generated-cover swatch, Then each carries its own ink', () {
      // The fallback a book with no thumbnail gets. Worth pinning separately because
      // these six are the only spine colours the app chooses for itself, so a failure
      // here is a design error rather than a data one.
      for (final swatch in kGeneratedCoverPalette) {
        final tone = spineToneFor(swatch);
        expect(
          _contrast(tone.fill, tone.title),
          greaterThanOrEqualTo(kSpineTintMinContrast - 0.001),
          reason: 'palette swatch $swatch cannot carry a title',
        );
        expect(
          _hue(tone.fill),
          _hue(swatch) == null ? isNull : closeTo(_hue(swatch)!, 1.0),
          reason: 'palette swatch $swatch changed hue',
        );
      }
    });

    test('Given the same cover twice, Then the tone is identical', () {
      // Stability, because a spine's colour is a book's identity in the pile. No
      // randomness, no time, no dependence on anything but the cover.
      for (final cover in _sweep(50)) {
        final a = spineToneFor(cover), b = spineToneFor(cover);
        expect(a.fill, b.fill);
        expect(a.title, b.title);
      }
    });

    test('Given the real library, Then no two distinct covers collapse together', () {
      // The homogenisation check. The old lift aimed every low-chroma cover at one
      // hue, so covers that started far apart converged — and on a shelf that reads
      // as duplicate books rather than as a colour bug. Seven real tones, seven
      // distinguishable spines.
      final fills = _realCovers.values.map((c) => spineToneFor(c).fill).toSet();

      expect(
        fills.length,
        _realCovers.length,
        reason:
            'two real covers produced the same spine: '
            '${_realCovers.keys.toList()} → $fills',
      );
    });
  });

  group('the inks are not theme colours', () {
    test('Given the dark ink, Then it is the light theme body-text colour', () {
      // `kSpineInkDark` is a copy of a theme token, so this is the test that keeps
      // the copy honest. If `AppColors.light.primaryText` is ever retuned, a pale
      // spine's title would silently stop matching body text everywhere else.
      expect(
        kSpineInkDark,
        AppColors.light.primaryText,
        reason:
            'kSpineInkDark has drifted from the token it was copied from — '
            'update it, or document why a pale spine now uses another near-black',
      );
    });

    test("Given dark mode's primaryText as the dark ink, Then a white cover would be "
        'ruined — which is why no theme colour is passed', () {
      // **The bug this design started with, kept as an executable argument.** The
      // first draft threaded `context.colors.primaryText` in as `darkInk`, which
      // looks more correct than a constant and is not: in dark mode that token is
      // `#F1F3F5`, so both inks are light, there is no dark ink for a pale spine,
      // and the walk has to darken a white jacket a long way to make room for
      // off-white type. A white book stops being white when the user turns the
      // lights off.
      //
      // Asserted rather than only commented, because the shape of the failure is
      // the whole justification for [kSpineInkDark] being a constant. If this ever
      // stops holding, the constant may no longer be needed.
      final withThemeInk = spineToneFor(
        _white,
        darkInk: AppColors.dark.primaryText,
      );
      expect(
        withThemeInk.fill.computeLuminance(),
        lessThan(0.5),
        reason:
            'the premise has changed: a dark-mode text token no longer forces '
            'a white cover down, so this test no longer argues anything',
      );

      // What the shipped defaults do with the same cover.
      expect(spineToneFor(_white).fill, _white);
    });

    test('Given a mid cover and a light ink, Then the fill is pushed darker', () {
      // The direction is taken from the chosen ink's own luminance, not from which
      // parameter it arrived in. Against a fixed ink, contrast is monotonic in the
      // fill's luminance, so the pole opposite the ink is always the direction that
      // helps — whatever the cover was, and whichever argument the ink came in.
      const cover = Color(0xFF808080);
      final tone = spineToneFor(cover, darkInk: AppColors.dark.primaryText);

      expect(
        tone.fill.computeLuminance(),
        lessThan(cover.computeLuminance()),
        reason:
            'a mid cover was lightened toward a light ink — the walk read the '
            'parameter name rather than the ink',
      );
      expect(
        _contrast(tone.fill, tone.title),
        greaterThanOrEqualTo(kSpineTintMinContrast - 0.001),
      );
    });
  });

  group('bookBoardColorFor', () {
    test('Given a cover, Then the board is darker than it', () {
      // Untouched by this work and still asserted, because the back board keeps the
      // always-darken rule that the spine gave up. That is not an inconsistency: a
      // board carries no type and is seen against the cover it came from, so it has
      // to be the deeper tone of the two.
      for (final cover in _sweep(100)) {
        expect(
          bookBoardColorFor(cover).computeLuminance(),
          lessThanOrEqualTo(cover.computeLuminance()),
        );
      }
    });
  });
}
