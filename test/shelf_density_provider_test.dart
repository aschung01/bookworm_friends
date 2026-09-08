// The shelf density is a persisted preference of the *reader*, in the same
// category as theme mode and the search source — not session state, and not a
// property of a library.
//
// The parse tests are the load-bearing ones: this value is read on launch, so an
// unrecognised stored name has to degrade rather than throw.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bookworm_friends/providers/book_search_provider.dart'
    show sharedPreferencesProvider;
import 'package:bookworm_friends/providers/shelf_density_provider.dart';

import 'support/prefs.dart';

/// A container reading a store seeded with [values].
Future<ProviderContainer> _container([
  Map<String, Object> values = const {},
]) async =>
    ProviderContainer(overrides: [await sharedPreferencesOverride(values)]);

void main() {
  group('ShelfDensityNotifier', () {
    test(
      'Given an empty store, When read, Then the density is covers',
      () async {
        final container = await _container();
        addTearDown(container.dispose);

        expect(container.read(shelfDensityProvider), ShelfDensity.covers);
      },
    );

    test(
      'Given a stored density, When read, Then that density is restored',
      () async {
        final container = await _container({'shelf_density': 'spines'});
        addTearDown(container.dispose);

        expect(container.read(shelfDensityProvider), ShelfDensity.spines);
      },
    );

    test(
      'Given an unrecognised stored value, When read, Then it degrades to covers',
      () async {
        // A name a later version renamed or removed must not throw on launch.
        final container = await _container({'shelf_density': 'shingled'});
        addTearDown(container.dispose);

        expect(container.read(shelfDensityProvider), ShelfDensity.covers);
      },
    );

    test(
      'Given set is called, When read back, Then the state changed',
      () async {
        final container = await _container();
        addTearDown(container.dispose);

        await container
            .read(shelfDensityProvider.notifier)
            .set(ShelfDensity.leaning);

        expect(container.read(shelfDensityProvider), ShelfDensity.leaning);
      },
    );

    test('Given a density was set, When a fresh container reads the same store, Then '
        'it survives', () async {
      // The round trip is the whole point of persisting it, and the second
      // container stands in for the next launch. Both are overridden with the
      // *same* store instance, because `setMockInitialValues` resets the backing
      // map — seeding a second store by hand would test the seed, not the write.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final override = sharedPreferencesProvider.overrideWithValue(prefs);

      final first = ProviderContainer(overrides: [override]);
      addTearDown(first.dispose);
      await first.read(shelfDensityProvider.notifier).set(ShelfDensity.spines);

      final next = ProviderContainer(overrides: [override]);
      addTearDown(next.dispose);

      expect(next.read(shelfDensityProvider), ShelfDensity.spines);
    });

    test(
      'Given cycle is called, When read, Then it advances one step',
      () async {
        final container = await _container();
        addTearDown(container.dispose);

        final notifier = container.read(shelfDensityProvider.notifier);
        await notifier.cycle();
        expect(container.read(shelfDensityProvider), ShelfDensity.leaning);
        await notifier.cycle();
        expect(container.read(shelfDensityProvider), ShelfDensity.spines);
        await notifier.cycle();
        expect(container.read(shelfDensityProvider), ShelfDensity.covers);
      },
    );
  });

  group('ShelfDensityCycle', () {
    test('Given any density, When next is read, Then the cycle wraps', () {
      expect(ShelfDensity.covers.next, ShelfDensity.leaning);
      expect(ShelfDensity.leaning.next, ShelfDensity.spines);
      expect(ShelfDensity.spines.next, ShelfDensity.covers);
    });

    test(
      'Given the cycle, When stepped once per state, Then it returns to the start',
      () {
        var density = ShelfDensity.covers;
        for (var i = 0; i < ShelfDensity.values.length; i++) {
          density = density.next;
        }
        expect(density, ShelfDensity.covers);
      },
    );
  });
}
