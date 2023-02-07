import 'dart:math' as Math;

import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:flutter/material.dart';

class BookRating extends StatelessWidget {
  final double rating;
  final Color backgroundColor;
  const BookRating({
    Key? key,
    required this.rating,
    this.backgroundColor = Colors.white,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: BookRatingPainter(
        rating: rating,
        backgroundColor: backgroundColor,
      ),
      size: const Size(84, 20),
    );
  }
}

class BookRatingPainter extends CustomPainter {
  final double rating;
  final Color backgroundColor;
  const BookRatingPainter({
    required this.rating,
    this.backgroundColor = Colors.white,
  }) : super();

  @override
  void paint(Canvas canvas, Size size) {
    Paint fillPaint = Paint()..color = AppController.to.themeColor;
    Paint emptyPaint = Paint()..color = backgroundColor;
    var _distanceBetweenCenters =
        size.height - ((size.height * 5 - size.width) / 4);
    var _radius = size.height / 2;

    for (int i = 9; i >= 0; i--) {
      if (i % 2 == 0) {
        canvas.drawArc(
          Rect.fromCenter(
            center:
                Offset(_radius + _distanceBetweenCenters * (i ~/ 2), _radius),
            height: size.height,
            width: size.height,
          ),
          Math.pi * 1 / 2,
          Math.pi,
          false,
          (i / 2) < rating ? fillPaint : emptyPaint,
        );
      } else {
        canvas.drawArc(
          Rect.fromCenter(
            center:
                Offset(_radius + _distanceBetweenCenters * (i ~/ 2), _radius),
            height: size.height,
            width: size.height,
          ),
          -Math.pi * 1 / 2,
          Math.pi,
          false,
          i / 2 < rating ? fillPaint : emptyPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
