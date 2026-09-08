import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

/// Height of the miniature cover shown in the collapsed app bar.
///
/// Small enough to clear the 56pt toolbar with room above and below, which also
/// keeps the cover's cast shadow faint: `BookChassis` scales its shadow off
/// cover width, and at this size that bottoms out at the minimum scale.
const double kCollapsedCoverHeight = 24;

/// How far the row rises into place as it fades in.
const double _kRise = 8;

/// A book's cover and title, shown in the app bar once the hero header has
/// scrolled away.
///
/// This is a *crossfade*, not a shared-element morph: the hero cover scrolls off
/// under the bar as normal and this second, smaller copy fades in over the top
/// of it. That is what iOS itself does — the App Store and Music both keep a
/// separate small artwork in the collapsed bar rather than flying the large one
/// up — and it sidesteps two problems a real morph would create here.
/// [BookWidget] already wraps itself in a [Hero] for the route transition, so a
/// scroll-driven copy would have to be lifted into an overlay and would then
/// fight that hero on pop. And a cover is not a flat image but a perspective
/// `BookChassis`, so interpolating its rect means interpolating a 3D transform
/// rather than a box.
class CollapsingBookTitle extends StatelessWidget {
  final String title;

  /// Drives the mini cover's size jitter and its generated-cover colour, exactly
  /// as it does for the hero copy, so the two stay recognisably the same book.
  final String isbn;

  final String imageUrl;

  /// 0 while the header is fully expanded (nothing is drawn), 1 once it has
  /// collapsed.
  final double progress;

  const CollapsingBookTitle({
    super.key,
    required this.title,
    required this.isbn,
    required this.imageUrl,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing to show at rest. The early return also keeps the mini cover's
    // image stream unsubscribed until the bar actually needs it.
    if (progress <= 0) return const SizedBox.shrink();

    final t = progress.clamp(0.0, 1.0);

    return IgnorePointer(
      child: Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * _kRise),
          // Both the opacity and the offset change on every scroll frame. With a
          // repaint boundary beneath them each becomes a compositor layer, so
          // the cover's four stacked shadows and its binding `saveLayer` are
          // painted once and only re-composited afterwards.
          child: RepaintBoundary(
            child: Row(
              children: [
                BookWidget(
                  height: kCollapsedCoverHeight,
                  imageUrl: imageUrl,
                  isbn: isbn,
                  title: title,
                  // Deliberately no `heroTag`: the header cover already owns
                  // `book_$isbn`, and two heroes sharing a tag on one route
                  // throws. `pressEffect` is off because a book in the nav bar
                  // has nowhere to navigate to, so holding it would start the
                  // turn and long-press timers for nothing.
                  pressEffect: false,
                ),
                const SizedBox(width: 10),
                // The toolbar hands its middle slot a bounded width — the gap
                // between leading and actions — so this ellipsises exactly where
                // the action buttons begin. The in-page title pans horizontally
                // instead; truncating is the right behaviour only up here, where
                // there is no room to scroll and nothing to scroll it with.
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.subtitle.copyWith(
                      color: context.colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
