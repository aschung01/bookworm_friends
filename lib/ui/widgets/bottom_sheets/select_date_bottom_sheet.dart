import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<({int year, int month})?> showYearMonthFilterBottomSheet(
  BuildContext context, {
  required int currentYear,
  required int currentMonth,
}) {
  int pickerYear = currentYear;
  int pickerMonth = currentMonth;

  return CNBottomSheet.show<({int year, int month})>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _YearMonthFilterSheet(
      initialYear: pickerYear,
      initialMonth: pickerMonth,
      onSave: (year, month) {
        Navigator.pop(context, (year: year, month: month));
      },
    ),
  );
}

class _YearMonthFilterSheet extends StatefulWidget {
  final int initialYear;
  final int initialMonth;
  final void Function(int year, int month) onSave;

  const _YearMonthFilterSheet({
    required this.initialYear,
    required this.initialMonth,
    required this.onSave,
  });

  @override
  State<_YearMonthFilterSheet> createState() => _YearMonthFilterSheetState();
}

class _YearMonthFilterSheetState extends State<_YearMonthFilterSheet> {
  late int _pickerYear;
  late int _pickerMonth;
  late FixedExtentScrollController _yearController;
  late FixedExtentScrollController _monthController;

  List<int> get _yearItems {
    return List<int>.generate(
      20,
      (i) => i == 0 ? 0 : DateTime.now().year + 1 - i,
    );
  }

  @override
  void initState() {
    super.initState();
    _pickerYear = widget.initialYear;
    _pickerMonth = widget.initialMonth;
    final yearIndex = _pickerYear == 0
        ? 0
        : (DateTime.now().year + 1 - _pickerYear);
    _yearController = FixedExtentScrollController(initialItem: yearIndex);
    _monthController = FixedExtentScrollController(initialItem: _pickerMonth);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 15, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.filterTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                GestureDetector(
                  onTap: () => widget.onSave(_pickerYear, _pickerMonth),
                  child: Text(
                    l10n.done,
                    style: TextStyle(
                      color: context.colors.brandText,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: CupertinoPicker(
                      scrollController: _yearController,
                      itemExtent: 80,
                      selectionOverlay: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: context.colors.brandText,
                              width: 0.5,
                            ),
                            bottom: BorderSide(
                              color: context.colors.brandText,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                      onSelectedItemChanged: (int index) {
                        setState(() {
                          final items = _yearItems;
                          _pickerYear = items[index];
                          if (_pickerYear == 0) {
                            _pickerMonth = 0;
                            _monthController.jumpToItem(0);
                          }
                        });
                      },
                      children: _yearItems.map((e) {
                        if (e == 0) {
                          return Center(
                            child: Text(
                              l10n.all,
                              style: TextStyle(
                                color: e == _pickerYear
                                    ? context.colors.brandText
                                    : context.colors.primaryText,
                                fontSize: e == _pickerYear ? 26 : 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }
                        final isSelected = e == _pickerYear;
                        return Center(
                          child: Text.rich(
                            TextSpan(
                              text: e.toString(),
                              style: TextStyle(
                                color: isSelected
                                    ? context.colors.brandText
                                    : context.colors.primaryText,
                                fontSize: isSelected ? 28 : 20,
                                fontWeight: FontWeight.bold,
                              ),
                              children: isSelected
                                  ? [
                                      TextSpan(
                                        text: l10n.yearSuffix,
                                        style: TextStyle(
                                          color: context.colors.brandText,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: CupertinoPicker(
                      scrollController: _monthController,
                      itemExtent: 80,
                      selectionOverlay: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: context.colors.brandText,
                              width: 0.5,
                            ),
                            bottom: BorderSide(
                              color: context.colors.brandText,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                      onSelectedItemChanged: (int index) {
                        setState(() {
                          _pickerMonth = index;
                        });
                      },
                      children: _pickerYear == 0
                          ? [
                              Center(
                                child: Text(
                                  '--',
                                  style: TextStyle(
                                    color: context.colors.brandText,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ]
                          : List.generate(13, (i) {
                              if (i == 0) {
                                return Center(
                                  child: Text(
                                    l10n.all,
                                    style: TextStyle(
                                      color: i == _pickerMonth
                                          ? context.colors.brandText
                                          : context.colors.primaryText,
                                      fontSize: i == _pickerMonth ? 26 : 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              }
                              final isSelected = i == _pickerMonth;
                              return Center(
                                child: Text.rich(
                                  TextSpan(
                                    text: i.toString(),
                                    style: TextStyle(
                                      color: isSelected
                                          ? context.colors.brandText
                                          : context.colors.primaryText,
                                      fontSize: isSelected ? 28 : 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    children: isSelected
                                        ? [
                                            TextSpan(
                                              text: l10n.monthSuffix,
                                              style: TextStyle(
                                                color: context.colors.brandText,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              );
                            }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

/// Strips the time component so two dates can be compared (and bounded) by
/// calendar day. Reading dates are stored as `yyyy-MM-dd`, so the time a date
/// happened to be created at must never affect a comparison.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

Future<void> showSelectDateBottomSheet(
  BuildContext context, {
  required DateTime initialDate,
  required ValueChanged<DateTime> onDateSelected,
  String? title,

  /// Earliest selectable day. Used to keep a finish date from landing before
  /// the book's start date.
  DateTime? minimumDate,
}) {
  final l10n = AppLocalizations.of(context);
  final resolvedTitle = title ?? l10n.selectDate;

  // A book can't be read in the future, and can't be finished before it was
  // started.
  final maximum = dateOnly(DateTime.now());
  final minimum = minimumDate == null ? null : dateOnly(minimumDate);

  // CupertinoDatePicker asserts that its initial value sits inside its own
  // bounds, so clamp rather than trusting the caller.
  var initial = dateOnly(initialDate);
  if (minimum != null && initial.isBefore(minimum)) initial = minimum;
  if (initial.isAfter(maximum)) initial = maximum;

  DateTime selected = initial;
  return CNBottomSheet.show(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SizedBox(
      height: 320,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  resolvedTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedActionButton(
                  // Wide enough for the label plus the glass button's own
                  // internal padding; 60 clipped it to "Co…".
                  width: 92,
                  height: 32,
                  buttonText: l10n.confirm,
                  onPressed: () {
                    onDateSelected(selected);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: initial,
              minimumDate: minimum,
              maximumDate: maximum,
              onDateTimeChanged: (dt) => selected = dateOnly(dt),
            ),
          ),
        ],
      ),
    ),
  );
}
