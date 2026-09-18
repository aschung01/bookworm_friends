// The fork keeps the original's library name, so the import path is
// `cached_network_image_ce/cached_network_image.dart` rather than the doubled
// `_ce` you would expect from the package name.
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// Resolves a book's stored thumbnail URL to something [Image] can draw.
///
/// Unlike an avatar, a cover is **not** ours: `books.thumbnail` holds an absolute URL
/// handed to us by whichever catalogue found the book — Kakao's CDN, `books.google.com`,
/// or `covers.openlibrary.org`. Nothing about it is fetched from Supabase, so there is no
/// bucket, no token and no path to assemble. The whole job is caching.
typedef CoverImageResolver = ImageProvider Function(String url);

/// Swappable so widget tests can draw a cover without a network.
///
/// The same seam, for the same reason, as `avatarImageProvider`: Flutter's test binding
/// stubs HTTP to return 400 and there is no `path_provider` under `flutter test`, so a
/// real [CachedNetworkImageProvider] never resolves. Tests assign a fake here and restore
/// [networkCoverImage] afterwards.
///
/// It is also the reason `cardCoverProviders` exists rather than callers building their
/// own providers: the list handed to a precache must be the same objects the row draws,
/// and one resolver is what guarantees that.
///
/// **Lives here rather than beside the shelf that started it** because four places draw a
/// cover — the library card's shelf, [BookWidget], and the owned-book and shelf-preview
/// rows in the bottom sheets. Two of them used to build their own `NetworkImage`, which
/// meant the same jacket was fetched twice and held in memory twice under two different
/// cache keys.
CoverImageResolver coverImageProvider = networkCoverImage;

/// The production resolver. Kept public so tests can restore it.
///
/// **[CachedNetworkImageProvider] rather than [NetworkImage], and the difference is a
/// disk.** `NetworkImage` caches in memory only, so every cold start re-fetched every
/// cover on every shelf — a reader with 200 books paid for 200 requests to draw a screen
/// they had already drawn yesterday.
///
/// No `maxWidth`/`maxHeight`: those resize on disk, and a cover arrives small already
/// (Google Books thumbnails run ~128px wide, Open Library's `-M` ~180px). Shrinking them
/// further would cost a decode-and-re-encode per cover to save nothing, and both the
/// book's drawn width and its spine tone are read off these pixels — [BookWidget] takes
/// the intrinsic aspect ratio from the decode and `coverToneColor` samples it.
///
/// No `cacheKey` either: the URL *is* the identity. A catalogue serves the same bytes for
/// the same URL indefinitely, and a URL that does change is a miss rather than a stale
/// hit, which is the right way round.
ImageProvider networkCoverImage(String url) => CachedNetworkImageProvider(url);
