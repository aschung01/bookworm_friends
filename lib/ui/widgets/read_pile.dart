import 'package:flutter/material.dart';

import 'package:bookworm_friends/constants/app_routes.dart';
import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/l10n/app_localizations.dart';
import 'package:bookworm_friends/models/book.dart';
import 'package:bookworm_friends/ui/widgets/book_vertical.dart';
import 'package:bookworm_friends/ui/widgets/shelf_widget.dart';

/// The read pile: spines standing on a shelf, scrolling sideways.
///
/// This is the read view's **collapsed** state. It was the sheet's only body
/// before Phase 2 and is unchanged; what changed is its role — it is now what you
/// see at rest, with the month grid above it.
///
/// Its height is a constant rather than a measurement, and that is load-bearing:
/// [LibrarySheet] needs the collapsed snap position while the *grid* is the body
/// on screen, so it cannot measure this. The number is honest because nothing here
/// scales — the spine row is a fixed-height horizontal scroller and the empty
/// state is sized to match it exactly.
class ReadPile extends StatelessWidget {
  final List<Book> books;

  const ReadPile({super.key, required this.books});

  /// Top padding, then the spine row, then the shelf it stands on, then the gap
  /// below it. Kept as the sum of the parts so a change to any of them is visibly
  /// a change to this number.
  static const double extent = _topPad + _rowExtent + _shelfHeight + _bottomPad;

  static const double _topPad = 14;

  /// A 124pt spine plus the 13pt a praised spine grows by, so a book that gains
  /// praise does not change the pile's height.
  static const double _rowExtent = 124 + 13;
  static const double _shelfHeight = 8;
  static const double _bottomPad = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: extent,
      child: Column(
        children: [
          Expanded(
            child: books.isEmpty
                ? Center(
                    child: Text(
                      l10n.noFinishedBooks,
                      style: TextStyle(
                        color: context.colors.secondaryText,
                        fontSize: 14,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(
                      top: _topPad,
                      left: 25,
                      right: 25,
                    ),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: books.length,
                      itemBuilder: (context, index) {
                        final opacityList = bookOpacityList;
                        final opacity = opacityList[index % opacityList.length];
                        return BookVertical(
                          title: books[index].title,
                          opacity: opacity,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.details,
                            arguments: books[index],
                          ),
                        );
                      },
                    ),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 25),
            child: ShelfWidget(),
          ),
          const SizedBox(height: _bottomPad),
        ],
      ),
    );
  }
}
