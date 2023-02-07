import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoadingPage extends StatelessWidget {
  const LoadingPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: const [
                    SmileBookwormIcon(
                      width: 150,
                    ),
                    Positioned(
                      top: 80,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 6,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text(
                  '서재를 정리중이에요',
                  style: TextStyle(
                    color: darkPrimaryColor,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
