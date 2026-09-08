/// Calls the `read-book-cover` Edge Function and turns its answers into a type.
///
/// Deliberately takes **bytes**, not a camera. How the photo is obtained is an open
/// question with a real design cost (see `docs/mockups/scan-to-add`), and this layer is
/// the part that does not depend on the answer: the function wants encoded image bytes
/// and a mime type, whoever produced them.
///
/// The result is a *search query*, never a book. An ISBN is an identifier; a model
/// reading stylised cover type is a guess, and it can be confidently wrong in ways an
/// ISBN cannot. So this path ends at the existing search field and results grid, where
/// the user confirms, rather than at the save sheet.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, SupabaseClient;

import 'package:bookworm_friends/core/supabase_config.dart';

/// Outcome of one cover read.
///
/// A sealed type rather than a nullable string because the four failures need four
/// different things said to the user, and collapsing them would mean telling someone on
/// a train that their book does not exist.
sealed class CoverReadResult {
  const CoverReadResult();
}

/// The model read a title. [query] is what goes in the search field.
class CoverReadQuery extends CoverReadResult {
  /// Title and author joined, which is what a person searching for a book types.
  final String query;

  /// Kept apart as well so the UI can show what was read without re-splitting a string
  /// it just joined.
  final String title;
  final String author;

  const CoverReadQuery({
    required this.query,
    required this.title,
    required this.author,
  });
}

/// The call succeeded and the model could not name a book.
///
/// Not an error: the ordinary cause is a photo of a mug, a hand over the title, or type
/// too stylised to transcribe. The advice is about the *photo*, so it is worth
/// distinguishing from every other failure.
class CoverReadUnreadable extends CoverReadResult {
  const CoverReadUnreadable();
}

/// The user has spent their allowance. Retrying immediately cannot help.
class CoverReadRateLimited extends CoverReadResult {
  const CoverReadRateLimited();
}

/// The call did not get through, or the far end broke.
///
/// The one failure where "try again" is honest advice.
class CoverReadFailed extends CoverReadResult {
  /// For the log, never for the user: it carries upstream detail.
  final String detail;
  const CoverReadFailed(this.detail);
}

/// Largest payload the function will accept, mirrored from its own `MAX_IMAGE_BYTES`.
///
/// Checked client-side too so an oversized photo fails instantly and for free, rather
/// than after uploading 4MB over cellular to be told 413. The two constants have to be
/// changed together; the function is the one that enforces it.
const int kMaxCoverImageBytes = 1400000;

/// Reads [bytes] as a book cover.
///
/// [client] is injectable so this is testable without a network or a Supabase instance —
/// the mapping from response to outcome is the part worth pinning, and it is pure.
Future<CoverReadResult> readBookCover(
  Uint8List bytes, {
  String mimeType = 'image/jpeg',
  SupabaseClient? client,
}) async {
  if (bytes.isEmpty) {
    return const CoverReadFailed('empty image');
  }
  if (bytes.lengthInBytes > kMaxCoverImageBytes) {
    // Not a `CoverReadUnreadable`: nothing was read and nothing was charged, and the fix
    // is in the capture step rather than in how the user held the book.
    return CoverReadFailed('image too large: ${bytes.lengthInBytes} bytes');
  }

  try {
    final response = await (client ?? supabase).functions.invoke(
      'read-book-cover',
      body: {'image': base64Encode(bytes), 'mime_type': mimeType},
    );

    final data = response.data;
    if (data is! Map) return const CoverReadFailed('malformed response');

    // `unreadable` comes back as HTTP 200 by design, so it arrives here rather than as a
    // `FunctionException`. That is deliberate on the function's side: it is an answer,
    // not a fault, and routing it through the exception path would put it next to the
    // failures whose advice is "try again".
    if (data['error'] == 'unreadable') return const CoverReadUnreadable();
    if (data['error'] != null) return CoverReadFailed('${data['error']}');

    final title = (data['title'] as String?)?.trim() ?? '';
    final author = (data['author'] as String?)?.trim() ?? '';
    final query = (data['query'] as String?)?.trim() ?? '';

    // A blank query with no error should not happen, and if it does it must not land in
    // the search field: an empty search reads to the user as the feature silently doing
    // nothing.
    if (query.isEmpty) return const CoverReadUnreadable();

    return CoverReadQuery(query: query, title: title, author: author);
  } on FunctionException catch (e) {
    if (e.status == 429) return const CoverReadRateLimited();
    return CoverReadFailed('function ${e.status}: ${e.details}');
  } catch (e) {
    return CoverReadFailed('$e');
  }
}
