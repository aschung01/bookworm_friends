import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';

class ComplimentBlock extends StatelessWidget {
  final List<dynamic> compliments;
  const ComplimentBlock({super.key, required this.compliments});

  @override
  Widget build(BuildContext context) {
    if (compliments.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: compliments.map((c) {
          final emoji = c is Map ? (c['compliment']?.toString() ?? '') : c.toString();
          return Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
              border: Border.all(color: greenThemeColor.withOpacity(0.3)),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          );
        }).toList(),
      ),
    );
  }
}
