/// Runs of consecutive reading days, derived from the days themselves.
///
/// **Nothing here is stored, and that is the design.** A counter in a column and a
/// set of days are two truths that can disagree — a failed write, a double tap, a
/// replayed offline queue, a repaired day — and once they disagree the counter is
/// the one that is wrong while being the one that is displayed. Days are set
/// membership (`reading_days` is keyed on `(user_id, day)`, so a write is idempotent
/// by construction) and the number is arithmetic over that set. There is no
/// increment to lose and nothing to reconcile.
///
/// It is cheap enough to mean it: one row per day, so even a perfect four-year
/// streak is under 1,500 entries, and the chip, the tile and the month grid are
/// three reads of one set rather than three things that must be kept in step.
library;

/// The length of the run that is still alive on [today], or `0` if none is.
///
/// Counts back from [today] when [today] is stamped, otherwise from the day before
/// it, otherwise returns `0`.
///
/// **A run ending yesterday is still current.** An unstamped today means the day is
/// _open_, not that the streak is _broken_ — the reader has not lost anything yet,
/// they simply have not read yet, and it is not tomorrow. Collapsing the two would
/// make the number a threat instead of encouragement, and it would flicker: every
/// streak in the app would read `0` each morning and jump back at bedtime. The UI
/// keeps the distinction visible by drawing this same figure as a grey chip until
/// today is stamped and a green one after.
///
/// A run that ended two days ago is over, and this returns `0` for it. The record is
/// not lost with it — see [longestReadingRun].
///
/// [days] holds date-only values as produced by `readingDate`; a stray time
/// component is stripped defensively, since `DateTime` keys only match as instants.
/// [today] must be a reading date too — `readingDate(DateTime.now())`, not
/// `DateTime.now()` — because only the caller knows what time it is, and the
/// rollover cannot be applied twice: this function cannot re-derive it, because
/// `readingDate` of a date-only midnight is the day _before_ it.
int currentReadingRun(Set<DateTime> days, DateTime today) {
  final stamped = _dayKeys(days);
  if (stamped.isEmpty) return 0;

  final start = _dayKey(today);
  var cursor = stamped.contains(start) ? start : _shiftDays(start, -1);
  if (!stamped.contains(cursor)) return 0;

  var length = 0;
  while (stamped.contains(cursor)) {
    length++;
    cursor = _shiftDays(cursor, -1);
  }
  return length;
}

/// The longest run anywhere in [days] — the record, not the latest run.
///
/// **A break does not erase the history.** [currentReadingRun] going to `0` is a
/// statement about this week; the record is a statement about the reader, and the
/// only figure that survives the missed night that reset everything else. With
/// freezes deferred, a single missed night severs a run outright, so this is the
/// number that stops that from reading as though the reading never happened.
///
/// Returns `0` for an empty set, never `null`: unlike the Library Card's tiles,
/// "no runs yet" and "a run of zero days" are the same fact here, so there is no
/// absent case to distinguish.
int longestReadingRun(Set<DateTime> days) {
  final stamped = _dayKeys(days);
  if (stamped.isEmpty) return 0;

  var longest = 0;
  for (final day in stamped) {
    // Walk forward from run starts only — a day whose predecessor is stamped is in
    // the middle of a run someone else already measured. That makes this one pass
    // over the set in total rather than one walk per day, and it removes the need to
    // sort: the set answers "is the day before this one present" directly.
    if (stamped.contains(_shiftDays(day, -1))) continue;

    var length = 0;
    var cursor = day;
    while (stamped.contains(cursor)) {
      length++;
      cursor = _shiftDays(cursor, 1);
    }
    if (length > longest) longest = length;
  }
  return longest;
}

/// [day] with its time component dropped, in the local zone.
///
/// Not `readingDate` — these values are already reading dates, and pushing a
/// midnight through the 4am rollover a second time would move every day in the set
/// back by one.
DateTime _dayKey(DateTime day) {
  final local = day.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// [days] as keys that can actually be looked up.
///
/// Rebuilt rather than trusted: one caller passing a `DateTime` with a time
/// component would make every `contains` below miss, silently, and report a streak
/// of zero to a reader who has one.
Set<DateTime> _dayKeys(Set<DateTime> days) => days.map(_dayKey).toSet();

/// [day] moved by [delta] calendar days.
///
/// On the calendar, not `add(Duration(days: 1))`: elapsed days are 23 or 25 hours
/// long twice a year, so a duration step lands at 23:00 or 01:00 and every
/// subsequent lookup misses on the exact-instant match a `Set<DateTime>` performs.
/// The bug that produces is a streak that truncates at a DST boundary, months from
/// where the mistake was made.
DateTime _shiftDays(DateTime day, int delta) =>
    DateTime(day.year, day.month, day.day + delta);
