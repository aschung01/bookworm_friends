// Finding the reader's library, which is what makes a Libby link exact.
//
// **Every fixture is trimmed from a live response.** The two services involved
// disagree about envelope shape and about which field holds the key, and both
// disagreements are the kind that a hand-invented fixture quietly gets right and
// production gets wrong.
//
// No network here: the two functions under test are the pure halves of the lookup.

import 'package:flutter_test/flutter_test.dart';

import 'package:bookworm_friends/services/libby_library_lookup.dart';

/// `locate.libbyapp.com/autocomplete/san francisco`, trimmed. Note the systems are
/// nested **inside each branch**, and the response has no top-level `systems` key.
const _sanFrancisco = '''
{ "branches": [
    { "id": 56307, "name": "Main Library", "city": "San Francisco",
      "region": "California", "countryCode": "US",
      "systems": [ { "id": 1683, "websiteId": 372,
                     "name": "San Francisco Public Library" } ] },
    { "id": 56308, "name": "Mission Bay Branch Library", "city": "San Francisco",
      "region": "California", "countryCode": "US",
      "systems": [ { "id": 1683, "websiteId": 372,
                     "name": "San Francisco Public Library" } ] } ],
  "total": 30, "sortDirection": "relevance" }
''';

/// The case the picker's second line exists for: two systems one letter apart, in
/// different states.
const _kingCounty = '''
{ "branches": [
    { "name": "Auburn Library", "region": "Washington", "countryCode": "US",
      "systems": [ { "websiteId": 12, "name": "King County Library System" } ] },
    { "name": "Hanford Branch", "region": "California", "countryCode": "US",
      "systems": [ { "websiteId": 999, "name": "Kings County Library" } ] } ],
  "total": 2 }
''';

/// `thunder/v2/libraries?websiteIds=372,1047,111`. **Three ids were asked about and
/// two came back**, which is why the mapping is by lookup and not by position.
const _libraries = '''
{ "items": [
    { "websiteId": 372, "preferredKey": "sfpl", "baseKey": null,
      "name": "San Francisco Public Library" },
    { "websiteId": 111, "preferredKey": "huntington", "baseKey": null,
      "name": "Huntington Public Library" } ] }
''';

void main() {
  group('libbyCandidatesFromAutocompleteJson', () {
    // A system runs many branches, so a town search returns it once per branch.
    // First occurrence is kept because the endpoint sorts by relevance and that is
    // the only ranking signal there is.
    test('collapses a system that appears under several branches', () {
      final got = libbyCandidatesFromAutocompleteJson(_sanFrancisco);
      expect(got, hasLength(1));
      expect(got.single.websiteId, 372);
      expect(got.single.name, 'San Francisco Public Library');
    });

    // The region comes off the **branch**, which spells it out ("California"),
    // rather than the system, which carries only a code list (["CA"]).
    test('labels a system with a spelled-out region and country', () {
      expect(
        libbyCandidatesFromAutocompleteJson(_sanFrancisco).single.region,
        'California, US',
      );
    });

    // **The reason the picker has two lines per row.** These two differ by one
    // letter, and nothing but the region tells a reader which is theirs.
    test('keeps two near-identically named systems apart', () {
      final got = libbyCandidatesFromAutocompleteJson(_kingCounty);
      expect(got.map((c) => '${c.name} (${c.region})'), [
        'King County Library System (Washington, US)',
        'Kings County Library (California, US)',
      ]);
    });

    // The endpoint searches branches and resolves them to the system that runs
    // them, so a branch name is a *working* query. Pinned because the drawn design
    // assumed the opposite and spent an empty state warning readers off it.
    test('resolves a branch name to the system that runs it', () {
      const branchOnly = '''
        { "branches": [
            { "name": "Mission Bay Branch Library", "region": "California",
              "countryCode": "US",
              "systems": [ { "websiteId": 372,
                             "name": "San Francisco Public Library" } ] } ] }
      ''';
      expect(
        libbyCandidatesFromAutocompleteJson(branchOnly).single.name,
        'San Francisco Public Library',
      );
    });

    test('a query matching nothing yields nothing', () {
      expect(
        libbyCandidatesFromAutocompleteJson(
          '{"branches": [], "total": 0, "count": 0}',
        ),
        isEmpty,
      );
    });

    test('treats an unusable body as no answer', () {
      expect(libbyCandidatesFromAutocompleteJson('<html>502</html>'), isEmpty);
      expect(libbyCandidatesFromAutocompleteJson('[]'), isEmpty);
      expect(
        libbyCandidatesFromAutocompleteJson('{"branches": "no"}'),
        isEmpty,
      );
      // A branch with no systems is not malformed, just useless here.
      expect(
        libbyCandidatesFromAutocompleteJson('{"branches": [{"name": "x"}]}'),
        isEmpty,
      );
    });

    // The ids go into a URL, and a list of forty near-identical consortia helps
    // nobody choose.
    test('caps the number of systems carried forward', () {
      final branches = List.generate(
        40,
        (i) =>
            '{"region": "R", "countryCode": "US", "systems": '
            '[{"websiteId": ${1000 + i}, "name": "System $i"}]}',
      ).join(',');
      expect(
        libbyCandidatesFromAutocompleteJson('{"branches": [$branches]}'),
        hasLength(15),
      );
    });
  });

  group('libbyKeysFromLibrariesJson', () {
    // **`preferredKey`, not `baseKey`** — the latter comes back null on this
    // endpoint even for libraries that plainly have a key, so reading it would
    // silently find nothing for every library.
    test('maps websiteId to preferredKey', () {
      expect(libbyKeysFromLibrariesJson(_libraries), {
        372: 'sfpl',
        111: 'huntington',
      });
    });

    // The two OverDrive services this file talks to disagree about the envelope.
    test('accepts a bare list as well as an items envelope', () {
      expect(
        libbyKeysFromLibrariesJson(
          '[{"websiteId": 372, "preferredKey": "sfpl"}]',
        ),
        {372: 'sfpl'},
      );
    });

    // A library with no usable key is **dropped, never guessed at**. A wrong key
    // lands the reader on Libby's "trouble fetching details about this library"
    // screen, which is the exact bug this whole row started with.
    test('drops a library with no usable key', () {
      expect(
        libbyKeysFromLibrariesJson('''
          { "items": [ { "websiteId": 372, "preferredKey": null },
                       { "websiteId": 373, "preferredKey": "" },
                       { "websiteId": 374, "name": "No key at all" } ] }
        '''),
        isEmpty,
      );
    });

    test('treats an unusable body as no answer', () {
      expect(libbyKeysFromLibrariesJson('nope'), isEmpty);
      expect(
        libbyKeysFromLibrariesJson('{"message": "Library not found"}'),
        isEmpty,
      );
    });
  });

  group('the two halves compose', () {
    // The point of the split: `locate` knows names, `thunder` knows keys, and a
    // candidate survives only if both answered about it. 372 has a key here; the
    // Kings County id does not, so it does not reach the picker.
    test('only candidates with a resolved key can be offered', () {
      final candidates = libbyCandidatesFromAutocompleteJson(_kingCounty);
      final keys = libbyKeysFromLibrariesJson(_libraries);
      final offered = [
        for (final c in candidates)
          if (keys[c.websiteId] != null) c.name,
      ];
      expect(candidates, hasLength(2));
      expect(offered, isEmpty, reason: 'neither id appears in the key map');

      final sf = libbyCandidatesFromAutocompleteJson(_sanFrancisco);
      expect(keys[sf.single.websiteId], 'sfpl');
    });
  });
}
