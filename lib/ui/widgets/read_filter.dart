import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/native_glass.dart';

/// The years a set of read books spans, newest first, with `0` for "all time"
/// leading.
///
/// Derived from the books rather than queried, which is the whole reason
/// `finishedBooksProvider` stopped taking a year: a year-filtered query can only
/// ever report the year you asked for.
///
/// Returns just `[0]` when a filter could not change anything — one year of
/// reading and nothing undated means "all time" and that year select the same
/// books, and a control whose options are indistinguishable is noise.
List<int> readFilterYears(List<Book> books) {
  final years = <int>{
    for (final book in books)
      if (book.finishDate != null) book.finishDate!.year,
  }.toList()..sort((a, b) => b.compareTo(a));
  final hasUndated = books.any((b) => b.finishDate == null);
  if (years.length < 2 && !(hasUndated && years.isNotEmpty)) return [0];
  return [0, ...years];
}

/// Filters the read view by year. `0` is all time.
///
/// Two shapes for one piece of state, because the sheet it lives in has two sizes:
///
///  * **expanded** — a capsule row under the header. Room for it exists, and
///    seeing the years at once is the point when you are browsing a grid.
///  * **collapsed** — a popover select in the header. Capsules there would cost
///    the whole spine pile, which is the only thing the collapsed state shows.
///
/// Both are the platform's own controls on iOS 26 and fall back to Flutter
/// elsewhere.
class ReadFilter extends StatelessWidget {
  final List<int> years;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Which shape to take. The sheet decides, since it knows its own state.
  final bool expanded;

  /// Inert while the library is being edited, like the rest of the sheet.
  final bool enabled;

  const ReadFilter({
    super.key,
    required this.years,
    required this.selected,
    required this.onChanged,
    required this.expanded,
    this.enabled = true,
  });

  /// `0` is all time; every other value is a year the user finished a book in.
  ///
  /// Goes through `yearLabel` rather than interpolating the number, because
  /// Korean writes a year as "2026년" and a bare `'$year'` would drop the 년.
  String _label(BuildContext context, int year) {
    final l10n = AppLocalizations.of(context);
    return year == 0 ? l10n.allTime : l10n.yearLabel(year);
  }

  @override
  Widget build(BuildContext context) {
    // One year and it is "all time": nothing to filter, so no control.
    if (years.length < 2) return const SizedBox.shrink();
    return expanded ? _capsules(context) : _popover(context);
  }

  /// A segmented control is exactly what a short list of mutually exclusive
  /// options is for, so on iOS 26 this is the native one — Liquid Glass, system
  /// selection animation and haptics.
  Widget _capsules(BuildContext context) {
    final labels = [for (final y in years) _label(context, y)];
    final index = years.indexOf(selected).clamp(0, years.length - 1);

    if (useNativeGlass) {
      return SizedBox(
        width: double.infinity,
        child: CNSegmentedControl(
          labels: labels,
          selectedIndex: index,
          // Untinted for the same reason `BookStatusSelector` is: the control
          // exposes one tint and no label colour, so tinting the selected segment
          // leaves the system's dark label on a dark thumb.
          // Gated inside the callback rather than by passing null: the native
          // control's `onValueChanged` is non-nullable.
          onValueChanged: (i) {
            if (enabled) onChanged(years[i]);
          },
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < years.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _Capsule(
              label: labels[i],
              selected: i == index,
              onTap: enabled ? () => onChanged(years[i]) : null,
            ),
          ],
        ],
      ),
    );
  }

  /// A real `UIMenu` with Liquid Glass on iOS 26; a Material menu elsewhere.
  Widget _popover(BuildContext context) {
    final label = _label(context, selected);

    if (useNativeGlass) {
      return ConstrainedBox(
        // Same idiom as `shelf_selector.dart`. `shrinkWrap` is the load-bearing
        // part: without it the platform view has no intrinsic width and simply
        // fills whatever the header gives it, which on device came out as a glass
        // pill across half the header rather than the compact select the drawings
        // show.
        constraints: const BoxConstraints(maxWidth: 160),
        child: CNPopupMenuButton(
          buttonLabel: label,
          buttonStyle: CNButtonStyle.glass,
          height: 36,
          shrinkWrap: true,
          items: [
            for (final year in years)
              CNPopupMenuItem(
                label: _label(context, year),
                checked: year == selected,
              ),
          ],
          onSelected: (i) {
            if (enabled) onChanged(years[i]);
          },
        ),
      );
    }

    return PopupMenuButton<int>(
      enabled: enabled,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final year in years)
          PopupMenuItem(value: year, child: Text(_label(context, year))),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible so a squeezed header ellipsizes the label instead of
          // overflowing: the sheet hands this whatever the title leaves, and an
          // accessibility-sized "All time" is wider than that.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _Capsule({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? context.colors.surfaceVariant : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected
                  ? context.colors.brandText
                  : context.colors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}
