// HTTP entry point for `read-book-cover`. The behaviour is all in `handler.ts`.
//
// The split exists so the handler can be tested (`supabase/tests/read_book_cover_test.ts`
// drives it against stub upstreams, including an upstream that returns 503 on cue). Kept
// as a separate file rather than an `import.meta.main` guard in one file, because a guard
// would make serving conditional on how Supabase's Edge Runtime loads the module -- and if
// that assumption were ever wrong the function would boot cleanly and answer nothing.
// `serve` here is unconditional, so it cannot.
//
// Deploy:
//   supabase secrets set GEMINI_API_KEY=...
//   supabase functions deploy read-book-cover
//
// Requires the `cover_read_events` table (20260821170000_cover_read_events.sql).

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { handler } from "./handler.ts";

serve(handler);
