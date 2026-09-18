import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

const String _appleWhiteIcon = 'assets/icons/appleWhiteIcon.svg';
const String _appleBlackIcon = 'assets/icons/appleBlackIcon.svg';
const String _googleIcon = 'assets/icons/googleIcon.svg';
const String _smileBookwormIcon = "assets/icons/smileBookwormIcon.svg";

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

class AppleWhiteIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const AppleWhiteIcon({super.key, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _appleWhiteIcon,
      width: width,
      height: height,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
    );
  }
}

class AppleBlackIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const AppleBlackIcon({super.key, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _appleBlackIcon,
      width: width,
      height: height,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
    );
  }
}

class GoogleIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const GoogleIcon({super.key, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _googleIcon,
      width: width,
      height: height,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
    );
  }
}

class SmileBookwormIcon extends StatelessWidget {
  final double? width;
  final double? height;
  const SmileBookwormIcon({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_smileBookwormIcon, width: width, height: height);
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
