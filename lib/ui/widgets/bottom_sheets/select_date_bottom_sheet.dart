import 'package:bookworm_friends/constants/constants.dart';
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

  return showModalBottomSheet<({int year, int month})>(
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
    return List<int>.generate(20, (i) => i == 0 ? 0 : DateTime.now().year + 1 - i);
  }

  @override
  void initState() {
    super.initState();
    _pickerYear = widget.initialYear;
    _pickerMonth = widget.initialMonth;
    final yearIndex = _pickerYear == 0 ? 0 : (DateTime.now().year + 1 - _pickerYear);
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
                  style: const TextStyle(color: darkPrimaryColor, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                GestureDetector(
                  onTap: () => widget.onSave(_pickerYear, _pickerMonth),
                  child: Text(
                    l10n.done,
                    style: const TextStyle(color: greenThemeColor, fontSize: 14, fontWeight: FontWeight.bold),
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
                      selectionOverlay: const DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: greenThemeColor, width: 0.5),
                            bottom: BorderSide(color: greenThemeColor, width: 0.5),
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
                                color: e == _pickerYear ? greenThemeColor : darkPrimaryColor,
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
                                color: isSelected ? greenThemeColor : darkPrimaryColor,
                                fontSize: isSelected ? 28 : 20,
                                fontWeight: FontWeight.bold,
                              ),
                              children: isSelected
                                  ? [
                                      TextSpan(
                                        text: l10n.yearSuffix,
                                        style: const TextStyle(color: greenThemeColor, fontSize: 20, fontWeight: FontWeight.bold),
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
                      selectionOverlay: const DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: greenThemeColor, width: 0.5),
                            bottom: BorderSide(color: greenThemeColor, width: 0.5),
                          ),
                        ),
                      ),
                      onSelectedItemChanged: (int index) {
                        setState(() {
                          _pickerMonth = index;
                        });
                      },
                      children: _pickerYear == 0
                          ? const [
                              Center(
                                child: Text(
                                  '--',
                                  style: TextStyle(color: greenThemeColor, fontSize: 26, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ]
                          : List.generate(13, (i) {
                              if (i == 0) {
                                return Center(
                                  child: Text(
                                    l10n.all,
                                    style: TextStyle(
                                      color: i == _pickerMonth ? greenThemeColor : darkPrimaryColor,
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
                                      color: isSelected ? greenThemeColor : darkPrimaryColor,
                                      fontSize: isSelected ? 28 : 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    children: isSelected
                                        ? [
                                            TextSpan(
                                              text: l10n.monthSuffix,
                                              style: const TextStyle(color: greenThemeColor, fontSize: 20, fontWeight: FontWeight.bold),
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

Future<void> showSelectDateBottomSheet(
  BuildContext context, {
  required DateTime initialDate,
  required ValueChanged<DateTime> onDateSelected,
  String? title,
}) {
  final l10n = AppLocalizations.of(context);
  final resolvedTitle = title ?? l10n.selectDate;
  DateTime selected = initialDate;
  return showModalBottomSheet(
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
                Text(resolvedTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkPrimaryColor)),
                ElevatedActionButton(
                  width: 60,
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
              initialDateTime: initialDate,
              maximumDate: DateTime.now(),
              onDateTimeChanged: (dt) => selected = dt,
            ),
          ),
        ],
      ),
    ),
  );
}
