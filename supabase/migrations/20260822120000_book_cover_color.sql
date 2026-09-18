-- `books.cover_color`: the average colour of a book's cover, stored.
--
-- The read pile draws each spine in a darkened form of its own cover's colour
-- (see `docs/superpowers/specs/2026-08-22-read-pile-spines-design.md`). The app
-- can already compute that colour -- `_sampleCoverColor` in `book_widget.dart`
-- downsamples a decoded cover to a single pixel to pick the back board behind it
-- -- so the obvious implementation is to sample it in the pile and store nothing.
--
-- That does not work, and the reason is timing rather than cost. The sample only
-- exists after the image resolves. A pile that sampled would therefore:
--
--   * fetch and decode every visible cover on the Library tab's *resting* state,
--     which today loads no images at all; and
--   * paint a colourless pile on a cold start and then colour it in, because
--     until each stream resolves the spine has no tone to use.
--
-- The second is the disqualifying one. `20260816160000_book_page_count.sql`
-- settled the identical question one property over: page count is stored, not
-- fetched on open, because "a book cannot change thickness while it is on
-- screen". A book changing colour while it is on screen is the same defect in a
-- different property, and the same answer applies.
--
-- ---------------------------------------------------------------------------
-- Nullable, and for the same reason `page_count` is nullable rather than for the
-- reason `authors` is NOT NULL.
--
-- `authors` defaults to '{}' on the grounds that nothing downstream distinguishes
-- "never backfilled" from "no author listed". Here something does: a value gives
-- the spine its cover's tone, while NULL routes it to `generatedCoverColor(isbn)`
-- -- one of six brand-harmonised swatches, derived from the ISBN, needing no
-- network. The two states drive different code, so the type has to tell them
-- apart.
--
-- That fallback is what makes this column safe to add without a backfill: every
-- spine has a colour on the first frame whatever proportion of rows is populated,
-- and a partly-filled table produces a pile of cover tones and generated tones
-- side by side rather than a pile with holes in it.
--
-- ---------------------------------------------------------------------------
-- `text`, holding `#RRGGBB`.
--
-- Alpha is deliberately absent: this is the average of an opaque cover, and a
-- transparent spine is not a state worth being able to represent. Hex rather than
-- an integer because it is legible in a psql session and in a Supabase table
-- view, and the only consumer parses it once at the client boundary.
--
-- No CHECK. A malformed value is ignored at the point of use --
-- `bookCoverColorFromHex` returns null for anything that is not six hex digits,
-- which puts the book back on the generated-cover fallback -- exactly the trade
-- `page_count` makes by clamping a nonsense count instead of rejecting the row.
-- A constraint here would lose a book over a cosmetic column.
--
-- No index. The only reader is a per-book widget rendering rows the app has
-- already fetched in full.
--
-- ---------------------------------------------------------------------------
-- How it gets populated.
--
--   1. At insert, from the cover the Add Book flow has already decoded.
--   2. For rows written before this column, opportunistically: `BookWidget`
--      already samples every cover it decodes, and reports the result to its
--      caller, which writes it back when the column is null and the book belongs
--      to the signed-in user.
--
-- Both paths run the app's own sampler, so a stored colour and a freshly sampled
-- one cannot disagree. A server-side backfill was rejected for that reason: no
-- server-side average equals Flutter's 1x1 GPU downsample, so every book would
-- visibly change tone on the day it ran.
-- ---------------------------------------------------------------------------

ALTER TABLE public.books
  ADD COLUMN cover_color text;

COMMENT ON COLUMN public.books.cover_color IS
  'Average colour of the book''s cover as #RRGGBB, sampled from the decoded '
  'thumbnail, or NULL when it has never been sampled. Drives the read pile''s '
  'spine tone and the 3D chassis'' back board; NULL falls back to a swatch '
  'derived from the ISBN. Never shown to the reader as a value.';
