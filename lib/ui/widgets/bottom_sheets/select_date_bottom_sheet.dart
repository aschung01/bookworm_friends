import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:bookworm_friends/constants/app_text_styles.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/cupertino.dart';

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
    builder: (_) => SizedBox(
      height: 320,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(resolvedTitle, style: AppTextStyles.subtitle),
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
