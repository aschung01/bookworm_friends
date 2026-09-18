/// The wall-clock hour at which one reading day gives way to the next.
///
/// Four, not zero, and this is the constant the whole streak mechanic rests on. A
/// reader who closes a chapter at 00:30 means _tonight_; a boundary at midnight
/// would file that chapter under tomorrow and break the run on the very night the
/// reader kept it. The feature exists to encourage the late chapter, so it must not
/// be the one thing that costs a streak.
///
/// 4am is also the deadline the evening warning quotes, which is why it is a named
/// constant rather than a literal in one expression: the number in the copy and the
/// number in the arithmetic are the same number, and cannot drift apart in a later
/// edit.
const int kReadingDayRolloverHour = 4;

/// The calendar day [now] belongs to, for streak purposes.
///
/// The local date of `now` shifted back by [kReadingDayRolloverHour] hours, with
/// the time component stripped — so 03:59 is still yesterday and 04:00 is today.
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

  // Wall-clock arithmetic, deliberately **not** `local.subtract(const
  // Duration(hours: 4))`. `Duration` is elapsed time, and on a spring-forward
  // morning four elapsed hours are five wall-clock hours: 04:00 local minus 4h of
  // elapsed time is 23:00 the previous evening, so the 4am rule inverts for one
  // morning a year and a reader loses a streak in a way nobody can reproduce.
  // Subtracting on the calendar keeps the rule the rule on every day, including
  // the two that are not 24 hours long.
  final shifted = DateTime(
    local.year,
    local.month,
    local.day,
    local.hour - kReadingDayRolloverHour,
  );

  return DateTime(shifted.year, shifted.month, shifted.day);
}
