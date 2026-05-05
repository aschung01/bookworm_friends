CREATE OR REPLACE FUNCTION public.poke_user(target_username text)
RETURNS void AS $$
DECLARE
  target_id uuid;
  target_token text;
  poker_username text;
BEGIN
  SELECT id, fcm_token INTO target_id, target_token
  FROM public.profiles
  WHERE username = target_username;

  SELECT username INTO poker_username
  FROM public.profiles
  WHERE id = auth.uid();

  IF target_token IS NOT NULL THEN
    PERFORM net.http_post(
      url := current_setting('app.settings.edge_function_url') || '/send-notification',
      body := jsonb_build_object(
        'type', 'poke',
        'target_user_id', target_id,
        'title', poker_username || '님이 콕 찔렀어요!',
        'body', '읽고 있는 책이 궁금해요'
      )
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
