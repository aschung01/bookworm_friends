import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

const String _kakaoIcon = 'assets/icons/kakaoIcon.svg';
const String _appleWhiteIcon = 'assets/icons/appleWhiteIcon.svg';
const String _appleBlackIcon = 'assets/icons/appleBlackIcon.svg';
const String _googleIcon = 'assets/icons/googleIcon.svg';
const String _bookwormIcon = "assets/icons/bookwormIcon.svg";
const String _smileBookwormIcon = "assets/icons/smileBookwormIcon.svg";
const String _bookmarkIcon = "assets/icons/bookmarkIcon.svg";
const String _sadCharacter = "assets/icons/sadCharacter.svg";

class KakaoIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const KakaoIcon({
    Key? key,
    this.width,
    this.height,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _kakaoIcon,
      width: width,
      height: height,
      color: color,
    );
  }
}

class AppleWhiteIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const AppleWhiteIcon({
    Key? key,
    this.width,
    this.height,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _appleWhiteIcon,
      width: width,
      height: height,
      color: color,
    );
  }
}

class AppleBlackIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const AppleBlackIcon({
    Key? key,
    this.width,
    this.height,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _appleBlackIcon,
      width: width,
      height: height,
      color: color,
    );
  }
}

class GoogleIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const GoogleIcon({
    Key? key,
    this.width,
    this.height,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _googleIcon,
      width: width,
      height: height,
      color: color,
    );
  }
}

class BookwormIcon extends StatelessWidget {
  final double? width;
  final double? height;
  const BookwormIcon({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _bookwormIcon,
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }
}

class SmileBookwormIcon extends StatelessWidget {
  final double? width;
  final double? height;
  const SmileBookwormIcon({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _smileBookwormIcon,
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }
}

class BookmarkIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const BookmarkIcon({
    Key? key,
    this.width,
    this.height,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _bookmarkIcon,
      width: width,
      height: height,
      color: color,
      fit: BoxFit.contain,
    );
  }
}

class SadCharacter extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const SadCharacter({
    Key? key,
    this.width,
    this.height,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _sadCharacter,
      width: width,
      height: height,
      color: color,
      fit: BoxFit.contain,
    );
  }
}
