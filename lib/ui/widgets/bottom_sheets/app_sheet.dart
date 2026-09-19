import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../../../constants/app_layout.dart';
import '../../../constants/app_theme.dart';

/// Presents a modal sheet, as a bottom sheet on a phone and as a floating form
/// sheet on a tablet.
///
/// ## Why this exists
///
/// Every sheet in the app reached [CNBottomSheet.show] directly and passed no
/// `constraints`, so all eighteen of them inherited Flutter's Material 3 default
/// of `maxWidth: 640`. On a phone that cap is never reached and is invisible. On a
/// 13-inch iPad it is 62% of the screen, and because **only the width was capped**
/// the result was two different wrong shapes:
///
/// - A tall sheet (search, add book) became a 640×1410 column holding ~120pt of
///   content, with its empty state marooned in a thousand points of nothing.
/// - A short sheet (the three-item Appearance picker) sat flush against the bottom
///   edge with square bottom corners, 700pt below the row that opened it, reading
///   as a panel stuck to the screen rather than a thing that was presented.
///
/// Capping the width was the right instinct — a 1032pt-wide text field is
/// unreadable and its far corner is out of reach. The bug was stopping there.
///
/// ## What changes on a tablet
///
/// The sheet keeps its inherited 640 width cap, which is already doing the
/// horizontal centring. This adds the parts that were missing: an inset from the
/// bottom so the card floats, **all four** corners rounded rather than the top two,
/// and a height cap so a sheet holding one paragraph is not full-bleed.
///
/// The card stays bottom-anchored rather than becoming vertically centred, and that
/// is a deliberate limit. Centring needs a full-height transparent sheet, which
/// swallows the taps that currently dismiss the scrim and would have to re-implement
/// barrier dismissal by hand — a real regression risk in exchange for a smaller
/// visual gain than the rounding and the height cap buy on their own.
///
/// A three-item picker still wants a *popover anchored to its row* on a tablet;
/// that is an interaction-model change, not a layout one, and [CNPopupMenuButton]
/// is the component for it. Out of scope here.
abstract final class AppSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    Color? backgroundColor,
    Color? barrierColor,
    bool isDismissible = true,
    bool enableDrag = true,
    bool? showDragHandle,
    bool useSafeArea = false,
    ShapeBorder? shape,
    double? elevation,
    BoxConstraints? constraints,
  }) {
    if (!isTabletLayout(context)) {
      return CNBottomSheet.show<T>(
        context: context,
        builder: builder,
        isScrollControlled: isScrollControlled,
        backgroundColor: backgroundColor,
        barrierColor: barrierColor,
        isDismissible: isDismissible,
        enableDrag: enableDrag,
        showDragHandle: showDragHandle,
        useSafeArea: useSafeArea,
        shape: shape,
        elevation: elevation,
        constraints: constraints,
      );
    }

    // Read from the *calling* context. `showModalBottomSheet` wraps its builder in
    // `MediaQuery.removePadding(removeTop: true)`, the same trap
    // `showAddBookBottomSheet` and `showInviteSheet` already document — and the
    // background colour has to be resolved out here too, because inside the builder
    // the theme is the same but reading it there would put a second lookup on every
    // sheet for no gain.
    final background = backgroundColor ?? context.colors.sheetBackground;

    return CNBottomSheet.show<T>(
      context: context,
      // Forced on, because the card supplies its own height cap below and the
      // 9/16-of-screen clamp that applies without it would fight that cap rather
      // than compose with it.
      isScrollControlled: true,
      // The sheet itself becomes the transparent stage the card floats on; the card
      // carries the colour and the corners.
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Cancels the theme's top-only `kSheetCornerRadius`, which would otherwise
      // round a surface that is now invisible while the visible card went square.
      shape: const RoundedRectangleBorder(),
      barrierColor: barrierColor,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      constraints: constraints,
      builder: (ctx) =>
          _FormSheetCard(background: background, child: builder(ctx)),
    );
  }
}

/// The floating card a sheet becomes on a tablet.
class _FormSheetCard extends StatelessWidget {
  const _FormSheetCard({required this.background, required this.child});

  final Color background;
  final Widget child;

  /// Gap between the card and the bottom of the screen — or the top of the
  /// keyboard, when one is up.
  static const double _bottomInset = 24;

  /// Share of the screen height the card may occupy.
  ///
  /// 0.82 leaves the scrim legible above a card that wants to be tall, so the
  /// library stays visible behind it and the sheet still reads as a layer rather
  /// than a screen. Short sheets are unaffected: their columns are
  /// `MainAxisSize.min` and never reach the cap.
  static const double _maxHeightFraction = 0.82;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Sheets in this app already add `viewInsets.bottom` to their own padding for
    // the keyboard. This inset is on top of that and must not double-count it, so
    // it is a flat gap rather than anything derived from the keyboard's height.
    return Padding(
      padding: const EdgeInsets.only(bottom: _bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: size.height * _maxHeightFraction,
        ),
        child: Material(
          color: background,
          // `antiAlias` rather than `hardEdge`: the sheets that scroll put a list
          // under this corner and a hard clip shows stair-stepping on the curve.
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(kSheetCornerRadius),
          child: child,
        ),
      ),
    );
  }
}
