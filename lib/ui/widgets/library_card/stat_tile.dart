import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';

/// The muted tone the hero paints its label and sub-line in.
///
/// White at 88%, not the 78% it started at. 78% measures **4.08:1** against
/// `brandFill`, which is under AA for normal text — caught by
/// `library_card_contrast_test.dart` on the light *and* dark themes, since `brandFill`
/// is the same colour in both. 88% clears it at 4.75:1 on the lighter stop while still
/// reading as secondary against the pure-white figure beside it.
Color statTileHeroMutedText() =>
    const Color(0xFFFFFFFF).withValues(alpha: 0.88);

/// Colours a non-hero [StatTile] paints its label and sub-line in.
///
/// A composite of [AppColors.primaryText] over the tile's own ground rather than
/// [AppColors.secondaryText], and that is a correction rather than a preference: the
/// first version used `secondaryText`, which is `#ADB5BD` and scores about **2.0:1**
/// on the `#E9ECEF` tile — the labels were visibly washed out on a device, which is
/// how it was caught. `brandText`'s own doc already says surfaceVariant is the
/// binding constraint for contrast on light surfaces, and a 10.5pt uppercase label is
/// the least forgiving text on the card.
///
/// Pinned by `test/library_card_contrast_test.dart`.
Color statTileMutedText(AppColors colors) =>
    colors.primaryText.withValues(alpha: 0.7);

/// The two stops a non-hero [StatTile] grades between.
///
/// Grades **darker**, from `surfaceVariant` toward the text colour. The first version
/// graded `surfaceVariant → surface`, which ends at pure white — lighter than the
/// `#EFF5EF` sheet behind it, so each tile's bottom-right corner dissolved into the
/// sheet and the tile stopped reading as a tile. Seen on a device; no test would have
/// noticed, because the gradient was present and correct in every way except which
/// direction it went.
List<Color> statTileFill(AppColors colors) => [
  colors.surfaceVariant,
  Color.lerp(colors.surfaceVariant, colors.primaryText, 0.07)!,
];

/// The two stops the hero grades between.
///
/// From [AppColors.brandFill] to a *darker* mix of it, never toward the vivid
/// [AppColors.brand]. `brandFill` is the one brand colour documented to carry white
/// text; the vivid green is 2.45:1 against white. Grading darker cannot make the
/// contrast worse than an endpoint that is already known good, and grading toward the
/// vivid green demonstrably would.
List<Color> statTileHeroFill(AppColors colors) => [
  colors.brandFill,
  Color.lerp(colors.brandFill, Colors.black, 0.22)!,
];

/// How a [StatTile] is sized and coloured.
enum StatTileVariant {
  /// The one tile at the top of the card: brand gradient, white text, the
  /// figure large enough to be the thing you see first.
  hero,

  /// Everything below the hero: a surface gradient and body-coloured text, so a
  /// card with three tiles does not read as three heroes competing.
  tile,
}

/// A stat card: uppercase label, oversized figure, optional sub-line, gradient fill.
///
/// The drawings' "Stat card" element, and the whole visual argument of the Library
/// Card. It matters more here than it would elsewhere because **the data is thin** —
/// the median reader in this app has finished two books, so the card cannot be
/// carried by how much it says and has to be carried by how it says it.
///
/// Two deliberate departures from the element note, both about contrast:
///
///  * The note says "gradient fill" without saying between what. Both variants grade
///    **darker** from their base rather than lighter — see [statTileHeroFill] and
///    [statTileFill], which each record the version that was wrong and why.
///  * Non-hero tiles take body-coloured text rather than the brand, and their muted
///    tone is [statTileMutedText] rather than `secondaryText`. Three brand-green
///    blocks stacked was louder than the drawing and made the hero stop being the
///    hero; `secondaryText` on a `surfaceVariant` tile was unreadable.
class StatTile extends StatelessWidget {
  /// Drawn uppercase and letterspaced. Pass it in natural case — `toUpperCase` is
  /// applied here, and is a no-op on Korean, which is the point of not baking the
  /// casing into the l10n string.
  final String label;

  /// The oversized part. A string rather than a number because it is sometimes a
  /// name (the most-read author), and a name is not formatted like a count.
  final String figure;

  /// Small print under the figure. Omitted when there is nothing true to say.
  final String? sub;

  final StatTileVariant variant;

  /// Set when [figure] is prose rather than a number, which needs smaller type and
  /// room to wrap. An author's name at figure size overflows a half-width tile on
  /// the first Korean name longer than three syllables.
  final bool figureIsText;

  /// Drawn below the small print, full width. The hero's cover row.
  ///
  /// A slot rather than a `CardCoverRow` parameter, because a stat tile has no
  /// business knowing what books are: it knows a label, a figure and a bit of small
  /// print, and this keeps that true while letting the hero become the card's face.
  final Widget? footer;

  const StatTile({
    super.key,
    required this.label,
    required this.figure,
    this.sub,
    this.variant = StatTileVariant.tile,
    this.figureIsText = false,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isHero = variant == StatTileVariant.hero;

    final fill = isHero ? statTileHeroFill(colors) : statTileFill(colors);

    final onFill = isHero ? Colors.white : colors.primaryText;
    final onFillMuted = isHero
        ? statTileHeroMutedText()
        : statTileMutedText(colors);

    // A name is words, not a number, so it takes a text token rather than a
    // figure one — which also gets it out of the way of the tabular figures the
    // figure tokens carry, since a name has no columns to line up.
    final TextStyle figureStyle = figureIsText
        ? (isHero ? AppTextStyles.figure : AppTextStyles.subtitle)
        : (isHero ? AppTextStyles.display : AppTextStyles.figure);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fill,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          isHero ? 16 : 14,
          16,
          isHero ? 18 : 14,
        ),
        child: Column(
          // Load-bearing, and the exact trap `GeneratedCover` fell into: a
          // Column's default `center` hands loose cross-axis constraints, so
          // every child would shrink-wrap and the tile would be as wide as its
          // longest word instead of as wide as its slot.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // Was 10.5/w700/0.9 spelled out here. [AppTextStyles.caption] is
              // 11/w700/0.9 — the half-point was not a decision anybody made, it
              // was the one size in the app that had no sibling.
              style: AppTextStyles.caption.copyWith(color: onFillMuted),
            ),
            SizedBox(height: isHero ? 8 : 6),
            Text(
              figure,
              maxLines: figureIsText ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              // The tracking and line-height that used to be computed here
              // (`letterSpacing: -0.02 * figureSize`) are the token's now. That
              // hand-tuning existed because every `Text` in the app inherited
              // Roboto's `letterSpacing: 0.25` from an unset `textTheme`, so
              // display sizes came out loose and had to be pulled back one call
              // site at a time. See [AppTextStyles].
              style: figureStyle.copyWith(color: onFill),
            ),
            if (sub != null) ...[
              SizedBox(height: isHero ? 7 : 5),
              Text(
                sub!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.label.copyWith(color: onFillMuted),
              ),
            ],
            if (footer != null) ...[const SizedBox(height: 12), footer!],
          ],
        ),
      ),
    );
  }
}
