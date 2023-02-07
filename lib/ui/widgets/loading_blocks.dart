import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:get/get.dart';

class LoadingBlock extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  const LoadingBlock({
    Key? key,
    this.height = 100,
    this.width,
    this.borderRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: backgroundColor,
      highlightColor: Colors.white.withOpacity(0.3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius ?? BorderRadius.circular(20),
          color: backgroundColor,
        ),
        child: SizedBox(
          height: height,
          width: width ?? context.width - 40,
        ),
      ),
    );
  }
}

class LoadingTitle extends StatelessWidget {
  const LoadingTitle({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: backgroundColor,
      highlightColor: Colors.white.withOpacity(0.3),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white,
                ),
                child: const SizedBox(
                  height: 24,
                  width: 200,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white,
                  ),
                  child: const SizedBox(
                    height: 16,
                    width: 80,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
