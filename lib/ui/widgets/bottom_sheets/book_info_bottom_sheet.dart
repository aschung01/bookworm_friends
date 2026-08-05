import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/services/book_search_service.dart';
import 'package:bookworm_friends/ui/widgets/book_widget.dart';
import 'package:bookworm_friends/ui/widgets/bottom_sheets/select_date_bottom_sheet.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Future<void> showBookInfoBottomSheet(
  BuildContext context, {
  required BookSearchResult book,
  required List<String> shelfNames,
  required void Function(String shelfName, int status, {DateTime? startDate, DateTime? finishDate}) onSavePressed,
}) {
  String? selectedShelf = shelfNames.isNotEmpty ? shelfNames.first : null;
  int status = 0;
  DateTime? startDate;
  DateTime? finishDate;

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
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookWidget(imageUrl: book.thumbnail, height: 120),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkPrimaryColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (book.authors.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            book.authors.join(', '),
                            style: const TextStyle(fontSize: 13, color: grayColor),
                          ),
                        ),
                      if (book.publisher != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            book.publisher!,
                            style: const TextStyle(fontSize: 12, color: grayColor),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (shelfNames.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: selectedShelf,
                decoration: InputDecoration(
                  labelText: l10n.selectShelf,
                  filled: true,
                  fillColor: lightGrayColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                items: shelfNames.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => selectedShelf = v),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatusChip(label: l10n.statusInterested, value: 0, selected: status == 0, onTap: () => setState(() { status = 0; startDate = null; finishDate = null; })),
                _StatusChip(label: l10n.statusReading, value: 1, selected: status == 1, onTap: () => setState(() { status = 1; startDate ??= DateTime.now(); finishDate = null; })),
                _StatusChip(label: l10n.statusFinished, value: 2, selected: status == 2, onTap: () => setState(() { status = 2; startDate ??= DateTime.now(); finishDate ??= DateTime.now(); })),
              ],
            ),
            if (status >= 1) ...[
              const SizedBox(height: 16),
              _DateRow(
                label: l10n.startDate,
                date: startDate,
                onTap: () {
                  showSelectDateBottomSheet(
                    context,
                    initialDate: startDate ?? DateTime.now(),
                    title: l10n.selectStartDate,
                    onDateSelected: (d) => setState(() => startDate = d),
                  );
                },
              ),
            ],
            if (status == 2) ...[
              const SizedBox(height: 8),
              _DateRow(
                label: l10n.finishDate,
                date: finishDate,
                onTap: () {
                  showSelectDateBottomSheet(
                    context,
                    initialDate: finishDate ?? DateTime.now(),
                    title: l10n.selectFinishDate,
                    onDateSelected: (d) => setState(() => finishDate = d),
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedActionButton(
                height: 44,
                buttonText: l10n.save,
                activated: selectedShelf != null,
                onPressed: () {
                  if (selectedShelf != null) {
                    Navigator.pop(context);
                    onSavePressed(selectedShelf!, status, startDate: startDate, finishDate: finishDate);
                  }
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

class _DateRow extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DateRow({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: lightGrayColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: darkPrimaryColor)),
            Text(
              date != null ? DateFormat('yyyy.MM.dd').format(date!) : l10n.select,
              style: TextStyle(fontSize: 14, color: date != null ? darkPrimaryColor : grayColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final int value;
  final bool selected;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.value, required this.selected, required this.onTap});

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
