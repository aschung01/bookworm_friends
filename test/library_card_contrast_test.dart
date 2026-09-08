// WCAG contrast guards for the Library Card's stat tiles.
//
// Separate from `color_contrast_test.dart`, which guards the brand *tokens*. What is
// checked here is different: the tile colours are **derived** — a gradient between two
// stops, and a muted text tone composited over one of them — so no token check reaches
// them, and the failure they had was invisible to every existing test.
//
// It was not invisible on a device. The first version of the tiles used
// `secondaryText` (`#ADB5BD`) on a `surfaceVariant` (`#E9ECEF`) ground, which is about
// 2.0:1, and the labels read as washed out in the first screenshot of the card. The
// same screenshot showed the other bug: the tile graded from `surfaceVariant` to
// `surface`, ending at pure white — lighter than the `#EFF5EF` sheet behind it — so
// each tile's bottom-right corner dissolved into the sheet.
//
// Both are now pinned. A gradient has to be checked at **both** stops, because a
// ratio that passes at the light end can fail at the dark one and the eye only ever
// sees the worst of the two.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';
import 'package:bookworm_friends/ui/widgets/library_card/stat_tile.dart';

/// WCAG 2.x relative luminance.
double _luminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Flattens a translucent foreground onto an opaque ground.
///
/// Required, not a nicety: the tiles' muted tone is `primaryText` at 70%, and reading
/// its contrast without compositing it first measures a colour that is never painted.
Color _over(Color foreground, Color ground) =>
    Color.lerp(ground, foreground.withValues(alpha: 1), foreground.a)!;

/// AA for normal-size text.
const _aaNormal = 4.5;

/// AA for text at 18pt+ bold or 24pt+ regular. The figures qualify; the labels and
/// sub-lines do not, so they are held to [_aaNormal].
const _aaLarge = 3.0;

void main() {
  for (final theme in {
    'light': AppColors.light,
    'dark': AppColors.dark,
  }.entries) {
    final name = theme.key;
    final colors = theme.value;

    group('stat tile contrast ($name)', () {
      test('Given the hero gradient, When white text sits on either stop, '
          'Then both clear AA', () {
        // White on the brand fill is the one combination the theme already
        // documents as safe. What needs checking is the *other* stop, which this
        // widget invents.
        for (final stop in statTileHeroFill(colors)) {
          expect(
            _contrast(const Color(0xFFFFFFFF), stop),
            greaterThanOrEqualTo(_aaNormal),
            reason:
                'the hero grades darker from brandFill precisely so this holds; '
                'grading toward the vivid brand green would put it at 2.45:1',
          );
        }
      });

      test(
        'Given the hero gradient, When the muted sub-line sits on either stop, '
        'Then it still clears AA',
        () {
          // The sub-line under the figure. Composited, because that is what is
          // painted — and it started at 78% white, which is 4.08:1 on brandFill.
          final muted = statTileHeroMutedText();
          for (final stop in statTileHeroFill(colors)) {
            expect(
              _contrast(_over(muted, stop), stop),
              greaterThanOrEqualTo(_aaNormal),
            );
          }
        },
      );

      test(
        'Given a non-hero tile, When its label sits on either stop, Then it clears AA',
        () {
          // The regression this file exists for. `secondaryText` here was ~2.0:1.
          for (final stop in statTileFill(colors)) {
            final ratio = _contrast(
              _over(statTileMutedText(colors), stop),
              stop,
            );
            expect(
              ratio,
              greaterThanOrEqualTo(_aaNormal),
              reason:
                  'a 10.5pt uppercase label is the least forgiving text on the '
                  'card, and it measured 2.0:1 against the tile before this',
            );
          }
        },
      );

      test(
        'Given a non-hero tile, When its figure sits on either stop, Then it clears AA',
        () {
          for (final stop in statTileFill(colors)) {
            expect(
              _contrast(colors.primaryText, stop),
              greaterThanOrEqualTo(_aaNormal),
            );
          }
        },
      );

      test('Given a non-hero tile, When it sits on the sheet, Then its edge is visible '
          'at both stops', () {
        // Not a WCAG rule — a shape rule. A tile whose fill is *lighter* than the
        // sheet behind it has no edge, which is exactly how the first version
        // dissolved into the sheet at its bottom-right corner. Both stops must be
        // distinguishable from the sheet, and both must be on the same side of it.
        final sheet = colors.sheetBackground;
        final stops = statTileFill(colors);
        for (final stop in stops) {
          expect(
            _contrast(stop, sheet),
            greaterThan(1.02),
            reason: '$stop is indistinguishable from the sheet behind it',
          );
        }
        final sheetLuminance = _luminance(sheet);
        final darker = stops.every((stop) => _luminance(stop) < sheetLuminance);
        final lighter = stops.every(
          (stop) => _luminance(stop) > sheetLuminance,
        );
        expect(
          darker || lighter,
          isTrue,
          reason:
              'the gradient must not cross the sheet\'s own tone, or the tile '
              'has an edge at one corner and none at the other',
        );
      });

      test(
        'Given the tile gradient, When it renders, Then it is actually a gradient',
        () {
          final stops = statTileFill(colors);
          expect(stops.length, 2);
          expect(
            _contrast(stops.first, stops.last),
            greaterThan(1.01),
            reason:
                'two identical stops is a flat fill wearing a gradient\'s API',
          );
        },
      );
    });
  }

  // The large-text allowance is referenced above only to say the figures do not need
  // it. Asserted so the constant is not dead.
  test('AA thresholds are the WCAG ones', () {
    expect(_aaNormal, 4.5);
    expect(_aaLarge, 3.0);
  });

  // The exported card is a different problem from the tiles, and a harder one: it is
  // ink on cream rather than white on brand, it is pinned in both themes so no theme
  // check reaches it, and it is read at thumbnail scale in a chat list before anyone
  // decides whether to open it. The drawings' label tone measured **3.3:1** here,
  // which is how `cardLabelInk` ended up at 70% rather than 55%.
  group('card stock contrast', () {
    test(
      'Given the stock, When the record is printed on it, Then the figures and '
      'values clear AA',
      () {
        expect(
          _contrast(kCardInk, kCardStock),
          greaterThanOrEqualTo(_aaNormal),
        );
      },
    );

    test(
      'Given the stock, When a label is printed on it, Then the composite clears AA',
      () {
        // Composited, because that is what is painted. Reading the alpha colour
        // directly measures a tone that never reaches the card.
        expect(
          _contrast(_over(cardLabelInk(), kCardStock), kCardStock),
          greaterThanOrEqualTo(_aaNormal),
          reason:
              'a 10pt label at 55% ink measures 3.3:1 on this stock, which is why '
              'it is 70%',
        );
      },
    );

    test('Given the stock, When the strip is printed on it, Then the return path '
        'clears AA by more than the labels do', () {
      // The strip earns the share. If anything on the card has to be legible after a
      // screenshot, a re-save and a forward, it is this.
      final strip = _contrast(_over(cardStripInk(), kCardStock), kCardStock);
      final label = _contrast(_over(cardLabelInk(), kCardStock), kCardStock);

      expect(strip, greaterThanOrEqualTo(_aaNormal));
      expect(strip, greaterThan(label));
    });

    test('Given the stock, When the title is printed on it, Then the brand green '
        'clears AA at both themes', () {
      // `brandFill` is the one theme colour the artifact still reads, and only
      // because it is documented as identical in light and dark. Asserted at both,
      // so that documentation cannot quietly stop being true.
      for (final colors in [AppColors.light, AppColors.dark]) {
        expect(
          _contrast(colors.brandFill, kCardStock),
          greaterThanOrEqualTo(_aaNormal),
          reason: 'the card title is brand green on cream',
        );
      }
    });

    test('Given the well, When it sits on the stock, Then it reads as a panel and is '
        'actually a gradient', () {
      // The shape rule the tiles taught: a panel whose fill matches the ground it
      // sits on has no edge. Both stops must differ from the stock, and the well
      // must not be a flat fill wearing a gradient\'s API.
      for (final stop in [kCardWellTop, kCardWellBottom]) {
        expect(_contrast(stop, kCardStock), greaterThan(1.005));
      }
      expect(_contrast(kCardWellTop, kCardWellBottom), greaterThan(1.01));
    });
  });

  // Candlelight, and the assertion this group exists for is the strip's.
  //
  // **The plan named it as the task's hardest constraint.** Physically the bottom of a
  // card held under a candle is its darkest region, and the strip is printed there — and
  // the strip is the one element on the artifact that earns the share, so it has to
  // survive being read off a screenshot. Where the physics and the return path disagree,
  // the return path wins: the falloff lives in the stock, *behind* the type, and the
  // bloom painted over the card carries no dark stop at all. Both stops are measured,
  // because the bottom one is where the strip actually sits.
  group('candlelight contrast', () {
    final lit = cardPalette(CardLighting.candlelight);

    test(
      'Given a lit card, When the strip is printed on it, Then it clears AA at the '
      'darkest end of the stock',
      () {
        for (final stop in lit.stock) {
          expect(
            _contrast(_over(lit.stripInk, stop), stop),
            greaterThanOrEqualTo(_aaNormal),
          );
        }
        // And by more than the labels, exactly as in daylight.
        expect(
          _contrast(_over(lit.stripInk, lit.stock.last), lit.stock.last),
          greaterThan(
            _contrast(_over(lit.labelInk, lit.stock.last), lit.stock.last),
          ),
        );
      },
    );

    test('Given a lit card, When the bloom is painted over the strip, Then it does not '
        'darken it', () {
      // The drawings' overlay ends at `rgba(0,0,0,.13)` and needed a `z-index` to keep
      // the strip out from under it. Removing the dark stop removes the need for the
      // trick — asserted here so it cannot come back.
      for (final stop in kCandleBloomColors) {
        expect(_luminance(stop.withValues(alpha: 1)), greaterThan(0.2));
      }
    });

    test(
      'Given a lit card, When labels and figures are printed, Then both clear AA at '
      'both stops',
      () {
        for (final stop in lit.stock) {
          expect(
            _contrast(_over(lit.labelInk, stop), stop),
            greaterThanOrEqualTo(_aaNormal),
          );
          expect(_contrast(lit.ink, stop), greaterThanOrEqualTo(_aaNormal));
        }
      },
    );

    test('Given a lit card, When the title and the unit are printed, Then the flame and '
        'the glow both clear AA', () {
      // These are the two colours that replace `brandFill`, and they replace it on a
      // ground four times darker than cream. Asserted with the light theme's own
      // `brandFill` passed in, which is what the widget does.
      for (final stop in lit.stock) {
        expect(
          _contrast(lit.titleInk(AppColors.light.brandFill), stop),
          greaterThanOrEqualTo(_aaNormal),
        );
        expect(
          _contrast(lit.accentInk(AppColors.light.brandFill), stop),
          greaterThanOrEqualTo(_aaNormal),
        );
      }
    });
  });

  // The `View and share` chrome, which is the opposite kind of colour from the stock
  // above it: themed rather than pinned, because it is read by the person holding the
  // phone rather than by whoever they send the image to. What it shares with the tiles
  // is the failure mode — a muted tone over a *gradient*, so no token check reaches it
  // and both stops have to be measured. `secondaryText` on the light stop is about
  // 2.0:1, which is precisely the bug this file was opened for.
  group('share screen chrome contrast', () {
    for (final (name, colors) in [
      ('light', AppColors.light),
      ('dark', AppColors.dark),
    ]) {
      test(
        'Given the $name theme, When the subtitle and destination labels are drawn, '
        'Then they clear AA at both ends of the ground',
        () {
          final ground = shareChromeGround(colors);
          expect(ground, hasLength(2));
          for (final stop in ground) {
            expect(
              _contrast(_over(shareChromeMutedInk(colors), stop), stop),
              greaterThanOrEqualTo(_aaNormal),
              reason:
                  'the scope subtitle is the only thing on screen that names the '
                  'year about to leave the phone',
            );
          }
        },
      );

      test(
        'Given the $name theme, When the title is drawn, Then the ground is a real '
        'gradient it stays legible across',
        () {
          final ground = shareChromeGround(colors);
          expect(_contrast(ground.first, ground.last), greaterThan(1.01));
          for (final stop in ground) {
            expect(
              _contrast(colors.primaryText, stop),
              greaterThanOrEqualTo(_aaNormal),
            );
          }
        },
      );
    }
  });

  // The same chrome under a candle, where every token is a pinned value rather than a
  // theme one — the whole screen becomes one scene when the card is lit, so the chrome
  // takes the same light and stops being themed.
  group('share screen chrome contrast, lit', () {
    for (final (name, colors) in [
      ('light', AppColors.light),
      ('dark', AppColors.dark),
    ]) {
      test(
        'Given the $name theme, When the candle is lit, Then the chrome is legible '
        'whichever theme the reader is in',
        () {
          // Both themes, because the lit chrome ignores the theme: if it did not, this
          // would catch it.
          final ground = shareChromeGround(
            colors,
            lighting: CardLighting.candlelight,
          );
          expect(ground, [kShareChromeLitTop, kShareChromeLitBottom]);
          for (final stop in ground) {
            expect(
              _contrast(
                shareChromeInk(colors, lighting: CardLighting.candlelight),
                stop,
              ),
              greaterThanOrEqualTo(_aaNormal),
            );
            expect(
              _contrast(
                _over(
                  shareChromeMutedInk(
                    colors,
                    lighting: CardLighting.candlelight,
                  ),
                  stop,
                ),
                stop,
              ),
              greaterThanOrEqualTo(_aaNormal),
            );
          }
        },
      );
    }
  });
}
