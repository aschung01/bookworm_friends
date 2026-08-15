import 'package:bookworm_friends/constants/app_theme.dart';
import 'package:flutter/material.dart';

class BookRating extends StatelessWidget {
  final double rating;
  final double size;
  const BookRating({super.key, required this.rating, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
          color: context.colors.brandText,
          size: size,
        );
      }),
    );
  }
}
