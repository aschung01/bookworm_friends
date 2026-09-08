import 'package:flutter/material.dart';

/// The two families the app sets, by their `pubspec.yaml` family names.
abstract final class AppFonts {
  /// Everything. Chosen because its Hangul is drawn to its Latin metrics, which
  /// is the actual problem: SF Pro has no Hangul, so before this every Korean
  /// string in the app was a *fallback* — Apple SD Gothic Neo on iOS, Noto Sans
  /// CJK KR on Android — sitting in the same line box as SF Pro Latin with a
  /// different x-height and a different weight ramp.
  ///
  /// Subset to Latin-1 plus the whole Hangul syllable block, because this face
  /// sets arbitrary text: usernames, book titles, memos, shelf names. Hanja or
  /// kana in an imported book title still falls through to the platform font,
  /// exactly as it did before. See `scripts/build_fonts.py`.
  static const String sans = 'Pretendard';

  /// [AppTextStyles.title], [AppTextStyles.hero] and [AppTextStyles.spine].
  ///
  /// Cut to Latin-1 plus **KS X 1001's 2,350 Hangul syllables** — 1.32MB, against
  /// 7.85MB for the whole 11,172-syllable block. The first two tokens set the
  /// app's own words, where coverage is guaranteed by construction; `spine` sets a
  /// book title, which is catalogue text and is not, so the cut has to be a
  /// judgement about what real Korean reaches. KS X 1001 has been that judgement
  /// since 1987, and it holds here: **0 misses** across the 618 distinct syllables
  /// in the 624 titles of `migration_data/book.jsonl`, the 290 in `app_ko.arb`, and
  /// 39 deliberately awkward words — loanword transliterations, foreign names,
  /// double-consonant finals. See `ks_x_1001_hangul` in `scripts/build_fonts.py`.
  ///
  /// **This face has no real bold, and that is a live constraint rather than
  /// trivia.** It ships 400 and 700 only; measured as ink coverage of the same
  /// Hangul string at the same point size, its 700 draws **21.3%** where Pretendard
  /// w700 draws 31.7%. So it reads about where a sans *medium* does, which is why
  /// [display] is Pretendard and why [title] is w700 beside a w600 [titleUser].
  /// Hahmlet was shipped here briefly to get a heavier spine (32.2%) and reverted;
  /// `docs/mockups/spine-type/README.md` has the survey of all seven Korean serifs
  /// on Google Fonts, none of which has both full coverage and a genuine bold.
  ///
  /// Every style using it sets `fontFamilyFallback: [sans]`, so a syllable outside
  /// KS X 1001 renders in Pretendard rather than as a box.
  static const String serif = 'GowunBatang';
}

/// The size an emoji is **drawn** at when it is the object on screen rather than
/// a character in a sentence — a praise picker cell, a reaction beside a name.
///
/// Not in [AppTextStyles], and the separation is the point. An emoji ignores
/// `fontFamily`, `fontWeight` and `letterSpacing` entirely; the only property a
/// type token would contribute is `fontSize`, which here is a graphic dimension
/// no different from an [Icon]'s `size`. Reaching for a text token to get it
/// silently tied a glyph's size to a title's, so `titleUser` could not be
/// retuned without resizing emoji in two unrelated sheets.
///
/// [AvatarCircle] does not use this: its glyph is sized from the circle it sits
/// in, which is a ratio rather than a constant.
const double kEmojiGlyphSize = 24;

/// The app's type scale.
///
/// ## Why this exists
///
/// [AppTheme] used to set no `textTheme` at all. `Material` seeds
/// `DefaultTextStyle` from `theme.textTheme.bodyMedium`, and every `Text` merges
/// its local style onto that — so all 88 hardcoded `TextStyle`s in the app were
/// silently inheriting Material 3's **Roboto** metrics:
///
///  * `letterSpacing: 0.25` — Roboto's tracking, applied to every size including
///    the Library Card's 46pt figure. `StatTile` was hand-compensating for this
///    with `letterSpacing: -0.02 * figureSize` without knowing why it had to.
///  * `height: 1.43` — a body line-height on single-line titles, 13pt tab labels
///    and badges, which is why rows measured taller than their padding implied.
///  * `color: black87` in light and **pure white** in dark, rather than
///    [AppColors.primaryText] / `#F1F3F5`. In light that was a near-coincidence;
///    in dark it meant the theme's off-white token was bypassed everywhere a call
///    site did not pass a colour explicitly.
///  * `fontFamily: CupertinoSystemText` on iOS — SF Pro *Text*, the optical size
///    drawn for ≤19pt — used for the 24pt auth title and the 30/46pt figures.
///
/// ## Eight tokens, four weights
///
/// Before this there were thirteen sizes (10.5, 11, 11.5, 12, 12.5, 13, 14, 15,
/// 16, 17, 18, 20, 24, plus 26/30/46 in `StatTile`) and six weight spellings, of
/// which `bold` and `w700` are the same weight written two ways. `bold` appeared
/// 44 times, which is the same as nothing being emphasised.
///
/// Eight rather than seven because [titleUser] is [title]'s metrics in the other
/// family; four weights (400/600/700/800) is what has to be shipped, and it is
/// one more than the three first quoted — w800 exists solely for [display], and
/// the alternative was faux-bolding.
///
/// ## Every token repeats three properties, and that is deliberate
///
/// `textBaseline`, `leadingDistribution` and `letterSpacing` are spelled out in
/// all eight tokens rather than inherited from a shared `_base`, because
/// `TextStyle.copyWith` and `merge` are not `const` and these have to be: a
/// non-const token cannot be used in a `const TextStyle` field, which several
/// widgets here have.
///
/// `textBaseline` is pinned because `material_ko.arb` declares
/// `scriptCategory: dense`, so under `ko` Material's geometry switches to
/// `TextBaseline.ideographic`. Rows that mix Latin and Hangul — the library
/// bar's `username` + `의 서재`, a sheet title beside its count — aligned
/// slightly differently in the two locales, for no reason a reader could see.
///
/// `letterSpacing: 0` is pinned for the reason above: unset, it inherits, and
/// what it inherited was Roboto's.
///
/// ## Colour is deliberately absent
///
/// No token sets a colour. [AppTheme] applies [AppColors.primaryText] to the
/// whole `textTheme`, and a call site that needs another one says so with
/// `.copyWith(color:)`. Baking a colour in here would put a light-mode value in
/// a const and break dark mode silently, which is the class of bug this file was
/// written to close.
abstract final class AppTextStyles {
  /// Tabular figures.
  ///
  /// Nothing in the app set `fontFeatures` before, and Pretendard's default
  /// figures are proportional — `1111` and `8888` differ by 27px at 40px. That
  /// was the sheet count nudging its title as books were added, the
  /// `ReadFilter` capsules reflowing per year, and `ReadMonthGrid`'s per-month
  /// counts failing to line up down the column.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// The Library Card's hero figure. The largest type in the app.
  ///
  /// **Pretendard, not the serif, and this is the decision rather than an
  /// oversight.** The Card's display face is Gowun Batang, whose heaviest weight
  /// is 700 and whose 700 is barely bold — 21.3% ink coverage where Pretendard
  /// w700 draws 31.7% on the same string at the same size. `StatTile`'s own doc
  /// says this figure should be "the thing you see first", and a serif that light
  /// is not. So the figure is Pretendard at w800 and the title beside it carries
  /// the serif: the number is emphatic, the words stay literary. Faux-bolding the
  /// serif to w800 was the alternative and is the one thing worth refusing.
  static const TextStyle display = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 46,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -0.92,
    fontFeatures: _tabular,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Non-hero stat figures.
  static const TextStyle figure = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -0.6,
    fontFeatures: _tabular,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The one-line promise at the top of a full-screen moment: the invite sheet,
  /// the consent screen, the seal after a friendship lands.
  ///
  /// **The serif, and 30pt — [figure]'s size in [title]'s family.** Those two
  /// tokens already bracket this: `figure` is 30pt sans for a number, `title` is
  /// 22pt serif for a page. A full-bleed screen whose entire job is one sentence
  /// needs that sentence to be the largest thing on it, and 22 is not — it is the
  /// size of the library bar behind it. Reusing `display` was the alternative and
  /// is wrong twice: 46pt is a figure's size, not a sentence's, and w800
  /// Pretendard is the app shouting rather than speaking.
  ///
  /// Metrics are lifted from [figure] rather than invented — same `height`, same
  /// `letterSpacing` ratio scaled for the family — so the two sit on a shared
  /// grid. `fontFeatures` is deliberately **not** carried across: this token sets
  /// words, and tabular figures in prose is the wrong default.
  ///
  /// Carries `fontFamilyFallback` for the reason [title] does — [AppFonts.serif]
  /// is subset to `app_ko.arb`. Do not put a username in it; there is no
  /// `heroUser`, and a name in a hero line is a sign the line should be shorter.
  static const TextStyle hero = TextStyle(
    fontFamily: AppFonts.serif,
    fontFamilyFallback: [AppFonts.sans],
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.6,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Page titles — the library bar's own title, and nothing else yet.
  ///
  /// The one place the serif is set. 22pt rather than the 18 it replaced: 18 was
  /// also the size of the sheet title stacked on top of it, so the foreground
  /// element did not read as more important than the page behind it, and neither
  /// read as a page title.
  ///
  /// [AppFonts.serif] is subset to the app's own l10n strings, so this token
  /// carries `fontFamilyFallback` to Pretendard. Use [titleUser] for a title
  /// containing someone's name.
  ///
  /// **w700 while [titleUser] is w600, and the mismatch is the honest spelling.**
  /// Gowun Batang ships one weight, 700, and that is the file `pubspec.yaml`
  /// registers — declaring w600 here would have named a cut that does not exist.
  /// It also happens to be the right *apparent* weight: Gowun Batang Bold draws
  /// 21.3% ink coverage where Pretendard w700 draws 31.7%, so it sits about where
  /// Pretendard's 600 does. Two different numbers for one visual weight is
  /// what having two families costs; see [titleUser].
  static const TextStyle title = TextStyle(
    fontFamily: AppFonts.serif,
    fontFamilyFallback: [AppFonts.sans],
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.4,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// [title]'s metrics in the UI face, for a title that contains user text.
  ///
  /// A username is the reader's content, not the app's voice, and the serif is
  /// subset to the app's own strings. Rendering `아모개의 서재` half in Gowun
  /// Batang and half in Pretendard — which is what the fallback would do — looks
  /// like a bug rather than a choice, so the whole title goes sans instead.
  ///
  /// Same size, height and tracking as [title] so the two are interchangeable in
  /// layout; w600 rather than w700 because that is where Pretendard matches Gowun
  /// Batang Bold by eye. Do not "fix" this to match — w700 Pretendard beside a
  /// serif title is visibly heavier, which is the thing the pairing exists to
  /// avoid.
  static const TextStyle titleUser = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -0.4,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Sheet titles and section headings.
  static const TextStyle subtitle = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.2,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Prose: memos, empty states, dialog copy, anything read as a sentence.
  static const TextStyle body = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Tab labels, shelf tabs, badges, capsules, buttons.
  static const TextStyle label = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0,
    fontFeatures: _tabular,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The title running up a book's spine — the read pile, and the Library
  /// Card's spine layout. Set by [BookVertical] and nothing else.
  ///
  /// **A serif, on the app's most bookish surface.** Until this existed a spine
  /// borrowed [label], whose own doc says "tab labels, shelf tabs, badges,
  /// capsules, buttons" — so in the collapsed Library tab a book title was the
  /// same family and weight as the `Library / Friends / Card` labels 40pt below
  /// it, and it carried [_tabular], which is right for a count and wrong for a
  /// title: `세계를 바꾼 테크놀로지 10` paid monospaced digit advances out of a
  /// measure with none to spare. The serif was already on screen directly above it
  /// — "My Library" is [title] — so this finishes a voice rather than introducing
  /// one.
  ///
  /// [AppFonts.serif] again, after a detour through Hahmlet to get a heavier
  /// spine. The reason it came back is that the detour was not buying what it
  /// looked like it was buying: Hahmlet's upstream has only 2,788 syllables, so its
  /// 1.38MB was never coverage, and at the KS X 1001 cut this face costs **1.32MB**
  /// — *less*. The 7.85MB that made a second serif look cheap was the price of the
  /// full 11,172-syllable block, which no corpus here reaches. So the two cost the
  /// same and this is a decision about how a spine should look, not a budget.
  ///
  /// What it costs in weight is real and worth stating: 21.3% ink coverage against
  /// Hahmlet 700's 32.2%. This is the lighter, quieter option.
  ///
  /// **12pt, one step above the 11 the drawing chose, and the reason is the weight
  /// this face does not have.** Size is the only lever left: 700 is its heaviest
  /// cut, faux-bolding is refused, so more presence has to come from more glyph
  /// rather than more stroke. Note this is *not* the old argument for 12, which was
  /// that Gowun Batang "draws small in its em" — that was measured and is false
  /// (mean Hangul ink height 0.9132em, against Hahmlet's 0.9013em, a 1.3%
  /// difference). 12 is a deliberate step up in size, not a correction to reach
  /// parity.
  ///
  /// It costs about one syllable of measure per line, which a spine can least
  /// afford — see `kSpinePadHead`. That is the trade: a lighter face set larger,
  /// truncating marginally sooner. `7_titles.png` is where to check it still reads.
  ///
  /// w700 because it is the only cut this face ships above 400, and asking for 800
  /// would make the engine synthesise one — see [display] for why that is refused.
  ///
  /// `height` is tight on purpose. A spine may carry two lines across its
  /// thickness, and at 1.08 two lines of 12pt occupy 25.9pt — inside the 33pt
  /// [BookVertical] requires before it will set two. No [_tabular]: a title is
  /// words, and a year in one is not a column to align.
  static const TextStyle spine = TextStyle(
    fontFamily: AppFonts.serif,
    fontFamilyFallback: [AppFonts.sans],
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.08,
    letterSpacing: 0.2,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The uppercase, letterspaced stat label. Pass the string in natural case and
  /// call `toUpperCase()` at the call site — it is a no-op on Korean, which is
  /// the point of not baking the casing into the l10n string.
  static const TextStyle caption = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.9,
    textBaseline: TextBaseline.alphabetic,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Every token, for the guard in `test/text_style_test.dart`.
  static const Map<String, TextStyle> all = {
    'display': display,
    'figure': figure,
    'hero': hero,
    'title': title,
    'titleUser': titleUser,
    'subtitle': subtitle,
    'body': body,
    'label': label,
    'spine': spine,
    'caption': caption,
  };

  /// The `textTheme` [AppTheme] installs.
  ///
  /// Material's roles are mapped onto the tokens rather than the other way
  /// round, because the roles are what the framework reads: `Material` seeds
  /// `DefaultTextStyle` from `bodyMedium`, `AppBar` from `titleLarge`, a
  /// `TextButton` from `labelLarge`. `bodyMedium` is therefore [body] — the sane
  /// thing for an unstyled `Text` to inherit — and the reason a `Text` with no
  /// style of its own now comes out at 15/w400 with zero tracking instead of
  /// Roboto's 14/w400/0.25.
  ///
  /// `titleLarge` is [titleUser], not [title]: `AppBar` and friends can be
  /// handed any string, and only a call site knows whether its title is the
  /// app's own words. The serif is opted into, never inherited.
  static TextTheme textTheme(Color color) {
    const t = TextTheme(
      displayLarge: display,
      displayMedium: display,
      displaySmall: figure,
      headlineLarge: figure,
      headlineMedium: figure,
      headlineSmall: subtitle,
      titleLarge: titleUser,
      titleMedium: subtitle,
      titleSmall: label,
      bodyLarge: subtitle,
      bodyMedium: body,
      bodySmall: label,
      labelLarge: label,
      labelMedium: label,
      labelSmall: caption,
    );
    return t.apply(bodyColor: color, displayColor: color);
  }
}
