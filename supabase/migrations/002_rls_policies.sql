ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shelves ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_memos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_compliments ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_profile_visible(target_user_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = target_user_id
    AND (
      is_private = false
      OR id = auth.uid()
      OR id IN (SELECT following_id FROM public.follows WHERE follower_id = auth.uid())
    )
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- profiles policies
CREATE POLICY "Users can read visible profiles" ON public.profiles
  FOR SELECT USING (
    is_private = false
    OR id = auth.uid()
    OR id IN (SELECT following_id FROM public.follows WHERE follower_id = auth.uid())
  );

CREATE POLICY "Users can insert own profile" ON public.profiles
  FOR INSERT WITH CHECK (id = auth.uid());

CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE USING (id = auth.uid());

-- follows policies
CREATE POLICY "Anyone can read follows" ON public.follows
  FOR SELECT USING (true);

CREATE POLICY "Users can insert own follows" ON public.follows
  FOR INSERT WITH CHECK (follower_id = auth.uid());

CREATE POLICY "Users can delete own follows" ON public.follows
  FOR DELETE USING (follower_id = auth.uid());

-- shelves policies
CREATE POLICY "Owner full access to shelves" ON public.shelves
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Others can read visible shelves" ON public.shelves
  FOR SELECT USING (public.is_profile_visible(user_id));

-- books policies
CREATE POLICY "Owner full access to books" ON public.books
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Others can read visible books" ON public.books
  FOR SELECT USING (public.is_profile_visible(user_id));

-- book_memos policies
CREATE POLICY "Owner full access to memos" ON public.book_memos
  FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Others can read visible memos" ON public.book_memos
  FOR SELECT USING (public.is_profile_visible(user_id));

-- book_compliments policies
CREATE POLICY "Sender can insert compliments" ON public.book_compliments
  FOR INSERT WITH CHECK (from_user_id = auth.uid());

CREATE POLICY "Book owner can read compliments" ON public.book_compliments
  FOR SELECT USING (
    book_id IN (SELECT id FROM public.books WHERE user_id = auth.uid())
    OR from_user_id = auth.uid()
  );

CREATE POLICY "Sender can delete own compliments" ON public.book_compliments
  FOR DELETE USING (from_user_id = auth.uid());
