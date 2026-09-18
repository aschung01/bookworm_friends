import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book/book_geometry.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';

/// How long the book takes to reach the centre, and to fly back.
///
/// Slower than a page push, deliberately. A page transition is a cover for a
/// screen change and wants to be over; here the flight *is* the content of the
/// route, so it is the thing being watched.
const Duration kBookMagnifyDuration = Duration(milliseconds: 340);

/// The tallest a magnified book is drawn, as a fraction of the screen's height.
///
/// Only binds where there is width to spare — a phone runs out of that first, see
/// [magnifiedBookHeight] — so in practice this is the iPad rule. Well short of 1
/// on purpose: the book is lifted *off the page it was tapped on*, and that page
/// has to stay legible behind it for this to read as a magnification rather than
/// as a navigation.
const double _kHeightFactor = 0.55;

/// Air kept between the book and the safe area on every side.
const double _kMargin = 32;

/// The page behind, dimmed. Black rather than a theme colour: the point is to take
/// the surface out of play so the only lit thing on screen is the book, and both
/// of this app's surfaces are far too close to their own book colours to do that.
const Color _kScrim = Color(0xA8000000);

/// The base height a magnified book is drawn at on a screen of [screenSize], with
/// [safeArea] insets.
///
/// Bound on three counts, and the tightest wins:
///
///  * the room left by [_kMargin] inside the safe area, vertically;
///  * the same room horizontally, via [kDefaultCoverAspect] — the true ratio is a
///    property of the decoded cover and nothing out here can know it, so this is an
///    estimate and [MagnifiedBook] keeps a `BoxFit.scaleDown` behind it for the
///    covers that turn out wider than the estimate;
///  * [_kHeightFactor] of the screen.
///
/// Both room bounds are divided through by [BookJitter.maxHeightFactor], because
/// what they cap is the book's *rendered* height and jitter can add 6% to whatever
/// is handed to `BookWidget.height`.
double magnifiedBookHeight({
  required Size screenSize,
  required EdgeInsets safeArea,
}) {
  final roomHeight = math.max(
    0.0,
    screenSize.height - safeArea.top - safeArea.bottom - _kMargin * 2,
  );
  final roomWidth = math.max(0.0, screenSize.width - _kMargin * 2);
  return math.min(
    screenSize.height * _kHeightFactor,
    math.min(
      roomHeight / BookJitter.maxHeightFactor,
      roomWidth / (BookJitter.maxHeightFactor * kDefaultCoverAspect),
    ),
  );
}

/// Lifts a book's cover off the page it was tapped on and holds it, enlarged, in
/// the centre of the screen. Tapping the book or the page behind it puts it back.
///
/// Presented as a **transparent [PageRoute]**, and all three words are
/// load-bearing:
///
///  * *Route*, so the system back gesture and `Navigator.pop` dismiss it, and so
///    the enlarged book is modal — the page underneath cannot be scrolled out from
///    under the cover that has to fly back to it.
///  * *Transparent*, so that page is still there to fly back to, and so the reader
///    can see what they lifted the book off of.
///  * ***`PageRoute` specifically***, because `HeroController` starts a flight only
///    when **both** routes are `PageRoute`s. A `PopupRoute` — which is what
///    `showDialog` and every sheet in this app is — would drop the enlarged book on
///    screen with no flight at all, and the flight is the entire effect.
///
/// The magnification is therefore a [Hero] on the tag the tapped cover already
/// carries: the book that arrives in the centre is drawn at its own larger metrics
/// and *scaled* through the flight by `BookWidget`'s shuttle, so what grows is a
/// real book rather than a bitmap of a small one — the binding band, the corner
/// radii and the fore-edge are all correct at the far end.
///
/// Being a plain `PageRoute` rather than a Material one also holds the page below
/// still: `MaterialRouteTransitionMixin.canTransitionTo` animates the outgoing
/// route only for another Material route or one with a `delegatedTransition`, and
/// this is neither, so the details page is dimmed and nothing else. Sliding it a
/// third of the way off would take the book's own destination with it.
Future<void> showMagnifiedBook(
  BuildContext context, {
  required Book book,
  required String heroTag,
}) {
  return Navigator.of(context).push(
    _MagnifiedBookRoute(
      book: book,
      heroTag: heroTag,
      // Read here rather than in the route, which has no context of its own. This
      // is what `showDialog` does with it too.
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class _MagnifiedBookRoute extends PageRoute<void> {
  _MagnifiedBookRoute({
    required this.book,
    required this.heroTag,
    required this.barrierLabel,
  }) : super(barrierDismissible: true);

  final Book book;
  final String heroTag;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => _kScrim;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => kBookMagnifyDuration;

  @override
  Duration get reverseTransitionDuration => kBookMagnifyDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => MagnifiedBook(book: book, heroTag: heroTag);

  /// Nothing of its own. The barrier already fades on this route's animation and
  /// the book is a hero flight; a fade or a scale here would be applied *on top of*
  /// the flight, cross-dissolving the one widget it is carrying.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// The enlarged book, centred, and still a book: held, it turns exactly as it does
/// on a shelf.
///
/// Nothing here is a still image or a scaled screenshot. It is a `BookWidget` at a
/// larger [magnifiedBookHeight], so the hold gesture, the press effect and the 3D
/// chassis all come with it — which is the reason the enlargement is worth doing at
/// all, since the fore-edge and the binding are what there is to look at up close.
class MagnifiedBook extends StatelessWidget {
  const MagnifiedBook({super.key, required this.book, required this.heroTag});

  final Book book;

  /// The tag the cover this was opened from carries, so the flight has one source
  /// and one destination.
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    // `viewPadding` rather than `padding`: this route sets no insets of its own, so
    // the two agree today — but `padding` is zeroed by anything that consumes the
    // inset, and the book would then grow up under the notch.
    final safeArea = MediaQuery.viewPaddingOf(context);
    final height = magnifiedBookHeight(
      screenSize: screenSize,
      safeArea: safeArea,
    );

    return Center(
      child: SizedBox(
        // Centred on the screen, which is what was asked for, with the safe insets
        // and [_kMargin] taken off the *room* rather than off the position. Both
        // insets are subtracted even though the box is symmetric about the centre,
        // so a tall notch keeps the book clear of the home indicator as well as of
        // itself — the alternative, insetting asymmetrically, would push the book
        // off centre to buy room it does not need.
        width: math.max(0.0, screenSize.width - _kMargin * 2),
        height: math.max(
          0.0,
          screenSize.height - safeArea.top - safeArea.bottom - _kMargin * 2,
        ),
        // The backstop for [magnifiedBookHeight]'s width estimate. A cover wider
        // than [kDefaultCoverAspect] would otherwise run past the margin; scaling
        // the composition down is safe where clipping it would not be, and it
        // preserves the aspect ratio the hero flight is interpolating. Costs
        // nothing — and inserts no transform — for the covers that already fit.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: BookWidget(
            height: height,
            imageUrl: book.thumbnail,
            isbn: book.isbn,
            title: book.title,
            pageCount: book.pageCount,
            heroTag: heroTag,
            // No `jitterOverride`, and that is the point: the hash and the page
            // count are the same two inputs the header cover used, so the book
            // that lands has an identical aspect ratio and an identical thickness
            // ratio to the one that left. `BookWidget`'s rect tween assumes
            // exactly that of a book's two rects — it lerps width and height
            // directly — and a book that changed shape in the air would crop its
            // own artwork through the flight.
            onTap: () => Navigator.of(context).maybePop(),
            // A tap closes this and a hold turns it, so the two cannot share a
            // release. Without this, looking at the fore-edge would be impossible:
            // letting go would dismiss the very book being looked at.
            holdSuppressesTap: true,
          ),
        ),
      ),
    );
  }
}
