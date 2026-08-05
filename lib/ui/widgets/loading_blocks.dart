import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class LoadingBlock extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  const LoadingBlock({
    super.key,
    this.width = 100,
    this.height = 20,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade50,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: lightGrayColor,
          borderRadius: borderRadius ?? BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class LoadingTitle extends StatelessWidget {
  const LoadingTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoadingBlock(width: MediaQuery.of(context).size.width * 0.6, height: 20),
        const SizedBox(height: 8),
        LoadingBlock(width: MediaQuery.of(context).size.width * 0.4, height: 16),
      ],
    );
  }
}

class LoadingShelfRow extends StatelessWidget {
  const LoadingShelfRow({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bookHeight = screenHeight * 0.15;

    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 26, left: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: List.generate(
                3,
                (i) => Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 15 : 0),
                  child: Container(
                    width: bookHeight / 1.6,
                    height: bookHeight,
                    decoration: BoxDecoration(
                      color: lightGrayColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 12,
              color: Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingLibrary extends StatelessWidget {
  const LoadingLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: lightGrayColor,
      padding: const EdgeInsets.only(top: 16),
      child: const Column(
        children: [
          LoadingShelfRow(),
          LoadingShelfRow(),
        ],
      ),
    );
  }
}
