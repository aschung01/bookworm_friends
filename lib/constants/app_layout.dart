import 'package:flutter/widgets.dart';

/// Widest a column of rows or prose is allowed to grow before it is centred in
/// whatever space is left.
///
/// 640 is not a fresh choice. It is the width Flutter's own Material 3 bottom
/// sheet already caps itself at — `_BottomSheetDefaultsM3.constraints` in
/// `material/bottom_sheet.dart` — which is why every modal sheet in this app was
/// already 640 on an iPad while the page *behind* it ran the full 1032, and a
/// settings row put its label at x=20 and its value at x=1010. Reusing the number
/// makes the sheet and the page agree rather than disagree by 400pt.
///
/// It is also close to the ~66-character measure typography has settled on, which
/// is the reason the number is defensible on a page and not only on a sheet.
const double kContentMaxWidth = 640;

/// Shortest side at or above which this is a tablet layout rather than a phone's.
///
/// Measured on `shortestSide`, **not `width`**, and that distinction is
/// load-bearing: an iPhone Pro Max in landscape is 932pt wide and sails through a
/// width test, but it is only 430pt tall, so handing it a centred form sheet
/// inset from the top and bottom would leave the card no room to be inset *from*.
///
/// The exact number is arbitrary inside a wide band, so it is chosen to sit clear
/// of every fixed point that matters:
///
/// | Surface                          | shortestSide |
/// | -------------------------------- | ------------ |
/// | iPhone Pro Max, widest phone     | 440          |
/// | Flutter's default test surface   | **600**      |
/// | iPad 11-inch portrait, narrowest | 834          |
///
/// 600 was the first choice, because it is Material's own compact/medium boundary.
/// It was wrong: `flutter test` renders at 800x600, so `shortestSide >= 600` put
/// **every widget test** on the tablet path and two height assertions changed
/// meaning under it. 700 clears the test surface and the widest phone while staying
/// far below the narrowest iPad, so no real device and no default harness lands
/// near the edge.
const double kTabletShortestSide = 700;

/// Whether [context] is being laid out on a tablet-sized screen.
///
/// Drives *presentation* decisions only — a bottom sheet becoming a floating form
/// sheet, say. Width capping deliberately does not ask this question: see
/// [CenteredContent].
bool isTabletLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= kTabletShortestSide;

/// Caps [child] at [maxWidth] and centres it horizontally, leaving it aligned to
/// the top of whatever it is given.
///
/// Deliberately **not** gated behind [isTabletLayout]. A cap needs no breakpoint:
/// on a phone in portrait the screen is narrower than the cap and this is a no-op,
/// and on a phone in *landscape* — 932pt on a Pro Max — the same stretch problem
/// exists in miniature and the same cap fixes it. Adding a device test would only
/// create a width at which the layout is wrong on purpose.
class CenteredContent extends StatelessWidget {
  const CenteredContent({
    super.key,
    required this.child,
    this.maxWidth = kContentMaxWidth,
  });

  final Widget child;

  /// Override only for content whose natural measure is not a column of text —
  /// a grid, say, which can use the room a paragraph cannot.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      // `topCenter` rather than `center`: a short list should hang from the top of
      // the page the way it does on a phone, not float in the middle of an iPad.
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
