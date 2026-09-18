import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Fired fire-and-forget from `handle_new_user()` via `net.http_post` whenever
// a brand-new signup's provider (currently only Google) supplied a photo in
// `raw_user_meta_data.avatar_url`. Nothing waits on the response, so every
// failure here is swallowed and logged rather than surfaced -- by the time
// this runs the account already exists with a perfectly good emoji avatar,
// and this function only ever improves on that, never blocks it.

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Matches the `avatars` bucket's own `file_size_limit` / `allowed_mime_types`
// (20260819154523_add_profile_avatar.sql). Checked here too so an oversized or
// wrong-typed fetch fails fast with a clear reason instead of a bare storage
// error.
const MAX_BYTES = 1_048_576;
const EXT_FOR_TYPE: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

serve(async (req) => {
  const { user_id, avatar_url } = await req.json();

  if (!user_id || !avatar_url) {
    return new Response(
      JSON.stringify({ error: "Missing user_id or avatar_url" }),
      { status: 400 },
    );
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  try {
    // Never overwrite a photo that already exists. Not reachable today --
    // this only runs once, from an AFTER INSERT trigger on a table that never
    // gets updated in place -- but the check is one query and it is what
    // makes "never overwrite a chosen photo" true by construction rather than
    // by the trigger only ever firing once.
    const { data: profile } = await supabase
      .from("profiles")
      .select("avatar_path")
      .eq("id", user_id)
      .single();

    if (profile?.avatar_path) {
      return new Response(JSON.stringify({ skipped: "avatar already set" }), {
        status: 200,
      });
    }

    // Google's `picture` claim is a 96px thumbnail
    // (`...googleusercontent.com/...=s96-c`). AvatarCircle draws at 40px on a
    // retina display, so ask for something closer to that instead of the
    // default thumbnail or a full-resolution original neither of us needs.
    const sizedUrl = avatar_url.includes("googleusercontent.com")
      ? avatar_url.replace(/=s\d+-c$/, "=s256-c")
      : avatar_url;

    const imageResponse = await fetch(sizedUrl);
    if (!imageResponse.ok) {
      throw new Error(`provider image fetch failed: ${imageResponse.status}`);
    }

    const contentType = imageResponse.headers.get("content-type") ?? "";
    const ext = EXT_FOR_TYPE[contentType];
    if (!ext) {
      throw new Error(`unsupported content-type: ${contentType}`);
    }

    const bytes = new Uint8Array(await imageResponse.arrayBuffer());
    if (bytes.byteLength > MAX_BYTES) {
      throw new Error(`provider image too large: ${bytes.byteLength} bytes`);
    }

    // Same shape as the client's own upload path: a fresh random name per
    // upload, under the user's own folder, which is also what
    // `profiles_avatar_path_owned` requires.
    const path = `${user_id}/${crypto.randomUUID()}.${ext}`;
    const { error: uploadError } = await supabase.storage
      .from("avatars")
      .upload(path, bytes, { contentType });

    if (uploadError) throw uploadError;

    const { error: updateError } = await supabase
      .from("profiles")
      .update({ avatar_path: path })
      .eq("id", user_id);

    if (updateError) throw updateError;

    return new Response(JSON.stringify({ success: true, path }), {
      status: 200,
    });
  } catch (error) {
    console.error("import-social-avatar failed", error);
    // 200, not 500: the caller is a trigger-side `net.http_post` with nothing
    // listening for the result, so there is no one for a failure status to
    // reach. The log line is the only audience.
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 200,
    });
  }
});
