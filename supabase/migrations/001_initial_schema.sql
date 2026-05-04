CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username varchar(20) UNIQUE,
  emoji varchar(6),
  is_private boolean NOT NULL DEFAULT false,
  fcm_token text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.follows (
  follower_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id != following_id)
);

CREATE TABLE public.shelves (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name varchar(15) NOT NULL,
  position int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.books (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  shelf_id uuid NOT NULL REFERENCES public.shelves(id) ON DELETE CASCADE,
  isbn varchar(13) NOT NULL,
  title varchar(100) NOT NULL,
  thumbnail text NOT NULL,
  status smallint NOT NULL DEFAULT 0,
  position int NOT NULL DEFAULT 0,
  rating real,
  start_date date,
  finish_date date,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.book_memos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.book_compliments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  from_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  compliment varchar(6) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_shelves_user_id ON public.shelves(user_id);
CREATE INDEX idx_books_user_id ON public.books(user_id);
CREATE INDEX idx_books_shelf_id ON public.books(shelf_id);
CREATE INDEX idx_book_memos_book_id ON public.book_memos(book_id);
CREATE INDEX idx_book_compliments_book_id ON public.book_compliments(book_id);
CREATE INDEX idx_follows_following_id ON public.follows(following_id);
