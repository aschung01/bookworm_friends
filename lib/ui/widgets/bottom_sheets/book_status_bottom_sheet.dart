import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';

Future<void> showBookStatusBottomSheet(
  BuildContext context, {
  required int currentStatus,
  required DateTime? startDate,
  required DateTime? finishDate,
  required void Function(int status, DateTime? start, DateTime? finish) onSave,
}) {
  int status = currentStatus;
  DateTime? start = startDate;
  DateTime? finish = finishDate;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        final l10n = AppLocalizations.of(context);
        return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.changeReadingStatus,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkPrimaryColor),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatusOption(label: l10n.statusInterested, value: 0, selected: status == 0, onTap: () => setState(() => status = 0)),
                _StatusOption(label: l10n.statusReading, value: 1, selected: status == 1, onTap: () => setState(() => status = 1)),
                _StatusOption(label: l10n.statusFinished, value: 2, selected: status == 2, onTap: () => setState(() => status = 2)),
              ],
            ),
            if (status >= 1) ...[
              const SizedBox(height: 16),
              _DateRow(
                label: l10n.startDate,
                date: start,
                onTap: () => showSelectDateBottomSheet(
                  context,
                  initialDate: start ?? DateTime.now(),
                  title: l10n.startDate,
                  onDateSelected: (d) => setState(() => start = d),
                ),
              ),
            ],
            if (status == 2) ...[
              const SizedBox(height: 12),
              _DateRow(
                label: l10n.finishDate,
                date: finish,
                onTap: () => showSelectDateBottomSheet(
                  context,
                  initialDate: finish ?? DateTime.now(),
                  title: l10n.finishDate,
                  onDateSelected: (d) => setState(() => finish = d),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedActionButton(
                height: 44,
                buttonText: l10n.save,
                onPressed: () {
                  Navigator.pop(context);
                  onSave(status, start, finish);
                },
              ),
            ),
          ],
        ),
      );
      },
    ),
  );
}

class _StatusOption extends StatelessWidget {
  final String label;
  final int value;
  final bool selected;
  final VoidCallback onTap;
  const _StatusOption({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? greenThemeColor : lightGrayColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : darkPrimaryColor,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DateRow({required this.label, this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: darkPrimaryColor)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: lightGrayColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              date != null ? '${date!.year}.${date!.month.toString().padLeft(2, '0')}.${date!.day.toString().padLeft(2, '0')}' : l10n.select,
              style: const TextStyle(color: darkPrimaryColor, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
