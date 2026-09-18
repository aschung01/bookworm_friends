-- `books.cover_color` is no longer an average, and this updates the column's own
-- description to say so.
--
-- No schema change. `20260822120000_book_cover_color.sql` documented the column as the
-- mean of the decoded thumbnail, taken by a 1x1 GPU downsample, and both halves of that
-- have since been replaced:
--
--   * The 1x1 `drawImageRect` was wrong on the device. Impeller returns roughly a single
--     texel at a 1x1 destination rather than a mipmapped average, so measured against 56
--     real covers the stored values were up to 110/255 from the true mean. Averaging is
--     now done in Dart, which also makes a phone, a widget test and the backfill tool
--     agree by construction.
--   * The mean itself turned out to be the wrong thing to want. It mixes type and artwork
--     into the answer, so a bright yellow jacket stores an olive that is nowhere on the
--     book. Measured over the 474 covers in this table, the mean is a colour present on a
--     median of **3%** of its own jacket.
--
-- What is stored now is the cover's **background** where the evidence supports one, and
-- the mean only as a fallback. The background is the mode of a histogram over the head
-- and flanks of the image -- deliberately not the foot, which is usually an obi, a
-- printed band, or the paper the book was photographed on -- with a detected paper
-- margin excluded by colour, and with a split border decided by which candidate covers
-- more of the whole jacket. `lib/ui/widgets/book/cover_sample.dart` documents each of
-- those corrections and the cover that forced it.
--
-- The effect on this table, measured before applying:
--
--   * 315 of 474 rows now take a background, against 222 before.
--   * The median share of the jacket actually occupied by the stored colour rose from
--     25% to 40%.
--   * Rows storing a colour present on under 5% of their own cover fell from 155 to 91.
--
-- Nullability, type and the absence of a CHECK are all unchanged, and so are the reasons
-- for them -- see the original migration. A malformed value is still ignored at the point
-- of use by `bookCoverColorFromHex`, which puts the book back on its ISBN-derived swatch
-- rather than losing the row.

COMMENT ON COLUMN public.books.cover_color IS
  'The book''s cover colour as #RRGGBB, or NULL when its thumbnail has never been '
  'decoded. Resolved by coverToneColor: the mode of the cover''s head and flanks when '
  'that carries enough of the evidence, otherwise the alpha-weighted sRGB mean of every '
  'pixel. Drives the read pile''s spine tone and the 3D chassis'' back board; NULL falls '
  'back to a swatch derived from the ISBN. Never shown to the reader as a value.';
