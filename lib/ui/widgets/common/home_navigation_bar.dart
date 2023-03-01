import 'package:bookworm_friends/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class HomeNavigationBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onIconTap;
  const HomeNavigationBar(
      {super.key, required this.currentIndex, required this.onIconTap});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onIconTap,
      selectedItemColor: darkPrimaryColor,
      showUnselectedLabels: false,
      iconSize: 26,
      elevation: 20,
      backgroundColor: Colors.white,
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          // icon: Icon(Icons.home),
          icon: Icon(
            PhosphorIcons.house,
          ),
          activeIcon: Icon(
            PhosphorIcons.houseFill,
          ),
          label: '홈',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            PhosphorIcons.magnifyingGlass,
          ),
          activeIcon: Icon(
            PhosphorIcons.magnifyingGlassFill,
          ),
          label: '탐색',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            PhosphorIcons.user,
          ),
          activeIcon: Icon(
            PhosphorIcons.userFill,
          ),
          label: '프로필',
        ),
      ],
    );
  }
}
