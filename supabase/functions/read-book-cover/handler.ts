import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Reads the title and author off a photo of a book cover, and returns them as a
// **search query string** -- not as a book.
//
// The HTTP entry point is `index.ts`; this file is only the handler. They are separate so
// the test can import `handler` without a `serve()` call running as a side effect of the
// import -- and, more importantly, so the deployed entry point stays an unconditional
// `serve(handler)`. Gating that on something like `import.meta.main` would make the
// function's ability to serve at all depend on how Supabase's Edge Runtime happens to load
// the module, and the failure mode is a function that starts cleanly and answers nothing.
//
// That return type is the whole design. An ISBN is an identifier and the barcode path
// takes it straight to the save sheet; an LLM reading stylised cover type is a *guess*,
// and it can be confidently wrong in a way an ISBN cannot: a misread character, a series
// name mistaken for a title, an author invented from a blurb. So this hands back the
// string a human would have typed and lets the existing search + results grid do the
// confirming. The user picks the book. Nothing here writes to the library.
//
// Why a function at all, rather than calling Gemini from the app: the API key cannot ship
// in the client. `--dart-define` is recoverable from the binary with `strings`, and a
// leaked key on a metered vision API is somebody else's bill. The key lives in Supabase
// secrets and never leaves this process.
//
// Deploy:
//   supabase secrets set GEMINI_API_KEY=...
//   supabase functions deploy read-book-cover
//
// Requires the `cover_read_events` table (20260821170000_cover_read_events.sql).

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

// Overridable without a code change, because model names move faster than this file
// will.
//
// **Flash-Lite by default, and the numbers are the argument.** A cover read is a
// tiled image (~1,750 input tokens at our 1600px cap) plus ~60 tokens out, so per
// read, at Standard pricing:
//
//   gemini-3.5-flash-lite   $0.30 / $2.50 per 1M  ->  ~$0.00068
//   gemini-3.1-flash-lite   $0.25 / $1.50 per 1M  ->  ~$0.00053
//   gemini-3.6-flash        $1.50 / $7.50 per 1M  ->  ~$0.0031
//
// Google describes Flash-Lite as being for "simple data processing", which is what
// transcribing two lines of display type is. 3.6-flash is ~5x the price to think
// harder about a problem that needs no thinking. Switch up to it if Hangul
// transcription on stylised covers turns out to be genuinely weak -- that is the
// one thing that would justify the difference, and `cover_read_events.outcome` is
// what tells you.
//
// **Do not "fall back" to a 2.5 model.** `gemini-2.5-flash` and
// `gemini-2.5-flash-lite` return 404 "no longer available to new users" on a
// project created after their retirement, and the API's own error text points at
// `gemini-3.6-flash` / `gemini-3.5-flash-lite` instead -- so those two ids are the
// vendor-confirmed current names, and an older-looking id is not the safe choice
// it appears to be.
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.5-flash-lite";

// Overridable for the same reason `MODEL` is, plus one more: it is the seam that makes the
// retry loop below testable. Pointed at a stub that returns `503, 503, 200`, the real
// handler can be run end to end without a network, which is the only way to know the retry
// works -- a transient upstream failure cannot be summoned on demand against the real API.
const GEMINI_BASE_URL =
  Deno.env.get("GEMINI_BASE_URL") ??
  "https://generativelanguage.googleapis.com";

// WARNING, and it is not about money.
//
// On the Gemini API **free tier** every model's terms say "Used to improve our
// products: Yes". The images this function forwards are photographs a user just
// took, in their home, of their shelf, with whatever else was in frame. Sending
// those to be trained on is a consent decision, not a default -- and in Korea it
// is a PIPA question, not only a policy one. The paid tier says "No".
//
// So: the project behind GEMINI_API_KEY should be on the **paid** tier before this
// is offered to real users, or the privacy policy has to say plainly what happens
// to the photo.

// Only what a camera produces. Kept narrow because the bytes are forwarded to a paid
// third-party API: an unchecked mime type here is an invitation to post arbitrary data
// through this endpoint on the project's key.
const ALLOWED_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);

// ~1.4MB of decoded image. The client downscales to the model's useful resolution before
// sending -- a cover only has to be legible, and a 12MP original is slower to upload,
// slower to process and no more readable. This bound is the backstop, and it is well
// inside both the Edge Function request limit and Gemini's 20MB inline-data cap.
const MAX_IMAGE_BYTES = 1_400_000;

// Base64 carries 3 bytes in every 4 characters, so the encoded string is checked before
// it is decoded. Decoding first would mean allocating the very thing the limit exists to
// refuse.
const MAX_BASE64_CHARS = Math.ceil(MAX_IMAGE_BYTES / 3) * 4 + 4;

// Generous on purpose -- see the migration. These stop a loop, not a person cataloguing a
// shelf.
const LIMIT_PER_HOUR = 30;
const LIMIT_PER_DAY = 100;

/** What the model must return. Enforced by `responseSchema`, not by prompt discipline. */
const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    title: {
      type: "string",
      description:
        "The book's MAIN title exactly as printed on the cover, in its own script, with any subtitle omitted. Empty string if no title can be read.",
    },
    author: {
      type: "string",
      description:
        "The author's name as printed on the cover, in its own script. Empty string if none is visible or legible.",
    },
    is_book_cover: {
      type: "boolean",
      description:
        "True only if this image actually shows the front cover of a book.",
    },
  },
  required: ["title", "author", "is_book_cover"],
};

const PROMPT = [
  "You are reading the front cover of a book to build a library-catalogue search query.",
  "",
  "Transcribe the title and author exactly as printed. Keep the original script:",
  "a Korean book must come back in Hangul, not romanised or translated, because the",
  "query is sent to a Korean book catalogue that will not match a translation.",
  "",
  "Rules:",
  "- Transcribe only. Never translate, correct or complete a title from memory.",
  "- Return only the MAIN title. Leave out any subtitle -- the secondary line,",
  "  often after a colon or dash, e.g. 'A Handbook of Agile Software Craftsmanship'.",
  "  The result is a search query, and a longer query matches fewer books.",
  "- If you cannot read the title with confidence, return an empty title. A wrong",
  "  title is worse than no title: it sends the user to results for a book that is",
  "  not the one in their hand, and looks like their own mistake.",
  "- Ignore anything that is not title or author: publisher, series, prizes,",
  "  review quotes, 'BESTSELLER' bands, price stickers, and any 'Foreword by' name.",
  "- If the image is not a book cover at all, set is_book_cover to false.",
].join("\n");

// Transient upstream statuses, retried rather than surfaced.
//
// Observed live, not assumed: a plain text prompt to `gemini-3.5-flash-lite` on the free
// tier returned `503 UNAVAILABLE` once, then `200` on the immediate retry, with no change
// in between. Without a retry that blip becomes "something went wrong" *after* the user
// has waited through a photo upload and an inference -- the most expensive possible moment
// to fail, and for a reason that had nothing to do with them or their photo.
//
// `429` is in here because it is **our** project's rate limit, not the user's. The
// per-user meter above is what rations a person; a 429 from Google means this key is
// briefly over its requests-per-minute, which is a queueing problem and not something to
// blame on the caller who happened to arrive during it.
const RETRYABLE_STATUS = new Set([429, 500, 502, 503, 504]);

// Three attempts, ~1.4s of added delay in the worst case. Bounded deliberately: this runs
// inside a request the user is watching a spinner for, so retrying is worth about one
// extra second and not more. Beyond that, saying "try again" and letting them decide is
// the more honest option.
const MAX_ATTEMPTS = 3;
const RETRY_BACKOFF_MS = [400, 1000];

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Collapses whitespace and trims. Cheap, and the model does sometimes wrap a title. */
function tidy(value: unknown): string {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
}

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Exported so `index.ts` can serve it and the test can drive it with a real `Request`
// instead of testing a copy of its logic.
export async function handler(req: Request): Promise<Response> {
  // Checked before anything else so a missing secret is a clear server error rather than
  // an "unreadable cover" the user would blame on their own photo.
  if (!geminiApiKey) {
    console.error("read-book-cover: GEMINI_API_KEY is not set");
    return json({ error: "not_configured" }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "no_auth" }, 401);

  const supabase = createClient(supabaseUrl, supabaseServiceKey);
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  // Authenticated, and not merely because the data is private -- it is a photo the user
  // just took. This endpoint spends money on every call, so it must never be reachable
  // by an anonymous caller who found the URL.
  if (authError || !user) return json({ error: "invalid_token" }, 401);

  let image: unknown;
  let mimeType: unknown;
  try {
    ({ image, mime_type: mimeType } = await req.json());
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }

  if (typeof image !== "string" || image.length === 0) {
    return json({ error: "bad_request" }, 400);
  }
  if (typeof mimeType !== "string" || !ALLOWED_MIME.has(mimeType)) {
    return json({ error: "unsupported_type" }, 400);
  }
  if (image.length > MAX_BASE64_CHARS) {
    return json({ error: "image_too_large" }, 413);
  }

  // Rate limit *before* the paid call, and count both windows in one round trip. The
  // hour window catches a runaway loop; the day window catches a patient one.
  const dayAgo = new Date(Date.now() - 86_400_000).toISOString();
  const hourAgo = new Date(Date.now() - 3_600_000).toISOString();
  const { data: recent, error: meterError } = await supabase
    .from("cover_read_events")
    .select("created_at")
    .eq("user_id", user.id)
    .gte("created_at", dayAgo);

  if (meterError) {
    // Fail *closed*. An unmetered paid endpoint is the thing this table exists to
    // prevent, so a meter that cannot be read is a reason to decline rather than a
    // reason to proceed -- and the barcode path still works, so declining is not a
    // dead end for the user.
    console.error("read-book-cover: meter unavailable", meterError);
    return json({ error: "unavailable" }, 503);
  }

  const inLastDay = recent?.length ?? 0;
  const inLastHour =
    recent?.filter((row: { created_at: string }) => row.created_at >= hourAgo)
      .length ?? 0;

  if (inLastHour >= LIMIT_PER_HOUR || inLastDay >= LIMIT_PER_DAY) {
    return json({ error: "rate_limited" }, 429);
  }

  const record = (outcome: "ok" | "unreadable" | "error") =>
    supabase
      .from("cover_read_events")
      .insert({ user_id: user.id, outcome })
      .then(({ error }: { error: unknown }) => {
        // Logged, never thrown: the read already happened and the user should get their
        // answer. A lost meter row undercounts by one; a request failed at the last step
        // wastes the call that was already paid for.
        if (error) console.error("read-book-cover: meter write failed", error);
      });

  // Built once, outside the retry loop: the image is the bulk of it and re-encoding the
  // same JSON on every attempt would be pure waste.
  const geminiBody = JSON.stringify({
    contents: [
      {
        parts: [
          { text: PROMPT },
          { inline_data: { mime_type: mimeType, data: image } },
        ],
      },
    ],
    generationConfig: {
      // Structured output rather than parsing prose. Without a schema the model
      // will sometimes wrap JSON in a code fence or add a sentence of preamble,
      // and a regex to strip that is a bug waiting for a title containing a
      // backtick.
      responseMimeType: "application/json",
      responseSchema: RESPONSE_SCHEMA,
      // Transcription, not composition. There is one right answer on the cover.
      temperature: 0,
      maxOutputTokens: 256,
    },
  });

  try {
    let geminiResponse: Response | undefined;
    let lastStatus = 0;
    let lastDetail = "";

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const response = await fetch(
        `${GEMINI_BASE_URL}/v1beta/models/${MODEL}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": geminiApiKey,
          },
          body: geminiBody,
        },
      );

      if (response.ok) {
        if (attempt > 1) {
          console.log(`read-book-cover: gemini ok on attempt ${attempt}`);
        }
        geminiResponse = response;
        break;
      }

      // Drained on every branch. An undrained body on a discarded response leaks the
      // connection, and the text is the only useful diagnostic when this ends up failing.
      lastStatus = response.status;
      lastDetail = (await response.text()).slice(0, 500);

      const retryable =
        RETRYABLE_STATUS.has(response.status) && attempt < MAX_ATTEMPTS;
      console.error(
        `read-book-cover: gemini ${response.status} on attempt ${attempt}${
          retryable ? " (retrying)" : ""
        } ${lastDetail}`,
      );
      if (!retryable) break;

      await sleep(RETRY_BACKOFF_MS[attempt - 1] ?? 1000);
    }

    if (!geminiResponse) {
      // Every attempt failed. Recorded as `error` -- see the migration on why failures are
      // metered at all -- and reported as `upstream`, which the client turns into the one
      // message where "try again" is honest advice.
      console.error(
        `read-book-cover: gemini gave up after ${MAX_ATTEMPTS} attempts, last ${lastStatus}`,
      );
      await record("error");
      return json({ error: "upstream" }, 502);
    }

    const payload = await geminiResponse.json();
    const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof text !== "string") {
      // Reached when the response was blocked by a safety filter or truncated: there is
      // a candidate but no text part. Reported as unreadable because from the user's
      // side that is exactly what happened.
      console.error(
        "read-book-cover: no text part",
        JSON.stringify(payload).slice(0, 500),
      );
      await record("unreadable");
      return json({ error: "unreadable" }, 200);
    }

    const parsed = JSON.parse(text);
    const title = tidy(parsed.title);
    const author = tidy(parsed.author);

    // A cover with no legible title is a failure even though the call succeeded, and the
    // model was told to prefer this over guessing. `is_book_cover: false` lands here too
    // -- pointing the camera at a mug is the same outcome from the user's side.
    if (!title || parsed.is_book_cover === false) {
      await record("unreadable");
      return json({ error: "unreadable" }, 200);
    }

    // Title and author together, which is what a person searching for a book types. Both
    // are returned separately as well so the client can show what was read without
    // re-splitting a string it just joined.
    const query = author ? `${title} ${author}` : title;

    await record("ok");
    return json({ query, title, author }, 200);
  } catch (error) {
    console.error("read-book-cover failed", error);
    await record("error");
    return json({ error: "upstream" }, 502);
  }
}
