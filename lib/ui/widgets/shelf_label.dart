import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Hero tag for the tab naming the shelf with [shelfId].
///
/// Separate from `shelfHeroTag`: the tab and the plank are two objects that happen
/// to travel together, and one tag shared between them would be two heroes under
/// one name on the same route, which throws.
String shelfLabelHeroTag(String shelfId) => 'shelf_label_$shelfId';

/// The small "tab" that names the shelf a book sits on.
///
/// Renders nothing for an empty [label] so callers don't have to special-case
/// a book whose shelf can't be resolved. Long shelf names are capped and
/// ellipsized instead of running past the edge of the screen.
///
/// Pass [heroTag] — built with [shelfLabelHeroTag] — to fly the tab between routes
/// alongside the plank it sits on, so the shelf travels to the details page as one
/// thing rather than the plank sliding up and the name blinking into place.
///
/// A tab that renders nothing is never a hero, which is the whole handling of an
/// unresolvable shelf: no tab at one end means no partner, and the other end's tab
/// simply stays put instead of flying to or from a zero-sized box.
///
/// No `createRectTween`, unlike `BookWidget`. The tab shrink-wraps the same name at
/// both ends, so its two rects are the *same size* and differ only by the 20pt of
/// side padding the details header adds — and the default [MaterialRectArcTween]
/// carries two congruent rects along congruent arcs, so the size is preserved to
/// floating-point noise. Holding it fixed matters, hence the check rather than the
/// assumption: this box is squeezed onto its text, so a fraction of a point off and
/// the name ellipsizes mid-flight.
///
/// **[count] is part of that same contract, which is why it is not optional in
/// practice even though it is nullable.** A tab showing `IT 12` is wider than one
/// showing `IT`, so passing the count at one end of a flight and not the other
/// resizes the hero in the air — precisely the failure the paragraph above exists to
/// prevent. Both ends derive it from [shelvedBookCount] so they cannot disagree.
class ShelfLabel extends StatelessWidget {
  final String label;

  /// How many books stand on this shelf, drawn after the name.
  ///
  /// Null draws no count at all, which is what the details page wants for a shelf
  /// it could not resolve. Use [shelvedBookCount] to compute it; a count that
  /// counted finished books would disagree with the shelf the reader is looking
  /// at, since those are drawn in the read pile rather than on the plank.
  ///
  /// This is the whole reason the clip at the end of a long row means anything:
  /// without it a shelf showing three covers and a sliver is indistinguishable
  /// from a shelf of three and a rendering fault.
  final int? count;

  /// Widest the tab may grow before its text ellipsizes.
  final double maxWidth;

  final Object? heroTag;

  /// The name's own colour, for a tab that is not one the reader named.
  ///
  /// The Reading shelf sets it to `brandText`, because that shelf belongs to the app:
  /// its books were put there by their *status* rather than by a reader filing them, and
  /// the colour is what says so without a second word on the tab. Null takes the
  /// ambient text colour, which is what every reader-named shelf wants.
  ///
  /// Safe for the hero contract above in a way that a font change would not be: colour
  /// does not affect the box's measured width, so a tab that flies keeps its size even
  /// if the two ends were ever to disagree about this. (They cannot today — the Reading
  /// shelf flies nothing. See `ReadingShelfRow`.)
  final Color? labelColor;

  const ShelfLabel({
    super.key,
    required this.label,
    this.count,
    this.maxWidth = 140,
    this.heroTag,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();

    final Widget tab = Container(
      // No `alignment` here: a Container with an alignment expands to fill the
      // space it is offered, which stretched the tab across the cover. Without
      // it the tab shrink-wraps its label, as it does in the library.
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          topRight: Radius.circular(3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      // A Row rather than one `Text.rich`, so that the *name* is what gives way
      // when the tab hits [maxWidth]. In a single text run the count trails the
      // name and is therefore the first thing an ellipsis eats — which would drop
      // the only new information on the tab exactly on the long-named shelves
      // where it is most useful.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              // A `const` token rather than a literal, and the constness is
              // load-bearing here rather than tidiness: the hero contract above
              // depends on this tab measuring the *same* width at both ends of
              // the flight. Two call sites spelling out 14/bold could drift
              // apart; one token cannot.
              style: labelColor == null
                  ? AppTextStyles.label
                  : AppTextStyles.label.copyWith(color: labelColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 5),
            Text(
              // Localised rather than `'$count'`: Korean counts books with a
              // counter word, so this renders `12` in English and `12권` in
              // Korean. A bare number would read as a fragment there.
              AppLocalizations.of(context).bookCountLabel(count!),
              style: AppTextStyles.label.copyWith(
                color: context.colors.secondaryText,
              ),
              maxLines: 1,
            ),
          ],
        ],
      ),
    );

    final tag = heroTag;
    if (tag == null) return tab;
    return Hero(tag: tag, child: tab);
  }
}
