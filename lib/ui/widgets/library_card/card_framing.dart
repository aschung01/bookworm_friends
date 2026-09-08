import 'package:flutter/material.dart';

import 'package:bookworm_friends/ui/widgets/library_card/card_lighting.dart';
import 'package:bookworm_friends/ui/widgets/library_card/shareable_library_card.dart';

/// How the exported image is composed around the card.
///
/// Two positions and one control, because Flighty has one and three would be a
/// settings panel.
enum CardFraming {
  /// The card bleeds to the edge of the image; there is no ground at all.
  ///
  /// Right for a feed post and for a chat bubble, where the surrounding app supplies
  /// its own background and a border of ours only makes the card look smaller. This is
  /// what shipped before Task 4, so it is also the framing the library bar's direct
  /// share still produces.
  fill,

  /// The card is inset on a coloured ground.
  ///
  /// The default, and not for decoration: the ground is what makes the card read as an
  /// object being held out rather than as a screenshot of one, and it is the only thing
  /// that can fill the difference between a 4:5 card and a 9:16 Story frame.
  float,
}

/// One drawing unit, in points. See [kShareableCardSize] and `_u` in
/// `shareable_library_card.dart` — the same conversion, because this file is laid out
/// in the same units as the card it wraps.
const double _u = 360 / 106;

/// How far the card pulls in from the image's edge under [CardFraming.float].
///
/// Seven units, against the drawings' eight. The drawing pads *outward* from a
/// full-size card; this pads inward from a fixed canvas (see [framedCardSize] for why),
/// so the same visual margin is a slightly smaller number.
const double kCardFloatInset = 7 * _u;

/// The ground the card floats on.
///
/// **Pinned values, like the stock and for the same reason** — the artifact must look
/// the same whoever exported it, so these cannot be theme tokens. A desaturated green
/// rather than more cream: two creams would put the card's own edge on a ground of
/// nearly its own value and the inset would stop reading as an inset at all.
const Color kCardGroundTop = Color(0xFFDFEADE);
const Color kCardGroundBottom = Color(0xFFBAD4C4);

/// The same ground under a candle.
///
/// Dark, because a lit card lying on a daylight ground would read as a photograph of a
/// screen rather than as an object in a dim room — the ground is part of the same scene
/// as the card, so it takes the same light.
const Color kCandleGroundTop = Color(0xFF2B1D0D);
const Color kCandleGroundBottom = Color(0xFF0A0603);

/// The exported image's size, whichever framing is chosen.
///
/// **One pinned size, and the plan expected two.** Task 4 set out to decide whether a
/// second constant was needed for a 9:16 Story export. It is not, twice over.
///
/// *First, framing does not change the canvas.* The obvious reading of "Float" is a
/// bigger image — the card plus a margin — which is what the drawings' CSS does. That
/// would give the two positions two different file shapes, so a reader who toggled
/// would be handed a differently-proportioned image for the same card, and
/// `shareable_library_card_test.dart`'s assertion against a size fixed in *both*
/// dimensions would have to become two assertions. Insetting the card within the same
/// 4:5 canvas is visually identical at any display scale — what the eye reads is the
/// ratio of card to ground, not the pixel count — and it keeps one constant, one
/// assertion, and one shape in circulation.
///
/// *Second, Instagram paints the Story ground itself.* The Stories hand-off is
/// `stickerImage` plus `backgroundTopColor`/`backgroundBottomColor`, not
/// `backgroundImage`: Instagram composites the card onto a ground it draws and leaves
/// it centred and movable, which is exactly why Flighty's passport lands that way. A
/// 9:16 PNG of our own would fight that. The only destination that could want one is
/// Photos → post by hand, which is not a reason to put a second shape of the product
/// into circulation.
Size get framedCardSize => kShareableCardSize;

/// Wraps the card in whatever ground the chosen framing calls for.
///
/// [card] must already be laid out at [kShareableCardSize] — [ShareableLibraryCard]
/// sizes itself. Under [CardFraming.float] a `FittedBox` scales that fixed layout down
/// to fit the inset, which is what makes **the toggle change the ground and never the
/// card**: the type, the well fraction and the strip's 44 columns are laid out once, at
/// one size, and the framing only decides how much of the image they occupy. Relaying
/// the card out into a smaller box would be free to break a line the other framing does
/// not.
///
/// Used for the preview and for the export, from the same call site, so the two cannot
/// disagree.
class FramedShareableCard extends StatelessWidget {
  final CardFraming framing;

  /// Which ground the float takes. Ignored under [CardFraming.fill], which has none.
  final CardLighting lighting;

  /// The card. Built at [kShareableCardSize].
  final Widget card;

  const FramedShareableCard({
    super.key,
    required this.framing,
    required this.card,
    this.lighting = CardLighting.daylight,
  });

  /// The two stops of the ground, for the chosen lighting.
  List<Color> get groundColors => lighting == CardLighting.candlelight
      ? const [kCandleGroundTop, kCandleGroundBottom]
      : const [kCardGroundTop, kCardGroundBottom];

  @override
  Widget build(BuildContext context) {
    if (framing == CardFraming.fill) return card;

    return SizedBox.fromSize(
      size: framedCardSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // **Square corners, deliberately, and it is not an oversight of the drawn
          // 4-unit radius.** A rounded corner on the outermost element of an exported
          // PNG is a *transparent* corner, and the targets this file lands on treat
          // alpha differently — a messenger that flattens onto black gets four dark
          // notches. The drawn radius is the preview sitting on the screen's own
          // ground, which is a different object.
          //
          // A consequence worth naming: Float is the only framing whose exported edge
          // is fully opaque. Fill inherits the card's own 3-unit radius, so its corners
          // have been transparent since Task 2.
          gradient: LinearGradient(
            // The drawings' 158°, which is nearly vertical with a lean to the right —
            // `tan(22°)` is 0.4, hence the horizontal extent.
            begin: const Alignment(-0.4, -1),
            end: const Alignment(0.4, 1),
            colors: groundColors,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(kCardFloatInset),
          child: FittedBox(child: card),
        ),
      ),
    );
  }
}
