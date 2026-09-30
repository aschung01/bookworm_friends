import 'dart:convert';

import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/models/reading_date.dart';

/// What the home-screen widget is handed, and the only thing it ever reads.
///
/// **A value type with a JSON encoding, kept apart from the channel that writes it**, so the
/// payload can be asserted in a plain unit test rather than only observed through a
/// `MethodChannel` mock. `test/streak_widget_snapshot_test.dart` pins the encoding, because the
/// Swift side decodes these exact key names and a rename here is a widget that silently shows
/// the invitation state to a reader with a live streak.
///
/// **What it deliberately does not carry: a phase.** The widget derives recorded / open / late
/// itself from [lastReadDay] and the date of the timeline entry being drawn. A snapshot written
/// at 22:00 is rendered again at 00:05 when the day has turned, so a baked-in phase would have
/// the widget insisting it is late at nine the next morning. For the same reason [streak] is the
/// run **ending at [lastReadDay]** rather than "the current streak": whether that run is still
/// alive depends on today, which is a question only the widget is in a position to ask.
class StreakWidgetSnapshot {
  const StreakWidgetSnapshot({
    required this.streak,
    required this.longestStreak,
    required this.lastReadDay,
    required this.copy,
    required this.lines,
    this.book,
  });

  /// Schema version, so a later field can arrive without breaking an installed widget.
  ///
  /// Bumped when a field changes meaning, not when one is added: the Swift decoder treats
  /// unknown keys as absent and every optional field is already nullable there. The first
  /// thing this is for is `kind = 'freeze'`, which the design defers.
  ///
  /// **[lines] arrived without a bump, and that is this rule being used rather than bent.** An
  /// installed widget reading a snapshot that has `lines` ignores it; a new widget reading one
  /// that does not falls back to [StreakWidgetCopy.todayOpen] / [StreakWidgetCopy.todayLate].
  /// So the copy ladder ships without a coordinated release, which is what `v` exists for.
  ///
  /// **`coverFile` arrived the same way.** An installed widget ignores the key; a new widget
  /// reading a snapshot without it — or with it, but before the thumbnail has been fetched —
  /// draws the `coverColor` rectangle it drew before. That fallback is the whole reason this
  /// could ship incrementally, so do not let it rot.
  static const int version = 1;

  /// The run ending at [lastReadDay]. Not today's streak.
  final int streak;

  /// The record, which a missed day does not erase. Read only on the broken path.
  final int longestStreak;

  /// The most recent recorded day, or null when nothing is recorded at all.
  final DateTime? lastReadDay;

  /// The book the reader is in, or null if the reading shelf is empty.
  final Book? book;

  /// The localized lines, passed through rather than duplicated into Swift.
  final StreakWidgetCopy copy;

  /// The copy ladder: one line per time-of-day tier, also localized and passed through.
  final StreakWidgetLines lines;

  Map<String, Object?> toJson() => {
    'v': version,
    'writtenAt': DateTime.now().toUtc().toIso8601String(),
    // The two hour constants travel with the payload so that Swift never holds its own copy.
    // `kReadingDayRolloverHour` is already the single source for the arithmetic and the copy in
    // Dart; shipping it here extends that across the language boundary instead of starting a
    // third copy in an extension nobody thinks to grep.
    'rolloverHour': kReadingDayRolloverHour,
    'warningHour': kReadingDayWarningHour,
    'lastReadDay': lastReadDay == null ? null : _wireDay(lastReadDay!),
    'streak': streak,
    'longestStreak': longestStreak,
    'book': book == null
        ? null
        : {
            'id': book!.id,
            'title': book!.title,
            // First author only. The widget has one line for it at 11pt and a joined list
            // would be truncated mid-name, which reads worse than one name does.
            'author': book!.authors.isEmpty ? null : book!.authors.first,
            'coverColor': book!.coverColor == null
                ? null
                : _wireColour(book!.coverColor!.toARGB32()),
            // **The filename, not a path and not a convention the two sides each spell.** Swift
            // resolves it inside the App Group's `covers/` directory; naming it here for the same
            // reason `rolloverHour` travels in the payload — so the extension never holds its own
            // copy of a rule that lives in Dart.
            //
            // Always present when there is a book, even though the file may not be: the thumbnail
            // is fetched after this snapshot is written, so on the first render after a book
            // change the name points at nothing and the widget draws `coverColor`. That is the
            // designed order, not a race to fix — the streak must not wait on a network call.
            'coverFile': book == null ? null : coverFileName(book!.id),
            'progress': book!.progress,
          },
    'copy': copy.toJson(),
    'lines': lines.toJson(),
  };

  String encode() => jsonEncode(toJson());

  /// The thumbnail's filename for [bookId], inside the App Group's `covers/` directory.
  ///
  /// **Keyed on the book id so a stale file can never be drawn under a new book.** The
  /// alternative — one fixed `cover.png` — would show the previous book's jacket for however
  /// long the next fetch takes, which is a wrong picture that looks like a right one.
  ///
  /// The id is a UUID from Postgres, so this is already free of path separators; the native side
  /// validates that rather than trusting it, because a name that could contain `../` would escape
  /// the container.
  static String coverFileName(String bookId) => 'cover-$bookId.png';

  /// `yyyy-MM-dd`, formatted by hand for the reason `ReadingDaysNotifier` does it: the value is
  /// already a date-only local midnight, and `toIso8601String` would add a time component and a
  /// `Z` for the other side to have to strip back off.
  static String _wireDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// `#RRGGBB`, dropping alpha. Jacket colours are opaque and the widget parses six digits.
  static String _wireColour(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  bool operator ==(Object other) =>
      other is StreakWidgetSnapshot &&
      other.streak == streak &&
      other.longestStreak == longestStreak &&
      other.lastReadDay == lastReadDay &&
      other.book?.id == book?.id &&
      other.book?.progress == book?.progress &&
      other.book?.title == book?.title &&
      other.copy == copy &&
      other.lines == lines;

  /// Equality exists so the writer can skip an unchanged snapshot.
  ///
  /// **`writtenAt` is deliberately not part of it.** It changes on every build, so including it
  /// would make every snapshot unequal to the last and turn `reloadAllTimelines` into a call on
  /// every rebuild — which is how a widget burns the refresh budget iOS grants it and then
  /// stops updating at all.
  @override
  int get hashCode => Object.hash(
    streak,
    longestStreak,
    lastReadDay,
    book?.id,
    book?.progress,
    book?.title,
    copy,
    lines,
  );
}

/// The copy ladder: what the widget says at each hour of an unrecorded day.
///
/// **A line per time-of-day tier, and the tier is the widget's to work out.** The app writes the
/// seven sentences and never which one to draw, for the same reason it writes no phase: an entry
/// generated at 22:00 is rendered again at 00:05, and a chosen sentence would be a baked-in answer
/// with six ways a day to be wrong instead of two.
///
/// **Why the lines travel at all rather than living in Swift.** They are translated, and an
/// extension cannot read `AppLocalizations`. Seven strings in two locales kept in step by
/// discipline is seven strings that drift, which is the argument [StreakWidgetCopy] already makes.
///
/// The voices are mixed on purpose across the day and two of them scold — see "The ladder, as
/// chosen" in `docs/superpowers/specs/2026-09-22-streak-widget-design.md`, which records the rules
/// that were amended to allow it and the reasoning that lost. **`recorded` has no line in any
/// voice**, so there is no field for it: the lit flame already says the thing, and a sentence under
/// it would be the tile explaining its own drawing.
class StreakWidgetLines {
  const StreakWidgetLines({
    required this.dawn,
    required this.morning,
    required this.afternoon,
    required this.evening,
    required this.late,
    required this.last,
    required this.none,
  });

  /// From 05:00.
  final String dawn;

  /// From 10:00.
  final String morning;

  /// From 14:00.
  final String afternoon;

  /// From 18:00.
  final String evening;

  /// From `kReadingDayWarningHour`, 21:00.
  final String late;

  /// From 23:00 — the last hour before the run dies.
  ///
  /// Named `last` rather than `final` because Dart will not have it, and the wire key stays
  /// `final` because Swift is where the tiers are named and the mockup's labels say `final`.
  final String last;

  /// No run at all, at every hour. Never escalates; see the design record.
  final String none;

  Map<String, Object?> toJson() => {
    'dawn': dawn,
    'morning': morning,
    'afternoon': afternoon,
    'evening': evening,
    'late': late,
    'final': last,
    'none': none,
  };

  @override
  bool operator ==(Object other) =>
      other is StreakWidgetLines &&
      other.dawn == dawn &&
      other.morning == morning &&
      other.afternoon == afternoon &&
      other.evening == evening &&
      other.late == late &&
      other.last == last &&
      other.none == none;

  @override
  int get hashCode =>
      Object.hash(dawn, morning, afternoon, evening, late, last, none);
}

/// The five strings the widget prints, already localized and already formatted.
///
/// **Every one of them is count-free in both locales**, which is what makes passing them
/// possible at all: the ARB's own note on `streakDays` records that "day streak" is attributive
/// and does not inflect, and the three status lines take no placeholder. So Swift never formats
/// a plural, and the alternative — a second copy of five translated strings in an extension that
/// cannot read `AppLocalizations` — does not have to exist.
class StreakWidgetCopy {
  const StreakWidgetCopy({
    required this.dayStreak,
    required this.todayOpen,
    required this.todayLate,
    required this.todayDone,
    required this.nothingYet,
  });

  final String dayStreak;
  final String todayOpen;
  final String todayLate;
  final String todayDone;
  final String nothingYet;

  Map<String, Object?> toJson() => {
    'dayStreak': dayStreak,
    'todayOpen': todayOpen,
    'todayLate': todayLate,
    'todayDone': todayDone,
    'nothingYet': nothingYet,
  };

  @override
  bool operator ==(Object other) =>
      other is StreakWidgetCopy &&
      other.dayStreak == dayStreak &&
      other.todayOpen == todayOpen &&
      other.todayLate == todayLate &&
      other.todayDone == todayDone &&
      other.nothingYet == nothingYet;

  @override
  int get hashCode =>
      Object.hash(dayStreak, todayOpen, todayLate, todayDone, nothingYet);
}
