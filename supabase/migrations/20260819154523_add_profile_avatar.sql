-- Profile photos: an optional image avatar alongside the emoji one.
--
-- The emoji is not replaced. It stays as the placeholder while a photo loads,
-- the fallback when a fetch fails, and the answer for everyone who never
-- uploads anything -- so the avatar never depends on the network to render.

-- The *object path*, never a URL. A URL would bake in the bucket, the project
-- ref and the public-vs-authenticated choice, all of which can change; a path
-- survives all three. Each upload gets a fresh random filename, so a change of
-- photo is a change of path, which is also what busts every cache without
-- needing an `avatar_updated_at` column.
ALTER TABLE public.profiles ADD COLUMN avatar_path text;

-- `avatar_path` is client-supplied, and the storage read below authorises
-- against the *folder owner*. Without this a user could point their row at
-- somebody else's object and wear their face -- including a private user
-- wearing a public one's. Pinning the path to the row's own id closes that for
-- one line, in the same spirit as `profiles_emoji_length`.
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_avatar_path_owned
  CHECK (avatar_path IS NULL OR avatar_path LIKE id::text || '/%');

-- A *private* bucket. `is_profile_visible` already gates shelves, books and
-- memos on public-OR-self-OR-you-follow-them; a public bucket would make the
-- profile photo the one thing `is_private` does not cover, and a public object
-- URL that has escaped cannot be recalled.
--
-- Reads do not need signed URLs. `GET /storage/v1/object/avatars/{path}` with
-- the caller's JWT enforces these policies per request and carries no
-- signature, so the URL derived from `avatar_path` is stable and cacheable
-- while authorisation lives in a header the HTTP cache never sees.
--
-- The size and mime limits here are the only ones that bind -- the client-side
-- checks are a courtesy to the user, not a defence. 1MB is far above what a
-- 512px re-encode produces and still refuses a raw phone photo outright.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  false,
  1048576,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Your own folder, every verb. The path is `{user_id}/{random}.{ext}`, so the
-- first segment is the owner and `auth.uid()` is the whole check.
--
-- Deliberately `FOR ALL` rather than a bare INSERT: replacing a photo needs
-- DELETE for the old object, and SELECT so the owner can always read their own
-- avatar even in the moment between the upload and the profile row pointing at
-- it. (This also sidesteps Supabase's upsert trap, where INSERT alone makes
-- overwrites fail silently -- nothing here upserts, because every upload gets a
-- new name.)
CREATE POLICY "Users manage own avatar" ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Everyone else reads an avatar on exactly the rule that governs the books.
--
-- Joined through `profiles.avatar_path` rather than casting the path's first
-- segment to uuid. Two reasons: a cast would throw on any object whose folder
-- is not a uuid, and throwing inside a policy fails the whole evaluation rather
-- than denying one row. And the join is strictly tighter -- only the object a
-- profile *currently* points at is readable, so a replaced photo becomes
-- unreadable the instant the row moves, without waiting on the cleanup delete.
CREATE POLICY "Users read visible avatars" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'avatars'
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.avatar_path = storage.objects.name
        AND public.is_profile_visible(p.id)
    )
  );
