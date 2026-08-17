import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

const String _mascot = 'assets/icons/smileBookwormIcon.svg';

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

/// Below this rendered width the mascot is dropped and the title takes the
/// space instead.
///
/// The widest book anywhere in the app is the details page at roughly 120px, so
/// this threshold means the mascot appears there and nowhere else. Any value
/// above ~120 would be dead code.
const double kMascotMinWidth = 110.0;

/// Picks a stable palette entry for a book.
Color generatedCoverColor(String isbn) {
  if (isbn.isEmpty) return kGeneratedCoverPalette.first;
  return kGeneratedCoverPalette[bookHash(isbn) % kGeneratedCoverPalette.length];
}

/// Stand-in cover for books with no usable thumbnail.
///
/// Follows the reference's `stripe` variant: a colour block on top, title below
/// on a light ground. Replaces what used to be a gray box reading "no image", so
/// a missing cover reads as a design choice rather than a failure.
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
    final showMascot = width >= kMascotMinWidth;
    // Larger type on smaller books: they have no mascot to share the space with,
    // and a title set at the large book's ratio would be unreadable.
    final titleSize = width * (showMascot ? 0.115 : 0.135);

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
                  if (showMascot) ...[
                    SizedBox(height: width * 0.06),
                    SvgPicture.asset(
                      _mascot,
                      width: width * 0.185,
                      colorFilter: ColorFilter.mode(
                        colors.primaryText,
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
