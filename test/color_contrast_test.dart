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
import 'package:bookworm_friends/ui/widgets/book_status_badge.dart';

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

/// AA for a boundary that identifies a component (WCAG 1.4.11).
const _aaNonText = 3.0;

/// Flattens a translucent colour over an opaque one.
///
/// The badge tints its *own* background, so its text is never actually read
/// against the surface underneath — it is read against the surface plus that
/// tint. Measuring against the bare surface is what let an unreadable badge ship
/// while every token-level assertion below passed.
Color _over(Color fg, Color bg) {
  final a = fg.a;
  return Color.fromARGB(
    255,
    ((fg.r * a + bg.r * (1 - a)) * 255).round(),
    ((fg.g * a + bg.g * (1 - a)) * 255).round(),
    ((fg.b * a + bg.b * (1 - a)) * 255).round(),
  );
}

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

  group('secondaryText contrast', () {
    // This group is a shipped defect closed. `secondaryText` was `#ADB5BD`, which
    // measures **2.07:1** on white and about 2.0:1 on the sheet — nowhere near
    // AA — and it was used as a *text* colour in twenty-nine files, including the
    // read sheet's empty state, which was very nearly invisible on a device.
    //
    // `stat_tile.dart` had already recorded this exact finding and worked around
    // it locally, for its own labels only. Nothing checked the token, because the
    // group above only ever checked the brand pair.

    test(
      'Given light mode, Then secondaryText clears AA on every light surface',
      () {
        const c = AppColors.light;
        for (final entry in <String, Color>{
          'surface': c.surface,
          // The binding one, exactly as `brandText`'s doc already argues.
          'surfaceVariant': c.surfaceVariant,
          'pageBackground': c.pageBackground,
          'sheetBackground': c.sheetBackground,
        }.entries) {
          expect(
            _contrast(c.secondaryText, entry.value),
            greaterThanOrEqualTo(_aaNormal),
            reason: 'secondaryText on ${entry.key}',
          );
        }
      },
    );

    test(
      'Given dark mode, Then secondaryText clears AA on every dark surface',
      () {
        const c = AppColors.dark;
        for (final entry in <String, Color>{
          'surface': c.surface,
          'surfaceVariant': c.surfaceVariant,
          'pageBackground': c.pageBackground,
          'sheetBackground': c.sheetBackground,
        }.entries) {
          expect(
            _contrast(c.secondaryText, entry.value),
            greaterThanOrEqualTo(_aaNormal),
            reason: 'secondaryText on ${entry.key}',
          );
        }
      },
    );

    test('Given the value it used to be, Then it would fail this group', () {
      // Keeps the reason on the record: without this, the assertions above look
      // like they were always true.
      const was = Color(0xffADB5BD);
      expect(_contrast(was, AppColors.light.surface), lessThan(_aaNormal));
      expect(_contrast(was, AppColors.light.surfaceVariant), lessThan(3.0));
    });
  });

  group('status badge contrast', () {
    // Measured against each badge's own composited fill rather than against the
    // surface, which is the distinction that matters here: `brandText` is 4.74:1
    // on `surfaceVariant` and the group above asserts exactly that, yet the
    // Reading badge only manages 4.14:1 because it darkens the background under
    // itself by 10% first.
    //
    // The badge that actually shipped broken was Interested, at **1.66:1** with
    // a 1.23:1 border, on 133 of 472 books. Nothing here covered it, because
    // everything above checks tokens and the defect was in a component. This
    // group is that gap closed.
    const c = AppColors.light;
    const surfaces = <String, Color>{
      'surfaceVariant': Color(0xffE9ECEF),
      'surface': Color(0xffFFFFFF),
    };

    test(
      'Given the Interested badge, Then its text clears AA on every surface it '
      'is drawn on',
      () {
        // No fill, so the text is read straight against the surface.
        for (final entry in surfaces.entries) {
          expect(
            _contrast(c.primaryText, entry.value),
            greaterThanOrEqualTo(_aaNormal),
            reason: 'Interested text on ${entry.key}',
          );
        }
      },
    );

    test(
      'Given the Interested badge has no fill, Then its border clears the 3:1 '
      'non-text bar so the chip is still identifiable',
      () {
        // With nothing behind it the outline is what says "this is a chip and
        // not loose text", so it carries the 1.4.11 obligation. The 0.35 first
        // drawn measured 2.06:1; 0.55 measures 3.41:1.
        for (final entry in surfaces.entries) {
          final border = _over(
            c.primaryText.withValues(
              alpha: BookStatusBadge.unfilledBorderAlpha,
            ),
            entry.value,
          );
          expect(
            _contrast(border, entry.value),
            greaterThanOrEqualTo(_aaNonText),
            reason: 'Interested border on ${entry.key}',
          );
        }
      },
    );

    test('Given the Read badge, Then its text clears AA over its own tint', () {
      for (final entry in surfaces.entries) {
        final fill = _over(c.primaryText.withValues(alpha: 0.1), entry.value);
        expect(
          _contrast(c.primaryText, fill),
          greaterThanOrEqualTo(_aaNormal),
          reason: 'Read text on its tint over ${entry.key}',
        );
      }
    });

    test(
      'Given the Reading badge, Then it is knowingly just under AA and pinned '
      'there',
      () {
        // Not a passing assertion dressed up as a guard: this records a
        // deliberate trade-off so it cannot quietly get worse. Fixing it costs
        // either the green text or the green fill, and green-means-reading is
        // load-bearing across the app.
        final fill = _over(
          c.brandText.withValues(alpha: 0.1),
          const Color(0xffE9ECEF),
        );
        final ratio = _contrast(c.brandText, fill);
        expect(ratio, lessThan(_aaNormal));
        expect(
          ratio,
          greaterThan(4.0),
          reason: 'if this drops further the trade-off stops being defensible',
        );
      },
    );
  });
}
