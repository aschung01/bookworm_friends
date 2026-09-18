import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';

/// How far the row's tap target reaches below its own ink.
///
/// The row draws 30pt and a touch target has to be 44, so the missing 14 is taken
/// **out of the band's 16pt bottom padding** rather than added to the layout — see
/// [kBandProgressRowResidualPadding]. The band's height is therefore unchanged by
/// making this row tappable, which is the whole point: the band sits above a pinned
/// tab strip on the one screen whose last redesign was about lifting content up.
const double kBandProgressRowSpill = 14;

/// What is left of the band's bottom padding once [kBandProgressRowSpill] is taken
/// out of it. 16 − 14.
const double kBandProgressRowResidualPadding = 2;

/// How far the row's leading text is inset, so it shares a left edge with the status
/// chip in the period card above it.
///
/// **The period card is inset 10pt inside the band**, so its badge's box sits at x40
/// while the band's own content edge — and therefore this row — is at x30. Matching it
/// lines the row's text up with the *chip's edge*, which is the object above it, rather
/// than with the letters inside the chip (x51, which reads as over-indented against the
/// card).
///
/// **Applied to both of the row's states, and that is the point.** Indenting only the
/// prompt would move the text 10pt left at the instant the reader answered — the one
/// moment they are looking straight at it.
///
/// **The trailing half does not move.** The chevron column at x362 was settled
/// separately and by pulling the *card's* glyph out to meet this row, so shifting the
/// percent or the chevron here would undo that.
const double kBandProgressRowTextInset = 10;

/// The reading position, printed on the band and tappable.
///
/// `p.147 / 320` on the left, `46%` on the right, a chevron last, **directly on the
/// grey band**. It is deliberately not wrapped in a card and not grouped into a
/// section with the period card above it; both were drawn (`cl-edge-sec`, the `bd-*`
/// family) and neither was chosen. Wrapping it in the app's own field ground costs a
/// permanent 27pt and opens the same sheet the bare row does, so it is this row plus
/// a tax rather than a different option.
///
/// **Why this row is the door and the app bar's pencil was not.** The row is 333×30
/// in the thumb's arc; the pencil was 48×48 at x341–389 in the top-right dead zone.
/// That is over four times the area, for an act done perhaps thirty times per book
/// against three status changes.
///
/// **Nothing else may be put in here.** A tappable row cannot contain a second,
/// smaller tappable object without repeating the failure of a 44pt ring drawn around
/// a 22pt chip. The streak chip's home is the library bar, not this row.
///
/// ## The prompt state, and why the row exists before the value does
///
/// With no position recorded the row draws `How far in? ›` — **no numbers, and no
/// bar.** That distinction is the whole of it. The rule the migration states is that
/// null draws *no bar*, because an empty track is a **claim**: it says the reader
/// started and got nowhere, and every book in the library would make that claim on the
/// day this shipped. A prompt is not a claim, so the rule does not reach it.
///
/// Drawing the row only once a value existed — which is what shipped first — left the
/// band with **no door for the first set**, which is the one moment every book passes
/// through. It also made the feature invisible: the streak chip hides at 0 too, so a
/// fresh install showed no trace of any of this until someone happened to open the
/// status sheet.
///
/// The cost is **40pt**, measured rather than estimated: the tab strip moves 390.5 to
/// 430.5 on a 390x844 device. Real, on the screen whose last redesign was about
/// lifting the reading books higher — but paid *only* while there is no position, and
/// it disappears the moment the reader answers.
class BandProgressRow extends StatelessWidget {
  const BandProgressRow({
    super.key,
    required this.progress,
    required this.pageCount,
    this.onTap,
  });

  /// The stored fraction 0..1, or null when nothing has been recorded.
  ///
  /// Null draws the prompt rather than `0%`: "never asked" and "at the very start"
  /// are different states, and only one of them is a thing the reader said.
  final double? progress;

  /// Turns the fraction into a page, or leaves the left-hand side empty. Null for
  /// about two reading books in three.
  final int? pageCount;

  /// Opens the percent wheel. **Null on a friend's book**, which drops the chevron
  /// and the tap target: the read-out stays legible, but a door nobody can open must
  /// not draw a handle.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = progress;
    final tappable = onTap != null;

    // Nothing to read and nothing to do. The caller does not ask for this — a
    // friend's book with no position gets no row at all — but a row that is neither
    // an answer nor a prompt would be a bare chevron on an empty line, so it is
    // refused here rather than left to every call site to remember.
    if (value == null && !tappable) return const SizedBox.shrink();

    final row = value == null
        ? Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: kBandProgressRowTextInset),
                child: Text(
                  l10n.howFarIn,
                  // `secondaryText`, not `brandText`. The numbers it will be replaced
                  // by are the row's answer and wear the brand; this is the app's own
                  // no-value-yet tone, the same one `ProgressFieldRow` uses for
                  // "Select". Same token and size as the numbers, so answering does
                  // not change the row's height.
                  style: AppTextStyles.label.copyWith(
                    color: context.colors.secondaryText,
                  ),
                ),
              ),
              const Spacer(),
              _chevron(context),
            ],
          )
        : Row(
            children: [
              if (pageCount != null)
                // Two spans rather than one string, so the total can sit back at 60%
                // opacity: the page is the answer and the count is only context.
                Padding(
                  padding: const EdgeInsets.only(
                    left: kBandProgressRowTextInset,
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: AppTextStyles.label.copyWith(
                        color: context.colors.brandText,
                      ),
                      children: [
                        TextSpan(
                          text: l10n.progressPage(
                            bookProgressPage(value, pageCount)!,
                          ),
                        ),
                        TextSpan(
                          text: ' ${l10n.progressOfPages(pageCount!)}',
                          style: TextStyle(
                            color: context.colors.brandText.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                // Not localized: a numeral and a percent sign, which sit the same way
                // round in both supported locales.
                '${(value * 100).round()}%',
                style: AppTextStyles.label.copyWith(
                  color: context.colors.brandText,
                ),
              ),
              if (tappable) _chevron(context),
            ],
          );

    if (!tappable) return SizedBox(height: 30, child: row);

    return GestureDetector(
      onTap: onTap,
      // Opaque, or the 14pt of empty spill below the ink is not hit-testable and
      // the target is back to 30.
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: kBandProgressRowSpill),
        child: SizedBox(height: 30, child: row),
      ),
    );
  }

  /// The same glyph in both states, and the same one the period card carries — or the
  /// two rows stop reading as peers.
  Widget _chevron(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Icon(
      Icons.chevron_right,
      size: 20,
      color: context.colors.secondaryText,
    ),
  );
}
