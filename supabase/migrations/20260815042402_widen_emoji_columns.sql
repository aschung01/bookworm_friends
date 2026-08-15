-- Praise is a free emoji now, and `varchar(6)` cannot hold one.
--
-- The column was sized when the app offered a fixed 16-emoji palette, where the
-- widest entry was ❤️ at two code points. A free picker reaches emoji that are
-- far wider: of the 3,544 in the Unicode set, 290 exceed six code points --
-- families at seven or eight, couples with skin tones at ten (🧑🏿‍❤️‍💋‍🧑🏾).
-- Postgres `varchar(n)` counts characters, so those are rejected outright rather
-- than truncated, and the insert fails.
--
-- The live data already argued for this: 28 of the 39 existing praises are emoji
-- outside the fixed 16, dated 2022-2024 and shaped like system-keyboard output
-- (✌🏻 carries a skin-tone modifier, ☃️ a variation selector). The palette was
-- never what people used.
--
-- `profiles.emoji` widens with it: both columns are written by the same sheet.

ALTER TABLE public.book_compliments
  ALTER COLUMN compliment TYPE text;

ALTER TABLE public.profiles
  ALTER COLUMN emoji TYPE text;

-- A cap is what keeps "free" from quietly becoming a text field. Sixteen code
-- points clears the widest emoji that exists with headroom while still refusing
-- prose, and the lower bound refuses the empty string.
--
-- Note this is deliberately a *length* check and not a membership check against
-- a known emoji list: any such list would reject the 28 legacy rows, and the
-- point of the change is that they are legitimate.
ALTER TABLE public.book_compliments
  ADD CONSTRAINT book_compliments_compliment_length
  CHECK (char_length(compliment) BETWEEN 1 AND 16);

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_emoji_length
  CHECK (emoji IS NULL OR char_length(emoji) BETWEEN 1 AND 16);
