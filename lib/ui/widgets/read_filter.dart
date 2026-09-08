import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
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
/// **Includes every year between the earliest finish and the current one,
/// whether or not a given year has a book in it.** A reader who finished books
/// in 2022 and 2024 gets 2022, 2023 and 2024 offered alongside 2025 and 2026 as
/// they pass — 2023 empty is still a year they might scroll back to, and hiding
/// it because it happens to be empty would make the row's meaning depend on
/// reading history rather than on the calendar.
///
/// `now` is a seam for tests; production leaves it as `DateTime.now()`.
///
/// **Never shorter than `[0, currentYear]`, so the control is never absent.** This
/// used to collapse to `[0]` alone — and therefore to no control at all — in the two
/// cases where a filter could not change which books were shown: nothing dated to
/// anchor a range, or exactly one year with nothing before or after it to fill in. The
/// argument was that a control whose options are indistinguishable is noise. The
/// argument against it is stronger and it is what this now does:
///
///  * **The header's shape stopped depending on the library's contents.** A rail that
///    comes and goes moves the furniture at moments the reader did not aim at — logging
///    a first finish in a new year made it appear from nowhere, and 43 of the 55 readers
///    in the migrated data sit on exactly the boundary that decides it.
///  * **"All time" is a scope, not a filter.** A visitor reading a library that is
///    empty, or a year deep, still wants to be told what they are looking at, and
///    `noFinishedBooks` versus `noFinishedBooksInYear` are two different things to be
///    told. Only one of them is reachable if the rail is missing.
///  * The cost is one capsule that selects what is already selected. That is a smaller
///    thing than a control a reader has to discover twice.
///
/// With nothing dated the range is the current year alone: it is the one year we know
/// exists, and it is offered empty for the same reason the gaps are.
List<int> readFilterYears(List<Book> books, {DateTime? now}) {
  final finishYears = <int>{
    for (final book in books)
      if (book.finishDate != null) book.finishDate!.year,
  };

  final currentYear = (now ?? DateTime.now()).year;
  // The range reaches at least the current year even if the last finish is
  // older, and at least the last finish even if it is somehow ahead of today —
  // dates are user-entered, and a clock skew or a typo should not truncate the
  // range, just look odd for a year.
  final earliest = finishYears.isEmpty
      ? currentYear
      : finishYears.reduce((a, b) => a < b ? a : b);
  final latestRead = finishYears.isEmpty
      ? currentYear
      : finishYears.reduce((a, b) => a > b ? a : b);
  final latest = latestRead > currentYear ? latestRead : currentYear;

  return [0, for (var year = latest; year >= earliest; year--) year];
}

/// Filters the read view by year. `0` is all time.
///
/// Two shapes for one piece of state, because the sheet it lives in has two sizes:
///
///  * **expanded** — a row of button-like capsules under the header. Room for it
///    exists, and seeing the years at once is the point when you are browsing a
///    grid. Laid out by Flutter, with real Liquid Glass behind the selected
///    capsule on iOS 26; see [_capsules].
///  * **collapsed** — a popover select in the header. Capsules there would cost
///    the whole spine pile, which is the only thing the collapsed state shows.
///    This one is the platform's own `UIMenu` on iOS 26, with a Flutter fallback.
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
    // A control with one option cannot be operated, so there is nothing to draw.
    // **Unreachable from the app**, since [readFilterYears] always offers at least
    // all time and the current year — it is the guard for a caller that builds
    // [years] by hand, and the reason a one-option rail has no rendering to argue
    // about.
    if (years.length < 2) return const SizedBox.shrink();
    return expanded ? _capsules(context) : _popover(context);
  }

  /// Individual buttons sized to their labels, only the selected one filled —
  /// `decided.html`'s `.caps`, which takes its shape from Flighty's Passport.
  ///
  /// **Not a `CNSegmentedControl`, which is what this was.** That control divides
  /// the full width into equal segments inside a grey track, so
  /// "All time / 2026 / 2025" came out as a full-bleed toolbar with the years
  /// given as much room as the option that actually matters. The drawing is the
  /// opposite: a short row of buttons hugging their text, flush left, with no
  /// track and no fill at all on the ones you did not pick.
  ///
  /// The row is laid out by Flutter, and so is every label — what the platform
  /// lends is the glass *material* behind the selected one. See [_Capsule], which
  /// records the two shapes this went through first and what each got wrong.
  /// `CNGlassButtonGroup` would have made the whole row native, but it puts it in
  /// one SwiftUI `HStack` that centres itself in whatever width it is given and
  /// sizes on a 44pt-per-button estimate, which clips a label like "All time".
  Widget _capsules(BuildContext context) {
    final labels = [for (final y in years) _label(context, y)];
    final index = years.indexOf(selected).clamp(0, years.length - 1);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Flush left and scrollable rather than spread across the width: the row is
      // three options wide for almost everyone, and a long-time reader with eight
      // years of history has to be able to reach 2019.
      //
      // The vertical padding is the selected pill's shadow, and the glass halo on
      // the native path. The viewport clips to its own bounds, so without room
      // inside it either one is shaved off flat against the label.
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          for (var i = 0; i < years.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
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
              style: AppTextStyles.label,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    );
  }
}

/// One option in the capsule row: a label when unselected, a glass pill when
/// selected.
///
/// **Flutter draws the label on every platform; the platform supplies the material
/// behind it.** The selected capsule stacks a native [CNButton] styled
/// `UIButton.Configuration.glass()` under the label with `Positioned.fill`, empty
/// of content and inert, so it acts purely as the pill's material — real Liquid
/// Glass, with the rim highlight and drop shadow that configuration carries.
///
/// Two earlier shapes are worth recording, because each looked right for one
/// reason and wrong for another:
///
///  * **A `CNButton` per option, label and all**, `.glass()` when selected and
///    `.plain()` otherwise. This is where the glass came from, but selecting a
///    year *restyled a live button*, and `CNButton`'s update path is a chain of
///    awaited channel calls: `setStyle` swaps the whole `UIButton.Configuration`,
///    which restores the title as a plain string and so drops the attributed
///    font, and `setLabelStyle` only re-applies 13pt several hops later. For about
///    half a second the label rendered at the system's 17pt in the theme's tint,
///    wrapped onto two lines inside a platform view Flutter had sized for 13pt.
///  * **[LiquidGlassContainer]**, which fixed that by leaving the text to Flutter
///    — but it renders `Capsule().glassEffect(.regular)`, a *bare* glass layer
///    with no material of its own. Glass refracts what is behind it, and behind
///    this is an opaque sheet the platform view is composited over, so it came out
///    flat: no rim, no shadow, barely a pill. (`CNGlassEffect.prominent` would not
///    have helped — the plugin's Swift pins `Glass.regular` either way.)
///
/// So the label stays Flutter's, and the material comes from the button
/// configuration rather than a raw effect. Nothing native holds text, so there is
/// nothing to fall out of sync; and because the button only exists while this
/// option is selected, its style is fixed for its whole life and `setStyle` never
/// runs.
///
/// **Pressing has to be felt on both halves.** The glass button is left
/// interactive, so UIKit gives the selected capsule the press response a real
/// glass button has — `CNButton` watches raw pointers and pushes `isHighlighted`
/// across for it. An unselected capsule has no platform view to do that, so it
/// **shrinks** under the finger instead, which is what Flighty's tab pills do. The
/// scale is deliberately not applied over the native pill: transforming a platform
/// view in hybrid composition is unreliable, and it already has a press response of
/// its own.
class _Capsule extends StatefulWidget {
  final String label;
  final bool selected;

  /// Null while the library is being edited, which is also what makes the pill
  /// stop answering taps.
  final VoidCallback? onTap;

  const _Capsule({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_Capsule> createState() => _CapsuleState();
}

class _CapsuleState extends State<_Capsule> {
  /// Held here rather than taken from the tap recognizer, because the tap may not
  /// be ours: the selected capsule's platform view competes for it in the gesture
  /// arena and usually wins, which would leave `onTapDown` unfired. Raw pointer
  /// events arrive either way.
  bool _pressed = false;

  /// The pill's box, not its type: [AppTextStyles.label] sizes the glyphs and
  /// this is the tap target they sit in, so the two are independent. Shared with
  /// [_glass], whose platform view has to match the box Flutter measured.
  static const double _height = 34;
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 7,
  );

  /// How far a capsule shrinks under the finger. Small enough to read as a press
  /// rather than an animation.
  static const double _pressedScale = 0.94;
  static const Duration _pressDuration = Duration(milliseconds: 110);

  void _setPressed(bool pressed) {
    if (_pressed == pressed || widget.onTap == null) return;
    setState(() => _pressed = pressed);
  }

  void _handleTap() {
    // Gated here rather than by withholding the callback, so an inert pill still
    // looks like itself rather than going grey: the sheet is inert as a whole
    // during an edit, not disabled. Same choice as the collapsed popover.
    if (widget.onTap == null) return;
    // The segmented control this replaced gave selection haptics for free, and
    // glass is a material rather than a behaviour. Asked for explicitly, because
    // the row reshuffles everything under it.
    HapticFeedback.selectionClick();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;

    Widget pill = Padding(
      padding: _padding,
      child: Text(
        widget.label,
        maxLines: 1,
        // **One token for both states**, as Flighty's tab pills are: the pill and
        // the colour below carry the selection between them, and emphasising the
        // chosen label as well made the row look like it had two type sizes.
        style: AppTextStyles.label.copyWith(
          color: selected
              ? colors.primaryText
              // Deliberately not `secondaryText`, which the drawing also passes
              // over: #ADB5BD on white is 2.2:1, and these are options you are
              // expected to read before choosing, not muted captions. Faded
              // `primaryText` lands on the drawn grey in light mode and stays
              // legible in dark. With the weight shared, this and the pill are
              // the whole of what marks the selection.
              : colors.primaryText.withValues(alpha: 0.55),
        ),
      ),
    );

    // The native pill answers a press itself, through UIKit; everything else is
    // shrunk here.
    final nativePill = selected && useNativeGlass;

    if (selected) {
      pill = nativePill ? _glass(pill) : _painted(context, pill);
    }

    if (!nativePill) {
      pill = AnimatedScale(
        scale: _pressed ? _pressedScale : 1,
        duration: _pressDuration,
        curve: Curves.easeOut,
        child: pill,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      child: Listener(
        // Raw pointers, so the press state does not depend on winning the arena.
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          // Opaque, because an unselected capsule has no fill: a bare `Text` inside
          // `Padding` hit-tests only where the glyphs are, so without this the
          // pill's padding — most of its width at short labels like "2026" — is a
          // dead zone.
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _height),
            child: Center(widthFactor: 1, child: pill),
          ),
        ),
      ),
    );
  }

  /// The pill's material: a glass `UIButton` filled in behind the label.
  ///
  /// `StackFit.passthrough` lets the label size the stack and `Positioned.fill`
  /// stretches the button to match it, so the capsule is exactly as wide as its
  /// text with no `getIntrinsicSize` round-trip to wait for.
  ///
  /// **Deliberately not wrapped in an `IgnorePointer`, and interactive.** That is
  /// what makes it feel like a glass button rather than a picture of one:
  /// `CNButton` hangs a `Listener` off the platform view and pushes
  /// `isHighlighted` to UIKit on pointer down, releasing it on up or once the
  /// finger travels past `kTouchSlop`. Letting it see pointers means its own tap
  /// recognizer joins the arena and usually beats the row's — hence the real
  /// callback here rather than a no-op: whichever of the two wins, the year is
  /// reported exactly once.
  Widget _glass(Widget child) {
    return Stack(
      // The glass shadow sits outside the pill's box; the row reserves 3pt for it.
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: CNButton(
            // No content: the label above it is Flutter's, and this is here for
            // the material and its press response only.
            label: '',
            onPressed: _handleTap,
            config: const CNButtonConfig(
              style: CNButtonStyle.glass,
              minHeight: _height,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        child,
      ],
    );
  }

  /// The glass pill imitated in paint, for everything that has no glass to lend:
  /// `surface` fill, a hairline and a soft shadow, per the drawing's `.caps s.on`.
  ///
  /// Chosen by [useNativeGlass] rather than by asking the platform, because the
  /// native path degrades to *nothing*: a `CNButton` off iOS 26 falls back to a
  /// `CupertinoButton`, which would leave the selected option with a stray
  /// Cupertino button behind its label instead of a pill.
  Widget _painted(BuildContext context, Widget child) {
    final colors = context.colors;

    // The drawing fills the selected pill with the *surface* colour and lets the
    // hairline and shadow lift it off the sheet. That only reads on a light
    // sheet: in dark mode a #1E1E1E pill on a #1E1E1E sheet would be carried
    // entirely by a black shadow, i.e. by nothing. `surfaceVariant` is the dark
    // theme's one-step-up-from-the-surface, which is what the light pill reads
    // as. Same reasoning as `BookChassisColors.of`.
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: isDark ? colors.surfaceVariant : colors.surface,
        shape: StadiumBorder(
          side: BorderSide(color: colors.divider, width: 0.5),
        ),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}
