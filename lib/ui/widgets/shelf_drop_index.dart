import 'package:bookworm_friends/providers/library_provider.dart'
    show clampDropIndex;

/// Where a book held at [pointerX] would be inserted into a row.
///
/// [slotCentres] is the horizontal centre of each book's slot in global coordinates, one
/// entry per book **with the lifted book already removed** — because an insertion index
/// refers to the row without it — in row order. Null where a cover has no laid-out box to
/// measure.
///
/// **Shared by `ShelfRow` and `ReadingShelfRow` because the two must not drift.** The
/// Reading shelf reorders with its own drag (a `ReadingBookDrag`, which no queue shelf can
/// accept) and the shelves reorder with theirs, but "where would this land" is one
/// question and a second implementation of it would eventually answer differently. The
/// three rules below are the whole of that answer.
///
/// **The finger is compared against the *centre* of each cover**, so a book is only
/// stepped over once the finger is more than halfway past it. That is the rule
/// `ReorderableListView` applied within a shelf, and it is what keeps the gap still while
/// a finger rests on a boundary.
///
/// **An unmeasured slot is placed by which end it is off.** A row builds lazily, so covers
/// scrolled off either end have no box: everything before the first *measured* cover is
/// behind the finger, everything after the last one is ahead of it. Without this a long
/// row would compute an index against only the covers that happen to be built.
///
/// **Then clamped to the row's own ends**, via [clampDropIndex], and clamped here rather
/// than at each call site so a third caller cannot forget. The point of clamping at all is
/// that **the gap never opens where the book cannot land**: a preview that has to be
/// corrected on release is a preview that lied.
int dropIndexForPointer({
  required double pointerX,
  required List<double?> slotCentres,
}) {
  var index = 0;
  var measuredOne = false;
  for (final centre in slotCentres) {
    if (centre == null) {
      if (measuredOne) break;
      index++;
      continue;
    }
    measuredOne = true;
    if (centre >= pointerX) break;
    index++;
  }
  return clampDropIndex(index, rowLength: slotCentres.length);
}
