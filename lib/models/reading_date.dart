/// The wall-clock hour at which one reading day gives way to the next.
///
/// Zero — midnight, matching Duolingo's own streak reset. This used to be 4,
/// specifically so a chapter finished at 00:30 read as _today's_ reading rather
/// than costing the run it had just extended; that reasoning did not stop being
/// true, it was outweighed on instruction by matching the reset everyone already
/// knows from Duolingo. The accepted cost is exactly the case 4 existed to avoid: a
/// page turned between midnight and whenever the reader actually goes to bed now
/// counts for tomorrow, not today.
///
/// Kept as a named constant rather than a literal in [readingDate] and in the
/// evening warning's copy, so the hour in the arithmetic and the hour in the copy
/// cannot drift apart if this is ever changed again.
const int kReadingDayRolloverHour = 0;

/// How many hours into a reading day the evening warning begins.
///
/// 21 — so the warning runs 21:00 to midnight while [kReadingDayRolloverHour] is zero.
/// 20 was the alternative and buys an hour; 21 wins on evenings having settled by then.
///
/// **Three hours, and that is a consequence of the midnight rollover rather than a
/// choice.** At the 4am rollover this file used to carry, a 21:00 warning gave the reader
/// seven hours to act. It now gives three, which makes the warning both more genuinely
/// urgent and more able to read as a scold — which is why the copy it drives names the
/// deadline and does not count one down.
///
/// Named for the reason the rollover is named: the hour in the arithmetic and the hour in
/// the copy have to be the same hour, and a literal in each is how they drift apart. It is
/// also what the iOS widget's snapshot will carry, so that Swift reads this number rather
/// than holding a third copy of it.
const int kReadingDayWarningHour = 21;

/// The calendar day [now] belongs to, for streak purposes.
///
/// The local date of `now` shifted back by [kReadingDayRolloverHour] hours, with
/// the time component stripped. At zero the shift does nothing and this is simply
/// today's calendar date — the shift only matters again if [kReadingDayRolloverHour]
/// is ever made nonzero.
///
/// **[now] is a parameter and there is no clock in here.** No `DateTime.now()`, no
/// clock singleton, no provider to override. Every boundary this function has is a
/// boundary a test has to be able to stand on, and a hidden clock turns each of
/// those cases into a mocking exercise. The caller is the only place that needs to
/// know what time it is.
///
/// **The device's local date, not a server day.** `profiles` has no timezone column
/// and the app has never collected one, so a server has nothing to compute a local
/// date from; it would be authoritative about something it cannot observe. The
/// accepted consequence, stated plainly rather than papered over: **a reader who
/// crosses the date line can gain or lose a day.** Two calls a few minutes apart
/// can return dates two days apart, or the second can precede the first. That is
/// accepted, not solved — the alternative is collecting and maintaining a timezone
/// the app does not have, to correct a case that resolves itself as soon as the
/// reader stops flying. It is also what the reader would answer if asked what day
/// it is: whatever their phone says.
///
/// A UTC instant is converted with [DateTime.toLocal] first, so a `created_at` read
/// back from Postgres lands on the same day the phone recorded.
///
/// The returned value is **date-only — midnight in the local zone** — which is what
/// makes it safe as a `Map` or `Set` key: `DateTime` equality is equality of
/// instants, so two values for the same day are only interchangeable if both came
/// from here. It is also how the `reading_days.day` column (a Postgres `date`)
/// round-trips, so the key a widget holds and the key a row carries are the same
/// value with no reformatting in between.
DateTime readingDate(DateTime now) {
  final local = now.toLocal();

  // Wall-clock arithmetic, deliberately **not** `local.subtract(Duration(hours:
  // kReadingDayRolloverHour))`. At zero the two are indistinguishable, but
  // `Duration` is elapsed time: the day this constant is nonzero again, an
  // elapsed-time subtraction inverts for one morning a year around a spring-forward
  // transition, and a reader loses a streak in a way nobody can reproduce.
  // Subtracting on the calendar keeps the rule the rule on every day, including
  // the two that are not 24 hours long — which is why this stays written the long
  // way rather than being simplified now that it is a no-op.
  final shifted = DateTime(
    local.year,
    local.month,
    local.day,
    local.hour - kReadingDayRolloverHour,
  );

  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// Where a reading day has got to: recorded, open, or open and nearly over.
///
/// **Three states rather than `readTodayProvider`'s two**, because "the day is open" and
/// "the day is open and it is 22:30" are different facts about the same day, and only one of
/// them is worth saying out loud.
///
/// `openLate` rather than `late`, because `late` is a Dart keyword and cannot name an enum
/// member.
enum ReadingDayPhase { recorded, open, openLate }

/// Which phase the reading day containing [now] is in, given the days already recorded.
///
/// **[now] is a parameter and there is no clock in here**, for the reason [readingDate]
/// states at length: every boundary this function has is a boundary a test has to be able to
/// stand on, and a hidden clock turns each of those into a mocking exercise.
///
/// [days] is asked for membership and nothing else, so a `Map`'s `keys` is the intended
/// argument — `contains` on a hash map's key iterable is that map's own `containsKey` rather
/// than a scan. It is the same collection `currentReadingRun` is handed, for the same reason.
///
/// **An empty [days] is not a special case.** A reader with nothing recorded has an open day
/// like anybody else, and it still turns late in the evening. That is deliberate: the first
/// day is the only day the warning has anything to do, and of 137 profiles in production
/// exactly one has a reading day at all.
ReadingDayPhase readingDayPhase(DateTime now, Iterable<DateTime> days) {
  final local = now.toLocal();
  if (days.contains(readingDate(local))) return ReadingDayPhase.recorded;

  // Hours *into the reading day*, which is the local hour only while the rollover is zero.
  // Written against the constant rather than as a bare `local.hour` so that restoring a
  // nonzero rollover cannot silently leave the warning measuring from the wrong origin.
  final hoursIn = (local.hour - kReadingDayRolloverHour) % 24;
  return hoursIn >= kReadingDayWarningHour
      ? ReadingDayPhase.openLate
      : ReadingDayPhase.open;
}

/// The next instant at which [readingDayPhase] would answer differently.
///
/// Either this reading day's warning hour or the start of the next one — the two wakes a
/// clock-driven consumer needs in a day, and nothing in between. Recording a day changes the
/// phase as well, but that arrives as a data change rather than as the passage of time, so it
/// is not this function's business.
///
/// **Wall-clock arithmetic**, like [readingDate]'s, so that neither of the two days a year
/// that are not 24 hours long moves the boundary. A `Timer` waiting out the gap is still
/// measuring elapsed time and will fire an hour out across a DST transition — which is why
/// the phase is also recomputed when the app resumes, rather than being trusted to a timer.
DateTime nextReadingPhaseBoundary(DateTime now) {
  final local = now.toLocal();
  final day = readingDate(local);

  // `DateTime` normalises an out-of-range hour, so a nonzero rollover pushing this past 24
  // lands on the next calendar day by itself rather than needing a second branch here.
  final warning = DateTime(
    day.year,
    day.month,
    day.day,
    kReadingDayRolloverHour + kReadingDayWarningHour,
  );
  if (local.isBefore(warning)) return warning;

  return DateTime(day.year, day.month, day.day + 1, kReadingDayRolloverHour);
}
