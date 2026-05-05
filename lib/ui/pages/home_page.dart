import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookworm_friends/providers/library_provider.dart';
import 'package:bookworm_friends/constants/constants.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: libraryAsync.when(
        data: (shelves) => Center(child: Text('Library: ${shelves.length} shelves')),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
