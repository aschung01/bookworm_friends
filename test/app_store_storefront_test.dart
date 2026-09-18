// The reader's App Store storefront, which decides which Apple Books catalogue any
// Apple URL is scoped to.
//
// **The defect this replaced.** `storeCountryFor` used to guess the storefront from
// the device language, and that was wrong in both directions: it hid Apple Books from
// a Korean-language phone signed in to a US account, and it handed `/us/` links to an
// English-language phone signed in to a Korean one — whose store answers those with a
// 404. Only the Apple ID knows, and only StoreKit can be asked.
//
// The channel is faked here rather than mocked at the platform layer, because what is
// worth pinning is the **conversion and the failure handling**, not Flutter's own
// message plumbing.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/app_store_storefront.dart';

/// Answers `storefrontCountryCode` with [reply], or throws [error].
///
/// Registered against the real channel name so the service under test is exercised
/// exactly as it ships.
void fakeStorefront({Object? reply, Object? error}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(appStoreChannel, (call) async {
        expect(call.method, 'storefrontCountryCode');
        if (error != null) throw error;
        return reply;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appStoreChannel, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('alpha2FromAlpha3', () {
    // StoreKit returns alpha-3 and Apple's own search API **rejects** it:
    // `itunes.apple.com/search?country=USA` answers with a non-JSON error where
    // `country=us` works. So the conversion is not cosmetic.
    test('converts the codes this app actually cares about', () {
      expect(alpha2FromAlpha3('USA'), 'us');
      expect(alpha2FromAlpha3('KOR'), 'kr');
      expect(alpha2FromAlpha3('JPN'), 'jp');
      expect(alpha2FromAlpha3('GBR'), 'gb');
    });

    // Lowercase, always: it goes into a URL path segment that Apple serves
    // case-sensitively in practice, and into a query parameter.
    test('always answers in lower case', () {
      for (final code in ['USA', 'usa', 'Usa']) {
        expect(alpha2FromAlpha3(code), 'us', reason: code);
      }
    });

    // Spot checks across the table, including two that are easy to get wrong because
    // the alpha-2 shares no letters with the alpha-3.
    test('handles codes whose two forms do not resemble each other', () {
      expect(alpha2FromAlpha3('DEU'), 'de');
      expect(alpha2FromAlpha3('CHE'), 'ch');
      expect(alpha2FromAlpha3('PRK'), 'kp'); // North Korea
      expect(alpha2FromAlpha3('MAC'), 'mo');
      expect(alpha2FromAlpha3('MYT'), 'yt');
    });

    // **The guard that makes a packed string safe.** Entries are five characters in a
    // space-separated run, so a naive substring search could match across a boundary:
    // 'AAU' would otherwise be found inside 'AUSau ATFtf'. Offsets must be multiples
    // of six.
    test('does not match across an entry boundary', () {
      // 'sau' spans the end of one token; 'SAU' proper must still resolve.
      expect(alpha2FromAlpha3('SAU'), 'sa');
      // Fabricated codes that appear as substrings of the packed table, if the
      // boundary check were missing.
      expect(alpha2FromAlpha3('AAU'), isNull);
      expect(alpha2FromAlpha3('SAF'), isNull);
    });

    // Returning null rather than a guess is deliberate: the caller falls back to the
    // locale, whereas a mangled code would build a URL for a storefront that does not
    // exist.
    test('is null for anything it does not recognise', () {
      expect(alpha2FromAlpha3('ZZZ'), isNull);
      expect(alpha2FromAlpha3(''), isNull);
      expect(alpha2FromAlpha3('US'), isNull);
      expect(alpha2FromAlpha3('USAA'), isNull);
    });
  });

  group('appStoreStorefrontCountry', () {
    test('converts what StoreKit reports', () async {
      fakeStorefront(reply: 'KOR');
      expect(await appStoreStorefrontCountry(), 'kr');
    });

    // **Null is an ordinary answer, not a failure**, and every one of these paths is
    // reached in normal use: no signed-in account on the simulator, and a short window
    // early in launch before StoreKit has resolved a storefront.
    test('a null storefront is null, not an error', () async {
      fakeStorefront(reply: null);
      expect(await appStoreStorefrontCountry(), isNull);
    });

    // The ordinary case on Android, where no channel is registered at all. Must not
    // throw into the sheet-opening path.
    test('a missing channel is null, which is the Android case', () async {
      expect(
        await appStoreStorefrontCountry(
          channel: const MethodChannel('bookworm/does_not_exist'),
        ),
        isNull,
      );
    });

    test('a platform error is null', () async {
      fakeStorefront(error: PlatformException(code: 'nope'));
      expect(await appStoreStorefrontCountry(), isNull);
    });

    // A storefront StoreKit knows about but the table does not would otherwise build
    // a URL for a nonexistent Apple storefront.
    test('an unrecognised code is null rather than passed through', () async {
      fakeStorefront(reply: 'ZZZ');
      expect(await appStoreStorefrontCountry(), isNull);
    });
  });
}
