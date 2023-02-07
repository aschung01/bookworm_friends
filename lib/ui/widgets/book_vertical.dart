import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BookVertical extends StatelessWidget {
  final double width;
  final double height;
  final double opacity;
  final String title;
  final bool complimented;
  final Function() onTap;
  const BookVertical({
    Key? key,
    this.width = 26,
    this.height = 124,
    this.opacity = 1.0,
    required this.title,
    this.complimented = false,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: complimented ? height + 13 : height,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: complimented ? 13 : null,
              child: ClipPath(
                clipper: BookShapeClipper(),
                child: Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: AppController.to.themeColor.withOpacity(opacity),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(top: 15, bottom: 15),
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: opacity > 0.7 ? Colors.white : darkPrimaryColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (complimented)
              Positioned(
                bottom: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: backgroundColor,
                    border: Border.all(
                      color: AppController.to.themeColor,
                    ),
                  ),
                  alignment: Alignment.center,
                  child:
                      // Text(
                      //   expression,
                      //   style: const TextStyle(
                      //     fontSize: 14,
                      //     height: 1.0,
                      //   ),
                      // ),
                      Icon(
                    PhosphorIcons.confettiFill,
                    color: Color(0xfff46036),
                    // color: AppController.to.themeColor,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BookShapeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = new Path();
    path.moveTo(0, 5);
    path.quadraticBezierTo(size.width / 2, 0, size.width, 5);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return true;
  }
}
