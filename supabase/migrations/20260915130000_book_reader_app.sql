-- `books.reader_app`: which shop or reader app the owner's copy of this book
-- lives in, or NULL when nothing is known.
--
-- The details page can offer a book's shops (Kindle, Apple Books, Play Books,
-- Libby). Two intents were asked for -- "I want to read this" and "I already own
-- this, take me to it" -- and they have *inverted reliability*. Of eight
-- store x intent cells only two are exact per-book URLs; Amazon publishes no
-- per-book deep link at all, so Kindle can only ever be a search, and
-- `kindle://` opens the app's library rather than a title.
--
-- Which means the second intent cannot be served by guessing. Worse, ownership is
-- unknowable from the client: even with the scheme declared in
-- `LSApplicationQueriesSchemes`, `canLaunchUrl('kindle://')` proves the app is
-- *installed*, never that the book is *in it*. A row of four interchangeable-
-- looking shops would therefore promise something it cannot keep in most cells,
-- and the failure is asymmetric in the worst way: a reader who taps Kindle
-- wanting their copy and lands on an Amazon search results page has been lied to.
--
-- This column is how that is answered without asking. Tapping a shop records it.
-- Afterwards "launch the app" stops being a guess about ownership and becomes
-- exactly right, because the reader said so by acting.
--
-- ---------------------------------------------------------------------------
-- Nullable, and NULL is load-bearing -- the same distinction `page_count` and
-- `cover_color` draw, and for the same reason rather than the reason `authors` is
-- NOT NULL DEFAULT '{}'.
--
-- `authors` defaults because nothing downstream tells "never backfilled" from "no
-- author listed". Here something does, and it drives entirely different UI:
--
--   * NULL     -> the acquire list. Every shop offered, each labelled with what a
--                 tap actually reaches.
--   * a value  -> one primary action for that shop, the sheet retitled "Your
--                 copy", and the verb reduced to what that shop can honestly
--                 deliver.
--
-- Two behaviours fall out of that for free, rather than needing rules of their
-- own. **Status conditionality**: an Interested book has nothing stored, so it
-- shows the acquire list, while a Reading book that was tapped through shows
-- Open -- no explicit `status != 2` guard of the kind `_ReactButton` carries.
-- **Owner conditionality**: this is the *owner's* fact, so a friend's book always
-- shows the acquire list and never "Open Kindle" because its owner uses Kindle.
-- A friend's book consequently needs no write path at all, which the existing
-- books policies would refuse anyway.
--
-- ---------------------------------------------------------------------------
-- `text`, holding a short opaque key: 'play' | 'apple' | 'kindle' | 'libby'.
--
-- Not an enum type. The set is expected to change per market -- Korean readers
-- use 리디북스, 밀리의서재, 예스24 and 교보, and Libby maps to US and UK library
-- systems, so it is meaningless there -- and `ALTER TYPE ... ADD VALUE` cannot run
-- in a transaction with other DDL, which makes an enum the more expensive shape
-- for the thing most likely to grow.
--
-- No CHECK constraint, for the same reason `cover_color` has none: an unknown
-- value is ignored at the point of use. `storeIdFromKey` returns null for
-- anything it does not recognise, which puts the book back on the acquire list --
-- exactly what it showed before it was ever tapped. A constraint here would risk
-- failing a write over a cosmetic column, and a build that learns a new shop key
-- would start rejecting rows against an older database.
--
-- No index. The only reader is a per-book widget rendering a row the app has
-- already fetched in full.
--
-- No backfill. There is nothing to backfill *from*: no prior column, no external
-- source, and no way to infer where a reader's copy lives. Every existing row
-- correctly reads as "nothing known yet".
--
-- ---------------------------------------------------------------------------
-- A tap is not a purchase, and this column cannot tell the difference. Tapping
-- Kindle to check a price and never buying leaves a book wrongly marked, so the
-- sheet always carries a way to clear this back to NULL. That is why the value is
-- treated as a hint rather than as a fact anywhere it is read.
-- ---------------------------------------------------------------------------

ALTER TABLE public.books
  ADD COLUMN reader_app text;

COMMENT ON COLUMN public.books.reader_app IS
  'Which shop or reader app the owner''s copy lives in (''play'', ''apple'', '
  '''kindle'', ''libby''), or NULL when nothing is known. Inferred from the '
  'owner tapping that shop, so it is a hint and not a fact -- the reader can '
  'always clear it. NULL shows the acquire list; a value shows one Open action. '
  'Unrecognised values are ignored at the point of use, which is why there is '
  'no CHECK.';
