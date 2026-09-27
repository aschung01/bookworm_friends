import Foundation

/// The container the app writes the snapshot into and this extension reads it out of.
///
/// Must match `com.apple.security.application-groups` in **both** targets' entitlements and
/// `kStreakWidgetAppGroup` in `lib/services/streak_widget_channel.dart`. A mismatch is silent:
/// `UserDefaults(suiteName:)` hands back a usable store for a group the process does not own,
/// so the widget reads nothing and shows the invitation state to a reader with a live streak.
let streakWidgetAppGroup = "group.com.unicorn.bookwormFriends"

/// The one key in that container. JSON, as a string.
let streakWidgetSnapshotKey = "streak_snapshot"

/// Where the app writes the jacket thumbnail, and the only file this extension ever opens.
///
/// **Must match `coversDirectory()` in `ios/Runner/AppDelegate.swift`**, which writes what this
/// reads. The filename itself is *not* derived here — it arrives in the snapshot as
/// `book.coverFile`, so the naming rule lives in Dart alone rather than being spelled a second
/// time in Swift. Same reasoning as `rolloverHour` travelling in the payload.
enum StreakWidgetCovers {
  static func url(for name: String) -> URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: streakWidgetAppGroup)?
      .appendingPathComponent("covers", isDirectory: true)
      .appendingPathComponent(name)
  }
}

/// What the reader is currently reading, as much of it as a widget needs.
struct StreakSnapshotBook: Decodable {
  let id: String
  let title: String
  let author: String?
  /// `#RRGGBB`, sampled from the jacket and already stored as `books.cover_color`.
  let coverColor: String?
  /// The jacket thumbnail's filename inside the App Group's `covers/` directory, named by Dart.
  ///
  /// **Optional, and the file it names may not exist.** The app writes the snapshot first and
  /// fetches the thumbnail after, so on the first render following a book change this points at
  /// nothing — by design, because the streak must not wait on a network call. `Jacket` falls back
  /// to `coverColor`, which is what it drew before thumbnails existed, and that fallback is why
  /// this field needed no `v` bump.
  let coverFile: String?
  /// 0...1, or nil for a book with no recorded position.
  let progress: Double?
}

/// The localized lines, carried in the snapshot rather than duplicated into Swift.
///
/// **Every string here is count-free in both locales**, which is what makes this work: the
/// ARB's own comment on `streakDays` records that "day streak" is attributive and does not
/// inflect, so there is no plural form for Swift to get wrong. The alternative was a second
/// copy of five strings in an extension that cannot read `AppLocalizations`, kept in step by
/// discipline — and translated copy kept in step by discipline is copy that drifts.
struct StreakSnapshotCopy: Decodable {
  let dayStreak: String
  let todayOpen: String
  let todayLate: String
  let todayDone: String
  let nothingYet: String
}

/// The ladder's six lines plus the no-run one, keyed by tier rather than chosen by the app.
///
/// **A map, never a sentence, for the same reason the phase is not written.** A chosen line is a
/// baked-in tier, and a baked-in tier goes stale six times a day rather than twice — an entry
/// generated at 22:00 is still rendered at 00:05.
///
/// **Every field is optional and the whole struct is optional, which is what kept the schema
/// version at 1.** `v` bumps when a field changes *meaning*, not when one is added: an installed
/// widget reading a snapshot that carries `lines` ignores the key, and this widget reading a
/// snapshot written before `lines` existed falls back to `copy.todayOpen` / `copy.todayLate`.
/// The ladder therefore ships without a coordinated app release, which is the property `v`
/// exists to protect. See `line(at:)` for the fallback itself — do not let it rot.
struct StreakSnapshotLines: Decodable {
  let dawn: String?
  let morning: String?
  let afternoon: String?
  let evening: String?
  let late: String?
  /// Backticked because `final` is a declaration modifier. The synthesized `CodingKeys` takes
  /// the identifier and not the escaping, so the JSON key stays the plain `final` the app writes.
  let `final`: String?
  let none: String?

  /// The line for a tier, or nil when the app shipped `lines` without this one.
  subscript(tier: StreakTier) -> String? {
    switch tier {
    case .dawn: return dawn
    case .morning: return morning
    case .afternoon: return afternoon
    case .evening: return evening
    case .late: return late
    case .`final`: return `final`
    }
  }
}

/// How far through the reading day the widget is drawing.
enum StreakDayPhase {
  case recorded
  case open
  case openLate
  /// The run ended before yesterday, so there is nothing live to show.
  case broken
}

/// Which time of day an unrecorded tile is drawing, which picks the line and the pose.
///
/// **The copy and the ground are two ladders on purpose.** This steps at six boundaries; the
/// ground interpolates continuously between its own anchors (`StreakGroundRamp`). A ground that
/// stepped with the copy would announce six times a day that something changed, and a sentence
/// that changed with the ground would be re-readable seventeen times and worn out by the third.
enum StreakTier {
  case dawn
  case morning
  case afternoon
  case evening
  case late
  /// The last hour before the run dies. Backticked; `final` is a declaration modifier.
  case `final`

  /// The tier an hour of the reading day falls in.
  ///
  /// Clamped below the first boundary rather than wrapping: the hours between the rollover and
  /// 05:00 belong to a reader who is up very late or up very early, and neither of them wants
  /// the 23:00 voice. Dawn is the gentlest line in the set, so it is the safe end to clamp to.
  static func forHour(_ hour: Int) -> StreakTier {
    if hour >= 23 { return .`final` }
    if hour >= 21 { return .late }
    if hour >= 18 { return .evening }
    if hour >= 14 { return .afternoon }
    if hour >= 10 { return .morning }
    return .dawn
  }
}

/// The app's streak, the book, and the two hour constants, as of the last time the app ran.
struct StreakSnapshot: Decodable {
  let v: Int
  /// Hour the reading day turns over. Carried rather than hardcoded so that
  /// `kReadingDayRolloverHour` stays the one source and Swift cannot hold a stale copy.
  let rolloverHour: Int
  /// Hour the evening warning begins — `kReadingDayWarningHour`, for the same reason.
  let warningHour: Int
  /// `yyyy-MM-dd`, the most recent recorded day, or nil if nothing is recorded at all.
  let lastReadDay: String?
  /// The run **ending at `lastReadDay`**, not "the current streak".
  ///
  /// The distinction is the whole reason this file can be correct days after the app last
  /// ran: a run ending yesterday is still current, a run ending a week ago is not, and which
  /// of those is true depends on *today* rather than on when the snapshot was written.
  let streak: Int
  let longestStreak: Int
  let book: StreakSnapshotBook?
  let copy: StreakSnapshotCopy?
  /// The ladder's lines, absent in every snapshot written before the ladder existed.
  let lines: StreakSnapshotLines?

  static func load(
    from defaults: UserDefaults? = UserDefaults(suiteName: streakWidgetAppGroup)
  ) -> StreakSnapshot? {
    guard
      let json = defaults?.string(forKey: streakWidgetSnapshotKey),
      let data = json.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode(StreakSnapshot.self, from: data)
  }
}

extension StreakSnapshot {
  /// The reading day a moment belongs to, as a date-only value in the local calendar.
  ///
  /// Mirrors `readingDate` in `lib/models/reading_date.dart`, including its choice to shift on
  /// the calendar rather than by elapsed time: `Calendar` arithmetic keeps the rule the rule on
  /// the two days a year that are not 24 hours long, where subtracting seconds would not.
  ///
  /// At the shipped `rolloverHour` of 0 this is simply `startOfDay`, which is also why the
  /// midnight rollover is the cheap one for a widget — the boundary is the one the OS already
  /// thinks in, and every date the widget displays agrees with the system's own.
  func readingDay(at date: Date, calendar: Calendar = .current) -> Date {
    let shifted =
      rolloverHour == 0
      ? date
      : calendar.date(byAdding: .hour, value: -rolloverHour, to: date) ?? date
    return calendar.startOfDay(for: shifted)
  }

  /// `lastReadDay` as a local date-only value.
  ///
  /// Parsed by components rather than through a `DateFormatter`, deliberately. A formatter
  /// carries a locale and a calendar, and the two ways that bites are a non-Gregorian device
  /// calendar reading "2026-09-22" as something else entirely, and a formatter defaulting to
  /// UTC and landing the day one off for half the planet. The string is three integers.
  func lastRecordedDay(calendar: Calendar = .current) -> Date? {
    guard let raw = lastReadDay else { return nil }
    let parts = raw.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(
      from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
    )
  }

  /// The hour of the *reading* day, 0...23.
  ///
  /// Factored out because three things now ask for it — the phase, the tier and the ground ramp
  /// — and they must agree to the hour or the tile will show the late line over the afternoon
  /// ground for an hour a day. At the shipped `rolloverHour` of 0 this is the wall-clock hour.
  func readingHour(at date: Date, calendar: Calendar = .current) -> Int {
    let hoursIn = calendar.component(.hour, from: date) - rolloverHour
    return ((hoursIn % 24) + 24) % 24
  }

  /// The same hour with its minutes as a fraction, for the ground ramp only.
  ///
  /// The ramp is continuous by design, and the *first* entry of a timeline lands at whatever
  /// minute `getTimeline` happened to run at. Sampling on the fraction means the tile a reader
  /// sees immediately after a reload agrees with the one they would have seen a minute later;
  /// sampling on the integer hour would step it backwards to the top of the hour. The anchors
  /// still land on their exact hexes, because a whole hour has a zero fraction.
  func readingHourFraction(at date: Date, calendar: Calendar = .current) -> Double {
    let minute = calendar.component(.minute, from: date)
    return Double(readingHour(at: date, calendar: calendar)) + Double(minute) / 60
  }

  /// Which phase to draw at [date].
  ///
  /// **Derived here, never read from the snapshot.** The app writes no phase flag, because an
  /// entry generated at 22:00 has to still be right at 00:05 when the day has turned — a
  /// baked-in "late" would have the widget insisting it is late at nine the next morning.
  ///
  /// The three live cases mirror `currentStreakProvider`'s rule exactly: a run ending *today*
  /// is recorded, a run ending *yesterday* is still current with the day merely open, and
  /// anything older is over. That last case is why this is worth building at all — a reader
  /// four days lapsed is who the nudge is for, and is exactly who is not opening the app.
  func phase(at date: Date, calendar: Calendar = .current) -> StreakDayPhase {
    guard let last = lastRecordedDay(calendar: calendar) else { return .broken }
    let today = readingDay(at: date, calendar: calendar)

    if last == today { return .recorded }

    guard
      let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
      last == yesterday
    else { return .broken }

    return readingHour(at: date, calendar: calendar) >= warningHour ? .openLate : .open
  }

  /// Which tier an unrecorded tile is drawing, derived from the entry's own hour.
  ///
  /// Same rule as the phase and for the same reason: a written tier would be a second baked-in
  /// phase with a shorter shelf life — six of them a day rather than two.
  func tier(at date: Date, calendar: Calendar = .current) -> StreakTier {
    StreakTier.forHour(readingHour(at: date, calendar: calendar))
  }

  /// The figure to print: the run while it is alive, and nothing once it is not.
  ///
  /// A broken run shows 0 here and the view prints `longestStreak` beside it as the record —
  /// `sc-broken`'s rule, which is that the record survives and the reader is not shown a zero
  /// where their number used to be.
  func run(at date: Date, calendar: Calendar = .current) -> Int {
    phase(at: date, calendar: calendar) == .broken ? 0 : streak
  }

  /// The line under the figure, or nil when the state has nothing to add.
  ///
  /// **Recorded has no line, in any voice, and that is the decision rather than an omission.**
  /// The reference's own recorded tiles carry a figure and nothing else: the lit flame already
  /// says the thing, and a sentence under it would be the tile explaining its own drawing — the
  /// same defect that withdrew the streak page's italic line. `copy.todayDone` is consequently
  /// unread here; it stays in the snapshot because it is what a future surface with no flame
  /// (the way the home-screen widget's *own* copy once was) would have to say in words.
  ///
  /// **The `lines`-absent fallback is load-bearing, not politeness.** It is the only reason the
  /// schema version stayed at 1: a widget updated ahead of the app reads a snapshot with no
  /// `lines` and must still draw phase 1's two sentences. Deleting either `??` below turns an
  /// additive field into a breaking one and the tile goes blank on every reader mid-rollout.
  func line(at date: Date, calendar: Calendar = .current) -> String? {
    let phase = self.phase(at: date, calendar: calendar)
    if phase == .recorded { return nil }

    // Broken, or a live-looking snapshot with nothing in it, gets the invitation's voice and
    // never the day's. The escalation is a function of an unrecorded day *inside a live run*,
    // and of 137 profiles in production exactly one has a reading day at all — so a reader who
    // has not started must never meet the 23:00 line. See `StreakTileStyle` for the other half
    // of this rule, which pins the same states to the dawn ground.
    if phase == .broken || run(at: date, calendar: calendar) == 0 {
      return lines?.none ?? copy?.nothingYet ?? "Record a night and it starts here."
    }

    let late = phase == .openLate
    let fallback =
      late
      ? (copy?.todayLate ?? "Nearly midnight. A page is enough.")
      : (copy?.todayOpen ?? "A page is enough. Today counts until midnight.")
    return lines?[tier(at: date, calendar: calendar)] ?? fallback
  }

  /// The next rollover after [date] — the moment the reading day, and so every phase and tier
  /// on the tile, turns over.
  ///
  /// **This used to be `nextBoundary`, which returned the warning hour when it was still ahead,
  /// and the timeline used it twice to make three entries. The reasoning behind that was
  /// wrong.** It held that a per-hour timeline "burns the refresh budget iOS grants and then
  /// visibly stalls", but the budget iOS meters is *reloads* — calls to `getTimeline` — and
  /// entries inside one timeline are rendered at their own dates without waking the extension.
  /// So the warning hour no longer needs singling out: it is one of the hours the walk in
  /// `getTimeline` already emits.
  func nextRollover(after date: Date, calendar: Calendar = .current) -> Date {
    let today = readingDay(at: date, calendar: calendar)
    // `readingDay` hands back a date-only value in the *reading* calendar, so the instant the
    // next one begins is tomorrow's midnight plus the rollover — which at the shipped
    // `rolloverHour` of 0 is simply tomorrow's midnight, the boundary the OS already thinks in.
    guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
      return date.addingTimeInterval(3600)
    }
    return calendar.date(byAdding: .hour, value: rolloverHour, to: tomorrow) ?? tomorrow
  }
}
