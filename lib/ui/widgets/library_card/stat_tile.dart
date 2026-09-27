import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';

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

/// The ground a [StatTileVariant.cool] tile is filled with: the streak tile on a day
/// the reader has not read yet.
///
/// **A fixed slate rather than [AppColors.secondaryText], and that is a correction
/// rather than a preference.** The candidate this shipped from used `secondaryText`,
/// which is `#626A72` in light mode and `#949599` in dark — so the cold tile was a dark
/// slate block on a white card and a *pale* block on a dark one. Measured, the dark-mode
/// version sat at 0.301 relative luminance against the hero green's 0.137, i.e. 3.04:1
/// against the ground where the hero is 2.97:1, which made "you have not read yet" the
/// loudest object on the card. White on it also fell from 5.49:1 to 2.99:1.
///
/// This is the trap `read_week_row.dart` records for its `stampMark`: a token chosen for
/// its role as *text* carries no promise about its lightness, so using one as a fill is a
/// coin flip per theme. [AppColors.brandFill] is the shape of the fix — a fill authored to
/// carry white text, and `#067657` in **both** themes for exactly this reason.
///
/// The value is the light theme's `secondaryText`, frozen. That is not a coincidence
/// worth hiding: it makes this a neutral twin of the hero's own fill, and the numbers say
/// so almost exactly — white 5.49:1 against the hero's 5.62:1, `statTileHeroMutedText`
/// 4.68:1 against 4.75:1, and 5.49:1/3.04:1 against the light and dark grounds where the
/// hero is 5.62:1/2.97:1. So a cold streak tile is as prominent as the card's own hero
/// and carries white text to the same standard, in both themes.
const Color kStatTileCool = Color(0xFF626A72);

/// The two stops a [StatTileVariant.cool] tile grades between.
List<Color> statTileCoolFill() => [
  kStatTileCool,
  Color.lerp(kStatTileCool, Colors.black, 0.22)!,
];

/// The two stops a [StatTileVariant.warm] tile grades between: the streak tile once
/// today is recorded.
///
/// [kCandleFlame], the streak's own amber, graded darker by the same 0.22 every filled
/// tile on this card uses.
///
/// **This fill is below AA for white text and was chosen anyway, on instruction.** White
/// measures **2.00:1** on the near stop and 3.23:1 on the far one; at
/// [statTileHeroMutedText]'s 88% that is 1.84:1 and 2.85:1. A readable version was built
/// and shown beside it — the same tile on `AppColors.flame` #B54708, where white is
/// 5.43:1 rising to 7.83:1, within a hair of the hero's own 5.62:1 — and the amber was
/// preferred. Recorded so nobody re-derives the analysis and concludes it was never
/// tried. It is the same trade `streak_celebration.dart` and `read_week_row.dart` already
/// carry, and it is the first thing to revisit if anyone asks why this tile is hard to
/// read.
List<Color> statTileWarmFill() => [
  kCandleFlame,
  Color.lerp(kCandleFlame, Colors.black, 0.22)!,
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

  /// The streak tile once today is recorded: the streak's amber, white text.
  ///
  /// **The one exception to [tile]'s "not three heroes competing" rule**, and it earns it
  /// by being a *state* rather than a stat. Pace and most-read author are true all week;
  /// this one changes tonight, and the card has no other way to say so. It is also the
  /// only tile a reader can open — see [StatTile.onTap].
  warm,

  /// The streak tile before today is recorded: the same filled shape, cooled.
  ///
  /// **Filled rather than plain, which is the whole choice here.** The alternative
  /// considered was [tile] — the streak tile becoming indistinguishable from Pace until
  /// the day is recorded, which is `ReadingStreakChip`'s rule, where cold means nothing
  /// painted at all. It was not taken: the chip lives in a bar the reader passes
  /// constantly and a loud object there is a nuisance, whereas the card is a place they
  /// go on purpose to look at figures, and a tile that changes *shape* between visits is
  /// harder to read than one that changes temperature. So the shape is constant and only
  /// the ground moves.
  cool,
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

  /// Drawn immediately before [figure], vertically centred against it.
  ///
  /// A slot rather than a flag, for the same reason [footer] is one: the streak's flame
  /// is the only thing that has ever wanted this, and a stat tile has no business
  /// importing it. The caller also picks the mark's colours, because on a filled tile
  /// they depend on which fill — see `library_card_body.dart`.
  final Widget? mark;

  /// Drawn below the small print, full width. The hero's cover row.
  ///
  /// A slot rather than a `CardCoverRow` parameter, because a stat tile has no
  /// business knowing what books are: it knows a label, a figure and a bit of small
  /// print, and this keeps that true while letting the hero become the card's face.
  final Widget? footer;

  /// Makes the whole tile a button.
  ///
  /// **Null for every tile but the streak's**, and that asymmetry is the point: a
  /// stat is normally the end of the line — the card is where `books read` and
  /// `pace` are *shown*, and there is nowhere further to go with either. The streak
  /// is the one figure on this card that has a screen of its own, so it is the one
  /// tile where a tap has somewhere to land.
  ///
  /// The tile does not draw a chevron or any other affordance for this. That is a
  /// live design question rather than an oversight — see the candidates under
  /// `docs/mockups/streak-tile/`.
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.figure,
    this.sub,
    this.variant = StatTileVariant.tile,
    this.figureIsText = false,
    this.mark,
    this.footer,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isHero = variant == StatTileVariant.hero;

    // Three of the four variants are filled with a colour of their own and take white
    // text; only [StatTileVariant.tile] sits on the card's grey and takes body ink. The
    // *type* still keys on `isHero` alone — a warm or cool tile is a peer of Pace and
    // gets Pace's sizes, not the hero's.
    final isFilled = variant != StatTileVariant.tile;

    final fill = switch (variant) {
      StatTileVariant.hero => statTileHeroFill(colors),
      StatTileVariant.warm => statTileWarmFill(),
      StatTileVariant.cool => statTileCoolFill(),
      StatTileVariant.tile => statTileFill(colors),
    };

    final onFill = isFilled ? Colors.white : colors.primaryText;
    final onFillMuted = isFilled
        ? statTileHeroMutedText()
        : statTileMutedText(colors);

    // A name is words, not a number, so it takes a text token rather than a
    // figure one — which also gets it out of the way of the tabular figures the
    // figure tokens carry, since a name has no columns to line up.
    final TextStyle figureStyle = figureIsText
        ? (isHero ? AppTextStyles.figure : AppTextStyles.subtitle)
        : (isHero ? AppTextStyles.display : AppTextStyles.figure);

    final tile = DecoratedBox(
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
            // A `Row` only when there is a mark, so every tile without one keeps the
            // exact layout it had: a bare `Text` in a stretch `Column` fills the width,
            // where a `Row` would shrink-wrap its children and hand the text loose
            // constraints. `Flexible` inside it is what keeps `overflow.ellipsis`
            // meaningful — a `Text` in an unbounded `Row` cannot ellipsize, it overflows.
            if (mark == null)
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
              )
            else
              Row(
                children: [
                  mark!,
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      figure,
                      maxLines: figureIsText ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: figureStyle.copyWith(color: onFill),
                    ),
                  ),
                ],
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

    if (onTap == null) return tile;

    // **`opaque`, so the whole gradient takes the tap and not just the glyphs on
    // it.** A stat tile is mostly empty fill by design — the figure is one line in a
    // box 140pt wide — so hit-testing only where something is painted would leave a
    // button that mostly ignores being pressed.
    //
    // No `InkWell`: there is no Material ancestor guaranteed here (the card lives in
    // a sheet the app draws itself), and a ripple on a gradient tile is not a gesture
    // this app makes anywhere else.
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: tile,
      ),
    );
  }
}
