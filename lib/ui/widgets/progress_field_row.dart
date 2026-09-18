import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';

/// A tappable "How far in? / 46%" field, opening the percent wheel.
///
/// **The sibling of `DateFieldRow`, not a new idiom** — same `surfaceVariant`
/// ground, same radius 10, same `symmetric(h14, v10)`, same 15pt body left and
/// value right, and the same "Select" placeholder in `secondaryText` when
/// nothing has been recorded. A reading position is one more field of exactly the
/// kind the change-status sheet already holds, so it is picked the way a date is.
///
/// **Echoes the unit the reader answered in**, which means a page only when they
/// gave a page. `p.200` appears when [progressPage] is non-null *and* [pageCount]
/// is known; every other row reads `46%`.
///
/// This used to read "shows the percent and not the page, even on a book whose page
/// count is known", on the grounds that a `p.147` here would be a derived label
/// standing in for the thing the wheel actually writes — the confusion that once had
/// the band printing `p.148` beside `p.147`. That objection still holds and this rule
/// does not violate it, because [progressPage] is **not derived**: it is stored, and
/// it is what the reader typed. The row never computes a page from a percent. A
/// reader who said "46%" still sees `46%`, and only a reader who said "p.200" is
/// shown `p.200` — which is the whole point, since 200/432 round-trips through the
/// wheel's 101 stops as p.199.
///
/// Deliberately *not* a glass control, for `DateFieldRow`'s reason: the row sits on
/// an opaque sheet surface with nothing behind it to refract.
class ProgressFieldRow extends StatelessWidget {
  const ProgressFieldRow({
    super.key,
    required this.progress,
    this.progressPage,
    this.pageCount,
    required this.onTap,
  });

  /// The stored fraction 0..1, or null when nothing has been recorded.
  ///
  /// **Null is not `0`.** Null shows the placeholder, `0.0` shows `0%` — "never
  /// asked" against "at the very start". Collapsing them would claim a position for
  /// every book in the library on the day this shipped.
  final double? progress;

  /// The page the reader typed, or null when they answered in percent.
  ///
  /// **Provenance, not position** — [progress] is always the position, and this only
  /// records which unit it arrived in. Null is the ordinary case and is not a
  /// missing value.
  final int? progressPage;

  /// Required alongside [progressPage] before a page is printed.
  ///
  /// Not because the page needs it to render — it does not — but because a book whose
  /// count has since gone missing can no longer show `p.200 / 432` anywhere else in
  /// the app, and a lone `p.200` in a form would be the only place it survived.
  final int? pageCount;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = progress;
    final page = progressPage;
    final showPage = page != null && pageCount != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.howFarIn, style: AppTextStyles.body),
            Text(
              showPage
                  ? l10n.progressPage(page)
                  // Not localized: a numeral and a percent sign, which sit the same
                  // way round in both supported locales.
                  : value != null
                  ? '${(value * 100).round()}%'
                  : l10n.select,
              style: AppTextStyles.body.copyWith(
                color: value != null
                    ? context.colors.primaryText
                    : context.colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
