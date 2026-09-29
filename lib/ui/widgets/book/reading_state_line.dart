import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';

/// The gap between the line's parts, and the gap between its runs when it wraps.
///
/// 8 horizontally is the drawing's `gap: 8pt`. 2 vertically is deliberately much
/// tighter than a paragraph's leading: when the page pair drops under the percent
/// the two runs must still read as **one** read-out, and the moment the run gap
/// approaches the line height the wrap looks like the two-line layout this whole
/// design merged away.
const double _gap = 8;
const double _runGap = 2;

/// The book's whole state on one line: status word, percent, page inside the total.
///
/// `Reading  46%  p.213 / 462`. Three of those parts are doors — the percent opens
/// the wheel, the page opens the same wheel in Page mode, the total opens the
/// total-pages sheet — and the line is the only read-out above the draggable track.
///
/// **One line, not two, and that is the point of the whole merge.** The status sheet
/// and the percent sheet each owned half of this state and a reader had to visit both
/// to learn it; a second line here would re-separate the two facts that were brought
/// together. It is also why the status word is *in* this line rather than in a chip
/// above it: a chip is a second object making the same claim.
///
/// ## Only the page numerals are underlined
///
/// The percent is equally tappable and carries **no** underline. It is the largest
/// thing on the line (20pt against the pair's 13) and obviously the value, where the
/// page numerals are small and sit inside a phrase — a phrase whose tappable parts
/// are not otherwise discoverable. Underlining all three made *three competing
/// affordances out of one read-out*, which is the objection that was raised against an
/// earlier draft and is recorded here because it has been re-litigated once already.
/// Do not "finish the job" by marking the percent.
///
/// ## The page pair reuses two existing strings, and prints `/` rather than `of`
///
/// `l10n.progressPage` is `p.{page}` under `en` and `{page}쪽` under `ko` — a prefix in
/// one locale and a suffix in the other — and `l10n.progressOfPages` is `/ {total}`.
/// Together they render `p.213 / 462` and `213쪽 / 462`.
///
/// **A deliberate deviation from the drawing**, which shows `p.213 of 462`. Spelling
/// `of` would need a third key, a written Korean translation of a word that has no
/// natural Korean equivalent in this position, and a second phrasing for the locale
/// where the page number is a suffix. Reusing the two keys the band already ships
/// keeps both locales correct for free, and `/` is what the band's deleted progress row had been
/// printing all along — so this is the app agreeing with itself rather than a
/// compromise.
///
/// **Each whole span is underlined, not just its digits.** The digits are embedded in
/// the placeholder (`p.213`, `213쪽`) and sit on a different side of the surrounding
/// text in each locale, so there is no locale-independent way to split a formatted
/// string into "the number" and "the rest" — any attempt is either a regex over
/// translated output or a second set of keys holding the affixes. Underlining the span
/// is also the truer affordance: the whole span is the tap target.
///
/// ## A derived page reads the same as a given one, and used to not
///
/// [progressPage] non-null means the reader typed a page and it is printed as typed;
/// null means it was computed from the fraction. **Both print `p.213` now.** The derived
/// case used to be `l10n.progressApproxPage` — `~ p.213` — and the tilde was removed on
/// instruction, taking the ARB key with it.
///
/// What the mark was for: in percent mode the wheel has 101 stops, so at 320 pages a stop
/// is 3.2 pages and p.148 is not expressible, and a reader who aimed at it lands on p.147.
/// The tilde was where that was admitted. **So the cost of losing it is that the line now
/// states a page the app computed as though the reader had said it** — off by up to a
/// stop's worth. Small, and the reason it is affordable is that the same tilde appeared
/// under the percent wheel too: one mark meaning "derived" in two places and nothing in a
/// third is read as a rendering glitch rather than as a distinction.
///
/// **It is not the reason `progress_page` is stored**, which this section used to claim.
/// The column earns its place by making a typed page round-trip exactly — `given` still
/// decides the number here, it just no longer decides the format — and that is untouched.
///
/// The derived page comes from [bookProgressPage] and is **never recomputed here**.
/// That free function is the app's single rounding site precisely so the band, the
/// wheel's rider and this line cannot disagree about which page 46% of 320 is; the
/// drawings did exactly that before it existed.
///
/// ## No page count is the majority case
///
/// About two reading books in three have no `page_count` — Kakao supplies none at all
/// — and then the pair is replaced by one underlined `l10n.addTotalPages`. It does
/// **not** render `p.213 of —`: a dash is not a total, and a read-out with a hole in it
/// invites the reader to look for the missing number rather than to supply it. Filling
/// the total in is what lights up Page mode, the derived page and the widget's page
/// read-out for a book that never had them, so the majority case is an offer.
///
/// ## A door nobody can open must not draw a handle
///
/// All three callbacks are independently nullable. Null drops the tap target *and* the
/// underline, and drops the page pair's ink from `primaryText` to `secondaryText`, so
/// the part reads as the ambient context it is. On a friend's book all three are null
/// and the whole line is plain text — the existing house rule, and the same one
/// the band's deleted progress row applied to its chevron.
///
/// ## The status word is a parameter, not a derivation
///
/// [statusLabel] and [statusColor] arrive from the caller. This widget deliberately
/// does **not** import `BookStatusBadge` or the `bookStatus*` constants and does not
/// map an int to a word. The caller owns that mapping, so the badge and this line
/// cannot drift — which matters more than usual here, because `BookStatusBadge`'s
/// `switch` ends in a soft `_ => statusOther` fallback that no test catches, and a
/// second copy of the mapping would be a second place for a new status to come out
/// wrong.
///
/// ## Wrapping, not ellipsising
///
/// A [Wrap], so under type pressure the page pair drops to a second run while the
/// status word and the percent stay whole. **No part sets `TextOverflow.ellipsis`
/// anywhere**, on purpose: the longest English case is `Set aside  46%  p.213 / 462`
/// and Korean is longer, and a clipped status word is the one failure that makes the
/// line lie about the book. `RenderWrap` hands each child the Wrap's own `maxWidth`,
/// so a single part too wide for the line soft-wraps inside itself rather than
/// overflowing — which is what keeps `Add total pages` (the longest single part) safe
/// at 2× scale on a 375pt phone.
///
/// A `Row` was the first attempt and cannot do this: its children have no run to drop
/// to, so the only degradations available are overflow and ellipsis.
///
/// **Baseline alignment is not available and [WrapCrossAlignment.end] is the
/// substitute.** `Wrap` has no baseline cross-alignment, and the two routes that do
/// have one were both rejected: a `Baseline` wrapper needs an ascent in points, which
/// cannot be read off a `TextStyle` without laying the text out and which no constant
/// survives 2× scale — the very case this widget exists to survive; and `Text.rich`
/// with baseline-aligned `WidgetSpan`s can only be spaced by a space *character*,
/// whose width is the font's rather than the drawing's 8pt, because a `SizedBox` gap
/// inside a paragraph is not a line-break opportunity and would take the wrapping away
/// again. `end` puts the 13pt run's descender line on the 20pt run's, so its baseline
/// hangs a little under 2pt low at 1× — visible only if you measure it, against a
/// wrapping failure that is visible to everyone.
///
/// ## Pure presentation
///
/// No providers, no writes, no clock. Everything it draws it was handed.
class ReadingStateLine extends StatelessWidget {
  const ReadingStateLine({
    super.key,
    required this.statusLabel,
    required this.statusColor,
    required this.progress,
    this.progressPage,
    this.pageCount,
    this.onPercentTap,
    this.onPageTap,
    this.onTotalTap,
  });

  /// The status word, already localized and already mapped from the book's `status`.
  ///
  /// A `String` rather than an int for the reason in the class doc: one mapping, owned
  /// by the caller.
  final String statusLabel;

  /// The ink for [statusLabel], chosen by the same caller that chose the word.
  ///
  /// A [Color] rather than a token name so this file needs no opinion about which
  /// status is green — *green-means-reading is load-bearing across the app* and the
  /// badge is where that is decided.
  final Color statusColor;

  /// The stored fraction 0..1, or null when nothing has been recorded.
  ///
  /// **Null is not `0`.** `0%` is a position the reader chose; null is the absence of
  /// one, and collapsing them would have every book in the library claim its reader
  /// started and got nowhere. So null draws the status word **alone** — no percent, no
  /// page pair, and no `Add total pages` either, since the whole right-hand region
  /// answers *where in the book* and there is no answer yet to qualify. The same
  /// distinction the band's deleted progress row and progress field both made.
  final double? progress;

  /// The page the reader typed, or null when the position arrived as a percent.
  ///
  /// **Provenance, not position** — [progress] is always the position. Null is the
  /// ordinary case and is not a missing value; it selects the `~` form.
  ///
  /// Printed as given, and not re-derived through [bookProgressPage], even when it
  /// disagrees with `progress * pageCount` after a total was corrected. A page past a
  /// later-corrected count is still the page the reader said, which is what
  /// [Book.progressPage] promises.
  final int? progressPage;

  /// The book's total, or null for about two reading books in three.
  ///
  /// Null replaces the whole pair with the `Add total pages` door — including when
  /// [progressPage] is set, because a lone `p.213` with nothing to sit inside is the
  /// one place a page would survive after its count went missing.
  final int? pageCount;

  /// Opens the percent wheel. Null drops the tap target; the percent has no underline
  /// to drop.
  final VoidCallback? onPercentTap;

  /// Opens the same wheel in Page mode. Null drops the underline and the tap target.
  final VoidCallback? onPageTap;

  /// Opens the total-pages sheet, from either the total or the `Add total pages`
  /// stand-in. Null drops the underline and the tap target — which is also how this
  /// line ships before that sheet exists.
  final VoidCallback? onTotalTap;

  /// The status word and the percent, at the drawing's 20pt.
  ///
  /// [AppTextStyles.titleUser] is the app's only 20pt token and is sans, which is what
  /// the read-out is drawn in. [AppTextStyles.subtitle] was the alternative and
  /// collapses the hierarchy the design leans on — 17 against the pair's 13 is a ratio
  /// of 1.31 where the drawing's 20/12 is 1.67, and "the percent is obviously the
  /// value" is the entire argument for it carrying no underline.
  /// [AppTextStyles.title] is 22pt but is the *serif*, which sets pages and book
  /// titles; a percent is a figure.
  static const TextStyle _wordStyle = AppTextStyles.titleUser;

  /// The percent, which is [_wordStyle] plus tabular figures.
  ///
  /// The numerals change under the reader's thumb while they drag the track. With
  /// proportional figures `9%` and `11%` are different widths, so the line would
  /// reflow — and at the wrap boundary it would gain and lose a second run — several
  /// times per drag.
  ///
  /// **A `copyWith` on the token rather than a `TextStyle` of its own, and that is a
  /// correction.** It was written out in full, restating `titleUser`'s 20/w600 in order to
  /// add the figures without touching a token authored to set a username. That reasoning is
  /// half right and the shape was wrong twice: `test/text_style_test.dart` flags a bare
  /// `fontSize`/`fontWeight` in a widget, on the grounds that *"a call site that needs a
  /// size the scale does not have is telling you the scale is wrong, not that it needs an
  /// exception"* — and this call site needs no such size, it needs the one the token
  /// already has. Restating the metrics also made them a second copy free to drift from the
  /// token they were copied from.
  ///
  /// `fontFeatures` and `decoration` are *additions* rather than overrides, so the
  /// username's typography stays the single authored source of both size and weight.
  static final TextStyle _percentStyle = AppTextStyles.titleUser.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
    // Stated, not merely omitted. This is the part that keeps getting marked, so the
    // style says out loud that it is not underlined.
    decoration: TextDecoration.none,
  );

  /// The page pair and the `Add total pages` stand-in.
  ///
  /// [AppTextStyles.label] already carries tabular figures, which the pair needs for
  /// the reason the percent does: the page is re-derived on every frame of a drag.
  static const TextStyle _pageStyle = AppTextStyles.label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final value = progress;

    // **Two groups, so the page pair can sit at the right edge.**
    //
    // The line was one flat run packed left — `Reading  71%  ~ p.307 / 432` — and the page
    // pair was asked for at the rightmost. That needs a free-space distribution, and
    // `WrapAlignment.spaceBetween` over the *flat* list is not it: with four children it
    // would spread all four evenly and float the percent somewhere in the middle. Over two
    // it does exactly the right thing, because `spaceBetween` puts the first child at the
    // leading edge and the last at the trailing one.
    //
    // **Nested `Wrap`s rather than a `Row` with a `Spacer`**, which is the obvious spelling
    // and throws away the degradation this widget exists for. See the class doc: a `Row`'s
    // children have no run to drop to, so its only failures are overflow and ellipsis, and a
    // clipped status word is the one failure that makes the line lie about the book. Nested,
    // each group is handed the outer `Wrap`'s own `maxWidth`, so a group too wide for the
    // line soft-wraps inside itself and `Add total pages` stays safe at 2× scale on a 375pt
    // phone.
    //
    // When the two groups will not fit side by side the pair drops to a second run and lands
    // **left**, because `spaceBetween` leaves a lone child in a run at the start. That is the
    // right answer for the wrapped case — a dropped run reads as a continuation, and
    // right-aligning it would open a ragged gutter mid-read-out.
    //
    // `WrapCrossAlignment.end` is on the outer Wrap as well as the inner ones, so the 13pt
    // group's descender line still sits on the 20pt group's. The class doc explains why that
    // is the substitute for a baseline alignment `Wrap` does not have.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      alignment: WrapAlignment.spaceBetween,
      spacing: _gap,
      runSpacing: _runGap,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: _gap,
          runSpacing: _runGap,
          children: [
            Text(
              statusLabel,
              // `decoration: none` is not redundant, and a render is what proved it.
              // `Text` merges its style **onto** the ambient `DefaultTextStyle`, so a
              // property this widget leaves unset is whatever the ancestor says -- and
              // `MaterialApp`'s own fallback default, the one in force whenever there is
              // no `Material` or `Scaffold` above (`_errorTextStyle` in
              // `material/app.dart`), carries `TextDecoration.underline`. A preview
              // harness without a `Scaffold` drew this word underlined for exactly that
              // reason. On a line whose entire contract is *which two of three parts are
              // marked*, inheriting an underline is not a risk worth leaving open.
              style: _wordStyle.copyWith(
                color: statusColor,
                decoration: TextDecoration.none,
              ),
            ),
            if (value != null)
              _Door(
                onTap: onPercentTap,
                // No underline, in either state. See the class doc — this is the part
                // that keeps getting marked and must not be.
                child: Text(
                  // Not localized: a numeral and a percent sign, which sit the same way
                  // round in both supported locales. Rounded the way the band rounds it.
                  '${(value * 100).round()}%',
                  style: _percentStyle.copyWith(color: colors.primaryText),
                ),
              ),
          ],
        ),
        // The trailing group. Absent entirely at the origin, which is why the status word
        // stays left there rather than being pushed anywhere by a `spaceBetween` with
        // nothing to space against: one child in a run sits at the start.
        if (value != null)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: _gap,
            runSpacing: _runGap,
            children: _pagePair(context, l10n, value),
          ),
      ],
    );
  }

  /// The page inside the total, or the offer to supply the total.
  List<Widget> _pagePair(
    BuildContext context,
    AppLocalizations l10n,
    double value,
  ) {
    final total = pageCount;
    if (total == null) {
      return [_pageDoor(context, l10n.addTotalPages, onTotalTap)];
    }

    final given = progressPage;
    // The single rounding site. `total` is non-null and `value` is non-null, so this
    // cannot return null — the `!` is the type system catching up with the two checks
    // above it rather than an assumption.
    final page = given ?? bookProgressPage(value, total)!;

    return [
      // One label for both cases. `given` still decides the *number* — a typed page is
      // printed as typed rather than re-derived — it just no longer decides the format.
      _pageDoor(context, l10n.progressPage(page), onPageTap),
      _pageDoor(context, l10n.progressOfPages(total), onTotalTap),
    ];
  }

  /// One span of the pair: underlined `primaryText` when it is a door, plain
  /// `secondaryText` when it is not.
  ///
  /// **The weight does not change with the state**, though the drawing sets the
  /// underlined spans a step heavier. A weight change is a width change, so a friend's
  /// copy of a line and your own would wrap at different points — and the two would be
  /// impossible to compare in a screenshot, which is how this line gets reviewed.
  ///
  /// Flutter has no `text-underline-offset` and its `decorationThickness` is a
  /// multiple of the font's own underline metric rather than a length, so the drawing's
  /// 1.25pt rule at a 2.5pt offset is not expressible in points. Left at the font's
  /// defaults rather than approximated with a magic multiplier.
  Widget _pageDoor(BuildContext context, String label, VoidCallback? onTap) {
    final colors = context.colors;
    final isDoor = onTap != null;
    return _Door(
      onTap: onTap,
      child: Text(
        label,
        style: _pageStyle.copyWith(
          color: isDoor ? colors.primaryText : colors.secondaryText,
          decoration: isDoor ? TextDecoration.underline : TextDecoration.none,
          // Pinned for the reason the status word's `none` is pinned: unset means
          // inherited, and the ambient fallback's underline is a *yellow double*
          // rule. The mark has to be one solid line in the span's own ink whatever
          // it is nested inside.
          decorationColor: isDoor ? colors.primaryText : null,
          decorationStyle: TextDecorationStyle.solid,
        ),
      ),
    );
  }
}

/// A part of the line that may or may not be tappable.
///
/// When it is not, it returns the text **bare** — no `GestureDetector`, no `Semantics`
/// and no inert wrapper — so nothing on a friend's book advertises a gesture that does
/// nothing, to the finger or to VoiceOver.
///
/// `button: true` is not decoration: the underline is the only visual affordance these
/// spans have and a screen reader cannot see it, so without this the three doors are
/// announced as three pieces of text. `HitTestBehavior.opaque` so the span's own
/// bounding box is the target rather than its glyphs.
///
/// **The targets are smaller than 44pt and that is accepted rather than overlooked.**
/// At 1× the pair measures about 33×16 and 34×16 and the percent about 45×23. Reaching
/// 44 would need ~14pt of vertical padding on *every* part — on the status word too,
/// or [WrapCrossAlignment.end] would shift the pair's underline up relative to it —
/// which is 28pt added to a line inside a 270pt sheet whose shortness is the merge's
/// headline number. The coarse control is the track directly below, which is 44pt and
/// spans the sheet; these numerals are the exact path, taken rarely and deliberately.
class _Door extends StatelessWidget {
  const _Door({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    if (tap == null) return child;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: tap,
        behavior: HitTestBehavior.opaque,
        child: child,
      ),
    );
  }
}
