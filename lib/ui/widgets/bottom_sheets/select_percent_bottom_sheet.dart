import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/glass_segmented_control.dart';

/// How many stops the percent wheel has: 0% through 100% inclusive.
///
/// **101, and the number is the argument.** Percent works for every book ever
/// printed, where a page wheel needs a `page_count` that is null for about two
/// reading books in three. So percent is the mode every book gets and the mode the
/// sheet always opens on; pages are the addition, not the replacement.
const int kProgressWheelStops = 101;

/// Row height of both wheels.
///
/// **34, not the 80 the recovered wheel used.** 80 shows one neighbour each side,
/// which is the ±1 nudge a page wheel is mostly for, and gives the emphasised
/// centre room to breathe. 34 shows ±3 and matches the iOS date picker one tap
/// away, so the two sheets scroll with the same weight under the thumb — which is
/// what it was chosen for. The cost is real and was looked at: a 30pt centred
/// number nearly fills a 34pt row, so it sits close to the hairlines.
const double _kItemExtent = 34;

/// The lowest page the wheel and the field will accept.
///
/// **1, because p.0 does not exist.** 0% does — "opened it and got nowhere" is a
/// real position, and null is not 0 — so a reader who means the very start says so
/// in percent. Page mode never has to express a page no book has. Mirrored by
/// `books_progress_page_positive` in the database, so the rule survives a UI
/// refactor.
///
/// **This is the one number the two modes disagree on**, which is why the field's
/// formatter takes a floor rather than hard-coding one.
const int kProgressPageFloor = 1;

/// The typing state's two fixed bands, shared with `_ProgressSheetState._sheetHeight`
/// so the sheet it is measured into and the content it holds cannot drift apart.
///
/// 56 for the field, matching the wheel row it replaces, and 18 reserved for the
/// clamp line. **The keyboard is not in this budget** — it arrives as
/// `viewInsets.bottom` and lifts the whole sheet.
const double _kFieldHeight = 56;
const double _kClampHeight = 18;

/// The narrowest the field is allowed to get.
///
/// Wide enough for three digits, which is every value either mode can hold, so the
/// unit beside it does not shuffle as the reader types — and, more importantly, so an
/// *empty* field still has a caret somewhere findable rather than collapsing.
const double _kFieldMinWidth = 56;

/// How far right of centre the wheel's static unit label sits.
const double _kUnitOffset = 92;

/// What one Confirm carries out of the sheet: the position, and the unit it was
/// given in.
///
/// **[page] is provenance, not position.** [progress] is always the position, and a
/// page answer round-trips through it exactly. [page] is non-null only when the
/// reader typed or scrolled a page, and it is what lets `ProgressFieldRow` print
/// `p.200` back to a reader who said p.200 rather than the percent it works out to.
/// Null means "answered in percent", which downstream is a real instruction to clear
/// the stored provenance rather than an absence of news.
typedef ProgressAnswer = ({double progress, int? page});

enum _Mode { percent, page }

/// Asks how far into a book the reader is.
///
/// **Percent is always the default**, on every book, including one whose page count
/// is known. Page is one tap away and never presumed, so a reader who already knows
/// this sheet opens it to exactly what they saw before and the new capability costs
/// them no relearning.
///
/// **The segment appears only when [pageCount] is non-null**, and is absent rather
/// than disabled when it is — a disabled control advertises something the book
/// cannot do. For the ~65% of books with no count this sheet is one wheel and nothing
/// else.
///
/// **Both modes are the same control.** Same wheel treatment, same tap-the-number-to-
/// type, same clamping formatter — they differ only in their range, their unit, and
/// whether an answer carries provenance. Percent was briefly the odd one out, wearing
/// the stock `CupertinoPicker` look while page got the branded one; that asymmetry
/// bought nothing and is gone.
///
/// Drawings and the full argument, including the four wheel treatments that lost:
/// `docs/mockups/page-progress/index.html`.
Future<void> showSelectPercentBottomSheet(
  BuildContext context, {

  /// The book's stored position, or null when nothing has been recorded. Null opens
  /// at 0 rather than refusing: the wheel's job is to record a first answer.
  required double? initialProgress,

  /// The page the reader typed last time, or null if they answered in percent.
  /// Only used to resume Page mode where they left it — the sheet still opens on
  /// Percent either way.
  int? initialPage,

  /// Enables Page mode and the rider's derived page. Never written.
  int? pageCount,
  required ValueChanged<ProgressAnswer> onProgressSelected,
  String? title,
}) {
  return CNBottomSheet.show(
    context: context,
    // **Required by the typing state, and by nothing else.**
    //
    // Without it the sheet is capped at 9/16 of the screen (474.75pt on an 844pt
    // phone), and the keyboard inset is paid out of that same budget rather than from
    // the screen below it. The iOS number pad is **not the 216pt the drawings assumed**
    // — with the letter sub-captions and the home indicator it is nearer 290 on a large
    // iPhone — so 290 + a 222pt sheet is 512 against a 474.75 cap, and the field's
    // column overflowed by ~32pt on device. Every wheel state fits the cap without
    // this flag; the typing state cannot, because the pad's height is the platform's
    // to choose and not ours to budget for.
    isScrollControlled: true,
    builder: (_) => _ProgressSheet(
      initialProgress: initialProgress,
      initialPage: initialPage,
      pageCount: pageCount,
      onProgressSelected: onProgressSelected,
      title: title,
    ),
  );
}

class _ProgressSheet extends StatefulWidget {
  const _ProgressSheet({
    required this.initialProgress,
    required this.initialPage,
    required this.pageCount,
    required this.onProgressSelected,
    required this.title,
  });

  final double? initialProgress;
  final int? initialPage;
  final int? pageCount;
  final ValueChanged<ProgressAnswer> onProgressSelected;
  final String? title;

  @override
  State<_ProgressSheet> createState() => _ProgressSheetState();
}

class _ProgressSheetState extends State<_ProgressSheet> {
  late int _stop;
  FixedExtentScrollController? _percentController;
  FixedExtentScrollController? _pageController;

  late final TextEditingController _input;
  late final FocusNode _fieldFocus;

  _Mode _mode = _Mode.percent;
  int? _page;

  /// Whether the field has replaced the wheel.
  ///
  /// Tracked rather than read off `_fieldFocus.hasFocus`, because the height this
  /// state occupies has to be known during `build` and focus changes arrive after it.
  bool _typing = false;

  /// **Whether the reader changed anything at all.**
  ///
  /// Confirm writes nothing when this is false, which fixes a live regression:
  /// Confirm used to write `selected / 100` unconditionally, so opening the sheet on
  /// a book stored at 200/432 = 0.462963 and simply agreeing with what it showed
  /// wrote 0.46 — moving the bookmark back to p.199. Comparing values cannot detect
  /// that, because the value the wheel can represent genuinely differs from the one
  /// stored; only "did they touch it" can.
  bool _touched = false;

  bool get _hasPages => widget.pageCount != null;

  @override
  void initState() {
    super.initState();
    // Snapped to a stop before the wheel ever sees it. A row written by page mode
    // holds something like 0.462963, which has no item to select, so
    // `FixedExtentScrollController` would round it invisibly.
    _stop = (((widget.initialProgress ?? 0) * 100).round()).clamp(
      0,
      kProgressWheelStops - 1,
    );
    _page = widget.initialPage;
    _input = TextEditingController();
    _fieldFocus = FocusNode();
    _fieldFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _percentController?.dispose();
    _pageController?.dispose();
    _fieldFocus.removeListener(_onFocusChanged);
    _fieldFocus.dispose();
    _input.dispose();
    super.dispose();
  }

  /// Where Page mode starts when it is first opened: the reader's own page if they
  /// typed one before, otherwise the page the current percent works out to, never
  /// below [kProgressPageFloor].
  int get _seedPage {
    final total = widget.pageCount!;
    final seed =
        _page ?? bookProgressPage(_stop / 100, total) ?? kProgressPageFloor;
    return seed.clamp(kProgressPageFloor, total);
  }

  /// The value the active mode is showing, in that mode's own unit.
  int get _value => _mode == _Mode.percent ? _stop : (_page ?? _seedPage);

  /// The active mode's range. Percent floors at 0 and pages at 1 — the one place the
  /// two modes genuinely differ, because 0% is a position a reader can be in and p.0
  /// is not.
  int get _min => _mode == _Mode.percent ? 0 : kProgressPageFloor;
  int get _max =>
      _mode == _Mode.percent ? kProgressWheelStops - 1 : widget.pageCount!;

  ProgressAnswer? get _answer {
    // **An empty field is not an answer**, in either mode. Confirm then writes
    // nothing, the same path as opening the sheet and changing nothing: clearing the
    // field and confirming is an abandon rather than a write of what was in it.
    if (_typing && _input.text.isEmpty) return null;
    return switch (_mode) {
      _Mode.percent => (progress: _stop / 100, page: null),
      _Mode.page =>
        _page == null
            ? null
            : (progress: _page! / widget.pageCount!, page: _page),
    };
  }

  void _onModeChanged(int index) {
    final mode = _Mode.values[index];
    if (mode == _mode) return;
    // Leaving with the keyboard up would strand a number pad over the other mode's
    // wheel. Unfocusing routes through `_onFocusChanged`, which restores the wheels.
    if (_typing) _fieldFocus.unfocus();
    setState(() {
      _touched = true;
      _mode = mode;
      // Only the entered mode's controller is rebuilt. The one being left is still
      // mounted for this frame, and disposing a live picker's controller under it is
      // how you get a use-after-dispose.
      if (mode == _Mode.page) {
        _page = _seedPage;
        _pageController?.dispose();
        _pageController = null;
      } else {
        _percentController?.dispose();
        _percentController = null;
      }
    });
  }

  /// Swaps the wheel for the field and raises the number pad.
  ///
  /// **The digits start selected**, so the first keystroke replaces the seeded value
  /// rather than extending it — tapping p.456 and typing 8 means p.8, where appending
  /// would give 4568 and clamp to the last page. This is the platform's own
  /// select-on-focus behaviour rather than a flag this file has to maintain.
  void _startTyping() {
    final seed = '${_value}';
    setState(() {
      _typing = true;
      if (_mode == _Mode.page) _page = _value;
      _input.value = TextEditingValue(
        text: seed,
        selection: TextSelection(baseOffset: 0, extentOffset: seed.length),
      );
    });
    _fieldFocus.requestFocus();
  }

  /// Dismissing the keyboard puts the wheel back, so the sheet is never left showing
  /// a field nothing can type into.
  ///
  /// **This is the way back, and it is the platform's.** The iOS number pad has no
  /// Done key, so the affordance is tapping the sheet around the field — handled by
  /// `_dismissTyping` — or the system gesture. Confirm stays in the header in every
  /// state and remains the way *out*, which is what a reader who has typed their
  /// number actually wants.
  void _onFocusChanged() {
    if (_fieldFocus.hasFocus || !_typing) return;
    setState(() {
      _typing = false;
      // An emptied field leaves the mode with no value, and a wheel cannot show that.
      // Returning to it therefore adopts the value it is about to display.
      if (_mode == _Mode.page) _page ??= _seedPage;
      // Safe to rebuild both here: neither wheel is mounted while typing, so there is
      // no live picker holding either controller.
      _percentController?.dispose();
      _percentController = null;
      _pageController?.dispose();
      _pageController = null;
    });
  }

  void _dismissTyping() {
    if (_typing) _fieldFocus.unfocus();
  }

  /// Only fires for edits the reader made. Deliberately `onChanged` rather than a
  /// listener on the controller, because `_startTyping` assigns to it and a listener
  /// would report that programmatic seed as a touch — which would defeat the no-op
  /// guard for anyone who merely opened the field and confirmed.
  void _onFieldChanged(String text) {
    setState(() {
      _touched = true;
      final value = text.isEmpty ? null : int.parse(text);
      if (_mode == _Mode.percent) {
        // Percent keeps its last value for the wheel to return to; emptiness lives in
        // the field and is read by [_answer], because `_stop` has nowhere to put null.
        if (value != null) _stop = value;
      } else {
        _page = value;
      }
    });
  }

  double get _sheetHeight {
    // Stated as a sum rather than a constant, so the three states cannot drift
    // apart. Header is 16+16 around a 32pt pill, which is taller than the 17/1.25
    // title line and therefore sets the row.
    const header = 64.0;
    const rider = 36.0;
    const wheel = 220.0;
    const segment = 48.0; // 32pt control + 16pt to whatever is under it
    final withSegment = _hasPages ? segment : 0.0;
    final body = _typing ? _kFieldHeight + _kClampHeight : wheel;
    return header + withSegment + body + rider;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Padding(
        // Lifts the sheet clear of the number pad instead of letting it be covered.
        // The pattern nine other sheets here already use, including the status sheet
        // this one is presented from.
        //
        // **Gated on [_typing] rather than read unconditionally.** Focus is lost the
        // instant the pad starts leaving, so the body swaps back to the 220pt wheel
        // while the inset is still ~290 — an unconditional read would balloon the sheet
        // to 658pt for a frame and then settle, a visible bounce on the way out.
        // Dropping the inset with the mode leaves one clean 512 → 368 animation.
        padding: EdgeInsets.only(
          bottom: _typing ? MediaQuery.viewInsetsOf(context).bottom : 0,
        ),
        child: SizedBox(
          height: _sheetHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.title ?? l10n.howFarIn,
                      style: AppTextStyles.subtitle,
                    ),
                    ElevatedActionButton(
                      width: 92,
                      height: 32,
                      buttonText: l10n.confirm,
                      onPressed: () {
                        final answer = _answer;
                        if (_touched && answer != null) {
                          widget.onProgressSelected(answer);
                        }
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              // The same control the status sheet uses: native `CNSegmentedControl` on
              // iOS 26+, the app's pill chips elsewhere. It replaced a
              // `CupertinoSlidingSegmentedControl` chosen only because the native one
              // has no Flutter hit target and so cannot be tapped in a widget test —
              // which was the wrong conclusion. The fallback is what tests drive, so
              // the native control costs nothing there.
              if (_hasPages)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 16,
                  ),
                  child: GlassSegmentedControl(
                    labels: [l10n.progressModePercent, l10n.progressModePage],
                    selectedIndex: _mode.index,
                    onChanged: _onModeChanged,
                  ),
                ),
              Expanded(child: _typing ? _valueField() : _wheel()),
              _Rider(
                mode: _mode,
                stop: _stop,
                page: _page,
                pageCount: widget.pageCount,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One wheel, parameterised by the active mode.
  ///
  /// **Both modes share this**, which is the point: the branded treatment — `figure`
  /// centre in `brandText` over `subtitle` siblings, 0.5pt hairlines top and bottom,
  /// bare numeral beside a static unit label, tap the centre to type — was built for
  /// the page wheel and then left percent wearing the stock `CupertinoPicker` look.
  /// Two controls that do the same job looked like two different controls.
  Widget _wheel() {
    final percent = _mode == _Mode.percent;
    final count = percent ? kProgressWheelStops : widget.pageCount!;
    final selected = _value;
    // Deliberately not localized. `%` is a suffix in both shipped locales, and the
    // page column label is the l10n string that carries the prefix/suffix problem.
    final unit = percent
        ? '%'
        : AppLocalizations.of(context).progressPageColumn;

    final controller = percent
        ? (_percentController ??= FixedExtentScrollController(
            initialItem: selected - _min,
          ))
        : (_pageController ??= FixedExtentScrollController(
            initialItem: selected - _min,
          ));

    return Stack(
      children: [
        // `.builder`, not a children list: a 912-page book would otherwise build 912
        // Text widgets on every scroll tick, because the centred row is styled
        // differently and that means rebuilding on selection change.
        CupertinoPicker.builder(
          // **Keyed by mode, and the wheel is wrong without it.**
          //
          // Both modes now return the same tree shape, so Flutter reuses this element
          // across a mode switch — and `Scrollable` responds to a swapped controller by
          // creating a position that *absorbs the old one's pixel offset*, ignoring the
          // new controller's `initialItem`. Switching to Page therefore kept the percent
          // wheel's offset and showed pages in the 40s. The key forces a fresh element
          // and a fresh position.
          //
          // This was previously masked rather than handled: percent returned a bare
          // picker and page returned a `Stack`, so the differing shapes rebuilt the
          // element for free. Unifying the two treatments is what surfaced it.
          key: ValueKey(_mode),
          itemExtent: _kItemExtent,
          scrollController: controller,
          onSelectedItemChanged: (i) => setState(() {
            final value = i + _min;
            if (value != selected) _touched = true;
            if (percent) {
              _stop = value;
            } else {
              _page = value;
            }
          }),
          // The recovered wheel's overlay: 0.5pt brandText hairlines, top and bottom
          // only, no fill and no radius — a measuring line rather than a system
          // picker's capsule.
          selectionOverlay: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colors.brandText, width: 0.5),
                bottom: BorderSide(color: context.colors.brandText, width: 0.5),
              ),
            ),
          ),
          childCount: count,
          itemBuilder: (context, index) {
            final value = index + _min;
            return Center(
              child: Text(
                '$value',
                // `figure` for the centre and `subtitle` for the rest, which is a
                // 30/17 pairing rather than the recovered 28/20. Forced twice over:
                // `test/text_style_test.dart` bans literal sizes in `lib/ui`, and of
                // the tokens that remain only `display`, `figure` and `label` carry
                // `tabularFigures()`. Without those the centred number changes width
                // as it counts and shuffles sideways under a fixed overlay, which is
                // the one place in the app where that is unmissable.
                style: value == selected
                    ? AppTextStyles.figure.copyWith(
                        color: context.colors.brandText,
                      )
                    : AppTextStyles.subtitle,
              ),
            );
          },
        ),
        // The unit, drawn once beside the wheel instead of on the centred row.
        //
        // **Because `progressPage` is `p.{page}` in English and `{page}쪽` in
        // Korean** — a prefix in one shipped locale and a suffix in the other — so
        // there is no suffix span to shrink, and a prefix would push the digits off
        // centre under the overlay and move them as the count gains a digit. A
        // static label is identical in both locales and never moves.
        //
        // Percent gets the same treatment even though `%` *is* a suffix in both,
        // because the second half of that argument still bites: `100` is wider than
        // `55`, so an inline unit slides as the wheel turns.
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              child: Padding(
                padding: const EdgeInsets.only(left: _kUnitOffset),
                child: Text(
                  unit,
                  style: AppTextStyles.label.copyWith(
                    color: context.colors.secondaryText,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Tapping the centred number raises the number pad. Sized to the centre row
        // and transparent, so the rest of the wheel still scrolls: a 912-page book is
        // tens of flicks away from an arbitrary page, which is what typing is for —
        // and percent gets it too, because 73% is four flicks from 55% and one tap
        // from anywhere.
        //
        // **`translucent`, emphatically not `opaque`.** Opaque ends the hit test here,
        // so the picker underneath never sees the pointer and the wheel could not be
        // dragged *by its centre row* — the most natural place to grab it. Translucent
        // lets this recogniser and the picker's compete: a stationary press is a tap and
        // wins, a moved press is a drag and the picker wins. The defect shipped in the
        // page wheel and went unseen because no test dragged from the centre; giving
        // percent the same overlay is what exposed it.
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _startTyping,
            child: const SizedBox(height: _kItemExtent, width: double.infinity),
          ),
        ),
      ],
    );
  }

  /// The number the reader types, and the platform's keypad under it.
  ///
  /// **A real text field rather than a self-drawn keypad**, which is a reversal — the
  /// drawings rejected this on the grounds that `64 + 48 + wheel 220 + keyboard 216 =
  /// 548` overflows the 474.75pt ceiling. That sum keeps the wheel on screen, which
  /// is the *other* rejected option; when the keyboard replaces the wheel the way a
  /// keypad would, the sheet is 222pt and the pad is `viewInsets`, not sheet content.
  ///
  /// What the reversal buys is everything the OS already does and a hand-rolled grid
  /// of `GestureDetector`s did not: VoiceOver reads a real text field, a hardware or
  /// Bluetooth keyboard can type a value at all, and dictation, paste, select-all, key
  /// clicks and the reader's own keyboard settings all work. The self-drawn version
  /// shipped with no `Semantics` on any key, which put it below this codebase's own
  /// bar.
  Widget _valueField() {
    final l10n = AppLocalizations.of(context);
    final percent = _mode == _Mode.percent;
    final clamped = _input.text == '$_max';
    return GestureDetector(
      // Tapping the sheet around the field dismisses the pad, which is the way back
      // to the wheel. The number pad has no Done key to do it for us.
      behavior: HitTestBehavior.opaque,
      onTap: _dismissTyping,
      child: Column(
        children: [
          // `Expanded`, not a fixed 56, purely as a floor against this recurring
          // through the next platform change: if the sheet is ever squeezed again the
          // field box shrinks instead of overflowing. `_kFieldHeight` is what the
          // sheet *asks* for.
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  // Hugs its digits so the unit sits beside them rather than the
                  // field stretching and pushing it to the edge — with a floor,
                  // because an emptied field has no intrinsic width at all and the
                  // unit would slide left over a vanished caret.
                  IntrinsicWidth(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: _kFieldMinWidth,
                      ),
                      child: CupertinoTextField.borderless(
                        controller: _input,
                        focusNode: _fieldFocus,
                        padding: EdgeInsets.zero,
                        textAlign: TextAlign.center,
                        // `number`, not `numberWithOptions(decimal: true)`: both a
                        // page and a percent are integers here, and the pad should
                        // not offer a separator the formatter would only strip.
                        keyboardType: TextInputType.number,
                        cursorColor: context.colors.brandText,
                        style: AppTextStyles.figure.copyWith(
                          color: context.colors.brandText,
                        ),
                        inputFormatters: [
                          _RangeFormatter(min: _min, max: _max),
                        ],
                        onChanged: _onFieldChanged,
                        onSubmitted: (_) => _dismissTyping(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    // Percent has no total to show, so it wears its unit here the way
                    // the wheel does; page shows `/ 432`, which is the unit and the
                    // context in one.
                    percent ? '%' : l10n.progressOfPages(_max),
                    style: AppTextStyles.label.copyWith(
                      color: context.colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Reserved in every state rather than grown into, for the rider's reason:
          // the sheet must not change height because of what was typed into it. And
          // stated in `secondaryText` rather than red — being stopped at the end is a
          // fact about the book, not a mistake the reader made.
          SizedBox(
            height: _kClampHeight,
            child: clamped && !percent
                ? Center(
                    child: Text(
                      l10n.progressPageClamped(_max),
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

/// Keeps the field inside the active mode's range, as it is typed.
///
/// **A formatter rather than validation**, so there is never an invalid state to
/// report: no error styling, no message and no inert Confirm — three pieces of UI
/// that then do not have to exist. Clamping does invent a value the reader did not
/// type, which was the argument against it; the answer is that it invents it while
/// they are still looking at it and can carry on typing.
///
/// Three rules, and each one is a decision:
///   * Non-digits are dropped, which matters because paste and dictation can deliver
///     them even though the number pad cannot.
///   * Leading zeros are dropped — but a lone `0` survives when [min] is 0. That is
///     the whole difference between the modes: 0% is a position a reader can be in,
///     and p.0 is not.
///   * Anything past [max] becomes [max].
class _RangeFormatter extends TextInputFormatter {
  const _RangeFormatter({required this.min, required this.max});

  final int min;
  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    var body = digits.replaceFirst(RegExp('^0+'), '');
    if (body.isEmpty) {
      // Everything typed was a zero. Legal in percent, refused in pages.
      if (min > 0) return TextEditingValue.empty;
      body = '0';
    }
    // `tryParse`, because a paste of forty digits overflows an int and would throw
    // where it should simply mean "past the end".
    final value = int.tryParse(body) ?? max;
    final text = '${value.clamp(min, max)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The line under the control, translating the answer into the other unit.
///
/// **A fixed box in every state**, so the sheet's height never depends on the data.
///
/// Percent mode prints `≈ p.N` — approximate on purpose, because 101 stops over 320
/// pages is 3.2 pages a stop and p.148 is not expressible. Page mode prints the
/// exact percent with **no tilde**, because nothing was approximated: the page the
/// reader typed is stored and reads back unchanged.
class _Rider extends StatelessWidget {
  const _Rider({
    required this.mode,
    required this.stop,
    required this.page,
    required this.pageCount,
  });

  final _Mode mode;
  final int stop;
  final int? page;
  final int? pageCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? text;
    if (mode == _Mode.page) {
      // Blank rather than the derived `≈ p.N`: in page mode the percent is what the
      // rider translates *to*, and with an empty field there is nothing to
      // translate. Falling through to the percent branch would print a page derived
      // from a stop the reader is not looking at.
      text = page == null || pageCount == null
          ? null
          // Not localized: a numeral and a percent sign, which sit the same way round
          // in both supported locales.
          : '${(page! / pageCount! * 100).round()}%';
    } else {
      final derived = bookProgressPage(stop / 100, pageCount);
      text = derived == null ? null : l10n.progressApproxPage(derived);
    }
    return SizedBox(
      height: 36,
      child: text == null
          ? null
          : Center(
              child: Text(
                text,
                style: AppTextStyles.label.copyWith(
                  color: context.colors.secondaryText,
                ),
              ),
            ),
    );
  }
}
