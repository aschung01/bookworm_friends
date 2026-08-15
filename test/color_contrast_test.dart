// WCAG contrast guards for the brand colour tokens.
//
// `brand` is the vivid brand green and is deliberately *not* checked: it exists
// for decoration (tints, spines, rings) where nothing has to be legible. The two
// tokens that carry meaning are checked in every direction they are used:
// `brandText` as foreground on each light/dark surface, and `brandFill` as a
// background under white text.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';

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

/// WCAG 2.x contrast ratio. Symmetric, so argument order doesn't matter.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// AA for normal-size text.
const _aaNormal = 4.5;

void main() {
  group('brand token contrast', () {
    test(
      'Given light mode, Then brandText clears AA on every light surface',
      () {
        const c = AppColors.light;
        expect(
          _contrast(c.brandText, c.surface),
          greaterThanOrEqualTo(_aaNormal),
        );
        expect(
          _contrast(c.brandText, c.surfaceVariant),
          greaterThanOrEqualTo(_aaNormal),
        );
        expect(
          _contrast(c.brandText, c.pageBackground),
          greaterThanOrEqualTo(_aaNormal),
        );
      },
    );

    test('Given dark mode, Then brandText clears AA on every dark surface', () {
      const c = AppColors.dark;
      expect(
        _contrast(c.brandText, c.surface),
        greaterThanOrEqualTo(_aaNormal),
      );
      expect(
        _contrast(c.brandText, c.surfaceVariant),
        greaterThanOrEqualTo(_aaNormal),
      );
      expect(
        _contrast(c.brandText, c.pageBackground),
        greaterThanOrEqualTo(_aaNormal),
      );
    });

    test('Given either theme, Then white text on brandFill clears AA', () {
      const white = Color(0xffFFFFFF);
      expect(
        _contrast(white, AppColors.light.brandFill),
        greaterThanOrEqualTo(_aaNormal),
      );
      expect(
        _contrast(white, AppColors.dark.brandFill),
        greaterThanOrEqualTo(_aaNormal),
      );
    });

    test(
      'Given the vivid brand green, Then it is retained for decoration and would fail as text',
      () {
        // Documents *why* the split exists: the brand hue is unusable as text on
        // a light surface, so it may only be used decoratively.
        expect(AppColors.light.brand, greenThemeColor);
        expect(AppColors.dark.brand, greenThemeColor);
        expect(
          _contrast(greenThemeColor, AppColors.light.surface),
          lessThan(3.0),
        );
      },
    );
  });
}
