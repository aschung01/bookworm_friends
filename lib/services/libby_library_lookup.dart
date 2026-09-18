/// Finding the reader's library, so a Libby link can name a title inside the app.
///
/// **Why this is needed at all**, and it is not a preference: Libby resolves
/// `title/<id>` only *beneath* `library/<key>`. Its own router builds the path from
/// its ancestor route —
///
/// ```js
/// var s = e.match(/^title\/(\d+)(\/(.+))?$/);
/// if (s) { var a = "library/" + this.ancestor.args.key; … }
/// ```
///
/// — so a keyless `libbyapp.com/title/<id>` matches nothing, and a device confirmed
/// it: Libby opened, said **"View not found."** and dropped the reader on the Shelf.
/// One library key is the difference between reaching the book and reaching a shelf.
///
/// **The endpoint, which a previous round concluded did not exist.** That conclusion
/// was wrong, and the way it was wrong is worth recording: `thunder`'s
/// `/v2/libraries` really is a 13,112-row directory that filters only by
/// `libraryKeys` and `websiteIds`, and `/libraries/search` and
/// `/libraries/autocomplete` really do 404. But Libby does not use `thunder` for
/// this. It uses a **separate service** whose base URL its bundle derives by
/// rewriting its own root:
///
/// ```js
/// _createDeweyLocateService: var i = this._serviceURI("ROOT_URI");
///                            i = i.replace("//", "//locate.");
/// … APP.services.deweyLocate.fetch("autocomplete/" + encodeURIComponent(query), …)
/// ```
///
/// Which is `https://locate.libbyapp.com/autocomplete/<query>`, keyless, 200. The
/// lesson generalises: *"this API does not exist"* is a much stronger claim than
/// *"I did not find it on the host I was looking at"*, and only the second one had
/// been established.
///
/// **Two hops, because neither service answers the whole question.** `locate` knows
/// names and geography but returns a system's `websiteId`, not its key; `thunder`
/// maps `websiteId` to `preferredKey`, which is what the URL needs.
///
///  1. `locate.libbyapp.com/autocomplete/<query>` → `branches[]`, each carrying the
///     `systems[]` that run it.
///  2. `thunder.api.overdrive.com/v2/libraries?websiteIds=…` → `preferredKey`.
///
/// **It searches branches, and that turns out to be a feature.** The drawn design
/// worried that a reader would type a branch and find nothing, and spent a whole
/// empty state on warning them. They will not: *"Mission Bay Branch Library"*
/// resolves to San Francisco Public Library, and *"Auburn Library"* to King County
/// Library System. Town, branch and system names all work, which is why the field's
/// hint offers all three.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Short, and for the same reason as the other lookups: this runs while the reader
/// is waiting, and it is typed into. A slow network must cost a result, never a
/// visibly stuck field.
const _timeout = Duration(seconds: 4);

/// How many library systems to carry into the second request.
///
/// One page of `autocomplete` is 30 *branches*, which collapse to far fewer
/// systems. The cap exists because the ids go into a URL, and because a picker
/// listing forty near-identical consortia helps nobody choose.
const _maxResults = 15;

/// Shortest query worth sending. One or two characters match thousands of branches
/// and tell the reader nothing, and this is called per keystroke.
const libbyMinQueryLength = 3;

/// One library system the reader could pick.
class LibbyLibrary {
  const LibbyLibrary({
    required this.key,
    required this.name,
    required this.region,
  });

  /// The `preferredKey`, e.g. `sfpl`. **This is the load-bearing field** — it is
  /// the segment in `libbyapp.com/library/<key>/title/<id>`.
  final String key;

  /// The system's name, e.g. `San Francisco Public Library`.
  final String name;

  /// Where it is, e.g. `California, US`.
  ///
  /// Not decoration. `King County Library System` (Washington) and
  /// `Kings County Library` (California) are one letter apart, and the region is
  /// the only thing on screen that tells them apart.
  final String region;

  @override
  String toString() => 'LibbyLibrary($key, $name, $region)';
}

/// Searches for a library system by name, town or branch.
///
/// Never throws. Offline, a timeout, a non-200 or a malformed body all return an
/// empty list, which the picker shows as "nothing by that name" — the same thing a
/// genuinely unknown name produces, and the distinction is not worth drawing here:
/// the reader's next move is to try different words either way.
Future<List<LibbyLibrary>> libbyLibrarySearch(
  String query, {
  http.Client? client,
}) async {
  final trimmed = query.trim();
  if (trimmed.length < libbyMinQueryLength) return const [];

  Future<String?> get(Uri uri) async {
    final response = await (client?.get(uri) ?? http.get(uri)).timeout(
      _timeout,
    );
    if (response.statusCode != 200) return null;
    // Explicit UTF-8, as with the other lookups: library names are compared and
    // displayed, and a Latin-1 fallback mangles every non-ASCII one.
    return utf8.decode(response.bodyBytes);
  }

  try {
    // `locate.libbyapp.com` puts the query in the **path**, not a parameter, which
    // is why it is percent-encoded as a path segment rather than handed to
    // `Uri.https`'s query map.
    final autocomplete = await get(
      Uri.parse(
        'https://locate.libbyapp.com/autocomplete/'
        '${Uri.encodeComponent(trimmed)}',
      ),
    );
    if (autocomplete == null) return const [];

    final candidates = libbyCandidatesFromAutocompleteJson(autocomplete);
    if (candidates.isEmpty) return const [];

    final libraries = await get(
      Uri.https('thunder.api.overdrive.com', '/v2/libraries', {
        'websiteIds': candidates.map((c) => c.websiteId).join(','),
      }),
    );
    if (libraries == null) return const [];

    final keys = libbyKeysFromLibrariesJson(libraries);
    return [
      for (final candidate in candidates)
        if (keys[candidate.websiteId] case final String key)
          LibbyLibrary(
            key: key,
            name: candidate.name,
            region: candidate.region,
          ),
    ];
  } catch (_) {
    return const [];
  }
}

/// A candidate system from an `autocomplete` response: enough to display, but
/// missing the key.
typedef LibbyCandidate = ({int websiteId, String name, String region});

/// The library systems in an `autocomplete` response, in relevance order.
///
/// Split from the request so the shape is testable without a network. Confirmed
/// against the live endpoint — note the systems are nested **inside each branch**,
/// and the response has no top-level `systems` key at all:
///
/// ```json
/// { "branches": [ { "name": "Mission Bay Branch Library",
///                   "region": "California", "countryCode": "US",
///                   "systems": [ { "websiteId": 372,
///                                  "name": "San Francisco Public Library" } ] } ],
///   "total": 30 }
/// ```
///
/// **Deduplicated by `websiteId`, keeping the first occurrence.** A system runs many
/// branches, so a search for a town returns the same system repeatedly; and first
/// occurrence preserves the endpoint's own relevance order (`sortDirection:
/// "relevance"`), which is the only ranking signal available.
///
/// The region comes off the **branch**, not the system: a branch carries a spelled
/// out `region` (`"California"`) where the system carries only a code list
/// (`["CA"]`), and the drawn design reads `Washington, US`.
List<LibbyCandidate> libbyCandidatesFromAutocompleteJson(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map<String, dynamic>) return const [];
  final branches = decoded['branches'];
  if (branches is! List) return const [];

  final out = <LibbyCandidate>[];
  final seen = <int>{};
  for (final branch in branches.whereType<Map<String, dynamic>>()) {
    final systems = branch['systems'];
    if (systems is! List) continue;
    for (final system in systems.whereType<Map<String, dynamic>>()) {
      final websiteId = system['websiteId'];
      final name = system['name'];
      if (websiteId is! int || name is! String || name.isEmpty) continue;
      if (!seen.add(websiteId)) continue;
      out.add((
        websiteId: websiteId,
        name: name,
        region: _region(branch['region'], branch['countryCode']),
      ));
      if (out.length == _maxResults) return out;
    }
  }
  return out;
}

/// `websiteId` → `preferredKey`, from a `thunder` `/v2/libraries` response.
///
/// The shape, confirmed live. Note **`preferredKey` and not `baseKey`** — the latter
/// comes back null on this endpoint even for libraries that plainly have a key:
///
/// ```json
/// { "items": [ { "websiteId": 372, "preferredKey": "sfpl", "baseKey": null,
///                "name": "San Francisco Public Library" } ] }
/// ```
///
/// **Not every id asked about comes back.** Three `websiteIds` returned two
/// libraries, so this is a lookup rather than a positional mapping, and a candidate
/// with no key is dropped rather than guessed at — a wrong key would send the reader
/// to Libby's "trouble fetching details about this library" screen, which is the
/// exact bug this whole row started with.
Map<int, String> libbyKeysFromLibrariesJson(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const {};
  }
  // Tolerates both an `{items: [...]}` envelope and a bare list, because the two
  // OverDrive services this file talks to disagree about which they return.
  final items = switch (decoded) {
    Map<String, dynamic> map => map['items'],
    List<Object?> list => list,
    _ => null,
  };
  if (items is! List) return const {};

  final out = <int, String>{};
  for (final item in items.whereType<Map<String, dynamic>>()) {
    final websiteId = item['websiteId'];
    final key = item['preferredKey'];
    if (websiteId is! int || key is! String || key.isEmpty) continue;
    out[websiteId] = key;
  }
  return out;
}

String _region(Object? region, Object? countryCode) {
  final parts = [
    if (region is String && region.trim().isNotEmpty) region.trim(),
    if (countryCode is String && countryCode.trim().isNotEmpty)
      countryCode.trim(),
  ];
  return parts.join(', ');
}
