import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/providers/library_provider.dart'
    show kMaxTotalPages, kMinTotalPages;
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'app_sheet.dart';

/// The field's band and the band reserved under it for the clamp line.
///
/// Both numbers are the progress wheel's, deliberately: 56 is the row that sheet's
/// field occupies and 18 is its clamp line, so the two sheets' keypads are the same
/// object at the same size rather than two controls that happen to both take a number.
/// **The keyboard is not in this budget** — it arrives as `viewInsets.bottom` and lifts
/// the whole sheet.
const double _kFieldHeight = 56;
const double _kClampHeight = 18;

/// The narrowest the field is allowed to get.
///
/// Wide enough for the five digits [kMaxTotalPages] can reach, so the clamp line under
/// it does not shuffle as the reader types — and, more importantly, so an **empty**
/// field still has a caret somewhere findable rather than collapsing to a point. Empty
/// is the ordinary state here, not the edge case: about two books in three have no
/// count at all.
const double _kFieldMinWidth = 56;

/// The sheet's height, stated as a sum so the parts cannot drift from the box that
/// holds them.
///
/// Header is 16+16 around a 32pt pill, which is taller than the 17/1.25 title line and
/// therefore sets that row. **One body state, so one height**: unlike the progress
/// wheel this sheet never swaps a wheel for a field, so there is nothing for an
/// `AnimatedSize` to animate between and none is used.
const double _kSheetHeight = 64 + _kFieldHeight + _kClampHeight;

/// Identifies the box whose height is [_kSheetHeight], so a test can measure the sheet
/// rather than infer it. Same device as `reading-streak-chip-footprint`.
const Key kTotalPagesSheetKey = ValueKey('total-pages-sheet');

/// Asks how many pages the book has, and hands the answer back.
///
/// **This is the first writer of `page_count` after `addBook`**, which is why it exists
/// at all: the column arrives once from metadata and is never touched again, and about
/// two books in three have nothing in it because one of the metadata sources supplies no
/// count. That absence is why the progress wheel stores a fraction and hides its Page
/// mode. Filling the total in lights up Page mode, the derived page read-out and the
/// home-screen widget's page display for a book that never had them.
///
/// **Keypad first, and there is no wheel behind it.** A total is read off the back of the
/// book and typed, not scrolled to — the progress wheel's own record calls reaching an
/// arbitrary page in a 912-page book "tens of flicks either way", and a wheel over
/// [kMinTotalPages]–[kMaxTotalPages] is 20,000 stops of exactly that. The deciding
/// argument is narrower though, and it is about the empty case: a wheel cannot display
/// "no total", so opening one for a book with no count would have to seed itself with an
/// invented number — a plausible-looking 300 drawn in `brandText` under a *Total pages*
/// title, for the state that is the common one. The progress wheel never faces this
/// because it always has a percent to fall back on. (Showing the wheel only for books
/// that already have a count was the alternative, and it buys a secondary state at the
/// price of two different sheets for one job.)
///
/// **No Percent/Page segment**, because a total has exactly one unit. Nothing else about
/// the keypad is new: same 56pt field, same reserved clamp band, same clamping formatter,
/// same header with Confirm on the right.
///
/// **It holds no progress value, and that is structural rather than careful.** The
/// fraction *is* the position and the page is derived from it, so correcting a total
/// re-derives the page and must leave the position alone — see
/// `LibraryNotifier.recordTotalPages`, which is where the write happens. The guarantee
/// here is that there is no parameter, no field and no callback in this file that a
/// fraction could arrive in or leave by, so no future edit can move one by accident.
/// That is also why there is no rider line under the field: the progress wheel's rider
/// translates an answer into the other unit, and every translation available here
/// ("p.213", "46%") would need the position.
///
/// The design record is `docs/superpowers/specs/2026-09-28-status-progress-merge-design.md`
/// ("Three tappable numerals").
Future<void> showSelectTotalPagesBottomSheet(
  BuildContext context, {

  /// The book's stored `page_count`, or null when it has none — which is the ordinary
  /// case. Null opens an empty field rather than seeding a guess, because the sheet's
  /// whole job is to take a fact the app does not have.
  ///
  /// A stored value outside the bounds is clamped before it is shown, so the field never
  /// displays a number Confirm would silently change.
  required int? initialTotalPages,

  /// Called with the confirmed total, already clamped, and **only when the reader
  /// changed something**. Agreeing with a pre-filled value reports nothing; see
  /// `_TotalPagesSheetState._touched`.
  ///
  /// A bare `int` rather than a record. The progress wheel needs a record because its
  /// answer carries provenance as well as a value; this one is a single fact, and a
  /// one-field record is an invitation to add a second field — which for this sheet
  /// would mean a progress value it must not have.
  required ValueChanged<int> onTotalPagesSelected,

  /// Overrides the title. Present for the same reason the sibling sheets have it, and
  /// defaults to `totalPagesTitle`.
  String? title,
}) {
  return AppSheet.show(
    context: context,
    // **Required by the keypad, and this sheet is nothing but keypad.**
    //
    // Without it the sheet is capped at 9/16 of the screen and the keyboard inset is
    // paid out of that budget rather than from the screen below it. The iOS number pad
    // is nearer 290pt than the 216 the drawings assumed, which overflows the cap on
    // its own. The progress wheel documents the same flag at length.
    isScrollControlled: true,
    builder: (_) => _TotalPagesSheet(
      initialTotalPages: initialTotalPages,
      onTotalPagesSelected: onTotalPagesSelected,
      title: title,
    ),
  );
}

class _TotalPagesSheet extends StatefulWidget {
  const _TotalPagesSheet({
    required this.initialTotalPages,
    required this.onTotalPagesSelected,
    required this.title,
  });

  final int? initialTotalPages;
  final ValueChanged<int> onTotalPagesSelected;
  final String? title;

  @override
  State<_TotalPagesSheet> createState() => _TotalPagesSheetState();
}

class _TotalPagesSheetState extends State<_TotalPagesSheet> {
  late final TextEditingController _input;
  late final FocusNode _fieldFocus;

  /// **Whether the reader changed anything at all.**
  ///
  /// Confirm reports nothing when this is false, and the progress wheel's history is why
  /// the gate is here rather than a value comparison. Its Confirm used to write
  /// unconditionally, so merely opening the sheet and agreeing with it moved the bookmark
  /// back a page. The trap is the same shape here and the consequence is worse in one
  /// respect: `page_count` is the number every derived page is computed from, so a total
  /// nudged by a round-trip through this sheet moves every page read-out in the app for
  /// that book. Only "did they touch it" can tell agreement from a change.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController();
    final stored = widget.initialTotalPages;
    if (stored != null) {
      // **Clamped before the field ever shows it.** A row holding a total outside the
      // bounds would otherwise be displayed as one number and confirmed as another,
      // which is the defect the progress wheel snaps its stop to avoid.
      final seed = '${stored.clamp(kMinTotalPages, kMaxTotalPages)}';
      // **The digits start selected**, so the first keystroke replaces the seeded total
      // rather than extending it: opening a 462-page book and typing 5 means 5, where
      // appending would give 4625 and clamp. Same behaviour the progress wheel's field
      // gets from the platform on focus, spelled out here because this field is seeded
      // before it is focused rather than at the moment of the tap.
      _input.value = TextEditingValue(
        text: seed,
        selection: TextSelection(baseOffset: 0, extentOffset: seed.length),
      );
    }
    _fieldFocus = FocusNode();
  }

  @override
  void dispose() {
    _fieldFocus.dispose();
    _input.dispose();
    super.dispose();
  }

  /// The total the sheet would hand out, or null when it has nothing to hand out.
  ///
  /// **An empty field is not an answer**, so clearing it and confirming is an abandon
  /// rather than a write of whatever was there before — the progress wheel's rule, and
  /// the reason Confirm is not disabled: there is a defined thing for it to do in every
  /// state.
  ///
  /// Clamped here as well as in the formatter. The formatter is what the reader sees
  /// working; this is the boundary the caller is behind, and a bound that only exists in
  /// a formatter is one a paste, a dictation or a future seed can walk around.
  int? get _answer {
    final value = int.tryParse(_input.text);
    if (value == null) return null;
    return value.clamp(kMinTotalPages, kMaxTotalPages);
  }

  /// Only fires for edits the reader made. Deliberately `onChanged` rather than a
  /// listener on the controller, because [initState] assigns to it and a listener would
  /// report that seed as a touch — which would defeat the guard for every reader who
  /// merely opened the sheet and agreed with it.
  void _onFieldChanged(String text) {
    setState(() => _touched = true);
  }

  /// Dismisses the number pad. The way back to a sheet you can read, since the iOS
  /// number pad has no Done key; tapping the field raises it again, and Confirm sits in
  /// the header above it in every state and remains the way *out*.
  void _dismissPad() {
    if (_fieldFocus.hasFocus) _fieldFocus.unfocus();
  }

  void _onConfirm() {
    final answer = _answer;
    if (_touched && answer != null) widget.onTotalPagesSelected(answer);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      // Lifts the sheet clear of the number pad instead of letting it be covered, the
      // pattern every other sheet here uses.
      //
      // **Read unconditionally, unlike the progress wheel's**, which gates it on its
      // typing state. That gate exists because its body shrinks from a 220pt wheel to a
      // 74pt field as focus is lost, so an ungated read balloons the sheet for a frame
      // on the way out. This sheet's body never changes size, so there is nothing to
      // bounce.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        key: kTotalPagesSheetKey,
        height: _kSheetHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title ?? l10n.totalPagesTitle,
                    style: AppTextStyles.subtitle,
                  ),
                  ElevatedActionButton(
                    // 92 and 32 are the sibling sheets': 60 clipped the label to "Co…".
                    width: 92,
                    height: 32,
                    buttonText: l10n.confirm,
                    onPressed: _onConfirm,
                  ),
                ],
              ),
            ),
            Expanded(child: _field(l10n)),
          ],
        ),
      ),
    );
  }

  /// The number the reader types, and the platform's keypad under it.
  ///
  /// **A real text field rather than a drawn keypad**, for everything the OS does for
  /// free and a grid of `GestureDetector`s does not: VoiceOver reads a field, a hardware
  /// or Bluetooth keyboard can type into it at all, and paste, dictation and select-all
  /// work. The progress wheel shipped a self-drawn version first, with no `Semantics` on
  /// any key, and replacing it is the precedent this follows rather than rediscovers.
  ///
  /// **No unit label beside the digits**, which is the one place this diverges from the
  /// progress wheel's field. That field wears `%` or `/ 432` because one control serves
  /// two units and because the total is context the reader needs. Here the title *is* the
  /// unit, and there is no plural-pages string to put there: `progressPageColumn` is a
  /// wheel column header, "Page" in English, so it would read "462 Page".
  Widget _field(AppLocalizations l10n) {
    final clamped = _input.text == '$kMaxTotalPages';
    return GestureDetector(
      // Tapping the sheet around the field dismisses the pad, the affordance the pad's
      // missing Done key forces. The field is a child and takes its own taps first, so
      // this does not swallow the tap that re-raises the keyboard.
      behavior: HitTestBehavior.opaque,
      onTap: _dismissPad,
      child: Column(
        children: [
          // `Expanded` rather than a fixed 56, purely as a floor: if the sheet is ever
          // squeezed the field box shrinks instead of overflowing. `_kFieldHeight` is
          // what the sheet *asks* for.
          Expanded(
            child: Center(
              child: IntrinsicWidth(
                // Hugs its digits so the caret sits under the middle of the number
                // rather than the field stretching to the sheet's edges — with a floor,
                // because an emptied field has no intrinsic width at all.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: _kFieldMinWidth),
                  child: CupertinoTextField.borderless(
                    controller: _input,
                    focusNode: _fieldFocus,
                    // **The sheet opens on the keypad**, which is the whole shape of it:
                    // a total is typed, so there is no state in front of the typing for
                    // the reader to get through first.
                    autofocus: true,
                    padding: EdgeInsets.zero,
                    textAlign: TextAlign.center,
                    // `number`, not `numberWithOptions(decimal: true)`: a page count is
                    // an integer and the pad should not offer a separator the formatter
                    // would only strip.
                    keyboardType: TextInputType.number,
                    cursorColor: context.colors.brandText,
                    style: AppTextStyles.figure.copyWith(
                      color: context.colors.brandText,
                    ),
                    inputFormatters: const [_TotalPagesFormatter()],
                    onChanged: _onFieldChanged,
                    // Puts the pad away rather than confirming. A hardware return could
                    // reasonably mean "done with the whole sheet" here, since there is
                    // one field, but Confirm is the way out in the sibling sheets and a
                    // key that pops the route in one of three is worse than a key that
                    // does the same small thing in all of them.
                    onSubmitted: (_) => _dismissPad(),
                  ),
                ),
              ),
            ),
          ),
          // Reserved in every state rather than grown into, so the sheet's height never
          // depends on what was typed into it. Stated in `secondaryText` rather than red,
          // and as a fact rather than an error: the digit simply does not take, so there
          // is no invalid state to report and no inert Confirm to explain.
          //
          // **Its own string rather than `progressPageClamped`.** That one reads "This book
          // ends at p.20000", which is true of the total in the field — the last page *is*
          // the count — but it tells the reader something the app knows and they do not,
          // where this line echoes a bound the app imposed on what they just typed. Those
          // are different sentences, so they are different keys.
          SizedBox(
            height: _kClampHeight,
            child: clamped
                ? Center(
                    child: Text(
                      l10n.totalPagesClamped(kMaxTotalPages),
                      style: AppTextStyles.label.copyWith(
                        color: context.colors.secondaryText,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// Keeps the field inside [kMinTotalPages]–[kMaxTotalPages] as it is typed.
///
/// **A formatter rather than validation**, so there is never an invalid state to report:
/// no error styling, no message and no inert Confirm — three pieces of UI that then do
/// not have to exist. Clamping does invent a value the reader did not type, which is the
/// argument against it; the answer is that it invents it while they are still looking at
/// it and can carry on typing.
///
/// A near-copy of the progress wheel's `_RangeFormatter`, which is private to that file
/// and so cannot be shared without making it public API for one caller. The rules are
/// the same three, and each is a decision:
///   * Non-digits are dropped, which matters because the number pad cannot produce them
///     but paste and dictation can.
///   * Leading zeros are dropped, and an all-zero entry empties the field rather than
///     becoming [kMinTotalPages]. **A book with no pages is not a book**, so there is no
///     sub-floor total to clamp *to* — and emptying is what lets "0462" mean 462, where
///     clamping "0" up to "1" would leave the next keystroke building 14 out of 1 and 4.
///     The floor is therefore enforced by refusal here, by `_answer`'s clamp at the
///     boundary, and by `recordTotalPages` at the database's.
///   * Anything past [kMaxTotalPages] becomes [kMaxTotalPages].
class _TotalPagesFormatter extends TextInputFormatter {
  const _TotalPagesFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    final body = digits.replaceFirst(RegExp('^0+'), '');
    if (body.isEmpty) return TextEditingValue.empty;
    // `tryParse`, because a paste of forty digits overflows an int and would throw where
    // it should simply mean "past the ceiling".
    final value = int.tryParse(body) ?? kMaxTotalPages;
    final text = '${value.clamp(kMinTotalPages, kMaxTotalPages)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
