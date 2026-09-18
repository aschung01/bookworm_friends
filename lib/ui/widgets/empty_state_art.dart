import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';

/// Which illustration to draw. One entry per empty state the app can reach.
///
/// The names are the states, not the drawings, so a call site reads as the
/// moment it is in rather than as a filename.
enum EmptyStateArtwork {
  /// Someone else's library with nothing on the shelves.
  emptyLibraryOther('rest'),

  /// Your own library, still empty -- the one that is an invitation.
  emptyLibraryMine('invite'),

  /// The add-book sheet before anything is typed.
  searchIdle('search'),

  /// A query that neither the library nor the catalogue could answer, and the
  /// scan that matched no book. Both are "we looked and found nothing".
  noMatch('nomatch'),

  /// A book with no note written yet.
  noNote('note'),

  /// No friends added yet.
  noFriends('duo');

  const EmptyStateArtwork(this.asset);

  /// Basename under `assets/icons/empty/`.
  final String asset;

  String get path => 'assets/icons/empty/$asset.png';
}

/// A chalk illustration for an empty state, tinted to the current theme.
///
/// The assets are **alpha stencils**: chalk coverage is in the alpha channel and
/// the RGB is flat, so one file per piece serves both themes. Tinting with
/// `BlendMode.srcIn` replaces the colour and keeps the grain, which is why there
/// is no light/dark pair to keep in sync -- and therefore no way for the two
/// themes to drift into different drawings, which is what happened when they
/// were generated separately. See `docs/mockups/empty-states/PROMPTS.md`.
///
/// Defaults to `secondaryText`, which puts the art in the same register as the
/// caption underneath it. Pass [color] where the surrounding surface does not
/// come from `context.colors` -- the scanner's failure card is always dark, so
/// it supplies its own palette's ink rather than the app theme's.
///
/// Decorative by default: every use sits directly above text that already says
/// what the state is, so announcing the image too would just repeat it. Pass
/// [semanticLabel] if that ever stops being true.
class EmptyStateArt extends StatelessWidget {
  const EmptyStateArt(
    this.artwork, {
    super.key,
    required this.size,
    this.color,
    this.semanticLabel,
  });

  final EmptyStateArtwork artwork;

  /// Rendered edge length in logical pixels. The artwork is square and centred
  /// with its own margins, so this is the box, not the drawing.
  final double size;

  /// Overrides the `secondaryText` default.
  final Color? color;

  /// Set only when the art is not accompanied by text saying the same thing.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      artwork.path,
      width: size,
      height: size,
      // srcIn is `Image`'s default when `color` is set, but naming it makes the
      // stencil contract explicit at the one place it matters: the asset's own
      // RGB is discarded and only its alpha is honoured.
      color: color ?? context.colors.secondaryText,
      colorBlendMode: BlendMode.srcIn,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      // The stencils are square masters; anything else means a bad cut.
      fit: BoxFit.contain,
    );
  }
}
