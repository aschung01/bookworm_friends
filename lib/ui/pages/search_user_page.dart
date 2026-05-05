import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchUserPage extends ConsumerWidget {
  const SearchUserPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('사용자 검색')),
      body: const Center(child: Text('User search - TODO')),
    );
  }
}
