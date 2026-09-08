import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';

/// How the card is lit.
///
/// **One toggle, and exactly one.** Flighty's passport has one; two would be a settings
/// panel on an object whose whole appeal is that it looks like a single printed thing.
enum CardLighting {
  /// Read by daylight: cream stock, dark ink. What every card looked like before
  /// Task 5, and still the default everywhere except the reader's own choice on the
  /// `View and share` screen.
  daylight,

  /// Read by a candle.
  ///
  /// **A flame, not a blacklight, and the difference is the whole feature.** Flighty
  /// uses UV, which is right for a passport: a passport really does hide fluorescent
  /// print, and a blacklight floods evenly and makes that ink *emit*. A library card
  /// hides nothing under UV. What it does hide is what has been pressed into the stock
  /// — the gilt ruling, the embossed seal, the date stamped on each cover — and a
  /// candle is a point source above the page, so it falls off and picks those out at a
  /// raking angle. Warm light **deepens** what is already there rather than making it
  /// glow, which is why the covers keep their colour.
  candlelight,
}

/// The flame's own colour: the warm ink everything lit is printed in.
const Color kCandleFlame = Color(0xFFF2A93F);

/// What the flame lights up — the paper's highlight, and the type's colour under it.
const Color kCandleGlow = Color(0xFFFFE8C4);

/// The stock under a candle, top and bottom.
///
/// **This gradient is where the falloff lives, and that placement is the answer to the
/// plan's hardest constraint.** Physically the bottom of a card held under a candle is
/// the darkest part of it — and the strip lives at the bottom, and the strip is the one
/// element on the artifact that earns the share. Painting the falloff as an overlay
/// *over* the card would darken the return path along with everything else. Putting it
/// in the stock puts it **behind** the type instead: the card still falls off toward the
/// bottom, and nothing printed on it is dimmed by doing so. See [kCandleBloomColors] for
/// what the overlay is left carrying.
const Color kCandleStockTop = Color(0xFF26190A);
const Color kCandleStockBottom = Color(0xFF130D05);

/// The well under a candle. Darker than the stock, as it is lighter in daylight.
const Color kCandleWellTop = Color(0xFF35230E);
const Color kCandleWellBottom = Color(0xFF1B1106);

/// The multiply applied to each cover: the colour of the light itself.
///
/// **Multiplied, not overlaid, and that is the physics rather than a trick.** A warm
/// point source scales what a surface already reflects, so `cover × light` is literally
/// what happens — it darkens and warms while keeping the cover's own hue, which is the
/// stated requirement that covers keep their colour instead of washing out. A blacklight
/// would flatten them to grey-green, and a translucent brown laid on top would do the
/// same thing more crudely.
const Color kCandleCoverLight = Color(0xFFD9A96B);

/// How many covers the flame will stamp a month on.
///
/// Six, and past it the reveal degrades to a warm mark instead. At twelve covers a
/// cover is 18pt wide in the export and a legible date will not fit in one — so a stamp
/// per cover would be a row of smudges. Texture is the honest outcome at that count, and
/// it is still a reveal: something appears that was not there in daylight.
const int kCardStampMax = 6;

/// Everything on the artifact whose colour depends on the light.
///
/// **A value type read once per build rather than a set of `if (lit)` branches at forty
/// call sites.** The card had one palette hard-coded into the widgets that drew it; a
/// second lighting state would have doubled every colour expression in the file, and the
/// failure mode of that is one element left in daylight in an image that has already
/// left the phone.
///
/// The two theme-dependent colours are methods rather than fields, because the artifact
/// still reads `brandFill` from the theme in daylight — documented as identical in light
/// and dark, so it cannot vary the artifact — and there is nowhere to get it from here.
@immutable
class CardPalette {
  final CardLighting lighting;

  /// The card's own ground, top and bottom. Flat in daylight, graded under a candle.
  final List<Color> stock;

  /// The card's outer hairline.
  final Color stockLine;

  /// Figures, values, the holder's name.
  final Color ink;

  /// Labels: `Holder`, `Days reading`, the bilingual stamp line.
  final Color labelInk;

  /// The machine-readable strip. Deliberately stronger than [labelInk].
  final Color stripInk;

  /// The well's ground, top and bottom.
  final List<Color> well;

  /// The gilt hatching: the heavier pass and the lighter one.
  ///
  /// **Nearly invisible in daylight, and that is not a bug.** Gilt is foil, not ink, and
  /// foil is what catches a raking light — so 7% ink on cream is what it should look like
  /// with the lights on, and being picked out by the flame is the point. Task 2
  /// deliberately did not draw this at all for exactly that reason.
  final Color giltStrong;
  final Color giltFaint;

  /// The shelf the covers stand on.
  ///
  /// **Warm and light, because it is furniture in the same room as everything else.** It
  /// used to be a wash of [kCardInk] over the well, which made it the one cold, grey
  /// element on a card that is otherwise cream and flame — and it read as a shadow under
  /// the books rather than as a plank they were standing on. Under a candle the board is
  /// [kCandleFlame], so the daylight version being neutral grey made the two look like
  /// different objects lit differently rather than one object under two lights.
  final Color shelf;

  /// The shadow the board casts on the back of the well, or null for no cast shadow.
  ///
  /// **What makes the books look like they are standing on the board rather than beside
  /// it**, and it is the library's own recipe: `ShelfWidget` puts `offset (0, 2)`,
  /// `blurRadius: 2` and a quarter-strength ink under its plank. The card had none, so
  /// its board was a bar behind a row of covers.
  ///
  /// [kCardInk] rather than black at that same quarter: `Colors.black.withOpacity(0.25)`
  /// means "the darkest ink at a quarter", and on cream stock pure black would be the one
  /// cold thing on the card — the exact mistake [shelf] itself used to make.
  ///
  /// Null under a candle, where the flame's halo on the board *is* the modelling and a
  /// second, contrary light source would be one too many. The mirror of [coverLight]
  /// being null in daylight.
  final Color? boardShadow;

  /// The tear line between the well and the record.
  final Color perforationInk;

  /// The rule above the stat row, and the one above the strip.
  final Color statRule;
  final Color stripRule;

  /// The embossed seal: its ink, its ring, and how much of it is visible at all.
  final Color sealInk;
  final Color sealRing;
  final double sealOpacity;

  /// Multiplied into every cover. Null in daylight, where there is no light to model.
  final Color? coverLight;

  /// The rim a warm light leaves on a cover's fore-edge. Null in daylight, where the
  /// covers cast an ordinary drop shadow instead.
  final Color? coverBloom;

  /// How dark a cover's binding band is. Deeper under a candle, because a raking light
  /// makes the gutter a shadow rather than a tint.
  final double bindingAlpha;

  /// The soft halo under lit type. Empty in daylight.
  final List<Shadow> bloom;

  const CardPalette({
    required this.lighting,
    required this.stock,
    required this.stockLine,
    required this.ink,
    required this.labelInk,
    required this.stripInk,
    required this.well,
    required this.giltStrong,
    required this.giltFaint,
    required this.shelf,
    required this.boardShadow,
    required this.perforationInk,
    required this.statRule,
    required this.stripRule,
    required this.sealInk,
    required this.sealRing,
    required this.sealOpacity,
    required this.coverLight,
    required this.coverBloom,
    required this.bindingAlpha,
    required this.bloom,
  });

  bool get isLit => lighting == CardLighting.candlelight;

  /// The card's title. `brandFill` with the lights on, the glow under a candle.
  Color titleInk(Color brandFill) => isLit ? kCandleGlow : brandFill;

  /// The unit beside the hero figure, and anything else the brand colour carries.
  /// The flame rather than the glow, so the figure's own line stays the brightest thing
  /// on the card.
  Color accentInk(Color brandFill) => isLit ? kCandleFlame : brandFill;

  /// Whether a row of [count] covers gets a date stamped on each one.
  bool stampsMonths(int count) => isLit && count <= kCardStampMax;

  /// Whether a row of [count] covers degrades to the warm mark instead.
  bool marksCovers(int count) => isLit && count > kCardStampMax;
}

/// The bloom the flame casts over the whole card, as gradient stops.
///
/// **No black stop, and that is deliberate — see [kCandleStockTop].** The drawings'
/// overlay ends at `rgba(0,0,0,.13)`, which darkens the bottom of the card and therefore
/// the strip printed on it. The falloff belongs in the stock, behind the type; what is
/// left for an overlay is only the highlight, so nothing on this card is made *less*
/// legible by the light. Where physics and the return path disagree, the return path
/// wins.
const List<Color> kCandleBloomColors = [
  Color(0x4DFFC76A),
  Color(0x14FF9A2E),
  Color(0x00FF9A2E),
];

/// Where those stops fall. The last one is transparent well before the card's edge, so
/// the bloom reads as a source above the page rather than as a wash over it.
const List<double> kCandleBloomStops = [0.0, 0.46, 0.85];

/// The bloom's centre: above the card's top edge, which is where a candle would be.
const Alignment kCandleBloomCenter = Alignment(0, -1.24);

/// How far the bloom reaches, as a fraction of the card's shorter side.
const double kCandleBloomRadius = 1.2;

/// The chrome's type under a candle.
///
/// A warmer white than `primaryText`, because the whole screen is one scene when the
/// card is lit: chrome in the app's cool grey over a card in a dim room reads as two
/// images stacked.
const Color kShareChromeLitInk = Color(0xFFFFF3DD);

/// The `View and share` screen's own ground under a candle.
const Color kShareChromeLitTop = Color(0xFF1D1509);
const Color kShareChromeLitBottom = Color(0xFF070402);

/// The ground the artifact stands on, as the two stops of its gradient.
///
/// **Theme tokens in daylight, pinned values under a candle**, and the split is the point.
/// The drawing's `#f7f8f6` → `#e5eae5` *is* `pageBackground` → `surfaceVariant` in the
/// light theme to within a point, so taking the tokens costs nothing and gives the screen
/// a dark mode. Once the card is lit the theme stops applying at all: the screen and the
/// card are one scene, and cool grey chrome around a card in a dim room reads as two
/// images stacked.
///
/// This is the opposite decision from the artifact's stock, for a reason worth stating:
/// the chrome is read by the person holding the phone, the artifact by whoever they send
/// it to. Only the second one has to look the same for everybody.
///
/// Graded rather than flat so the card reads as an object lying on something — the same
/// move the cover well makes inside the card.
List<Color> shareChromeGround(
  AppColors colors, {
  CardLighting lighting = CardLighting.daylight,
}) => lighting == CardLighting.candlelight
    ? const [kShareChromeLitTop, kShareChromeLitBottom]
    : [colors.pageBackground, colors.surfaceVariant];

/// The chrome's primary type.
Color shareChromeInk(
  AppColors colors, {
  CardLighting lighting = CardLighting.daylight,
}) => lighting == CardLighting.candlelight
    ? kShareChromeLitInk
    : colors.primaryText;

/// Ink for the chrome's secondary type: the `View and share` line, the destination
/// labels.
///
/// **70% of the primary, and explicitly not `secondaryText`.** `#ADB5BD` on this ground
/// measures about **2.0:1**, which is the exact failure the stat tiles shipped with and
/// `library_card_contrast_test.dart` was written for. 70% clears AA on both themes, under
/// both lighting states, and against both stops of [shareChromeGround].
///
/// A function rather than a `const` because `withValues` is not a constant expression —
/// the same shape [cardLabelInk] and `stat_tile.dart` use.
Color shareChromeMutedInk(
  AppColors colors, {
  CardLighting lighting = CardLighting.daylight,
}) => shareChromeInk(colors, lighting: lighting).withValues(alpha: 0.7);

CardPalette _daylight = CardPalette(
  lighting: CardLighting.daylight,
  stock: const [kCardStock, kCardStock],
  stockLine: kCardStockLine,
  ink: kCardInk,
  labelInk: cardLabelInk(),
  stripInk: cardStripInk(),
  well: const [kCardWellTop, kCardWellBottom],
  giltStrong: kCardInk.withValues(alpha: 0.07),
  giltFaint: kCardInk.withValues(alpha: 0.045),
  // The card's own hairline tone, opaque. Brighter than the ink wash it replaces — the
  // composite goes from roughly #C7C6BB to #DDD3BD — and it introduces no new colour: this
  // is the value the card already rules its stat row and its strip with.
  shelf: kCardStockLine,
  boardShadow: kCardInk.withValues(alpha: 0.25),
  perforationInk: kCardInk.withValues(alpha: 0.32),
  statRule: kCardInk.withValues(alpha: 0.18),
  stripRule: kCardInk.withValues(alpha: 0.25),
  sealInk: kCardInk.withValues(alpha: 0.55),
  sealRing: kCardInk.withValues(alpha: 0.55),
  // What an unlit emboss looks like: a shape in the stock, not a mark on it.
  sealOpacity: 0.1,
  coverLight: null,
  coverBloom: null,
  bindingAlpha: 0.18,
  bloom: const [],
);

CardPalette _candlelight = CardPalette(
  lighting: CardLighting.candlelight,
  stock: const [kCandleStockTop, kCandleStockBottom],
  stockLine: kCandleFlame.withValues(alpha: 0.4),
  ink: kCandleGlow,
  labelInk: kCandleGlow.withValues(alpha: 0.72),
  // Full strength, where daylight's is 78%. The strip is the return path and the card's
  // bottom is its darkest region; this is the one element the light is not allowed to
  // cost anything.
  stripInk: kCandleGlow,
  well: const [kCandleWellTop, kCandleWellBottom],
  giltStrong: kCandleFlame.withValues(alpha: 0.32),
  giltFaint: kCandleFlame.withValues(alpha: 0.2),
  shelf: kCandleFlame.withValues(alpha: 0.45),
  boardShadow: null,
  perforationInk: kCandleFlame.withValues(alpha: 0.45),
  statRule: kCandleFlame.withValues(alpha: 0.3),
  stripRule: kCandleFlame.withValues(alpha: 0.4),
  sealInk: kCandleGlow,
  sealRing: kCandleFlame,
  sealOpacity: 1,
  coverLight: kCandleCoverLight,
  coverBloom: kCandleFlame.withValues(alpha: 0.42),
  bindingAlpha: 0.42,
  bloom: const [Shadow(color: kCandleFlame, blurRadius: 2 * (360 / 106))],
);

/// The palette for a lighting state.
///
/// Built once and shared rather than per call: the two are immutable, and the card reads
/// its palette in every one of its eight sub-widgets.
CardPalette cardPalette(CardLighting lighting) =>
    lighting == CardLighting.candlelight ? _candlelight : _daylight;
