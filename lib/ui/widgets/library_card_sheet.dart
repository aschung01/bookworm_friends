import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/ui/widgets/library_sheet.dart';

/// The Card tab's sheet: header and an empty state, and nothing else yet.
///
/// The Library Card (도서관 카드) holds stats and shareable artifacts, which are
/// Phase 3. It ships empty in Phase 1 on purpose: the tab is what proves a tab
/// switch swaps only the sheet and leaves the library behind it alone, and that
/// is worth verifying before there is content to blame a bug on.
///
/// Deliberately holds **no** read-books list. Read books belong entirely to the
/// Library tab, which already groups them by month; a second sortable list of the
/// same rows here would be a second home for one set of data.
class LibraryCardSheet extends StatelessWidget {
  /// See [LibrarySheet.bottomReserve].
  final double bottomReserve;

  const LibraryCardSheet({super.key, this.bottomReserve = 0});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LibrarySheet(
      bottomReserve: bottomReserve,
      header: LibrarySheetTitle(title: l10n.libraryCard),
      body: SizedBox(
        height: 96,
        child: Center(
          child: Text(
            l10n.libraryCardEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.secondaryText, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
