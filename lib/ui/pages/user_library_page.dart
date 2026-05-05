import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserLibraryPage extends ConsumerWidget {
  const UserLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('서재')),
      body: const Center(child: Text('User library - TODO')),
    );
  }
}
