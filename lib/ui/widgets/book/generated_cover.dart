import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

/// The publisher's-mark slot at the bottom of the title half.
///
/// Deliberately **not** the bookworm. That asset is a two-tone illustration — a
/// green open book under a white domed head with antennae and eyes — authored for
/// the 120px it is drawn at on the auth page. At the ~21px this slot gives it, the
/// dome and two eyes are all that survive and it reads as the Android robot, with
/// the book beneath it illegible. Tinting made it worse rather than better: a
/// `srcIn` filter replaced the white dome and the eyes with one colour and left a
/// featureless blob.
///
/// So this is the same geometry reduced to what a glyph can carry — the logo's two
/// pages, outlined rather than filled, monochrome so it can take the title's
/// colour. Which is what the reference does: Geist can tint its mark because its
/// mark is a triangle.
const String _glyph = 'assets/icons/openBookGlyph.svg';

/// Swatches for generated covers.
///
/// Harmonised with the brand green rather than sampled at random, so a shelf of
/// coverless books still looks like it belongs to this app. The colour block
/// carries no text, so there is no contrast requirement on these — the title
/// lives on the `surface`-toned half below.
const List<Color> kGeneratedCoverPalette = [
  Color(0xFF09BC8A), // brand green
  Color(0xFF0E7C7B), // deep teal
  Color(0xFF2F6690), // slate blue
  Color(0xFFE0644E), // coral
  Color(0xFFF2B544), // amber
  Color(0xFF7C5CBF), // violet
];

/// Below this rendered width the glyph is dropped and the title takes the space
/// instead.
///
/// The widest book anywhere in the app is the details page at roughly 120px, so
/// this threshold means the glyph appears there and nowhere else. Any value above
/// ~120 would be dead code.
///
/// It is kept even though the glyph stays legible smaller than this: on a shelf or
/// in the read grid a cover is a thumbnail you are scanning to *identify* a book,
/// and there the mark would cost the third line of the title. A colophon is worth
/// less than the title it would push out.
const double kCoverGlyphMinWidth = 110.0;

/// Picks a stable palette entry for a book.
Color generatedCoverColor(String isbn) {
  if (isbn.isEmpty) return kGeneratedCoverPalette.first;
  return kGeneratedCoverPalette[bookHash(isbn) % kGeneratedCoverPalette.length];
}

/// Stand-in cover for books with no usable thumbnail.
///
/// Follows the reference's `stripe` variant: a colour block on top, title below
/// on a light ground, with a small mark in the corner. Replaces what used to be a
/// gray box reading "no image", so a missing cover reads as a design choice rather
/// than a failure.
class GeneratedCover extends StatelessWidget {
  final String isbn;
  final String title;

  /// Rendered width of the cover, used to size type and decide whether the
  /// mascot fits.
  final double width;

  const GeneratedCover({
    super.key,
    required this.isbn,
    required this.title,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showGlyph = width >= kCoverGlyphMinWidth;
    // Larger type on smaller books: they have no glyph to share the space with,
    // and a title set at the large book's ratio would be unreadable.
    final titleSize = width * (showGlyph ? 0.115 : 0.135);

    return ColoredBox(
      // Shows through beneath the title half, and covers the sliver left by
      // rounding when the two halves don't divide evenly.
      color: colors.surface,
      child: Column(
        // Load-bearing, and its absence was invisible: a Column's default
        // `center` hands loose cross-axis constraints, and a childless
        // `ColoredBox` is a `RenderProxyBox` that sizes to
        // `constraints.smallest` — so the colour block below was laid out 0pt
        // wide and every generated cover rendered as a plain white card. Exactly
        // the trap documented on `BookPageBlock`, which collapsed the same way.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ColoredBox(color: generatedCoverColor(isbn))),
          Expanded(
            child: Padding(
              // Left padding is wider so the text clears the binding band.
              padding: EdgeInsets.fromLTRB(
                width * 0.143,
                width * 0.061,
                width * 0.061,
                width * 0.061,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: titleSize,
                        height: 1.25,
                        letterSpacing: -0.02 * titleSize,
                        fontWeight: FontWeight.w600,
                        // Always primaryText: the title sits on `surface`, never
                        // on the colour block, so no per-swatch contrast logic
                        // is needed and dark mode adapts for free.
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  if (showGlyph) ...[
                    SizedBox(height: width * 0.06),
                    SvgPicture.asset(
                      _glyph,
                      width: width * 0.185,
                      colorFilter: ColorFilter.mode(
                        // Same tone as the title, at the weight of a printed
                        // colophon rather than a second piece of content.
                        colors.primaryText.withValues(alpha: 0.55),
                        BlendMode.srcIn,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
