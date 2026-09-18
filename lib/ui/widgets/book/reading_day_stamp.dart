import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/models/book.dart';

/// How many days a book has been open, counted from `start_date`.
///
/// Null when there is no start date to count from. That is rarer than it looks —
/// `book_info_bottom_sheet` sets one the moment a book's status becomes
/// [bookStatusReading] — but it is not impossible: a row written before the column
/// was populated, or a status set by some path that forgot. The stamp draws nothing
/// in that case rather than inventing a zero, because "D+0" and "we don't know" are
/// different statements and only one of them is true.
///
/// **Whole days, floored, in local time, and inclusive of today.** A book started
/// this morning is D+1 rather than D+0: the reader has been reading it *today*, and a
/// stamp that says nothing on the first day would be missing from exactly the book
/// they just opened. Counted from the calendar dates rather than the instants, so a
/// book started at 11pm is not D+2 by 1am — which is the bug a naive
/// `DateTime.now().difference(start).inDays` produces.
int? readingDayCount(Book book, {DateTime? now}) {
  final start = book.startDate;
  if (start == null) return null;
  final today = now ?? DateTime.now();
  final from = DateTime(start.year, start.month, start.day);
  final to = DateTime(today.year, today.month, today.day);
  // Negative for a start date in the future, which is a data fault rather than a
  // state to draw. Clamped to 1 so the stamp says "open since today" instead of
  // "D+-3", and so nothing has to special-case it upstream.
  final days = to.difference(from).inDays + 1;
  return days < 1 ? 1 : days;
}

/// The mark on an open book that says *how long*.
///
/// **The ribbon and this say two different things, and the pair is deliberate.**
/// `ReadingBookmark` says the book is open; this says it has been open for
/// twenty-three days. Neither is a rephrasing of the other, which is the test a
/// second mark on one cover has to pass — the app has failed it before, when the
/// shelf drew a white ribbon and the Library Card drew a red rectangle for the same
/// state (see `reading_bookmark.dart`).
///
/// **Real data, and the only reading fact the schema has.** `books.start_date` is
/// set when the status flips. There is no page position and no `last_opened`, so a
/// progress bar would be an invention and a "currently reading" ranking would be a
/// claim nothing can support — see the note on `ReadingShelfRow` about why every
/// book on that shelf leans at the same angle.
///
/// **Deliberately not drawn on the Library Card.** The card's grammar is that an open
/// book is marked by the *absence* of a stamp: `cardStampMonth` returns null for it,
/// and "bookmark, no month" is how the hero figure keeps meaning books *read*
/// (`card_cover_row.dart`). Putting a D+n on a card cover would invert that rule on
/// one surface and leave it standing on the other. If the card ever wants this, it
/// has to be decided there and for both.
class ReadingDayStamp extends StatelessWidget {
  /// Days open, from [readingDayCount]. The caller resolves it so this widget draws
  /// or does not draw one thing, rather than owning a clock.
  final int days;

  const ReadingDayStamp({super.key, required this.days});

  /// The stamp's own inset from the cover's edges.
  ///
  /// Bottom-**right**, which is the one corner the ribbon can never reach: the ribbon
  /// hangs at `top: 0, right: kReadingBookmarkInset`, so the two marks sit at
  /// opposite ends of the same edge and cannot collide however short a cover is.
  static const double inset = 5;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Near-opaque rather than solid, so a little of the cover reads through and
        // the stamp sits *on* the jacket instead of punching a hole in it. The same
        // reasoning as the Library Card's month stamps.
        color: colors.surface.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 0.5),
            blurRadius: 1.5,
            color: Colors.black.withValues(alpha: 0.25),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          // `D+` is not localised, and that is a decision rather than an oversight.
          // It is the register Korean readers already count days in — D-day, D+3 —
          // and it is short enough to survive on a 84pt cover in both locales, which
          // a translated "23일째" is not.
          'D+$days',
          style: AppTextStyles.caption.copyWith(color: colors.primaryText),
          maxLines: 1,
        ),
      ),
    );
  }
}
