import 'dart:developer';

import 'package:bookworm_friends/constants/constants.dart';
import 'package:bookworm_friends/core/controllers/app_controller.dart';
import 'package:bookworm_friends/core/controllers/auth_controller.dart';
import 'package:bookworm_friends/core/controllers/library_controller.dart';
import 'package:bookworm_friends/core/controllers/user_controller.dart';
import 'package:bookworm_friends/core/services/amplify_service.dart';
import 'package:bookworm_friends/core/services/kakao_service.dart';
import 'package:bookworm_friends/helpers/url_launcher.dart';
import 'package:bookworm_friends/ui/widgets/buttons/buttons.dart';
import 'package:bookworm_friends/ui/widgets/svg_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';

const String _logoText = '책벌레\n친구들';

const String _kakaoLoginButtonText = '카카오 로그인';
const String _appleLoginButtonText = 'Apple로 로그인';
const String _googleLoginButtonText = 'Google 계정으로 로그인';
const String _facebookLoginButtonText = 'Facebook으로 로그인';
const String _registerButtonText = '회원가입';
const String _loginLabelText = '이미 계정이 있으신가요?';
const String _loginButtonText = '로그인';
const Color _registerButtonColor = Color(0xffEEEEEE);
final Color _kakaoLoginTextColor = Colors.black.withOpacity(0.85);
final Color _googleLoginTextColor = Colors.black.withOpacity(0.54);
const Color _facebookLoginTextColor = Colors.white;
const String _privacyPolicyUrl = endpointUrl + '/user/policy/privacy';
const String _termsOfUseUrl = endpointUrl + '/user/policy/terms_of_use';

class AuthPage extends StatelessWidget {
  const AuthPage({Key? key}) : super(key: key);

  Future<void> _onKakaoLoginPressed() async {
    dynamic accessToken;
    late var token;

    EasyLoading.show();
    try {
      if (AuthController.to.isKakaoInstalled) {
        token = await KakaoService.loginWithKakaoTalk();
        accessToken = token['access_token']!.toString();
      } else {
        token = await KakaoService.loginWithKakao();
        accessToken = token['access_token'];
      }
      bool success = await AmplifyService.signUserInWithKakaoLogin(accessToken);
      print('success:');
      print(success);
      if (success) {
        await AuthController.to.checkAuthentication();
        await AuthController.to.registerUserInfo();
        EasyLoading.dismiss();
        AuthController.to.getUserInfoIfEmpty();
        if (LibraryController.to.library.isEmpty) {
          LibraryController.to.getLibrary();
        }
        if (LibraryController.to.finishedBooks.isEmpty) {
          LibraryController.to.getFinishedBooks();
        }
       await  UserController.to.getUserFollowing();
                Get.until((route) => Get.currentRoute == '/home');
      }
    } catch (e) {
      print(e);
    }
    inspect(token);
    EasyLoading.dismiss();
  }

  void _onSignInLaterPressed() {
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const BookwormIcon(),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _logoText,
                  style: TextStyle(
                    color: AppController.to.themeColor,
                    fontSize: 50,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'DesignHouse',
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 40, bottom: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '서재에 책을 추가하려면 로그인하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: darkPrimaryColor,
                    ),
                  ),
                ),
              ),
              const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '책벌레 친구들과 함께 독서 시작!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: darkPrimaryColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 45, bottom: 10),
                child: AppleLoginButton(
                  onPressed: () => UrlLauncher.launchInApp(
                    AmplifyService.getSocialLoginUrl('SignInWithApple'),
                  ),
                ),
              ),
              KakaoLoginButton(
                onPressed: _onKakaoLoginPressed,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 50),
                child: GoogleLoginButton(
                  onPressed: () => UrlLauncher.launchInApp(
                    AmplifyService.getSocialLoginUrl('Google'),
                  ),
                  // () async {
                  //   try {
                  //     var res = await Amplify.Auth.signInWithWebUI(
                  //       provider: AuthProvider.google,
                  //     );
                  //     print(res);
                  //   } on AuthException catch (e) {
                  //     print(e);
                  //   }
                  // },
                ),
              ),
              TextActionButton(
                buttonText: '로그인하지 않고 조금 더 구경할래요 >',
                textColor: grayColor,
                onPressed: _onSignInLaterPressed,
                isUnderlined: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KakaoLoginButton extends StatelessWidget {
  final Function() onPressed;
  const KakaoLoginButton({
    Key? key,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ButtonStyle _style = ButtonStyle(
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      backgroundColor: MaterialStateProperty.all(kakaoLoginColor),
      elevation: MaterialStateProperty.all(0),
    );

    return SizedBox(
      width: 250,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: _style,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: KakaoIcon(
                height: 16,
              ),
            ),
            Text(
              _kakaoLoginButtonText,
              style: TextStyle(
                height: 1,
                color: _kakaoLoginTextColor,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppleLoginButton extends StatelessWidget {
  final Function() onPressed;
  const AppleLoginButton({
    Key? key,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ButtonStyle _style = ButtonStyle(
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      backgroundColor: MaterialStateProperty.all(Colors.black),
      overlayColor: MaterialStateProperty.all(Colors.black),
      elevation: MaterialStateProperty.all(0),
    );

    return SizedBox(
      width: 250,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: _style,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Padding(
              padding: EdgeInsets.only(right: 3),
              child: AppleWhiteIcon(
                height: 50,
                width: 50,
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _appleLoginButtonText,
                  style: TextStyle(
                    height: 1,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 21.5,
                  ),
                ),
              ),
            ),
            SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}

class GoogleLoginButton extends StatelessWidget {
  final Function() onPressed;
  const GoogleLoginButton({
    Key? key,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ButtonStyle _style = ButtonStyle(
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      backgroundColor: MaterialStateProperty.all(Colors.white),
      // overlayColor: MaterialStateProperty.all(lightGrayColor.withOpacity(0.15)),
      elevation: MaterialStateProperty.all(1),
    );

    return SizedBox(
      width: 250,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: _style,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(right: 24),
              child: GoogleIcon(
                width: 18,
              ),
            ),
            Text(
              _googleLoginButtonText,
              style: TextStyle(
                height: 1,
                color: _googleLoginTextColor,
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
