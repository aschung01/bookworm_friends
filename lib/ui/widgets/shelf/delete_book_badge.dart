import 'package:flutter/material.dart';

/// The badge that takes a book off a shelf while the covers are wiggling.
///
/// **A white disc with a minus — iOS's own remove badge — rather than a red ✕.**
/// Three things were wrong with the red one, and the first is the one you saw before
/// reading any of them: a saturated red disc is the loudest thing that can be put on
/// a screen, and there was one per cover, so a shelf in edit mode read as a shelf
/// full of errors rather than a shelf waiting to be rearranged.
///
/// ✕ also means *close* everywhere else in this app — ending a visit, dismissing a
/// sheet — so this was the single place the glyph meant something destructive. And a
/// red fill under a white glyph is what a *committed* destructive action looks like,
/// which this is not: the tap opens a confirm sheet and nothing has happened yet. A
/// minus says "take this one out", which is exactly what the badge does, in the
/// vocabulary every reader already has from rearranging a home screen.
///
/// **Fixed colours, deliberately not the theme's.** The badge sits on a book cover,
/// not on the app's surface, and covers are arbitrary artwork under either theme — a
/// disc that flipped with the theme would be dark-on-dark half the time. What keeps
/// it off a *pale* cover, of which the shelves hold plenty, is the shadow rather than
/// the fill.
///
/// **Lifted out of `shelf_row.dart` when the Reading shelf gained one too.** It was
/// `_ShelfRowState._DeleteBookButton`, private, on the reasoning that this shelf was the
/// only place a book could be removed from. It is not any more — see
/// `ReadingShelfRow` — and the two rows have to draw the *same* badge under the same key,
/// or a reader would learn one gesture per row and a test could pin either drawing without
/// noticing the other had drifted.
class DeleteBookBadge extends StatelessWidget {
  const DeleteBookBadge({
    super.key,
    required this.label,
    required this.onPressed,
  });

  /// The key both rows mount it under, so `delete_book_<id>` means one thing.
  static ValueKey<String> keyFor(String bookId) =>
      ValueKey<String>('delete_book_$bookId');

  /// The disc itself, centred on the cover's top-left corner.
  static const double _diameter = 22;

  /// The square the tap is taken over, bigger than the disc on purpose: 44pt is the
  /// minimum target both platforms ask for, and a 22pt one hanging mostly off the
  /// edge of its cover is the hardest kind there is to hit.
  static const double _target = 44;

  /// The minus, as a proportion of the disc rather than a glyph. Drawn rather than
  /// set as `Icons.remove`, because at this size the icon font's own padding and
  /// stroke weight decide the picture and neither of them is ours to choose.
  static const double _barWidth = 10;
  static const double _barThickness = 2;

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onPressed,
          child: const SizedBox(
            width: _target,
            height: _target,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xBFFFFFFF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    // The only thing separating the badge from a white jacket.
                    BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: SizedBox.square(
                  dimension: _diameter,
                  child: Center(
                    child: SizedBox(
                      width: _barWidth,
                      height: _barThickness,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          // Near-black rather than black, and rather than the
                          // theme's ink: see the note on this class.
                          color: Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.all(
                            Radius.circular(_barThickness / 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
