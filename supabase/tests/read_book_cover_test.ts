// Runs the *real* `read-book-cover` handler against stub upstreams.
//
//   deno test --allow-net --allow-env supabase/tests/read_book_cover_test.ts
//
// Why this exists: the retry loop in the function was added because a live probe of
// `gemini-3.5-flash-lite` on the free tier returned `503 UNAVAILABLE` and then `200` on
// the immediate retry. A transient upstream failure cannot be summoned on demand against
// the real API, so the only way to know the retry actually works -- rather than looks like
// it should -- is to point the handler at something that fails on cue.
//
// It drives `handler` with real `Request` objects rather than re-implementing its logic,
// so what passes here is the code that deploys. Two servers stand in for the outside
// world: one speaking enough GoTrue and PostgREST for `supabase-js`, one speaking Gemini.

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------- stub upstreams

/** Queued Gemini replies, consumed in order. Each test sets what it needs. */
let geminiReplies: Array<{ status: number; body: unknown }> = [];
let geminiCalls = 0;
/** Bodies the handler actually sent, so the prompt/schema wiring can be inspected. */
let geminiBodies: Array<Record<string, unknown>> = [];

const geminiServer = Deno.serve(
  { port: 0, onListen: () => {} },
  async (req) => {
    geminiCalls++;
    geminiBodies.push(await req.json());
    const reply = geminiReplies.shift();
    if (!reply) return new Response("no reply queued", { status: 500 });
    return new Response(JSON.stringify(reply.body), {
      status: reply.status,
      headers: { "Content-Type": "application/json" },
    });
  },
);

/** The authenticated user, or `null` to make token validation fail. */
let authUser: { id: string } | null = {
  id: "11111111-1111-1111-1111-111111111111",
};
/** Rows the meter query returns. */
let meterRows: Array<{ created_at: string }> = [];
/** Set to make the meter read fail, exercising the fail-closed branch. */
let meterBroken = false;
/** Outcomes the handler wrote. */
let meterWrites: string[] = [];

const supabaseServer = Deno.serve(
  { port: 0, onListen: () => {} },
  async (req) => {
    const url = new URL(req.url);

    if (url.pathname === "/auth/v1/user") {
      if (!authUser) {
        return new Response(JSON.stringify({ message: "bad jwt" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify(authUser), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (url.pathname === "/rest/v1/cover_read_events") {
      if (req.method === "GET") {
        if (meterBroken) {
          return new Response(
            JSON.stringify({ message: "relation missing", code: "42P01" }),
            { status: 500, headers: { "Content-Type": "application/json" } },
          );
        }
        return new Response(JSON.stringify(meterRows), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      if (req.method === "POST") {
        const body = await req.json();
        meterWrites.push(body.outcome);
        return new Response(null, { status: 201 });
      }
    }

    return new Response("unexpected " + req.method + " " + url.pathname, {
      status: 404,
    });
  },
);

const geminiPort = (geminiServer.addr as Deno.NetAddr).port;
const supabasePort = (supabaseServer.addr as Deno.NetAddr).port;

// Set before the import: the module reads these into consts at load time, which is also
// how it behaves in production.
Deno.env.set("SUPABASE_URL", `http://127.0.0.1:${supabasePort}`);
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");
Deno.env.set("GEMINI_API_KEY", "test-gemini-key");
Deno.env.set("GEMINI_BASE_URL", `http://127.0.0.1:${geminiPort}`);

const { handler } = await import("../functions/read-book-cover/handler.ts");

// ---------------------------------------------------------------- helpers

/** A small but valid base64 payload. Its content is irrelevant -- Gemini is stubbed. */
const IMAGE_B64 = btoa("not really a jpeg, and it does not need to be");

function request(
  body: unknown,
  { auth = "Bearer test-jwt" }: { auth?: string | null } = {},
): Request {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (auth !== null) headers["Authorization"] = auth;
  return new Request("http://localhost/read-book-cover", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const coverRequest = (mime = "image/jpeg") =>
  request({ image: IMAGE_B64, mime_type: mime });

/** Wraps a model answer the way `generateContent` does. */
function geminiOk(fields: Record<string, unknown>) {
  return {
    status: 200,
    body: {
      candidates: [{ content: { parts: [{ text: JSON.stringify(fields) }] } }],
    },
  };
}

const unavailable = {
  status: 503,
  body: {
    error: {
      code: 503,
      message: "The service is currently unavailable.",
      status: "UNAVAILABLE",
    },
  },
};

function reset() {
  geminiReplies = [];
  geminiCalls = 0;
  geminiBodies = [];
  authUser = { id: "11111111-1111-1111-1111-111111111111" };
  meterRows = [];
  meterBroken = false;
  meterWrites = [];
}

// Each case resets first, so ordering cannot leak state between them.
//
// Sanitizers are off because the two stub servers and `supabase-js`'s token-refresh
// interval are created once for the whole file, which is the point -- the module reads its
// config into consts at import time, so the servers have to exist before that and outlive
// every case. Deno's leak detector cannot tell that from a real leak.
function test(name: string, fn: () => Promise<void>) {
  Deno.test({
    name,
    sanitizeOps: false,
    sanitizeResources: false,
    fn: async () => {
      reset();
      await fn();
    },
  });
}

// ---------------------------------------------------------------- the retry, which is the point

test("a 503 followed by a 200 succeeds, and costs the user one meter row", async () => {
  geminiReplies = [
    unavailable,
    geminiOk({
      title: "위대한 개츠비",
      author: "F. 스콧 피츠제럴드",
      is_book_cover: true,
    }),
  ];

  const response = await handler(coverRequest());
  assertEquals(response.status, 200);
  const body = await response.json();

  assertEquals(body.title, "위대한 개츠비");
  assertEquals(body.author, "F. 스콧 피츠제럴드");
  assertEquals(body.query, "위대한 개츠비 F. 스콧 피츠제럴드");
  assertEquals(geminiCalls, 2, "should have retried exactly once");
  // The blip must not be billed to the user's allowance, and must not be logged as an
  // error either -- from every point of view that matters this was one successful read.
  assertEquals(meterWrites, ["ok"]);
});

test("two 503s followed by a 200 still succeeds", async () => {
  geminiReplies = [
    unavailable,
    unavailable,
    geminiOk({
      title: "Clean Code",
      author: "Robert C. Martin",
      is_book_cover: true,
    }),
  ];

  const response = await handler(coverRequest());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).query, "Clean Code Robert C. Martin");
  assertEquals(geminiCalls, 3);
  assertEquals(meterWrites, ["ok"]);
});

test("three 503s gives up as upstream rather than retrying forever", async () => {
  geminiReplies = [unavailable, unavailable, unavailable, unavailable];

  const response = await handler(coverRequest());
  assertEquals(response.status, 502);
  assertEquals((await response.json()).error, "upstream");
  assertEquals(geminiCalls, 3, "capped at MAX_ATTEMPTS, not unbounded");
  assertEquals(meterWrites, ["error"]);
});

test("a 429 from Google is retried, because that is our quota and not the user's", async () => {
  geminiReplies = [
    { status: 429, body: { error: { code: 429, message: "rate limit" } } },
    geminiOk({ title: "Dune", author: "Frank Herbert", is_book_cover: true }),
  ];

  const response = await handler(coverRequest());
  assertEquals(response.status, 200);
  assertEquals(geminiCalls, 2);
});

test("a 400 from Google is not retried -- a malformed request will not fix itself", async () => {
  geminiReplies = [
    { status: 400, body: { error: { code: 400, message: "bad image" } } },
  ];

  const response = await handler(coverRequest());
  assertEquals(response.status, 502);
  assertEquals(geminiCalls, 1, "no retry on a non-transient status");
  assertEquals(meterWrites, ["error"]);
});

test("a 403 from Google is not retried -- a blocked key stays blocked", async () => {
  geminiReplies = [
    {
      status: 403,
      body: {
        error: { code: 403, message: "requests to this API are blocked" },
      },
    },
  ];

  const response = await handler(coverRequest());
  assertEquals(response.status, 502);
  assertEquals(geminiCalls, 1);
});

// ---------------------------------------------------------------- the ordinary answers

test("a readable cover returns title, author and a joined query", async () => {
  geminiReplies = [
    geminiOk({ title: "소년이 온다", author: "한강", is_book_cover: true }),
  ];

  const body = await (await handler(coverRequest())).json();
  assertEquals(body, {
    query: "소년이 온다 한강",
    title: "소년이 온다",
    author: "한강",
  });
  assertEquals(meterWrites, ["ok"]);
});

test("a title with no author queries on the title alone", async () => {
  geminiReplies = [
    geminiOk({ title: "Beowulf", author: "", is_book_cover: true }),
  ];

  const body = await (await handler(coverRequest())).json();
  assertEquals(body.query, "Beowulf");
  assertEquals(body.author, "");
});

test("whitespace and wrapped lines are collapsed", async () => {
  geminiReplies = [
    geminiOk({
      title: "  The   Left\nHand of Darkness ",
      author: " Ursula K. Le Guin\n",
      is_book_cover: true,
    }),
  ];

  const body = await (await handler(coverRequest())).json();
  assertEquals(body.title, "The Left Hand of Darkness");
  assertEquals(body.author, "Ursula K. Le Guin");
});

test("an empty title is unreadable, at HTTP 200, not an error", async () => {
  geminiReplies = [
    geminiOk({ title: "", author: "someone", is_book_cover: true }),
  ];

  const response = await handler(coverRequest());
  // 200 on purpose: it is an answer, not a fault, and the client keys off the body so it
  // can give advice about the *photo* instead of saying "try again".
  assertEquals(response.status, 200);
  assertEquals((await response.json()).error, "unreadable");
  assertEquals(meterWrites, ["unreadable"]);
});

test("a photo of something that is not a book is unreadable even with a title read", async () => {
  geminiReplies = [
    geminiOk({ title: "COFFEE", author: "", is_book_cover: false }),
  ];

  const response = await handler(coverRequest());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).error, "unreadable");
  assertEquals(meterWrites, ["unreadable"]);
});

test("a candidate with no text part is unreadable, not a crash", async () => {
  geminiReplies = [
    { status: 200, body: { candidates: [{ finishReason: "SAFETY" }] } },
  ];

  const response = await handler(coverRequest());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).error, "unreadable");
  assertEquals(meterWrites, ["unreadable"]);
});

test("unparseable JSON in the text part is an upstream failure, not a crash", async () => {
  geminiReplies = [
    {
      status: 200,
      body: {
        candidates: [{ content: { parts: [{ text: "```json {oops" }] } }],
      },
    },
  ];

  const response = await handler(coverRequest());
  assertEquals(response.status, 502);
  assertEquals((await response.json()).error, "upstream");
  assertEquals(meterWrites, ["error"]);
});

// ---------------------------------------------------------------- the guards

test("no Authorization header is refused before anything is spent", async () => {
  const response = await handler(
    request({ image: IMAGE_B64, mime_type: "image/jpeg" }, { auth: null }),
  );
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, "no_auth");
  assertEquals(geminiCalls, 0);
  assertEquals(meterWrites, []);
});

test("an invalid token is refused before anything is spent", async () => {
  authUser = null;

  const response = await handler(coverRequest());
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, "invalid_token");
  assertEquals(geminiCalls, 0);
});

test("a body that is not JSON is a bad request", async () => {
  const response = await handler(request("this is not json"));
  assertEquals(response.status, 400);
  assertEquals((await response.json()).error, "bad_request");
  assertEquals(geminiCalls, 0);
});

test("a missing image is a bad request", async () => {
  const response = await handler(request({ mime_type: "image/jpeg" }));
  assertEquals(response.status, 400);
  assertEquals((await response.json()).error, "bad_request");
});

test("a mime type the camera cannot produce is refused", async () => {
  for (const mime of ["application/pdf", "image/gif", "text/plain", ""]) {
    reset();
    const response = await handler(coverRequest(mime));
    assertEquals(response.status, 400, mime);
    assertEquals((await response.json()).error, "unsupported_type", mime);
    assertEquals(geminiCalls, 0, mime);
  }
});

test("jpeg, png and webp are all accepted", async () => {
  for (const mime of ["image/jpeg", "image/png", "image/webp"]) {
    reset();
    geminiReplies = [
      geminiOk({ title: "Ok", author: "", is_book_cover: true }),
    ];
    const response = await handler(coverRequest(mime));
    assertEquals(response.status, 200, mime);
    assertEquals(geminiBodies[0] ? 1 : 0, 1, mime);
  }
});

test("an oversized image is refused without being decoded or forwarded", async () => {
  const response = await handler(
    request({ image: "A".repeat(2_000_000), mime_type: "image/jpeg" }),
  );
  assertEquals(response.status, 413);
  assertEquals((await response.json()).error, "image_too_large");
  assertEquals(geminiCalls, 0);
  assertEquals(meterWrites, [], "nothing was spent, so nothing is metered");
});

test("the hourly limit refuses before the paid call", async () => {
  const now = Date.now();
  meterRows = Array.from({ length: 30 }, (_, i) => ({
    created_at: new Date(now - i * 60_000).toISOString(),
  }));

  const response = await handler(coverRequest());
  assertEquals(response.status, 429);
  assertEquals((await response.json()).error, "rate_limited");
  assertEquals(geminiCalls, 0, "the limit must precede the spend");
});

test("29 reads in the hour is still allowed", async () => {
  const now = Date.now();
  meterRows = Array.from({ length: 29 }, (_, i) => ({
    created_at: new Date(now - i * 60_000).toISOString(),
  }));
  geminiReplies = [geminiOk({ title: "Ok", author: "", is_book_cover: true })];

  assertEquals((await handler(coverRequest())).status, 200);
  assertEquals(geminiCalls, 1);
});

test("old reads fall out of the hour window", async () => {
  const now = Date.now();
  // 40 reads, all within the day but more than an hour ago: over the hourly limit by
  // count, under it by time. The day limit is 100, so this must be allowed.
  meterRows = Array.from({ length: 40 }, (_, i) => ({
    created_at: new Date(now - 7_200_000 - i * 60_000).toISOString(),
  }));
  geminiReplies = [geminiOk({ title: "Ok", author: "", is_book_cover: true })];

  assertEquals((await handler(coverRequest())).status, 200);
});

test("the daily limit refuses even when the hour is clear", async () => {
  const now = Date.now();
  meterRows = Array.from({ length: 100 }, (_, i) => ({
    created_at: new Date(now - 7_200_000 - i * 60_000).toISOString(),
  }));

  const response = await handler(coverRequest());
  assertEquals(response.status, 429);
  assertEquals(geminiCalls, 0);
});

test("an unreadable meter fails closed", async () => {
  meterBroken = true;

  const response = await handler(coverRequest());
  // Declining is safe here in a way proceeding is not: an unmetered paid endpoint is the
  // whole thing the table exists to prevent, and the barcode path still works.
  assertEquals(response.status, 503);
  assertEquals((await response.json()).error, "unavailable");
  assertEquals(geminiCalls, 0);
});

// ---------------------------------------------------------------- what we send

test("the request carries the image, the schema and temperature 0", async () => {
  geminiReplies = [geminiOk({ title: "Ok", author: "", is_book_cover: true })];
  await handler(coverRequest("image/png"));

  const sent = geminiBodies[0] as Record<string, any>;
  const parts = sent.contents[0].parts;
  assertEquals(parts[1].inline_data.mime_type, "image/png");
  assertEquals(parts[1].inline_data.data, IMAGE_B64);

  const cfg = sent.generationConfig;
  assertEquals(cfg.responseMimeType, "application/json");
  assertEquals(cfg.temperature, 0);
  assertEquals(cfg.responseSchema.required, [
    "title",
    "author",
    "is_book_cover",
  ]);

  // The subtitle rule is the one instruction a run has actually been seen to disobey, so
  // its presence in the prompt is worth pinning rather than trusting.
  assert(parts[0].text.includes("MAIN title"));
  assert(parts[0].text.includes("Leave out any subtitle"));
  assert(
    parts[0].text.includes("Hangul"),
    "the query goes to a Korean catalogue, so the script must be preserved",
  );
});

test("the retry sends a byte-identical body, not a re-encoded one", async () => {
  geminiReplies = [
    unavailable,
    geminiOk({ title: "Ok", author: "", is_book_cover: true }),
  ];
  await handler(coverRequest());

  assertEquals(geminiCalls, 2);
  assertEquals(
    JSON.stringify(geminiBodies[0]),
    JSON.stringify(geminiBodies[1]),
  );
});

// ---------------------------------------------------------------- teardown

Deno.test({
  name: "shutdown",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    await geminiServer.shutdown();
    await supabaseServer.shutdown();
  },
});
