import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:bookworm_friends/ui/widgets/svg_icons.dart';

/// The mark on a book the reader has open, and **the only one in the app.**
///
/// It used to be two. `shelf_row.dart` hung `bookmarkIcon.svg` over a shelved cover — a
/// white notched ribbon with a soft drop shadow — while the Library Card drew a red
/// rectangle of its own, on the argument that a bookmark red "reads as an object" and that
/// brand green would read as decoration. The colour argument was sound and the conclusion
/// was not: **the card exists to look like the shelf the reader already knows**, and two
/// marks for one state is two things to recognise. So the card wears the shelf's ribbon,
/// and this class is where that ribbon lives, once.
///
/// The shape is why the shadow is a blurred copy of the ribbon rather than a `BoxShadow`:
/// the bottom is notched, so a box's shadow would show through the notch. The asset carries
/// an SVG `filter` for exactly this and `flutter_svg` does not render it, which is why
/// `shelf_row.dart` drew the shadow by hand — that code is now here.
class ReadingBookmark extends StatelessWidget {
  /// 1 on a library shelf, where the ribbon is drawn at the asset's own size.
  ///
  /// On the Library Card, the ratio of its cover's height to [kReadingBookmarkBook] — so
  /// the ribbon arrives at the card's scale rather than being given a size of its own.
  /// **The shadow scales with it**, or a 3.4pt ribbon turns up under a 4pt drop shadow.
  final double scale;

  const ReadingBookmark({super.key, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    final icon = BookmarkIcon(
      width: kReadingBookmarkWidth * scale,
      height: kReadingBookmarkHeight * scale,
    );
    return SizedBox(
      width: kReadingBookmarkWidth * scale,
      height: kReadingBookmarkHeight * scale,
      child: Stack(
        children: [
          Transform.translate(
            offset: Offset(0, _kShadowDrop * scale),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: _kShadowBlur * scale,
                sigmaY: _kShadowBlur * scale,
              ),
              child: Opacity(
                opacity: _kShadowAlpha,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.black,
                    BlendMode.srcATop,
                  ),
                  child: icon,
                ),
              ),
            ),
          ),
          icon,
        ],
      ),
    );
  }
}

/// The asset's own box, which is **not the ribbon**.
///
/// `bookmarkIcon.svg` has a 22 x 38 viewBox holding a ribbon that spans x 4 to 17.5 and y 0
/// to 30; the rest is bleed the SVG's own drop-shadow filter needed. So the visible ribbon
/// is 13.5 wide, and anything positioning this has to allow for the 4.5 of empty box down
/// its right-hand side — which is what [kReadingBookmarkInset] already accounts for.
const double kReadingBookmarkWidth = 22;
const double kReadingBookmarkHeight = 38;

/// How far in from the cover's right edge the box hangs, from `shelf_row.dart`'s own
/// `right: 8`. With the box's 4.5 of bleed that puts the ribbon's right edge 12.5 in.
const double kReadingBookmarkInset = 8;

/// The book a shelf draws, and therefore the cover `scale: 1` is sized against.
///
/// **Not a constant it can be read from**, which is the honest part: `shelf_row.dart` takes
/// `screenHeight * 0.15`, so the shelf's book is 124 on an 824pt phone and 128 on an 852pt
/// one, while the ribbon is a fixed 22 x 38 on both. 124 is the book `BookVertical` draws
/// its 26 x 124 spine as and the one `kCardSpineUnits` is already derived from, so the card
/// scales against that rather than inventing a size. What follows is that on a small phone
/// the shelf's ribbon is a hair larger against its cover than the card's is; making the
/// shelf's book height a real constant would remove that, and is the right change the first
/// time anything else needs it.
const double kReadingBookmarkBook = 124;

/// `shelf_row.dart`'s own shadow: dropped 4, blurred 4, at half strength.
const double _kShadowDrop = 4;
const double _kShadowBlur = 4;
const double _kShadowAlpha = 0.5;

/// Decodes the ribbon before something captures it.
///
/// **The same failure as an undecoded cover, in a smaller shape.**
/// `RepaintBoundary.toImage` paints only what is already resolved, and an `SvgPicture` that
/// has not loaded its bytes paints nothing — so without this the exported PNG leaves the
/// phone with the mark missing from exactly the covers whose whole job is to be marked.
/// Invisible on screen, because the preview has had time; invisible to a widget test that
/// asserts geometry; visible only by opening the file.
///
/// Cheap and idempotent after the first call: `svg.cache` keeps the decoded bytes, so
/// `exportLibraryCardFile` awaiting it on every share is a cache hit. A null `BuildContext`
/// is what the loader's own precache recipe passes — an asset needs no `DefaultAssetBundle`.
Future<void> warmReadingBookmark() {
  const loader = SvgAssetLoader(kBookmarkIconAsset);
  return svg.cache.putIfAbsent(
    loader.cacheKey(null),
    () => loader.loadBytes(null),
  );
}
