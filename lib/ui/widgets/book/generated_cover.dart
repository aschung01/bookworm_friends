import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';

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

/// Picks a stable palette entry for a book.
Color generatedCoverColor(String isbn) {
  if (isbn.isEmpty) return kGeneratedCoverPalette.first;
  return kGeneratedCoverPalette[bookHash(isbn) % kGeneratedCoverPalette.length];
}

/// Fraction of the cover's width used as the title's type size.
///
/// One value at every size. There were two, because a corner mark used to share
/// the title half on wide covers and the type had to give way to it — no mark, no
/// tier. The reference sets its own title at 10.5% of the width; this runs a little
/// larger because a Korean title carries far more meaning per character and needs
/// to survive at 78pt.
const double _kTitleSizeRatio = 0.135;

/// Narrowest cover width at which the title is worth drawing at all.
///
/// The title is [_kTitleSizeRatio] of the width, so a 20pt cover sets it at 2.7pt.
/// Phase 4 shipped that exact smudge on the friends rail, and it looked like a
/// rendering fault rather than a small title. Below this width a caller should draw
/// the colour block alone — `CardCoverRow` does — which reads as a deliberately blank
/// cover instead of a broken one.
///
/// 7pt is the floor the type has to clear; the constant is derived rather than typed
/// so it cannot drift away from the ratio above it.
const double kGeneratedCoverMinWidth = 7 / _kTitleSizeRatio;

/// Stand-in cover for books with no usable thumbnail.
///
/// Follows the reference's `stripe` variant: a colour block on top, title below on
/// a light ground, left-aligned and inset far enough to clear the binding band.
/// Replaces what used to be a gray box reading "no image", so a missing cover reads
/// as a design choice rather than a failure.
///
/// **No mark of any kind.** The reference puts a small triangle in the corner and
/// this carried a book glyph there for a while; both are a publisher's colophon,
/// which is a thing a real cover earns and a generated one does not. It also cost
/// the space the title wants — the whole lower half is now the title's.
class GeneratedCover extends StatelessWidget {
  final String isbn;
  final String title;

  /// Rendered width of the cover, which every other measurement is taken from.
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
    final titleSize = width * _kTitleSizeRatio;

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
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  // Explicit rather than inherited. It is the default, but this
                  // is the one property of the cover that a reader notices
                  // immediately when it is wrong, and nothing else here pins it.
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: titleSize,
                    height: 1.25,
                    letterSpacing: -0.02 * titleSize,
                    fontWeight: FontWeight.w600,
                    // Always primaryText: the title sits on `surface`, never on
                    // the colour block, so no per-swatch contrast logic is needed
                    // and dark mode adapts for free.
                    color: colors.primaryText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
