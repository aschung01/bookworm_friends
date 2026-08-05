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
  const KakaoIcon({super.key, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_kakaoIcon, width: width, height: height, colorFilter: color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null);
  }
}

class AppleWhiteIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const AppleWhiteIcon({super.key, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_appleWhiteIcon, width: width, height: height, colorFilter: color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null);
  }
}

class AppleBlackIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const AppleBlackIcon({super.key, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_appleBlackIcon, width: width, height: height, colorFilter: color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null);
  }
}

class GoogleIcon extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  const GoogleIcon({super.key, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_googleIcon, width: width, height: height, colorFilter: color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null);
  }
}

class BookwormIcon extends StatelessWidget {
  final double? width;
  final double? height;
  const BookwormIcon({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_bookwormIcon, width: width, height: height);
  }
}

class SmileBookwormIcon extends StatelessWidget {
  final double? width;
  final double? height;
  const SmileBookwormIcon({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_smileBookwormIcon, width: width, height: height);
  }
}

class BookmarkIcon extends StatelessWidget {
  final double? width;
  final double? height;
  const BookmarkIcon({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_bookmarkIcon, width: width, height: height);
  }
}

class SadCharacter extends StatelessWidget {
  final double? width;
  final double? height;
  const SadCharacter({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_sadCharacter, width: width, height: height);
  }
}
