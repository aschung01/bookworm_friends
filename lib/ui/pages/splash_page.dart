import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

const String _logoText = '책벌레\n친구들';

class SplashPage extends StatelessWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Future.delayed(
      Duration.zero,
      () {
        Get.offAllNamed('/home');
      },
    );

    return Scaffold(
      body: Container(
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: BookwormIcon(),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  _logoText,
                  style: TextStyle(
                    color: AppController.to.themeColor,
                    fontSize: 50,
                    fontFamily: 'DesignHouse',
                    fontWeight: FontWeight.bold,
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
