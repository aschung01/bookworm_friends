import 'dart:typed_data';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

/// Diameter of a lone circular icon button.
///
/// **44, because that is the floor below which a single icon control is hard to
/// hit** — and because a tap target is the one part of this family that has no
/// reason to vary by glyph. Every way out of a focused context is drawn at it: the
/// scanner, the share card, Add Book, Manage Shelves, the invite sheet, the two
/// invite dead-ends, and `AdaptiveBackButton`.
///
/// **The back chevron is the reason this is a token rather than a repeated 44.** It
/// was 36 with an unset `iconSize`, so the app shipped a nav control whose disc was
/// smaller than every ✕ while its glyph was larger than all of them — the ratio
/// inverted, which is what made the two read as unrelated controls rather than as
/// one idea at two sizes. Numbers copied by hand at fifteen call sites drift; this
/// is the fix for the drift, not just for the chevron.
///
/// **The one deliberate exception is `home_page._LibraryBar`**, whose end-visit ✕
/// stays at 36 because it is crowded in beside Poke. Crowding is the only argument
/// that has ever justified going below this floor; absent one, use this.
const double kIconButtonDiameter = 44;

/// Size of the SF Symbol inside a [kIconButtonDiameter] button.
const double kIconButtonSymbolSize = 15;

/// Size of the Material icon inside a [kIconButtonDiameter] button.
const double kIconButtonIconSize = 20;

/// The back chevron's SF Symbol, deliberately larger than [kIconButtonSymbolSize].
///
/// **A thinner mark needs more nominal size to carry the same weight.** `xmark` is
/// two strokes crossing at its centre; `chevron.backward` is one open angle with
/// nothing in the middle, so at 15 it reads visibly lighter than the ✕ it sits
/// opposite elsewhere in the app. The disc is what the two share — see
/// [kIconButtonDiameter] — and the glyph is what they are allowed not to.
const double kBackButtonSymbolSize = 17;

/// The back chevron's Material icon. Larger than [kIconButtonIconSize] for the
/// reason given on [kBackButtonSymbolSize].
///
/// **This value was the constructor's default rather than anyone's choice**:
/// `AdaptiveBackButton` passed `symbolSize` and omitted `iconSize`, so it fell
/// through to `22` while every other call site in the family set all three. It
/// happens to be right for a chevron, so it is kept and made deliberate rather than
/// flattened to 20 for a symmetry the glyphs do not actually have.
const double kBackButtonIconSize = 22;

/// A circular icon button that renders as a native Liquid Glass button on
/// iOS 26+ / macOS 26+, and as a themed Material [IconButton] everywhere else.
class AdaptiveIconButton extends StatelessWidget {
  /// Whether icon buttons currently render as native Liquid Glass.
  static bool get usesNativeGlass => useNativeGlass;

  /// SF Symbol name used for the native glass rendering.
  ///
  /// Null on the [AdaptiveIconButton.svg] path, where the glyph is a bundled
  /// vector on both renderings instead.
  final String? symbol;

  /// Material icon used on every other platform / OS version.
  ///
  /// Null on the [AdaptiveIconButton.svg] path, for the same reason [symbol] is.
  final IconData? icon;

  /// Bundled SVG used as the glyph on *both* renderings, in place of the
  /// [symbol]/[icon] pair. Set only by [AdaptiveIconButton.svg].
  final String? assetPath;

  /// Optional raster counterpart used only by the native `CNButton.icon` path.
  /// Flutter continues to render [assetPath] as SVG.
  final String? nativeAssetPath;

  final VoidCallback? onPressed;

  /// Overall diameter of the button.
  final double diameter;

  /// Size of the SF Symbol inside the native glass button.
  final double symbolSize;

  /// Size of the Material icon in the fallback.
  final double iconSize;

  /// Gives the Material fallback a circular `surfaceVariant` fill. The glass
  /// rendering always supplies its own material, so this only affects fallback.
  final bool filledFallback;

  /// Accessible name for the button. Required in practice for icon-only
  /// controls: neither an SF Symbol nor an [IconData] carries a label, so
  /// without this the button is announced as just "button".
  final String? semanticLabel;

  /// Colour for the glyph, applied to both renderings.
  ///
  /// Null leaves each to its own default — the native button's automatic label
  /// colour on glass, the ambient [IconTheme] on Material — which is what every
  /// caller that does not pass it wants, and why it is optional rather than
  /// required.
  ///
  /// It exists for chrome whose ground is not a theme surface. The `View and
  /// share` screen inverts its background under Candlelight, and a glyph left to
  /// the Material default there is near-black ink on a near-black ground.
  ///
  /// **Carried on the symbol, not through `CNButton.tint`.** `tint` colours the
  /// button's own material, so tinting the glyph with it would stain the glass
  /// disc instead of the mark on it.
  ///
  /// On the [AdaptiveIconButton.svg] path it is *not* optional in effect: a vector
  /// has a colour written into it and neither renderer knows the theme, so null
  /// resolves to the ambient [IconTheme] rather than being left alone.
  final Color? iconColor;

  /// Colours the button's **material** rather than its glyph — the disc itself.
  ///
  /// Only meaningful with [prominent]; see it for why the two travel together.
  final Color? tint;

  /// Makes this the affirmative button: a filled, [tint]-coloured disc rather
  /// than clear glass.
  ///
  /// **Why a second flag and not just a non-null [tint].** The two colour
  /// different things and the platform decides which from the *style*: at
  /// `prominentGlass` a tint becomes the button's background, at `glass` it
  /// becomes its foreground. Passing a colour cannot say which was meant, so the
  /// style is asked for explicitly and [tint] only ever means "the disc".
  ///
  /// The Material fallback mirrors it as an opaque circle in the same colour,
  /// which is why [iconColor] has to be set alongside: a glyph left to the
  /// ambient [IconTheme] is dark ink on a saturated fill.
  final bool prominent;

  const AdaptiveIconButton({
    super.key,
    required this.symbol,
    required this.icon,
    this.onPressed,
    this.diameter = 40,
    this.symbolSize = 18,
    this.iconSize = 22,
    this.filledFallback = false,
    this.semanticLabel,
    this.iconColor,
    this.tint,
    this.prominent = false,
  }) : assetPath = null,
       nativeAssetPath = null;

  /// An [AdaptiveIconButton] whose glyph is a bundled SVG, for the marks the SF
  /// Symbols catalog does not have.
  ///
  /// `flutter_svg` draws [assetPath] on Material. On glass, [nativeAssetPath]
  /// can provide a raster counterpart when the plugin's SVGKit path is unreliable;
  /// otherwise [assetPath] is used directly. Either source occupies the native
  /// `UIButton` image slot, so it receives UIKit's press treatment rather than
  /// sitting inert over the disc.
  ///
  /// [symbolSize] is measured on the vector's own 24pt grid, which draws a little
  /// larger than an SF Symbol of the same number — Apple's are inset in their box
  /// and Lucide's are not.
  const AdaptiveIconButton.svg({
    super.key,
    required String this.assetPath,
    this.nativeAssetPath,
    this.onPressed,
    this.diameter = 40,
    this.symbolSize = 20,
    this.iconSize = 22,
    this.filledFallback = false,
    this.semanticLabel,
    this.iconColor,
    this.tint,
    this.prominent = false,
  }) : symbol = null,
       icon = null;

  @override
  Widget build(BuildContext context) {
    // Glass only while nothing is over it. Anything covering this control breaks
    // the platform view's compositing *and* leaves the native button tappable
    // through the barrier, so it renders as the Material fallback for as long as
    // it is behind one — see [ModalCoverBuilder], which counts a fully-arrived page
    // as well as a modal. The fallback rather than a gap: the sheet it belongs to is
    // still on screen behind the scrim, and a header with a hole in it reads as
    // broken.
    return ModalCoverBuilder(
      builder: (context, covered) =>
          usesNativeGlass && !covered ? _glass(context) : _fallback(context),
    );
  }

  /// The style the native button is built at, and the one that decides what [tint]
  /// colours. See [prominent].
  CNButtonConfig get _config => CNButtonConfig(
    style: prominent ? CNButtonStyle.prominentGlass : CNButtonStyle.glass,
  );

  Widget _glass(BuildContext context) {
    // CNButton.icon already defaults to CNButtonStyle.glass.
    // The native button is a PlatformView, so the label has to be attached
    // from the Flutter side rather than via a tooltip.
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Semantics(
        label: semanticLabel,
        button: true,
        container: true,
        child: assetPath != null
            ? CNButton.icon(
                imageAsset: CNImageAsset(
                  nativeAssetPath ?? assetPath!,
                  size: symbolSize,
                  // Never null here, unlike the symbol path: an image is drawn in
                  // the colour it was authored in unless one is supplied, and the
                  // file ships a flat black.
                  color: _glyphColor(context),
                ),
                tint: tint,
                config: _config,
                onPressed: onPressed,
              )
            : CNButton.icon(
                icon: CNSymbol(symbol!, size: symbolSize, color: iconColor),
                tint: tint,
                config: _config,
                onPressed: onPressed,
              ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      // Doubles as the semantic label on Material.
      tooltip: semanticLabel,
      splashRadius: 20,
      color: iconColor,
      icon: assetPath != null
          ? SvgPicture.asset(
              assetPath!,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(
                _glyphColor(context),
                BlendMode.srcIn,
              ),
            )
          : Icon(icon, size: iconSize),
    );

    final fill = _fallbackFill(context);

    return SizedBox(
      width: diameter,
      height: diameter,
      child: fill != null
          ? Material(type: MaterialType.circle, color: fill, child: button)
          : button,
    );
  }

  /// The colour a *vector* glyph is recoloured to, which unlike a symbol's cannot
  /// be left unset. See [iconColor].
  Color _glyphColor(BuildContext context) =>
      iconColor ?? IconTheme.of(context).color ?? context.colors.primaryText;

  /// The Material fallback's disc, or null for a bare glyph.
  ///
  /// [prominent] wins over [filledFallback]: it is the affirmative button, and a
  /// neutral `surfaceVariant` under it would read as the secondary one.
  Color? _fallbackFill(BuildContext context) {
    if (prominent) return tint ?? context.colors.brandFill;
    return filledFallback ? context.colors.surfaceVariant : null;
  }
}

/// A circular Liquid Glass **material** with arbitrary Flutter content drawn on it.
///
/// [AdaptiveIconButton]'s sibling for the case its [AdaptiveIconButton.symbol]
/// cannot serve: content that is not an SF Symbol. The reader's avatar is the
/// motivating one — an emoji or a photograph, neither of which can be handed to a
/// native button as a symbol name.
///
/// **Built the way `read_filter._Capsule` builds its selected pill, and for the same
/// reason.** An empty, inert-looking `CNButton` is stretched behind Flutter's own
/// content, so the material and its press response are the platform's while
/// everything visible stays ours. The obvious alternative — `LiquidGlassContainer` —
/// is the thing that does *not* work, and that note records why: it renders a bare
/// `glassEffect(.regular)` layer with no material of its own, which over an opaque
/// surface comes out flat, with no rim and no shadow.
///
/// [builder] is told which path it is on, because content that looks right on glass
/// usually does not look right on the fallback: an avatar has to drop its own fill to
/// let the material through, and has to put it back when there is no material.
///
/// **The press response is UIKit's, and the content has to be inside the button to
/// get it.** [AdaptiveIconButton] hands its glyph over as an SF Symbol, so the symbol
/// becomes the `UIButton`'s own image and `adjustsImageWhenHighlighted` transforms it
/// along with the glass. Content *layered over* the platform view gets none of that,
/// and three attempts to mirror the press from Dart each shipped a worse defect.
/// Recorded so none is tried again:
///
///  1. *Scale the content up on press.* The magnitude cannot be read from Dart:
///     `setPressed` is one-way and only sets `isHighlighted`
///     (`CupertinoButtonPlatformView.swift:370`). The 1.08 used here was invented.
///  2. *The overflow is clipped square.* Content filling the disc and scaling past 1
///     leaves the platform view's rect — measured, 44pt at 1.08 overhangs 1.76pt a
///     side — and Flutter content over a `UiKitView` is lifted into a *rectangular*
///     overlay quad, so the overhang returned as square corners on a round avatar.
///  3. *Clip it to a circle.* The clip is a fixed 44pt and the native disc shrinks on
///     press, so a ring of bare glass opened between them: the button appeared to
///     *gain* padding under the finger.
///
/// [imageBytes] is the actual fix. Given PNG bytes, this hands them to `CNButton` as
/// a [CNImageAsset] and the image becomes the button's own `UIImage` — the same slot
/// an SF Symbol lands in, with the same native press treatment and nothing guessed.
/// `AvatarRaster` produces them; see `avatar_raster.dart` for why a rasterised widget
/// rather than the stored photo.
///
/// [builder] remains the fallback and is *not* optional: bytes arrive a frame or two
/// late, may fail, and never exist off the glass path. It is told which path it is on,
/// because content that looks right on glass usually does not on Material — an avatar
/// drops its own fill to let the disc through and puts it back when there is none.
///
/// **Never set a glass-effect id on this button.** `glassEffectUnionId` or
/// `glassEffectId` flips the plugin to its SwiftUI renderer
/// (`CupertinoButtonPlatformView.swift:203`), and that path applies
/// `.renderingMode(.template)` to every image unconditionally
/// (`GlassButtonSwiftUI.swift:41`) — which would flatten a photograph to a
/// single-colour silhouette. The UIKit path this uses does not template
/// [CNImageAsset.imageData], which is the whole reason the colour survives.
class AdaptiveGlassCircle extends StatelessWidget {
  /// Drawn when [imageBytes] is null, and on the Material fallback always.
  ///
  /// Passed true when a glass disc is being drawn behind it.
  final Widget Function(BuildContext context, bool glass) builder;

  /// The content as PNG bytes, put *inside* the native button so UIKit animates it.
  ///
  /// Null falls back to [builder] layered over the glass — correct, just without the
  /// press response. That is the state during the raster's first frames and after a
  /// failed one, so it is a normal path rather than an error.
  final Uint8List? imageBytes;

  /// The disc, and the tap target. [builder]'s content is centred in it.
  final double diameter;

  final VoidCallback? onPressed;

  /// Required in practice, as on [AdaptiveIconButton]: the glass path is a platform
  /// view with nothing an accessibility client can read out of it.
  final String? semanticLabel;

  const AdaptiveGlassCircle({
    super.key,
    required this.builder,
    this.imageBytes,
    this.diameter = 44,
    this.onPressed,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Same gate, and the same reasoning, as [AdaptiveIconButton] — see the comment
    // there. A platform view that stays native under a sheet leaks its own rectangle
    // through the scrim and keeps answering taps behind it.
    return ModalCoverBuilder(
      builder: (context, covered) =>
          useNativeGlass && !covered ? _glass(context) : _fallback(context),
    );
  }

  Widget _glass(BuildContext context) {
    final bytes = imageBytes;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Semantics(
        label: semanticLabel,
        button: true,
        container: true,
        child: bytes != null ? _nativeContent(bytes) : _layeredContent(context),
      ),
    );
  }

  /// The content **inside** the button, which is what earns the native press.
  ///
  /// The empty `assetPath` is deliberate and is the documented way in: [CNImageAsset]
  /// states that `imageData` "takes precedence over assetPath", and the Swift reads
  /// the path only `if !path.isEmpty` before falling to the bytes branch
  /// (`CupertinoButtonPlatformView.swift:117`). That branch is also the one that does
  /// *not* apply `.alwaysTemplate` — `customIconBytes` at line 164 does, and would
  /// flatten a photograph — so this is the only route that keeps an avatar's colour.
  Widget _nativeContent(Uint8List bytes) => CNButton.icon(
    imageAsset: CNImageAsset(
      '',
      imageData: bytes,
      imageFormat: 'png',
      size: diameter,
    ),
    onPressed: onPressed,
    config: CNButtonConfig(
      style: CNButtonStyle.glass,
      // A capsule as wide as it is tall is a circle, which is why no `borderRadius`
      // is set: null means capsule, and the square box below does the rest.
      minHeight: diameter,
      width: diameter,
      padding: EdgeInsets.zero,
    ),
  );

  /// The content **over** the button, for when there are no bytes yet.
  ///
  /// Correct but inert: the glass answers the press and the mark does not. See this
  /// class's note for why no attempt is made to animate it here.
  Widget _layeredContent(BuildContext context) => Stack(
    // The glass shadow sits outside the disc's box.
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(
        child: CNButton(
          // No content: what is visible is Flutter's, below. This is here for the
          // material and the press response only.
          label: '',
          onPressed: onPressed,
          config: CNButtonConfig(
            style: CNButtonStyle.glass,
            minHeight: diameter,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
      // Takes no pointers: every touch goes to the native button, so the tap is
      // entirely UIKit's.
      Positioned.fill(
        child: IgnorePointer(child: Center(child: builder(context, true))),
      ),
    ],
  );

  Widget _fallback(BuildContext context) => SizedBox(
    width: diameter,
    height: diameter,
    child: IconButton(
      onPressed: onPressed,
      // Doubles as the semantic label on Material, as on [AdaptiveIconButton].
      tooltip: semanticLabel,
      splashRadius: diameter / 2,
      // Zero, because the default 8pt inset squeezes content sized against the
      // diameter into a box smaller than the one it was measured for.
      padding: EdgeInsets.zero,
      icon: builder(context, false),
    ),
  );
}

/// Gap to place between two adjacent [AdaptiveIconButton]s.
///
/// A glass button fills its whole diameter, so neighbours would otherwise touch
/// edge to edge. The Material fallback is an [IconButton], which already insets
/// its icon, so it needs no extra gap and gets none.
///
/// Reads the *platform* gate, not [ModalCoverBuilder]: a button that degrades to
/// Material under a sheet must not also move, or the header reflows behind the
/// scrim.
class AdaptiveIconButtonGap extends StatelessWidget {
  const AdaptiveIconButtonGap({super.key, this.width = 8});

  /// Gap applied when the buttons render as native glass.
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: AdaptiveIconButton.usesNativeGlass ? width : 0);
  }
}
