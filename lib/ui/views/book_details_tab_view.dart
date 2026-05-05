import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookDetailsTabView extends ConsumerWidget {
  const BookDetailsTabView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('도서 상세')),
      body: const Center(child: Text('Book details - TODO')),
    );
  }
}
