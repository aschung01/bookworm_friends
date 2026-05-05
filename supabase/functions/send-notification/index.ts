import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const fcmServerKey = Deno.env.get("FCM_SERVER_KEY")!;

serve(async (req) => {
  const { type, target_user_id, title, body } = await req.json();

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  const { data: profile } = await supabase
    .from("profiles")
    .select("fcm_token")
    .eq("id", target_user_id)
    .single();

  if (!profile?.fcm_token) {
    return new Response(JSON.stringify({ error: "No FCM token" }), {
      status: 404,
    });
  }

  const fcmResponse = await fetch(
    "https://fcm.googleapis.com/fcm/send",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `key=${fcmServerKey}`,
      },
      body: JSON.stringify({
        to: profile.fcm_token,
        notification: { title, body },
        data: { type },
      }),
    }
  );

  const result = await fcmResponse.json();
  return new Response(JSON.stringify(result), { status: 200 });
});
