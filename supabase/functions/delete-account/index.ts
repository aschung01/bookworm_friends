import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "No auth header" }), {
      status: 401,
    });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Invalid token" }), {
      status: 401,
    });
  }

  // Storage objects are not cascaded by `deleteUser` the way the `profiles` row
  // is, so without this an avatar outlives its owner forever in a bucket nobody
  // can list. Best-effort and *before* the delete: a failure here should not
  // block someone leaving, and the alternative order would drop the only record
  // of which folder was theirs.
  try {
    const { data: objects } = await supabase.storage
      .from("avatars")
      .list(user.id);

    if (objects && objects.length > 0) {
      await supabase.storage
        .from("avatars")
        .remove(objects.map((o) => user.id + "/" + o.name));
    }
  } catch (_) {
    // Swallowed on purpose. An orphaned object is a cost; a user who cannot
    // delete their account is a bug.
  }

  const { error: deleteError } = await supabase.auth.admin.deleteUser(user.id);

  if (deleteError) {
    return new Response(JSON.stringify({ error: deleteError.message }), {
      status: 500,
    });
  }

  return new Response(JSON.stringify({ success: true }), { status: 200 });
});
