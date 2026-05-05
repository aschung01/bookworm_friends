import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/providers/auth_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => ref.read(authProvider.notifier).signOut(),
          child: const Text('로그아웃'),
        ),
      ),
    );
  }
}
