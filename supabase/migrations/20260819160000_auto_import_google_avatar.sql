-- Auto-import a Google profile photo on signup, when Google supplied one.
--
-- Apple never gives us anything to import here -- its identity payload is
-- email, email_verified, iss, provider_id, sub, and nothing resembling a
-- picture -- so this only ever fires for the google provider. Gotrue already
-- writes Google's `picture` claim into `raw_user_meta_data.avatar_url` on
-- every OAuth signup; nothing before this migration ever read it.
--
-- Fire-and-forget over `net.http_post`, the same pattern `poke_user`
-- (20260505053443_poke_function.sql) already uses to reach an Edge Function
-- from inside Postgres. Postgres cannot itself fetch an external image or
-- call Storage's binary upload endpoint, so that work moves to
-- `import-social-avatar`, which runs after this trigger's INSERT has already
-- committed the profile row and can fail without taking signup down with it.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  provider_avatar_url text;
BEGIN
  INSERT INTO public.profiles (id) VALUES (NEW.id);

  provider_avatar_url := NEW.raw_user_meta_data ->> 'avatar_url';

  IF NEW.raw_app_meta_data ->> 'provider' = 'google'
     AND provider_avatar_url IS NOT NULL THEN
    PERFORM net.http_post(
      url := current_setting('app.settings.edge_function_url') || '/import-social-avatar',
      body := jsonb_build_object(
        'user_id', NEW.id,
        'avatar_url', provider_avatar_url
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
