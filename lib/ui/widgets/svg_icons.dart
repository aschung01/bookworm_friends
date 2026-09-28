import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

const String _appleLogo = 'assets/icons/appleLogo.svg';
const String _googleIcon = 'assets/icons/googleIcon.svg';

/// Public, alone among these, so that [ReadingBookmark] can warm it before an export:
/// an `SvgPicture` that has not loaded its bytes paints nothing, and
/// `RepaintBoundary.toImage` captures only what is already resolved.
const String kBookmarkIconAsset = "assets/icons/bookmarkIcon.svg";

/// Lucide's `stretch-horizontal`, used for Manage Shelves in the library bar.
/// The SVG remains the scalable Flutter fallback and has an explicit stroke so
/// renderers do not need to resolve Lucide's upstream `currentColor`.
const String kStretchHorizontalIconAsset =
    "assets/icons/stretchHorizontalIcon.svg";

/// Raster counterpart used by `CNButton.icon` on native glass. The package's
/// SVGKit path is blank for this control on-device, while its PNG image path
/// preserves the native button's press treatment reliably.
///
/// **It must be transparent outside the glyph.** iOS tints an `imageAsset` by
/// clipping a fill to the image *as a mask* (`ImageUtils.tintImage`), so every
/// opaque pixel is painted in the glyph colour. A first cut of this file was
/// rasterised with `qlmanage`, which bakes Quick Look's opaque backdrop in; the
/// mask was then the whole canvas and the button rendered as a solid white
/// square. Regenerate with a real rasteriser instead:
///
/// ```sh
/// rsvg-convert -w 72 -h 72 -o assets/icons/stretchHorizontalIcon.png <svg>
/// ```
///
/// 72px is the 24pt grid at 3x. The stroke is authored white so the file is
/// also correct if the mask is ever read as luminance rather than alpha; the
/// tint replaces it either way, so this is not the on-screen colour.
const String kStretchHorizontalIconNativeAsset =
    "assets/icons/stretchHorizontalIcon.png";

/// The Apple logo, sized and coloured by the caller.
///
/// **[color] is required, and [height] sizes the glyph itself.** Both replace a
/// pair of widgets, `AppleWhiteIcon` and `AppleBlackIcon`, that wrapped Apple's
/// *logo-only button* artwork -- files carrying an opaque 44x44 plate behind the
/// glyph. Which of the two you picked therefore decided a background as well as an
/// ink, and getting it wrong was invisible in one theme and glaring in the other:
/// the black-plated file vanished on a black button, and the white-plated one drew a
/// pale square on the dark theme's surface. One tintable glyph removes the choice.
///
/// Apple require the logo and the title to be the same colour and both either black
/// or white inside a button. That cannot be enforced by a type, but it is why this
/// takes a colour rather than defaulting to one.
class AppleLogo extends StatelessWidget {
  final double height;
  final Color color;

  const AppleLogo({super.key, required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _appleLogo,
      // Height only. The asset's box is cropped tight to the glyph and the glyph is
      // taller than it is wide, so constraining the width would scale it down.
      height: height,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// Google's mark. **Never tinted** -- unlike [AppleLogo] it is four brand colours,
/// and Google's own guidelines forbid recolouring it. There is deliberately no
/// `color` parameter; one used to exist and applying it flattened the mark to a
/// single-colour blob.
class GoogleIcon extends StatelessWidget {
  final double? width;
  final double? height;
  const GoogleIcon({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_googleIcon, width: width, height: height);
  }
}

class BookmarkIcon extends StatelessWidget {
  final double? width;
  final double? height;
  const BookmarkIcon({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(kBookmarkIconAsset, width: width, height: height);
  }
}
