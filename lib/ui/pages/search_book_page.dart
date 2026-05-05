import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchBookPage extends ConsumerWidget {
  const SearchBookPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('도서 검색')),
      body: const Center(child: Text('Book search - TODO')),
    );
  }
}
