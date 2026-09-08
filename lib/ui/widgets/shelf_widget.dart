import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:flutter/material.dart';

/// Hero tag for the plank under the shelf with [shelfId].
///
/// A function rather than a literal at each end, because the two ends of the
/// flight are in different files and a tag that stops matching fails *silently*:
/// the plank simply stays where it is, which is the state this was added to
/// replace. Nothing here is allowed to look like a coincidence.
String shelfHeroTag(String shelfId) => 'shelf_$shelfId';

/// The plank a shelf's books stand on.
///
/// Pass [heroTag] to fly the plank between routes, so a book tapped on a shelf
/// carries the shelf with it to the details page instead of leaving it behind and
/// finding a different one waiting there. Use [shelfHeroTag] to build it; the tag
/// names the *shelf*, since one plank serves every book standing on it.
///
/// Null on a plank that is not a particular shelf's — the read pile's, the Add
/// Book sheet's — because those have nothing to fly to.
///
/// No `createRectTween`, unlike `BookWidget`, and that is a measured decision
/// rather than an omission. The default [MaterialRectArcTween] arcs the rect's
/// top-left and bottom-right corners along two separate circles, which is what
/// distorts a book mid-flight — but a plank's two rects differ by 20pt of width
/// and nothing else, and both are centred on the screen's midline, so the arc is
/// degenerate: across the whole flight the bar's height stays within 0.1pt of 8
/// and its width only narrows. There is nothing here for an override to fix.
class ShelfWidget extends StatelessWidget {
  final double? width;
  final Object? heroTag;
  const ShelfWidget({super.key, this.width, this.heroTag});

  @override
  Widget build(BuildContext context) {
    final Widget plank = Container(
      height: 8,
      width: width ?? MediaQuery.of(context).size.width * 0.95,
      decoration: BoxDecoration(
        color: context.colors.surface,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 2),
            blurRadius: 2,
            color: Colors.black.withOpacity(0.25),
          ),
        ],
      ),
    );

    final tag = heroTag;
    if (tag == null) return plank;
    return Hero(tag: tag, child: plank);
  }
}
