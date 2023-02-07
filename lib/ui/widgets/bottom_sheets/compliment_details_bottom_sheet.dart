import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ComplimentDetailsBottomSheet extends StatelessWidget {
  final List data;
  const ComplimentDetailsBottomSheet({
    Key? key,
    required this.data,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: context.height * 0.4,
        minHeight: context.height * 0.2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: darkPrimaryColor,
            ),
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 10),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding:
                const EdgeInsets.only(top: 10, bottom: 30, left: 25, right: 25),
            itemCount: data.length,
            itemBuilder: (context, index) {
              return Row(
                children: [
                  Text(
                    data[index]['compliment'],
                    style: const TextStyle(
                      fontSize: 26,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      data[index]['username'],
                      style: const TextStyle(
                        fontSize: 16,
                        color: darkPrimaryColor,
                      ),
                    ),
                  ),
                ],
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 5),
          ),
        ],
      ),
    );
  }
}

void getComplimentDetailsBottomSheet({
  required List data,
}) {
  Get.bottomSheet(
    ComplimentDetailsBottomSheet(
      data: data,
    ),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
    ),
    backgroundColor: Colors.white,
  );
}
