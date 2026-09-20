import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';

/// The brand mark master: the shipping launcher artwork, white on transparency.
///
/// **The one file from `assets/branding/` bundled at runtime** — everything else in
/// that directory is a build-time input for `flutter_launcher_icons`. See the note
/// above `flutter_launcher_icons` in `pubspec.yaml` before adding a second.
///
/// White on transparency because both runtime uses need pure alpha: [BrandMark]
/// composites it onto a brand plate, and the Library Card's seal *tints* it (see
/// `kCardSealMarkAsset`). The full-bleed `app_icon.png` carries its own green plate
/// and can do neither.
const String kBrandMarkAsset = 'assets/branding/app_icon_mark.png';

/// The launcher icon, drawn in-app: brand plate, white mark, Apple's corner radius.
///
/// **A green plate with a white mark, never a green mark on the page.** That rule is
/// from `assets/branding/README.md` and it is why this is not an [EmptyStateArt]-style
/// tinted stencil: the vivid brand green scores 2.45:1 on a light surface
/// (`AppColors.brand`), so a green-tinted mark floating on `pageBackground` loses its
/// soft chalk edge into the page. The plate is a closed field, which is the relationship
/// the artwork was drawn for — and it is also what the reader just tapped on their home
/// screen, so the sign-in screen and the launcher are the same object.
///
/// The plate is rebuilt here rather than bundling the opaque `app_icon.png`, which would
/// add ~145KB for something two lines of Flutter can draw. [kBrandMarkAsset] is already
/// in the bundle for the Library Card seal, so this costs no new bytes.
///
/// Decorative: every use sits beside the app's name in text, so announcing the image
/// would only repeat it.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size});

  /// Edge length of the plate in logical pixels. The mark is full-bleed inside it,
  /// exactly as `build_master.py` composites `app_icon.png`; the drawing keeps its
  /// own margins (furthest opaque pixel at ~76% of the canvas), so nothing reaches
  /// the corners and there is no inset to tune.
  final double size;

  /// `MACOS_RADIUS / MACOS_BODY` from `assets/branding/build_master.py` — 185/824,
  /// which is Apple's icon-grid ratio. Taken from there rather than picked by eye so
  /// the in-app tile and the generated macOS master round identically.
  static const double _cornerRatio = 185 / 824;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.brand,
        borderRadius: BorderRadius.circular(size * _cornerRatio),
      ),
      // No `color:` — unlike the seal and the empty-state stencils this one is *not*
      // tinted. The master's own white is the mark, and the plate behind it is what
      // makes it visible, which is why this reads the same in both themes.
      child: Image.asset(
        kBrandMarkAsset,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
